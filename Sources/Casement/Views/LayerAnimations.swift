import AppKit
import CasementCore
import QuartzCore
import SwiftUI

// Perpetual animations (spinners, the "playing" indicator) are built from Core Animation
// layers: the window server interpolates them, so the app itself stays near 0% CPU.
// The SwiftUI equivalents (repeatForever / symbolEffect) re-render the view every frame
// and measured 8–12% CPU in the closed island (see scripts/perf.sh).

/// How paused music looks in the closed island: the indicator settles to a dim, still pose and
/// the artwork dims with it, over the same moment.
enum PausedLook {
    static let indicatorOpacity: Float = 0.55
    static let artworkOpacity: Double = 0.6
    static let fade: CFTimeInterval = 0.2
}

/// The "playing" indicator: bars, mirrored bars, dots, a wave or a pulse that move while music
/// plays and settle when it pauses (Vinyl's still dot too). Moving between the two is animated
/// too, so pausing never snaps. Reduce Motion holds the loops in a still pose that breathes
/// slowly, so a playing song never looks paused; Animation Off holds them still. Low Power Mode
/// runs them at a lower frame rate.
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var playing: Bool
    var style: VisualiserStyle = .bars

    func makeNSView(context: Context) -> PlayingIndicatorNSView {
        PlayingIndicatorNSView(style: style)
    }

    func updateNSView(_ view: PlayingIndicatorNSView, context: Context) {
        let pose = context.environment.loopPose
        view.update(style: style, color: color, playing: playing, reduceMotion: pose != .moving, breathing: pose == .breathing)
    }
}

/// Holds the drawing for the chosen look and swaps it when the look changes. It hears about
/// Low Power Mode from the system (no checking) and carries the loop on at that mode's frame
/// rate, from where it was.
final class PlayingIndicatorNSView: NSView {
    private var style: VisualiserStyle
    private var drawing: IndicatorLayerView
    private var reduceMotion = false
    private var lowPower: Bool
    private var last: (color: NSColor, playing: Bool)?

    /// `lowPower` fixes the power state instead of following the system's (snapshots, which
    /// should look the same on any Mac).
    init(style: VisualiserStyle, lowPower fixed: Bool? = nil) {
        self.style = style
        drawing = Self.drawing(for: style)
        lowPower = fixed ?? ProcessInfo.processInfo.isLowPowerModeEnabled
        super.init(frame: .zero)
        wantsLayer = true
        install(drawing)
        guard fixed == nil else { return }
        // Removed by the system when the view goes.
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged(_:)),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 14) }

    private static func drawing(for style: VisualiserStyle) -> IndicatorLayerView {
        switch style {
        case .wave: return WaveNSView()
        case .pulse: return PulseNSView()
        case .vinyl: return DotNSView()
        // The sticker has its own view in the closed island; anywhere else, the bars.
        case .gif, .off: return EqualizerNSView(style: .bars)
        case .bars, .slim, .dots, .mirror: return EqualizerNSView(style: style)
        }
    }

    private func install(_ view: IndicatorLayerView) {
        view.frame = bounds
        addSubview(view)
    }

    /// The drawing always fills the view.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if drawing.frame != bounds { drawing.frame = bounds }
    }

    override func layout() {
        super.layout()
        if drawing.frame != bounds { drawing.frame = bounds }
    }

    func update(style: VisualiserStyle, color: NSColor, playing: Bool, reduceMotion: Bool, breathing: Bool = false) {
        if style != self.style {
            self.style = style
            drawing.removeFromSuperview()
            drawing = Self.drawing(for: style)
            install(drawing)
        }
        self.reduceMotion = reduceMotion
        last = (color, playing)
        drawing.update(color: color, playing: playing, still: reduceMotion, breathing: breathing)
    }

    /// Posted on whichever thread changed the power state.
    @objc nonisolated private func powerStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyPowerState() }
        }
    }

    private func applyPowerState() {
        let now = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard now != lowPower else { return }
        lowPower = now
        // The loop carries on from where it is at the new frame rate: no stop, no jump.
        drawing.retimeLoops()
    }
}

/// One look of the playing indicator, drawn with layers. Subclasses draw the resting pose of
/// each state, the move between them and the loop while playing.
class IndicatorLayerView: NSView {
    /// nil until the first update, so the first state is drawn without a transition.
    private(set) var playing: Bool?
    /// No loop: Reduce Motion or Animation Off. Playing then holds a lively pose.
    private(set) var still = false
    /// Held still for Reduce Motion: playing, the pose breathes slowly (`IslandLoops.breathe`).
    private(set) var breathing = false
    /// Bumped whenever the state changes, so a loop scheduled for an older state never starts.
    private(set) var generation = 0
    private var laidOutSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var isPlaying: Bool { playing == true }

