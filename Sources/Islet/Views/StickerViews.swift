import AppKit
import IsletCore
import IsletSystem
import QuartzCore
import SwiftUI

/// The sticker in the closed island's right wing (the GIF look). It takes the wing's room and
/// sits where `StickerLayout` puts it, always inside the menu bar row.
struct StickerWing: View {
    let model: AppModel
    var mode: StickerMode
    /// The menu bar row's height.
    var row: CGFloat
    /// Space between the room and the island's outer edge, part of which the sticker may use.
    var outerSpace: CGFloat
    @Environment(\.wingRoom) private var room

    var body: some View {
        let library = model.stickers
        let choice = library.resolved(model.settings.sticker)
        let rect = StickerLayout.frame(room: room, row: row, outerSpace: outerSpace, aspect: library.aspect(choice),
                                       settings: model.settings.sticker)
        ZStack(alignment: .topLeading) {
            StickerView(library: library, choice: choice, mode: mode)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: max(0, room), height: row, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// A sticker drawn at its size: Core Animation plays it; snapshots draw one still frame.
struct StickerView: View {
    let library: StickerLibrary
    let choice: StickerChoice
    var mode: StickerMode
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            GeometryReader { g in
                let pixel = StickerLayout.pixelSize(g.size, scale: 2)
                if let image = library.still(choice, pixel: pixel) {
                    Image(decorative: image, scale: 2).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: g.size.width, height: g.size.height)
                }
            }
            .opacity(mode == .paused ? Double(PausedLook.indicatorOpacity) : 1)
        } else {
            StickerLayer(library: library, choice: choice, mode: mode)
        }
    }
}

private struct StickerLayer: NSViewRepresentable {
    let library: StickerLibrary
    let choice: StickerChoice
    var mode: StickerMode

    func makeNSView(context: Context) -> StickerNSView { StickerNSView() }

    func updateNSView(_ view: StickerNSView, context: Context) {
        view.update(library: library, choice: choice, mode: mode, reduceMotion: context.environment.reduceMotionAnywhere)
    }

    static func dismantleNSView(_ view: StickerNSView, coordinator: ()) {
        view.release()
    }
}

