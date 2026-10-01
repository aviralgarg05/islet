import AppKit
import IsletCore
import QuartzCore
import SwiftUI

// Perpetual animations (spinners, the "playing" equalizer) are built from Core Animation
// layers: the window server interpolates them, so the app itself stays near 0% CPU.
// The SwiftUI equivalents (repeatForever / symbolEffect) re-render the view every frame
// and measured 8–12% CPU in the closed island (see scripts/perf.sh).

/// The "playing" indicator: bars or dots that move while music plays and settle when it
/// pauses. Moving between the two is animated too, so pausing never snaps.
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var playing: Bool
    var style: VisualiserStyle = .bars

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView(style: style)
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.update(style: style, color: color, playing: playing, reduceMotion: context.environment.reduceMotionAnywhere)
    }
}

final class EqualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var style: VisualiserStyle
    /// nil until the first update, so the first state is drawn without a transition.
    private var playing: Bool?
    private var reduceMotion = false
    private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47, 0.58, 0.44]
    /// Heights while playing without motion (Reduce Motion), and where a rise lands.
    private static let lively: [CGFloat] = [0.55, 0.9, 0.45, 0.75, 0.6, 0.8]
    /// Height while paused: a low, even line.
    private static let pausedScale: CGFloat = 0.2
    /// The lowest a bar goes while playing.
    private static let floor: CGFloat = 0.25
    private static let pausedOpacity: Float = 0.55

    init(style: VisualiserStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 14) }

    private var count: Int {
        switch style {
        case .bars: return 4
        case .slim: return 6
        case .dots: return 3
        case .off: return 0
        }
    }

    private var isDots: Bool { style == .dots }

    private func rebuild() {
        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<count).map { _ in
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
            return bar
        }
        playing = nil
        generation &+= 1
        needsLayout = true
    }

    private var laidOutSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard !bars.isEmpty else { return }
        // A new size changes how far dots travel and where bars sit: start the state again.
        let resized = bounds.size != laidOutSize
        laidOutSize = bounds.size
        let n = CGFloat(bars.count)
        let gap: CGFloat = style == .slim ? 1.5 : isDots ? 3 : 2
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        // Dots are round and sit at the bottom; they move up and down instead of stretching.
        let h = isDots ? min(w, bounds.height) : bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            bar.cornerRadius = isDots ? w / 2 : min(1.25, w / 2)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: 0)
            if bar.animation(forKey: "eq") == nil { apply(rest(i), to: bar) }
        }
        CATransaction.commit()
        if resized, playing != nil {
            generation &+= 1
            for (i, bar) in bars.enumerated() { settle(bar, i) }
        }
    }

    func update(style: VisualiserStyle, color: NSColor, playing: Bool, reduceMotion: Bool) {
        if style != self.style {
            self.style = style
            rebuild()
        }
        bars.forEach { $0.backgroundColor = color.cgColor }
        let changed = playing != self.playing || reduceMotion != self.reduceMotion
        let first = self.playing == nil
        self.playing = playing
        self.reduceMotion = reduceMotion
        guard changed else { return }
        generation &+= 1
        for (i, bar) in bars.enumerated() {
            if first { settle(bar, i) } else { transition(bar, i) }
        }
    }

    // MARK: States

    /// The resting value of bar `i` in the current state: its height (bars) or lift (dots).
    private func rest(_ i: Int) -> CGFloat {
        guard playing == true else { return isDots ? 0 : Self.pausedScale }
        return isDots ? Self.lively[i % Self.lively.count] * 0.5 : Self.lively[i % Self.lively.count]
    }

    private var keyPath: String { isDots ? "transform.translation.y" : "transform.scale.y" }

    /// Lift for dots is a share of the free height above them.
    private func lift(_ v: CGFloat) -> CGFloat { v * max(0, bounds.height - (bars.first?.bounds.height ?? 0)) }

    private func apply(_ v: CGFloat, to bar: CALayer) {
        bar.transform = isDots ? CATransform3DMakeTranslation(0, lift(v), 0) : CATransform3DMakeScale(1, v, 1)
        bar.opacity = playing == true ? 1 : Self.pausedOpacity
    }

    /// The first state, drawn as it is.
    private func settle(_ bar: CALayer, _ i: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.removeAnimation(forKey: "eq")
        apply(rest(i), to: bar)
        CATransaction.commit()
        if playing == true, !reduceMotion { loop(bar, i, after: 0) }
    }

    /// Play to pause, or pause to play: from where each bar is now to the new state, a little
    /// staggered, then (when playing) into the loop.
    private func transition(_ bar: CALayer, _ i: Int) {
        let from = (bar.presentation()?.value(forKeyPath: keyPath) as? CGFloat) ?? (isDots ? 0 : Self.pausedScale)
        let fromOpacity = bar.presentation()?.opacity ?? bar.opacity
        bar.removeAnimation(forKey: "eq")
        bar.removeAnimation(forKey: "fade")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(rest(i), to: bar)
        CATransaction.commit()
        let target = (bar.value(forKeyPath: keyPath) as? CGFloat) ?? 0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = bar.opacity
        fade.duration = 0.2
        bar.add(fade, forKey: "fade")

        if reduceMotion {
            // No movement: a quick cross-fade to the new heights.
            let swap = CABasicAnimation(keyPath: keyPath)
            swap.fromValue = from
            swap.toValue = target
            swap.duration = 0.15
            bar.add(swap, forKey: "eq")
            return
        }

        let delay = Double(i) * 0.035
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.fromValue = from
        spring.toValue = target
        spring.damping = playing == true ? 12 : 16
        spring.stiffness = 220
        spring.mass = 0.6
        spring.duration = min(0.5, spring.settlingDuration)
        spring.beginTime = CACurrentMediaTime() + delay
        spring.fillMode = .backwards
        bar.add(spring, forKey: "eq")
        if playing == true { loop(bar, i, after: delay + spring.duration) }
    }

    /// Bumped whenever the state changes, so a loop scheduled for an older state never starts.
    private var generation = 0

    /// The perpetual movement while playing, run by Core Animation. After a rise it starts once
    /// the rise has landed, so the hand-over is seamless.
    private func loop(_ bar: CALayer, _ i: Int, after delay: CFTimeInterval) {
        guard delay > 0 else { startLoop(i); return }
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected, self.playing == true, !self.reduceMotion else { return }
                self.startLoop(i)
            }
        }
    }

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