    /// A new size means the layers must be placed again.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    func update(color: NSColor, playing: Bool, still: Bool, breathing: Bool = false) {
        apply(color: color)
        let changed = playing != self.playing || still != self.still
        let first = self.playing == nil
        self.playing = playing
        self.still = still
        self.breathing = breathing
        if changed {
            generation &+= 1
            if first { settle() } else { transition() }
        } else if lostLoop {
            restart()
        }
        applyBreath()
    }

    // MARK: Keeping the loop alive

    /// Whether this look loops while it plays (Vinyl's dot is always still).
    var loops: Bool { true }
    /// Whether the still pose breathes under Reduce Motion (not a turning record).
    var breathes: Bool { true }

    /// It should be moving or breathing, but no animation is left on any of its layers: the
    /// window it was in was rebuilt or its layers were redrawn without them. Nothing would
    /// start the loop again, since the state hasn't changed.
    private var lostLoop: Bool {
        guard isPlaying, loops, !still || (breathing && breathes) else { return false }
        return !hasAnimations
    }

    private var hasAnimations: Bool {
        var layers = layer.map { [$0] } ?? []
        while let l = layers.popLast() {
            if !(l.animationKeys() ?? []).isEmpty { return true }
            layers += l.sublayers ?? []
        }
        return false
    }

    /// Draw the state again from its resting pose and start its loop.
    private func restart() {
        generation &+= 1
        settle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Back in a window (the panel brought back or rebuilt, after sleep): if the loop went
        // missing on the way, start it again.
        guard window != nil, playing != nil else { return }
        if lostLoop { restart() }
        applyBreath()
    }

    /// Under Reduce Motion a playing look holds its pose and fades slowly up and down, with
    /// no movement; anything else has no breath.
    private func applyBreath() {
        guard let root = layer else { return }
        let wanted = isPlaying && still && breathing && breathes
        let running = root.animation(forKey: "breathe") != nil
        if wanted, !running {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = IslandLoops.breatheLow
            a.duration = IslandLoops.breathe
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.capFrameRate()
            root.add(a, forKey: "breathe")
        } else if !wanted, running {
            let from = root.presentation()?.opacity ?? 1
            root.removeAnimation(forKey: "breathe")
            fade(root, "opacity", from: from)
        }
    }

    /// Low Power Mode changed: every loop carries on from where it is, at the new frame rate.
    /// Animations that end on their own (a rise, a spin-up) are left alone; the loop after
    /// them asks for the new rate when it starts.
    func retimeLoops() {
        var layers = layer.map { [$0] } ?? []
        while let l = layers.popLast() {
            layers += l.sublayers ?? []
            for key in l.animationKeys() ?? [] {
                guard let old = l.animation(forKey: key), old.repeatCount == .infinity,
                      let copy = old.copy() as? CAAnimation else { continue }
                let now = l.convertTime(CACurrentMediaTime(), from: nil)
                // The begin time Core Animation gave it when it was added; without one, from the top.
                let elapsed = old.beginTime > 0 ? (now - old.beginTime) * Double(old.speed) : 0
                copy.timeOffset = IslandLoops.resumeOffset(elapsed: elapsed, offset: old.timeOffset)
                copy.beginTime = 0
                copy.capFrameRate()
                l.add(copy, forKey: key)
            }
        }
    }

    override func layout() {
        super.layout()
        // A new size changes where everything sits: lay out, and start the state again.
        let resized = bounds.size != laidOutSize
        laidOutSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutLayers()
        CATransaction.commit()
        if resized, playing != nil {
            generation &+= 1
            settle()
        }
    }

    // MARK: For subclasses

    func apply(color: NSColor) {}
    /// Size and place the layers for `bounds`.
    func layoutLayers() {}
    /// Draw the current state as it is, then loop if it plays.
    func settle() {}
    /// Move from where it is now to the current state, then loop if it plays.
    func transition() {}

    /// Call `start` after `delay` (once a rise has landed), unless the state has changed by then.
    func loop(after delay: CFTimeInterval, _ start: @escaping () -> Void) {
        guard isPlaying, !still else { return }
        guard delay > 0 else { start(); return }
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected, self.isPlaying, !self.still else { return }
                start()
            }
        }
    }

    /// A spring from `from` to the value already set on `layer` for `keyPath`.
    func spring(_ layer: CALayer, _ keyPath: String, from: Any?, damping: CGFloat, delay: CFTimeInterval = 0) -> CFTimeInterval {
        let s = CASpringAnimation(keyPath: keyPath)
        s.fromValue = from
        s.toValue = layer.value(forKeyPath: keyPath)
        s.damping = damping
        s.stiffness = 220
        s.mass = 0.6
        s.duration = min(0.5, s.settlingDuration)
        if delay > 0 {
            s.beginTime = CACurrentMediaTime() + delay
            s.fillMode = .backwards
        }
        layer.add(s, forKey: keyPath)
        return s.duration
    }

    /// A short ease from `from` to the value already set on `layer` (no movement to speak of).
    func fade(_ layer: CALayer, _ keyPath: String, from: Any?, duration: CFTimeInterval = PausedLook.fade) {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = layer.value(forKeyPath: keyPath)
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: keyPath)
    }

    /// Set a layer's model values without implicit animations.
    func setQuietly(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}