/// Plays a sticker's frames with one keyframe animation on a layer's contents, each frame for
/// its own time, at no more than 30 frames a second. Paused, it freezes on the frame it had
/// reached and dims, as the bars settle; playing again carries on from that frame. It stands
/// still with Reduce Motion (on the first frame) and in Low Power Mode, and lets its frames go
/// as soon as it leaves the window.
final class StickerNSView: NSView {
    private let sprite = CALayer()
    private weak var library: StickerLibrary?
    private var choice: StickerChoice?
    private var animation: StickerAnimation?
    /// The sticker and pixel size `animation` holds.
    private var loadedKey: String?
    private var loading: String?
    private var mode: StickerMode = .idle
    private var reduceMotion = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The frame on show while it isn't playing, and where the loop starts again.
    private var frozen = 0
    /// When the loop began, and the time into the loop it began at.
    private var loopBegan: (time: CFTimeInterval, offset: Double)?
    private var appliedState: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .linear
        sprite.minificationFilter = .trilinear
        layer?.addSublayer(sprite)
        // Removed by the system when the view goes.
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged(_:)),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(library: StickerLibrary, choice: StickerChoice, mode: StickerMode, reduceMotion: Bool) {
        self.library = library
        if choice != self.choice {
            self.choice = choice
            frozen = 0
            loopBegan = nil
        }
        self.mode = mode
        self.reduceMotion = reduceMotion
        load()
        apply()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        sprite.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        load()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { release() } else { load() }
    }

    /// Lets the frames go: the island no longer shows this sticker. They linger until the
    /// main queue's next turn, so a view SwiftUI swaps for a new one in the same update (the
    /// end of a cross-morph) finds them ready instead of drawing nothing while it decodes.
    func release() {
        if let animation { library?.linger(animation) }
        sprite.removeAllAnimations()
        sprite.contents = nil
        animation = nil
        loadedKey = nil
        loading = nil
        appliedState = nil
        loopBegan = nil
    }

    private var pixel: Int {
        StickerLayout.pixelSize(bounds.size, scale: window?.backingScaleFactor ?? 2)
    }

    private func load() {
        guard window != nil, let library, let choice, bounds.width >= 1, bounds.height >= 1 else { return }
        let pixel = self.pixel
        let key = "\(choice.id)@\(pixel)"
        guard key != loadedKey, key != loading else { return }
        if let ready = library.cached(choice, pixel: pixel) {
            show(ready, key: key)
            return
        }
        loading = key
        Task { @MainActor [weak self, weak library] in
            guard let library, let a = await library.frames(choice, pixel: pixel) else { return }
            guard let self, self.loading == key, self.window != nil else { return }
            self.loading = nil
            self.show(a, key: key)
        }
    }

    private func show(_ a: StickerAnimation, key: String) {
        // The same sticker at a new size carries on from the frame it had reached.
        if let old = animation, old.frames.count == a.frames.count { frozen = currentFrame(old) }
        loopBegan = nil
        animation = a
        loadedKey = key
        frozen = min(frozen, max(0, a.frames.count - 1))
        appliedState = nil
        apply()
    }

    /// No loop: Reduce Motion, or a picture with one frame. Low Power Mode plays at a lower rate.
    private var still: Bool { reduceMotion || !(animation?.isAnimated ?? false) }

    private func apply() {
        guard let a = animation, !a.frames.isEmpty else { return }
        let state = "\(mode)-\(still)-\(reduceMotion)"
        guard state != appliedState else { return }
        let first = appliedState == nil
        appliedState = state
        let fromOpacity = sprite.presentation()?.opacity ?? sprite.opacity
        let opacity = StickerPlayback.opacity(mode, paused: PausedLook.indicatorOpacity)
        let plan = StickerPlayback.plan(mode: mode, animated: a.isAnimated, reduceMotion: reduceMotion, current: currentFrame(a))
        switch plan {
        case .loop(let from):
            frozen = min(from, a.frames.count - 1)
            startLoop(a)
        case .hold(let frame):
            // Frozen where it had got to; Reduce Motion and the resting sticker show the first frame.
            frozen = min(frame, a.frames.count - 1)
            loopBegan = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.removeAnimation(forKey: "frames")
            sprite.contents = a.frames[frozen]
            CATransaction.commit()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.opacity = opacity
        CATransaction.commit()
        if !first, fromOpacity != opacity {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = opacity
            fade.duration = PausedLook.fade
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sprite.add(fade, forKey: "opacity")
        }
    }

    /// The frame the loop is showing now.
    private func currentFrame(_ a: StickerAnimation) -> Int {
        guard let began = loopBegan else { return frozen }
        return StickerTiming.frame(at: CACurrentMediaTime() - began.time + began.offset, delays: a.delays)
    }

    private func startLoop(_ a: StickerAnimation) {
        let offset = StickerTiming.start(of: frozen, delays: a.delays)
        let loop = CAKeyframeAnimation(keyPath: "contents")
        loop.values = a.frames
        loop.keyTimes = StickerTiming.keyTimes(a.delays).map { NSNumber(value: $0) }
        loop.calculationMode = .discrete
        loop.duration = a.duration
        loop.repeatCount = .infinity
        loop.timeOffset = offset
        // As often as the quickest frame needs, and never more than 30 a second.
        let rate = StickerTiming.frameRate(a.delays)
        loop.preferredFrameRateRange = CAFrameRateRange(minimum: min(10, rate), maximum: 30, preferred: rate)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = a.frames[frozen]
        sprite.add(loop, forKey: "frames")
        CATransaction.commit()
        loopBegan = (CACurrentMediaTime(), offset)
    }

    /// Posted on whichever thread changed the power state.
    @objc nonisolated private func powerStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                guard now != self.lowPower else { return }
                self.lowPower = now
                self.apply()
            }
        }
    }
}

/// A gallery tile's picture: the sticker's first frame, on black like the island.
struct StickerThumbnail: View {
    let library: StickerLibrary
    let choice: StickerChoice
    var size: CGFloat

    var body: some View {
        let pixel = StickerLayout.pixelSize(CGSize(width: size, height: size), scale: 2)
        Group {
            if let image = library.still(choice, pixel: pixel) {
                Image(decorative: image, scale: 2).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark").foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
    }
}
