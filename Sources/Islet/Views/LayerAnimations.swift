import AppKit
import IsletCore
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

/// The "playing" indicator: bars, dots, a wave or a pulse that move while music plays and
/// settle when it pauses. Moving between the two is animated too, so pausing never snaps.
/// The loops stand still with Reduce Motion and in Low Power Mode.
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var playing: Bool
    var style: VisualiserStyle = .bars

    func makeNSView(context: Context) -> PlayingIndicatorNSView {
        PlayingIndicatorNSView(style: style)
    }

    func updateNSView(_ view: PlayingIndicatorNSView, context: Context) {
        view.update(style: style, color: color, playing: playing, reduceMotion: context.environment.reduceMotionAnywhere)
    }
}

/// Holds the drawing for the chosen look and swaps it when the look changes. It hears about
/// Low Power Mode from the system (no checking), and holds the loops still while it is on.
final class PlayingIndicatorNSView: NSView {
    private var style: VisualiserStyle
    private var drawing: IndicatorLayerView
    private var reduceMotion = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var last: (color: NSColor, playing: Bool)?

    init(style: VisualiserStyle) {
        self.style = style
        drawing = Self.drawing(for: style)
        super.init(frame: .zero)
        wantsLayer = true
        install(drawing)
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
        default: return EqualizerNSView(style: style)
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

    func update(style: VisualiserStyle, color: NSColor, playing: Bool, reduceMotion: Bool) {
        if style != self.style {
            self.style = style
            drawing.removeFromSuperview()
            drawing = Self.drawing(for: style)
            install(drawing)
        }
        self.reduceMotion = reduceMotion
        last = (color, playing)
        drawing.update(color: color, playing: playing, still: reduceMotion || lowPower)
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
        if let last { drawing.update(color: last.color, playing: last.playing, still: reduceMotion || lowPower) }
    }
}

/// One look of the playing indicator, drawn with layers. Subclasses draw the resting pose of
/// each state, the move between them and the loop while playing.
class IndicatorLayerView: NSView {
    /// nil until the first update, so the first state is drawn without a transition.
    private(set) var playing: Bool?
    /// No loop: Reduce Motion or Low Power Mode. Playing then holds a lively pose.
    private(set) var still = false
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

    func update(color: NSColor, playing: Bool, still: Bool) {
        apply(color: color)
        let changed = playing != self.playing || still != self.still
        let first = self.playing == nil
        self.playing = playing
        self.still = still
        guard changed else { return }
        generation &+= 1
        if first { settle() } else { transition() }
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

// MARK: - Bars, slim bars and dots

/// Bars or dots that bob while playing and settle to a low, dim line when paused.
final class EqualizerNSView: IndicatorLayerView {
    private var bars: [CALayer] = []
    private let style: VisualiserStyle
    private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47, 0.58, 0.44]
    /// Heights while playing without motion (Reduce Motion), and where a rise lands.
    private static let lively: [CGFloat] = [0.55, 0.9, 0.45, 0.75, 0.6, 0.8]
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
        default: count = 4
        }
        bars = (0..<count).map { _ in
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
            return bar
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isDots: Bool { style == .dots }

    override func apply(color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
    }

    override func layoutLayers() {
        guard !bars.isEmpty else { return }
        let n = CGFloat(bars.count)
        let gap: CGFloat = style == .slim ? 1.5 : isDots ? 3 : 2
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        // Dots are round and sit at the bottom; they move up and down instead of stretching.
        let h = isDots ? min(w, bounds.height) : bounds.height
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            bar.cornerRadius = isDots ? w / 2 : min(1.25, w / 2)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: 0)
            if bar.animation(forKey: "eq") == nil { pose(rest(i), bar) }
        }
    }

    /// The resting value of bar `i` in the current state: its height (bars) or lift (dots).
    private func rest(_ i: Int) -> CGFloat {
        guard isPlaying else { return isDots ? 0 : Self.pausedScale }
        return isDots ? Self.lively[i % Self.lively.count] * 0.5 : Self.lively[i % Self.lively.count]
    }

    private var keyPath: String { isDots ? "transform.translation.y" : "transform.scale.y" }

    /// Lift for dots is a share of the free height above them.
    private func lift(_ v: CGFloat) -> CGFloat { v * max(0, bounds.height - (bars.first?.bounds.height ?? 0)) }

    private func pose(_ v: CGFloat, _ bar: CALayer) {
        bar.transform = isDots ? CATransform3DMakeTranslation(0, lift(v), 0) : CATransform3DMakeScale(1, v, 1)
        bar.opacity = isPlaying ? 1 : PausedLook.indicatorOpacity
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
            let from = (bar.presentation()?.value(forKeyPath: keyPath) as? CGFloat) ?? (isDots ? 0 : Self.pausedScale)
            let fromOpacity = bar.presentation()?.opacity ?? bar.opacity
            bar.removeAnimation(forKey: "eq")
            bar.removeAnimation(forKey: "opacity")
            setQuietly { pose(rest(i), bar) }
            fade(bar, "opacity", from: fromOpacity)
            guard !still else {
                // No movement: a quick cross-fade to the new heights.
                let swap = CABasicAnimation(keyPath: keyPath)
                swap.fromValue = from
                swap.toValue = bar.value(forKeyPath: keyPath)
                swap.duration = 0.15
                bar.add(swap, forKey: "eq")
                continue
            }
            let delay = Double(i) * 0.035
            let s = CASpringAnimation(keyPath: keyPath)
            s.fromValue = from
            s.toValue = bar.value(forKeyPath: keyPath)
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
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
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