// MARK: - Bars, slim bars, mirrored bars and dots

/// Bars or dots that bob while playing and settle to a low, dim line when paused. Mirrored
/// bars grow up and down from the middle and settle to a short dash there.
final class EqualizerNSView: IndicatorLayerView {
    private var bars: [CALayer] = []
    private let style: VisualiserStyle
    private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47, 0.58, 0.44]
    /// Heights while playing without motion (Reduce Motion), and where a rise lands.
    private static let lively: [CGFloat] = [0.55, 0.9, 0.45, 0.75, 0.6, 0.8]
    /// Mirrored bars at rest: tallest in the middle, the same on both sides.
    static let mirrorLively: [CGFloat] = [0.45, 0.75, 1.0, 0.7, 0.5]
    /// Height while paused: a low, even line.
    private static let pausedScale: CGFloat = 0.2
    /// The lowest a bar goes while playing.
    private static let floor: CGFloat = 0.25

    init(style: VisualiserStyle) {
        self.style = style
        super.init(frame: .zero)
        let count: Int
        switch style {
        case .slim: count = 6
        case .dots: count = 3
        case .mirror: count = 5
        default: count = 4
        }
        let mirrored = style == .mirror
        bars = (0..<count).map { _ in
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: mirrored ? 0.5 : 0)
            layer?.addSublayer(bar)
            return bar
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isDots: Bool { style == .dots }
    private var isMirror: Bool { style == .mirror }

    override func apply(color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
    }

    override func layoutLayers() {
        guard !bars.isEmpty else { return }
        let n = CGFloat(bars.count)
        let gap: CGFloat = style == .slim || isMirror ? 1.5 : isDots ? 3 : 2
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        // Dots are round and sit at the bottom; they move up and down instead of stretching.
        let h = isDots ? min(w, bounds.height) : bounds.height
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            bar.cornerRadius = isDots ? w / 2 : min(1.25, w / 2)
            // Mirrored bars are centred on the middle line and stretch both ways.
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: isMirror ? bounds.midY : 0)
            if bar.animation(forKey: "eq") == nil { pose(rest(i), bar) }
        }
    }

    /// The resting value of bar `i` in the current state: its height (bars) or lift (dots).
    /// Paused, every look settles on the middle line, as the mirror, wave and pulse do.
    private func rest(_ i: Int) -> CGFloat {
        guard isPlaying else { return isDots ? Self.pausedLift : Self.pausedScale }
        if isMirror { return Self.mirrorLively[i % Self.mirrorLively.count] }
        return isDots ? Self.lively[i % Self.lively.count] * 0.5 : Self.lively[i % Self.lively.count]
    }

    /// Paused dots sit halfway up their room: on the middle line.
    static let pausedLift: CGFloat = 0.5

    private var keyPath: String { isDots ? "transform.translation.y" : "transform.scale.y" }

    /// Lift for dots is a share of the free height above them.
    private func lift(_ v: CGFloat) -> CGFloat { v * max(0, bounds.height - (bars.first?.bounds.height ?? 0)) }

    private func pose(_ v: CGFloat, _ bar: CALayer) {
        bar.transform = transform(v)
        bar.opacity = isPlaying ? 1 : PausedLook.indicatorOpacity
    }

    /// Bars grow from the bottom while playing; paused, the short bars are lifted to sit on the
    /// middle line (mirrored bars are centred already).
    private func transform(_ v: CGFloat) -> CATransform3D {
        if isDots { return CATransform3DMakeTranslation(0, lift(v), 0) }
        let scale = CATransform3DMakeScale(1, v, 1)
        guard !isPlaying, !isMirror else { return scale }
        return CATransform3DConcat(scale, CATransform3DMakeTranslation(0, (1 - v) * bounds.height / 2, 0))
    }

    override func settle() {
        for (i, bar) in bars.enumerated() {
            setQuietly {
                bar.removeAnimation(forKey: "eq")
                pose(rest(i), bar)
            }
            loop(after: 0) { [weak self] in self?.startLoop(i) }
        }
    }

    /// Play to pause, or pause to play: from where each bar is now to the new state, a little
    /// staggered, then (when playing) into the loop.
    override func transition() {
        for (i, bar) in bars.enumerated() {
            // The whole transform: a bar settling to the middle line moves as it shrinks.
            let from = NSValue(caTransform3D: bar.presentation()?.transform ?? bar.transform)
            let fromOpacity = bar.presentation()?.opacity ?? bar.opacity
            bar.removeAnimation(forKey: "eq")
            bar.removeAnimation(forKey: "opacity")
            setQuietly { pose(rest(i), bar) }
            fade(bar, "opacity", from: fromOpacity)
            guard !still else {
                // No movement: a quick cross-fade to the new heights.
                let swap = CABasicAnimation(keyPath: "transform")
                swap.fromValue = from
                swap.toValue = NSValue(caTransform3D: bar.transform)
                swap.duration = 0.15
                bar.add(swap, forKey: "eq")
                continue
            }
            let delay = Double(i) * 0.035
            let s = CASpringAnimation(keyPath: "transform")
            s.fromValue = from
            s.toValue = NSValue(caTransform3D: bar.transform)
            s.damping = isPlaying ? 12 : 16
            s.stiffness = 220
            s.mass = 0.6
            s.duration = min(0.5, s.settlingDuration)
            s.beginTime = CACurrentMediaTime() + delay
            s.fillMode = .backwards
            bar.add(s, forKey: "eq")
            loop(after: delay + s.duration) { [weak self] in self?.startLoop(i) }
        }
    }

    /// The perpetual movement while playing, run by Core Animation. After a rise it starts once
    /// the rise has landed, so the hand-over is seamless.
    private func startLoop(_ i: Int) {
        guard bars.indices.contains(i) else { return }
        let bar = bars[i]
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = (bar.value(forKeyPath: keyPath) as? CGFloat) ?? 1
        a.toValue = isDots ? 0 : Self.floor
        a.duration = Self.durations[i % Self.durations.count]
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.capFrameRate()
        bar.add(a, forKey: "eq")
    }
}

