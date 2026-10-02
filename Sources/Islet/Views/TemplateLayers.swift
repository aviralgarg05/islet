import AppKit
import QuartzCore
import SwiftUI

// Core Animation pieces for the Live Activity templates. Like LayerAnimations.swift, the window
// server runs these, so a draining timer ring or a call waveform costs the app no CPU per
// frame. Each has a static SwiftUI twin for snapshots (ImageRenderer can't draw NSViews).

/// A ring that drains from `fraction` to empty by `endsAt`, turning red for the last 10 s.
struct CountdownRing: NSViewRepresentable {
    var endsAt: Date
    var fraction: Double
    var color: NSColor
    var lineWidth: CGFloat
    var animate: Bool

    func makeNSView(context: Context) -> CountdownRingNSView { CountdownRingNSView() }

    func updateNSView(_ view: CountdownRingNSView, context: Context) {
        view.configure(endsAt: endsAt, fraction: fraction, color: color, lineWidth: lineWidth, animate: animate)
    }
}

final class CountdownRingNSView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var key: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [track, arc] {
            l.fillColor = nil
            l.lineCap = .round
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inset = arc.lineWidth / 2
        let r = max(1, min(bounds.width, bounds.height) / 2 - inset)
        // From 12 o'clock, clockwise (the layer's y axis points up).
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: r, startAngle: .pi / 2,
                    endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for l in [track, arc] {
            l.frame = bounds
            l.path = path
        }
        CATransaction.commit()
    }

    func configure(endsAt: Date, fraction: Double, color: NSColor, lineWidth: CGFloat, animate: Bool) {
        // Restart only when the deadline, look or motion setting changes, not on every render.
        let newKey = "\(endsAt.timeIntervalSince1970)|\(color)|\(lineWidth)|\(animate)|\(animate ? 0 : (fraction * 200).rounded())"
        guard newKey != key else { return }
        key = newKey
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = color.withAlphaComponent(0.25).cgColor
        track.lineWidth = lineWidth
        arc.lineWidth = lineWidth
        arc.removeAllAnimations()
        let remaining = endsAt.timeIntervalSinceNow
        let red = NSColor.systemRed.cgColor
        arc.strokeColor = remaining <= 10 ? red : color.cgColor
        arc.strokeEnd = animate ? 0 : max(0, min(1, fraction))
        CATransaction.commit()
        needsLayout = true
        guard animate, remaining > 0, fraction > 0 else { return }
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = max(0, min(1, fraction))
        drain.toValue = 0
        drain.duration = remaining
        drain.timingFunction = CAMediaTimingFunction(name: .linear)
        // A 25-minute countdown moves well under a pixel a second: a few frames a second are
        // plenty, as for the song progress ring.
        drain.preferredFrameRateRange = Self.slowRate
        arc.add(drain, forKey: "drain")
        if remaining > 10 {
            let turn = CABasicAnimation(keyPath: "strokeColor")
            turn.fromValue = color.cgColor
            turn.toValue = red
            turn.beginTime = arc.convertTime(CACurrentMediaTime(), from: nil) + remaining - 10
            turn.duration = 0.6
            turn.fillMode = .forwards
            turn.isRemovedOnCompletion = false
            // A short fade, at the loops' rate rather than the display's.
            turn.capFrameRate()
            arc.add(turn, forKey: "turn")
        }
    }

    /// At most 8 frames a second, and one in Low Power Mode.
    private static var slowRate: CAFrameRateRange {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? CAFrameRateRange(minimum: 1, maximum: 1, preferred: 1)
                                                      : CAFrameRateRange(minimum: 1, maximum: 8, preferred: 8)
    }
}

/// Voice waveform: bars that swell around the centre line. Stops (flat bars) when `active` is false.
struct Waveform: NSViewRepresentable {
    var color: NSColor
    var active: Bool
    var barCount = 5

    func makeNSView(context: Context) -> WaveformNSView { WaveformNSView(barCount: barCount) }

    func updateNSView(_ view: WaveformNSView, context: Context) {
        view.update(color: color, active: active)
    }
}

final class WaveformNSView: NSView {
    private var bars: [CALayer] = []
    private var isAnimating = false
    static let rest: [CGFloat] = [0.35, 0.7, 1.0, 0.6, 0.4, 0.8, 0.5]
    private static let durations: [CFTimeInterval] = [0.46, 0.38, 0.55, 0.42, 0.5, 0.36, 0.6]

    init(barCount: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let n = CGFloat(bars.count)
        let gap: CGFloat = 1.5
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.cornerRadius = w / 2
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            if !isAnimating { bar.transform = CATransform3DMakeScale(1, Self.rest[i % Self.rest.count] * 0.5, 1) }
        }
        CATransaction.commit()
    }

    func update(color: NSColor, active: Bool) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        guard active != isAnimating else { return }
        isAnimating = active
        for (i, bar) in bars.enumerated() {
            if active {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.2
                a.toValue = Self.rest[i % Self.rest.count]
                a.duration = Self.durations[i % Self.durations.count]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.timeOffset = Double(i) * 0.11
                a.capFrameRate()
                bar.add(a, forKey: "wave")
            } else {
                bar.removeAnimation(forKey: "wave")
                bar.transform = CATransform3DMakeScale(1, Self.rest[i % Self.rest.count] * 0.5, 1)
            }
        }
    }
}

/// A capsule that breathes slowly, marking the stage in progress.
struct BreathingCapsule: NSViewRepresentable {
    var color: NSColor
    var animate: Bool

    func makeNSView(context: Context) -> BreathingCapsuleNSView { BreathingCapsuleNSView() }

    func updateNSView(_ view: BreathingCapsuleNSView, context: Context) {
        view.update(color: color, animate: animate)
    }
}

final class BreathingCapsuleNSView: NSView {
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fill.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }

    func update(color: NSColor, animate: Bool) {
        fill.backgroundColor = color.cgColor
        if animate, fill.animation(forKey: "breathe") == nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0.45
            a.duration = 1.1
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.capFrameRate()
            fill.add(a, forKey: "breathe")
        } else if !animate {
            fill.removeAnimation(forKey: "breathe")
        }
    }
}
