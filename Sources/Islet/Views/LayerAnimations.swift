import AppKit
import QuartzCore
import SwiftUI

// Perpetual animations (spinners, the "playing" equalizer) are built from Core Animation
// layers: the window server interpolates them, so the app itself stays near 0% CPU.
// The SwiftUI equivalents (repeatForever / symbolEffect) re-render the view every frame
// and measured 8–12% CPU in the closed island (see scripts/perf.sh).

/// Animated equalizer bars.
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var playing: Bool
    var barCount = 4

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView(barCount: barCount)
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.update(color: color, playing: playing, reduceMotion: context.environment.reduceMotionAnywhere)
    }
}

final class EqualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var isAnimating = false
    private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47, 0.58]
    private static let rest: [CGFloat] = [0.45, 0.8, 0.35, 0.65, 0.5]

    init(barCount: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.25
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 14) }

    override func layout() {
        super.layout()
        let n = CGFloat(bars.count)
        let gap: CGFloat = 2
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: 0)
            if !isAnimating { bar.transform = CATransform3DMakeScale(1, Self.rest[i % Self.rest.count], 1) }
        }
        CATransaction.commit()
    }

    func update(color: NSColor, playing: Bool, reduceMotion: Bool) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        let animate = playing && !reduceMotion
        guard animate != isAnimating else { return }
        isAnimating = animate
        for (i, bar) in bars.enumerated() {
            if animate {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.25
                a.toValue = 1.0
                a.duration = Self.durations[i % Self.durations.count]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.timeOffset = Double(i) * 0.13
                a.capFrameRate()
                bar.add(a, forKey: "eq")
            } else {
                bar.removeAnimation(forKey: "eq")
                bar.transform = CATransform3DMakeScale(1, Self.rest[i % Self.rest.count], 1)
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