// MARK: - Wave

/// The wave's shape, shared by the live layer and the still drawing in snapshots.
enum IndicatorWave {
    /// Points along the line; every phase has the same count, so Core Animation can morph them.
    static let segments = 24
    /// How far the wave travels per loop, and how tall each step is, for a lively but calm line.
    static let steps = 8
    static let amplitudes: [CGFloat] = [1, 0.82, 0.94, 0.7, 0.98, 0.78, 0.9, 0.74]
    /// The pose shown while playing without motion.
    static let stillPhase: CGFloat = 0.15

    /// A wave across `rect` at `phase` (0...1 of a cycle) with `amplitude` (share of the room),
    /// fading to the middle at both ends. Amplitude 0 is a flat line with the same points.
    static func path(in rect: CGRect, phase: CGFloat, amplitude: CGFloat, lineWidth: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let inset = lineWidth / 2 + 0.5
        let w = max(1, rect.width - inset * 2)
        let mid = rect.midY
        let room = max(0, rect.height / 2 - inset) * amplitude
        for k in 0...segments {
            let t = CGFloat(k) / CGFloat(segments)
            let envelope = sin(.pi * t)
            let y = mid + room * envelope * sin(2 * .pi * (1.5 * t - phase))
            let point = CGPoint(x: rect.minX + inset + w * t, y: y)
            if k == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}

/// One line that flows like a sound wave while playing and lies flat and dim when paused.
final class WaveNSView: IndicatorLayerView {
    private let line = CAShapeLayer()
    private static let lineWidth: CGFloat = 1.5
    private static let period: CFTimeInterval = 1.2

    override init(frame: NSRect) {
        super.init(frame: frame)
        line.fillColor = nil
        line.lineWidth = Self.lineWidth
        line.lineCap = .round
        line.lineJoin = .round
        layer?.addSublayer(line)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(color: NSColor) { line.strokeColor = color.cgColor }

    override func layoutLayers() {
        line.frame = bounds
        if line.animation(forKey: "path") == nil, line.animation(forKey: "wave") == nil { line.path = restPath }
    }

    private func wave(_ phase: CGFloat, _ amplitude: CGFloat) -> CGPath {
        IndicatorWave.path(in: bounds, phase: phase, amplitude: amplitude, lineWidth: Self.lineWidth)
    }

    /// Flat when paused; the first step of the loop when playing (a still pose without motion).
    private var restPath: CGPath {
        guard isPlaying else { return wave(0, 0) }
        return still ? wave(IndicatorWave.stillPhase, 1) : wave(0, IndicatorWave.amplitudes[0])
    }

    private func pose() {
        line.path = restPath
        line.opacity = isPlaying ? 1 : PausedLook.indicatorOpacity
    }

    override func settle() {
        setQuietly {
            line.removeAllAnimations()
            pose()
        }
        loop(after: 0) { [weak self] in self?.startLoop() }
    }

    override func transition() {
        let from = line.presentation()?.path ?? line.path
        let fromOpacity = line.presentation()?.opacity ?? line.opacity
        line.removeAllAnimations()
        setQuietly { pose() }
        fade(line, "opacity", from: fromOpacity)
        guard !still else {
            fade(line, "path", from: from, duration: 0.15)
            return
        }
        let landed = spring(line, "path", from: from, damping: isPlaying ? 12 : 16)
        loop(after: landed) { [weak self] in self?.startLoop() }
    }

    /// The flow: the wave moves along one cycle, rising and falling a little, and starts again
    /// where it began, so the loop has no seam.
    private func startLoop() {
        let n = IndicatorWave.steps
        let a = CAKeyframeAnimation(keyPath: "path")
        a.values = (0...n).map { k in wave(CGFloat(k) / CGFloat(n), IndicatorWave.amplitudes[k % n]) }
        a.duration = Self.period
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.capFrameRate()
        line.add(a, forKey: "wave")
    }
}

// MARK: - Pulse

/// A dot that beats while a ring ripples out of it; paused, the dot alone, smaller and dim.
final class PulseNSView: IndicatorLayerView {
    private let dot = CALayer()
    private let ring = CAShapeLayer()
    private static let ringWidth: CGFloat = 1.5
    /// The dot's size against the ring's, playing and paused.
    private static let dotShare: CGFloat = 0.5
    private static let pausedDot: CGFloat = 0.8
    /// The ring's pose while playing without motion.
    private static let stillRing: (scale: CGFloat, opacity: Float) = (0.8, 0.45)
    private static let beat: CFTimeInterval = 0.6
    private static let ripple: CFTimeInterval = 1.2

    override init(frame: NSRect) {
        super.init(frame: frame)
        ring.fillColor = nil
        ring.lineWidth = Self.ringWidth
        layer?.addSublayer(ring)
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(color: NSColor) {
        dot.backgroundColor = color.cgColor
        ring.strokeColor = color.cgColor
    }

    override func layoutLayers() {
        let d = min(bounds.width, bounds.height)
        // At the wing's outer end, where the bars, the mirror and the wave end too.
        let centre = CGPoint(x: bounds.maxX - d / 2, y: bounds.midY)
        ring.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        ring.position = centre
        let inset = Self.ringWidth / 2
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: inset, dy: inset), transform: nil)
        let dd = d * Self.dotShare
        dot.bounds = CGRect(x: 0, y: 0, width: dd, height: dd)
        dot.cornerRadius = dd / 2
        dot.position = centre
        if dot.animationKeys() == nil { pose() }
    }

    private var dotScale: CGFloat { isPlaying ? 1 : Self.pausedDot }

    private func pose() {
        dot.transform = CATransform3DMakeScale(dotScale, dotScale, 1)
        dot.opacity = isPlaying ? 1 : PausedLook.indicatorOpacity
        // Playing with motion, the loop draws the ring; playing still, it holds one ripple.
        let shown = isPlaying && still
        ring.transform = CATransform3DMakeScale(Self.stillRing.scale, Self.stillRing.scale, 1)
        ring.opacity = shown ? Self.stillRing.opacity : 0
    }

    override func settle() {
        setQuietly {
            dot.removeAllAnimations()
            ring.removeAllAnimations()
            pose()
        }
        loop(after: 0) { [weak self] in self?.startLoop() }
    }

    override func transition() {
        let fromScale = dot.presentation()?.value(forKeyPath: "transform.scale.x") ?? dotScale
        let fromOpacity = dot.presentation()?.opacity ?? dot.opacity
        let fromRing = ring.presentation()?.opacity ?? ring.opacity
        let ringSize = ring.presentation()?.transform
        dot.removeAllAnimations()
        ring.removeAllAnimations()
        setQuietly {
            pose()
            // A ripple on its way out keeps its size while it fades.
            if !isPlaying, let ringSize { ring.transform = ringSize }
        }
        fade(dot, "opacity", from: fromOpacity)
        // The ripple fades where it is rather than snapping away.
        fade(ring, "opacity", from: fromRing)
        guard !still else {
            fade(dot, "transform.scale", from: fromScale, duration: 0.15)
            return
        }
        let landed = spring(dot, "transform.scale", from: fromScale, damping: isPlaying ? 12 : 16)
        loop(after: landed) { [weak self] in self?.startLoop() }
    }

    /// The beat and the ripple, run by Core Animation.
    private func startLoop() {
        let beat = CABasicAnimation(keyPath: "transform.scale")
        beat.fromValue = 1
        beat.toValue = 0.8
        beat.duration = Self.beat
        beat.autoreverses = true
        beat.repeatCount = .infinity
        beat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        beat.capFrameRate()
        dot.add(beat, forKey: "beat")

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = Self.dotShare * 0.9
        grow.toValue = 1
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 0.9
        vanish.toValue = 0
        let ripple = CAAnimationGroup()
        ripple.animations = [grow, vanish]
        ripple.duration = Self.ripple
        ripple.repeatCount = .infinity
        ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.capFrameRate()
        ring.add(ripple, forKey: "ripple")
    }
}

// MARK: - Vinyl

/// Vinyl's mark beside the notch: one small dot, still, that shrinks and dims when the music
/// pauses. The artwork on the other side does the moving.
final class DotNSView: IndicatorLayerView {
    private let dot = CALayer()
    static let diameter: CGFloat = 5
    private static let pausedScale: CGFloat = 0.8

    /// Vinyl's mark is still whatever the motion settings: the record does the moving.
    override var loops: Bool { false }
    override var breathes: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(color: NSColor) { dot.backgroundColor = color.cgColor }

    override func layoutLayers() {
        let d = min(Self.diameter, bounds.height)
        dot.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        dot.cornerRadius = d / 2
        // At the wing's outer end, where the bars, the mirror and the wave end too.
        dot.position = CGPoint(x: bounds.maxX - d / 2, y: bounds.midY)
        if dot.animationKeys() == nil { pose() }
    }

    private var scale: CGFloat { isPlaying ? 1 : Self.pausedScale }

    private func pose() {
        dot.transform = CATransform3DMakeScale(scale, scale, 1)
        dot.opacity = isPlaying ? 1 : PausedLook.indicatorOpacity
    }

    override func settle() {
        setQuietly {
            dot.removeAllAnimations()
            pose()
        }
    }

    override func transition() {
        let fromScale = dot.presentation()?.value(forKeyPath: "transform.scale.x") ?? scale
        let fromOpacity = dot.presentation()?.opacity ?? dot.opacity
        dot.removeAllAnimations()
        setQuietly { pose() }
        fade(dot, "opacity", from: fromOpacity)
        if still {
            fade(dot, "transform.scale", from: fromScale, duration: 0.15)
        } else {
            _ = spring(dot, "transform.scale", from: fromScale, damping: isPlaying ? 12 : 16)
        }
    }
}

/// The closed artwork as a record for the Vinyl look: round, with a spindle hole and a couple
/// of grooves, turning slowly while the song plays. It spins up when the music starts and
/// coasts to a stop when it pauses, where it stays until the music plays again. Core Animation
/// turns it; it holds still with Reduce Motion (or Animation Off), and in Low Power Mode it
/// turns at a lower frame rate.
final class VinylNSView: IndicatorLayerView {
    /// The artwork itself never fades up and down.
    override var breathes: Bool { false }

    private let disc = CALayer()
    /// Drawn instead of the artwork when there's none: a dark record with a label in the music colour.
    private let label = CALayer()
    private let grooves = CAShapeLayer()
    private let hole = CALayer()
    /// One turn, in seconds: slow enough to stay calm beside the menu bar.
    static let period: CFTimeInterval = 6
    /// Spinning up from still, and coasting down to it.
    private static let spinUp: CFTimeInterval = 1.2
    private static let coast: CFTimeInterval = 0.9
    private static var speed: CGFloat { 2 * .pi / CGFloat(period) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        disc.masksToBounds = true
        disc.contentsGravity = .resizeAspectFill
        disc.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        grooves.fillColor = nil
        grooves.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        grooves.lineWidth = 0.7
        hole.backgroundColor = NSColor.black.cgColor
        hole.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        hole.borderWidth = 0.75
        disc.addSublayer(label)
        disc.addSublayer(grooves)
        disc.addSublayer(hole)
        layer?.addSublayer(disc)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(color: NSColor) { label.backgroundColor = color.withAlphaComponent(0.85).cgColor }

    /// The artwork, or nil for the drawn record. A new song's artwork fades in.
    func setArtwork(_ image: CGImage?) {
        guard image !== artwork else { return }
        artwork = image
        disc.contents = image
        label.isHidden = image != nil
    }
    private var artwork: CGImage?

    override func layoutLayers() {
        let d = min(bounds.width, bounds.height)
        disc.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        disc.cornerRadius = d / 2
        disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let centre = CGPoint(x: d / 2, y: d / 2)
        let l = d * 0.42
        label.bounds = CGRect(x: 0, y: 0, width: l, height: l)
        label.cornerRadius = l / 2
        label.position = centre
        grooves.frame = disc.bounds
        let path = CGMutablePath()
        for share in [0.62, 0.82] as [CGFloat] {
            let r = d / 2 * share
            path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        }
        grooves.path = path
        let h = max(2, d * 0.13)
        hole.bounds = CGRect(x: 0, y: 0, width: h, height: h)
        hole.cornerRadius = h / 2
        hole.position = centre
    }

    private var angle: CGFloat {
        (disc.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
            ?? (disc.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
    }

    private func setAngle(_ a: CGFloat) {
        setQuietly { disc.transform = CATransform3DMakeRotation(a, 0, 0, 1) }
    }

    override func settle() {
        let a = angle
        disc.removeAllAnimations()
        setAngle(a)
        loop(after: 0) { [weak self] in self?.startLoop() }
    }

    override func transition() {
        let a = angle
        disc.removeAllAnimations()
        guard !still else {
            setAngle(a)
            return
        }
        // Clockwise, as a record turns: negative in the layer's upward y.
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = a
        if isPlaying {
            // From rest, speeding up until it meets the loop's pace (the curve ends at twice
            // its average speed).
            let end = a - Self.speed * CGFloat(Self.spinUp) / 2
            setAngle(end)
            turn.toValue = end
            turn.duration = Self.spinUp
            turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.8, 0.6)
            turn.capFrameRate()
            disc.add(turn, forKey: "spin")
            loop(after: Self.spinUp) { [weak self] in self?.startLoop() }
        } else {
            // Coasting: from the loop's pace to rest.
            let end = a - Self.speed * CGFloat(Self.coast) / 2
            setAngle(end)
            turn.toValue = end
            turn.duration = Self.coast
            turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.4, 0.4, 1)
            turn.capFrameRate()
            disc.add(turn, forKey: "spin")
        }
    }

    private func startLoop() {
        let a = disc.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = a
        spin.toValue = a - 2 * .pi
        spin.duration = Self.period
        spin.repeatCount = .infinity
        spin.capFrameRate()
        disc.add(spin, forKey: "spin")
    }
}

/// The artwork for the Vinyl look: the song's artwork as a turning record.
struct VinylArtwork: View {
    let media: NowPlaying
    var size: CGFloat
    var tint: Color

    var body: some View {
        VinylDisc(image: Self.image(media), size: size, tint: tint, playing: media.isPlaying)
    }

    /// The song's artwork as a picture: from its bytes, or from the copy the island already
    /// loaded from its address (never a new download). Made once per artwork and kept for
    /// the last few, so a redraw of the island neither decodes it again nor hands the record
    /// a new picture.
    static func image(_ np: NowPlaying) -> CGImage? {
        if let data = np.artworkData {
            let key = "data-\(ArtworkCache.key(data))"
            if let image = images[key] { return image }
            guard let image = ArtworkCache.image(for: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            remember(image, key)
            return image
        }
        if let url = np.artworkURL {
            let key = "url-\(url.absoluteString)"
            if let image = images[key] { return image }
            guard let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url)),
                  let image = ArtworkCache.decode(cached.data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            remember(image, key)
            return image
        }
        return nil
    }

    private static var images: [String: CGImage] = [:]

    private static func remember(_ image: CGImage, _ key: String) {
        if images.count >= 3 { images.removeAll() }
        images[key] = image
    }
}

/// A record with `image` as its face (or a drawn label in `tint`), turning while `playing`:
/// Core Animation in the island and in Settings, one still drawing in snapshots.
struct VinylDisc: View {
    var image: CGImage?
    var size: CGFloat
    var tint: Color
    var playing: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size).clipShape(Circle())
                } else {
                    Circle().fill(Color(white: 0.13))
                    Circle().fill(tint.opacity(0.85)).frame(width: size * 0.42, height: size * 0.42)
                }
                ForEach([0.62, 0.82], id: \.self) { share in
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.7).frame(width: size * share, height: size * share)
                }
                Circle().fill(Color.black).frame(width: max(2, size * 0.13), height: max(2, size * 0.13))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.75))
            }
            .frame(width: size, height: size)
        } else {
            VinylLayer(image: image, color: NSColor(tint), playing: playing).frame(width: size, height: size)
        }
    }
}

private struct VinylLayer: NSViewRepresentable {
    var image: CGImage?
    var color: NSColor
    var playing: Bool

    func makeNSView(context: Context) -> VinylHostView { VinylHostView() }

    func updateNSView(_ view: VinylHostView, context: Context) {
        view.vinyl.setArtwork(image)
        view.vinyl.update(color: color, playing: playing, still: context.environment.reduceMotionAnywhere)
    }
}

/// Holds the record and follows Low Power Mode's frame rate, as the indicator does.
final class VinylHostView: NSView {
    let vinyl = VinylNSView()
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(vinyl)
        // Removed by the system when the view goes.
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged(_:)),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if vinyl.frame != bounds { vinyl.frame = bounds }
    }

    @objc nonisolated private func powerStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                guard now != self.lowPower else { return }
                self.lowPower = now
                // The record keeps turning from where it is, at the new frame rate: it never
                // stops and spins up again.
                self.vinyl.retimeLoops()
            }
        }
    }
}

/// Indeterminate progress ring.
struct LayerSpinner: NSViewRepresentable {
    var color: NSColor
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> SpinnerNSView { SpinnerNSView() }

    func updateNSView(_ view: SpinnerNSView, context: Context) {
        view.configure(color: color, lineWidth: lineWidth, reduceMotion: context.environment.reduceMotionAnywhere)
    }
}

final class SpinnerNSView: NSView {
    private let arc = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.28
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        let inset = arc.lineWidth / 2
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        CATransaction.commit()
    }

    func configure(color: NSColor, lineWidth: CGFloat, reduceMotion: Bool) {
        arc.strokeColor = color.cgColor
        arc.lineWidth = lineWidth
        needsLayout = true
        if reduceMotion {
            arc.removeAnimation(forKey: "spin")
        } else if arc.animation(forKey: "spin") == nil {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = 0
            a.toValue = -2 * Double.pi
            a.duration = 1
            a.repeatCount = .infinity
            a.capFrameRate()
            arc.add(a, forKey: "spin")
        }
    }
}

// MARK: - Song progress ring

/// The outline the song progress ring follows: a rounded rectangle that starts at the top
/// centre and runs clockwise, in y-down coordinates (SwiftUI's).
enum SongRingPath {
    static func path(in r: CGRect, corner: CGFloat) -> CGPath {
        let c = max(0, min(corner, r.width / 2, r.height / 2))
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: c)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: c)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: c)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.midX, y: r.minY), radius: c)
        p.closeSubpath()
        return p
    }
}

/// The same outline as a SwiftUI shape, for snapshots and the drawing in Settings: `inset`
/// points inside the frame (half the line, so the stroke stays inside), corners kept parallel.
struct SongRingShape: Shape {
    var corner: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        Path(SongRingPath.path(in: rect.insetBy(dx: inset, dy: inset), corner: max(0, corner - inset)))
    }
}

/// A thin ring round the closed artwork that fills as the song plays (Settings → Now Playing →
/// Show song progress). Core Animation fills it from the player's last report to the end of the
/// song, so the app does no work while the song plays on; a new report (a seek, a pause, a new
/// song) starts it again. Paused, it holds still. It glides at a few frames a second, and steps
/// once a second in Low Power Mode and with Reduce Motion. A static drawing in snapshots.
struct SongRing: View {
    let media: NowPlaying
    var tint: Color
    /// The artwork's corner; the ring keeps parallel to it.
    var corner: CGFloat
    var lineWidth: CGFloat = 1.5
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let inset = lineWidth / 2
        if snapshotMode {
            let fraction = SongProgress(media, now: Date())?.fraction ?? 0
            ZStack {
                SongRingShape(corner: corner, inset: inset).stroke(Color.white.opacity(SongRingNSView.trackOpacity), lineWidth: lineWidth)
                SongRingShape(corner: corner, inset: inset).trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        } else {
            SongRingLayer(media: media, color: NSColor(tint), corner: corner, lineWidth: lineWidth)
        }
    }
}

private struct SongRingLayer: NSViewRepresentable {
    let media: NowPlaying
    var color: NSColor
    var corner: CGFloat
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> SongRingNSView { SongRingNSView() }

    func updateNSView(_ view: SongRingNSView, context: Context) {
        view.update(media: media, color: color, corner: corner, lineWidth: lineWidth,
                    reduceMotion: context.environment.reduceMotionAnywhere)
    }
}

final class SongRingNSView: NSView {
    static let trackOpacity = 0.14
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private var corner: CGFloat = 0
    private var lineWidth: CGFloat = 1.5
    /// What the fill was last started from: the player's report, not the moment it was drawn.
    private var lastReport: Report?
    private var reduceMotion = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private struct Report: Equatable {
        var track: String
        var elapsed: Double?
        var timestamp: Date
        var rate: Double
        var playing: Bool
        var duration: Double?
        var stepped: Bool

        init(_ np: NowPlaying, stepped: Bool) {
            track = np.trackKey; elapsed = np.elapsed; timestamp = np.timestamp; rate = np.playbackRate
            playing = np.isPlaying; duration = np.duration; self.stepped = stepped
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [track, fill] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            layer?.addSublayer(l)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(Self.trackOpacity).cgColor
        fill.strokeEnd = 0
        // Removed by the system when the view goes.
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged(_:)),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inset = lineWidth / 2
        // Drawn y-down, then flipped into the layer's y-up space, so it starts at the top.
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let path = SongRingPath.path(in: bounds.insetBy(dx: inset, dy: inset), corner: max(0, corner - inset)).copy(using: &flip)
        for l in [track, fill] {
            l.frame = bounds
            l.lineWidth = lineWidth
            l.path = path
        }
        CATransaction.commit()
    }

    func update(media: NowPlaying, color: NSColor, corner: CGFloat, lineWidth: CGFloat, reduceMotion: Bool) {
        fill.strokeColor = color.cgColor
        if corner != self.corner || lineWidth != self.lineWidth {
            self.corner = corner
            self.lineWidth = lineWidth
            needsLayout = true
        }
        self.reduceMotion = reduceMotion
        lastMedia = media
        start(media)
    }

    /// Fill from where the song is to its end, unless that is already under way.
    private func start(_ np: NowPlaying) {
        let stepped = reduceMotion || lowPower
        let report = Report(np, stepped: stepped)
        guard report != lastReport else { return }
        lastReport = report
        fill.removeAnimation(forKey: "fill")
        guard let progress = SongProgress(np, now: Date()) else {
            setStrokeEnd(0)
            return
        }
        setStrokeEnd(progress.fraction)
        guard let remaining = progress.remaining, remaining > 0, progress.fraction < 1 else { return }
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = progress.fraction
        a.toValue = 1
        a.duration = remaining
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        // Most of a pixel a second: a few frames are plenty, and one a second when saving power.
        a.preferredFrameRateRange = stepped ? CAFrameRateRange(minimum: 1, maximum: 1, preferred: 1)
                                            : CAFrameRateRange(minimum: 1, maximum: 4, preferred: 4)
        fill.add(a, forKey: "fill")
    }

    private func setStrokeEnd(_ value: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.strokeEnd = value
        CATransaction.commit()
    }

    /// Posted on whichever thread changed the power state.
    @objc nonisolated private func powerStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                // Start again from the last report at the new pace.
                if let last = self.lastMedia { self.lastReport = nil; self.start(last) }
            }
        }
    }

    private var lastMedia: NowPlaying?
}
