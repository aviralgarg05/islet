import CoreGraphics
import Foundation

/// A damped spring, moving the way SwiftUI's `.spring(response:dampingFraction:)` does: unit
/// mass, stiffness (2π / response)² and damping 4π · damping / response. `value(at:)` is how
/// far along it is, 0 at the start and 1 at the target, above 1 while it overshoots.
///
/// The island animates with SwiftUI's own springs built from these numbers; the motion contact
/// sheets (`Islet --snapshot-motion`) sample the same curve, so a frame on the sheet is the
/// frame the island draws at that moment.
public struct MotionSpring: Equatable, Sendable {
    /// Roughly how long one swing takes, in seconds.
    public var response: Double
    /// 1 settles without overshoot; less overshoots and rings a little.
    public var damping: Double

    public init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }

    /// The same spring `pace` times slower ("Animation speed").
    public func paced(_ pace: Double) -> MotionSpring {
        MotionSpring(response: response * max(0.05, pace), damping: damping)
    }

    /// How far along the spring is `t` seconds after it starts from rest.
    public func value(at t: Double) -> Double {
        guard t > 0, response > 0 else { return 0 }
        let w = 2 * Double.pi / response
        let z = max(0, damping)
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let decay = exp(-z * w * t)
            return 1 - decay * (cos(wd * t) + (z * w / wd) * sin(wd * t))
        } else if z == 1 {
            return 1 - exp(-w * t) * (1 + w * t)
        } else {
            let root = (z * z - 1).squareRoot()
            let r1 = -w * (z - root), r2 = -w * (z + root)
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        }
    }

    /// When the spring has come within `tolerance` of the target for good.
    public func settlingTime(tolerance: Double = 0.002) -> Double {
        let step = 1.0 / 240
        var last = 0.0
        var t = 0.0
        while t < 6 {
            t += step
            if abs(1 - value(at: t)) > tolerance { last = t }
        }
        return last + step
    }

    /// The furthest it goes: 1 plus its overshoot.
    public var peak: Double {
        var best = 0.0
        var t = 0.0
        while t < 3 {
            t += 1.0 / 480
            best = max(best, value(at: t))
        }
        return best
    }
}

/// The island's motion, as plain numbers: one spring family, the order things move in, the
/// squash and stretch of the shell and the liquid bubbles. Everything here is a function of
/// time (seconds since a change began), so the island's transitions and the frames on the
/// motion contact sheets come from the same maths.
///
/// The rules it encodes:
/// - Shape first, content after. The shell starts moving at once; content fades and scales in
///   once the shell has made room, and the page switcher follows the content.
/// - Closing goes the other way: content and the switcher fade out quickly first, then the
///   shell closes on its calmer spring.
/// - The closed island stays in the menu bar row. Nothing here grows a bubble taller than the
///   row, and the shell's squash never leaves it wider than its closed shape at rest.
public enum IslandMotion {
    // MARK: The spring family

    /// Opening: lively, a touch of overshoot.
    public static let open = MotionSpring(response: 0.47, damping: 0.76)
    /// Closing: a little longer and nearly critically damped, so it lands without a bounce.
    public static let close = MotionSpring(response: 0.54, damping: 0.90)
    /// Small moves in place: a highlight sliding, a row arriving, the switcher rising.
    public static let settle = MotionSpring(response: 0.30, damping: 0.86)
    /// A bubble settling beside the island: quicker than opening, with a small overshoot.
    public static let bud = MotionSpring(response: 0.34, damping: 0.64)
    /// A glyph arriving in a wing: one soft bounce.
    public static let bounce = MotionSpring(response: 0.36, damping: 0.58)

    // MARK: Shape first, content after

    /// Content starts fading in this long after the shell starts moving.
    public static let contentDelay = 0.10
    /// Closing, the smaller shape's content waits until the shell has mostly closed.
    public static let contentDelayClosing = 0.18
    /// How long content takes to fade and scale in.
    public static let contentFade = 0.24
    /// Content scales in from this.
    public static let contentScale = 0.98
    /// Outgoing content fades out this quickly, before the shell closes.
    public static let contentExit = 0.08
    /// Closing waits this long, so the content is gone before the shell moves.
    public static let closeDelay = 0.06
    /// The page switcher starts rising this long after the shell, 0.06 s after the content.
    public static let switcherDelay = 0.16
    /// Each later part of the switcher (the discs beside the capsule) starts this much later.
    public static let switcherStep = 0.05
    /// How far the switcher's parts rise as they fade in.
    public static let switcherRise: CGFloat = 6
    /// How long each part takes to fade in.
    public static let switcherFade = 0.18
    /// The switcher goes first when the island closes, this quickly.
    public static let switcherExit = 0.06

    /// How far content has faded in, `t` seconds after the shell started (0 to 1, eased).
    public static func contentReveal(at t: Double, delay: Double = contentDelay, pace: Double = 1) -> Double {
        eased(EaseCurve.easeOut, from: delay * pace, length: contentFade * pace, at: t)
    }

    /// How much of the outgoing content is left `t` seconds after a change (1 to 0).
    public static func contentLeft(at t: Double, length: Double = contentExit, pace: Double = 1) -> Double {
        1 - eased(EaseCurve.easeIn, from: 0, length: length * pace, at: t)
    }

    /// The time the whole switcher takes to appear, from its first part starting to its last
    /// one landing, not counting `switcherDelay`.
    public static let switcherSpan = switcherStep + settle.settlingTime(tolerance: 0.01)

    /// One part of the switcher, `t` seconds after the switcher started (after `switcherDelay`):
    /// how far it has risen (0 to 1, from the settle spring) and how opaque it is.
    /// `index` 0 is the capsule; 1, the discs beside it, comes `switcherStep` later.
    public static func switcherPart(_ index: Int, at t: Double, pace: Double = 1) -> (rise: Double, opacity: Double) {
        let local = t - Double(max(0, index)) * switcherStep * pace
        guard local > 0 else { return (0, 0) }
        let rise = settle.paced(pace).value(at: local)
        let opacity = eased(EaseCurve.easeOut, from: 0, length: switcherFade * pace, at: local)
        return (rise, opacity)
    }

    /// When a part of the switcher starts moving, counted from the start of the shell's move.
    public static func switcherStart(_ index: Int, pace: Double = 1) -> Double {
        (switcherDelay + Double(max(0, index)) * switcherStep) * pace
    }

    // MARK: Squash and stretch

    /// The most the shell squashes or stretches on each side, in points.
    public static let stretchLimit: CGFloat = 2.5

    /// How far the closed island may reach past its resting width on each side of the menu bar
    /// row while it moves: the room kept clear beside the wings
    /// (`MenuBarLayoutEngine.clearance`) less the hover response's share.
    public static let rowRoom: CGFloat = MenuBarLayoutEngine.clearance - NotchGeometry.hoverGrow

    /// Whether a change of `delta` points of width squashes and stretches the shell. Not when
    /// it barely changes width, and not while it grows into a shape that sits in the menu bar
    /// row (an activity growing out of the notch): its wings have only `rowRoom` before the
    /// nearest menu bar item, and the open spring's own overshoot is all they can take.
    public static func squashes(opening: Bool, delta: CGFloat, intoRow: Bool) -> Bool {
        abs(delta) > 0.5 && !(opening && intoRow)
    }

    /// Extra width on each side of the shell `t` seconds into a change of `delta` points of
    /// width (the open minus the closed width, either way round). Opening, the shell overshoots
    /// a touch wider as it lands; closing, it pulls in a little narrower on the way. It is 0 at
    /// rest, and closing never pulls it inside the shape it is closing to, so the closed island
    /// never ends up narrower or wider than the notch and its wings. `intoRow`: the shape it is
    /// moving to sits in the menu bar row (`squashes`).
    public static func stretch(at t: Double, opening: Bool, delta: CGFloat, intoRow: Bool = false,
                               pace: Double = 1) -> CGFloat {
        let size = abs(delta)
        guard squashes(opening: opening, delta: delta, intoRow: intoRow), t > 0 else { return 0 }
        let amount = min(stretchLimit, 0.025 * size)
        if opening {
            return amount * CGFloat(bump(at: t, from: 0.14 * pace, to: 0.62 * pace))
        }
        let start = closeDelay * pace
        let pull = amount * CGFloat(bump(at: t, from: start + 0.02 * pace, to: start + 0.36 * pace))
        // Never inside the closed shape: at most part of what is still left to close.
        let left = size / 2 * CGFloat(1 - close.paced(pace).value(at: t - start))
        return -min(pull, max(0, left) * 0.6)
    }

    /// The stem's width for a shell `width` points wide (its body, without the flare) stretched
    /// `d` points on each side. A shape whose stem is as wide as its body (the closed island,
    /// the open island without a stem) stretches as a whole, so the closed island never grows
    /// a lip below the row; a stemmed one stretches only its body, so its stem stays the width
    /// of the row. 0 (no stem) stays 0.
    public static func stretchedStem(_ stem: CGFloat, width: CGFloat, by d: CGFloat) -> CGFloat {
        stem > 0 && stem >= width - 0.01 ? stem + 2 * d : stem
    }

    /// Long enough for every part of a change to have settled, for keyframes and frame sheets.
    public static let stretchSpan = 0.7

    /// The island's bounce when something new arrives ("Bounce on activity") peaks at this
    /// scale.
    public static let pulsePeak: CGFloat = 1.04

    /// The bounce's horizontal scale at `scale`, for an island whose part in the menu bar row
    /// is `rowWidth` points wide: the whole bounce on a narrow island, a smaller one on a wide
    /// island, so the row never reaches more than `rowRoom` past its resting width on a side
    /// and the wings never cover a menu bar item.
    public static func pulseWidthScale(_ scale: CGFloat, rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return scale }
        let most = 2 * rowRoom / rowWidth
        let share = min(1, most / (pulsePeak - 1))
        return min(1 + most, 1 + (scale - 1) * share)
    }

    /// The shell's width on the way from `from` to `to`, `t` seconds in, with its squash.
    public static func shellWidth(from: CGFloat, to: CGFloat, at t: Double, opening: Bool, intoRow: Bool = false,
                                  pace: Double = 1) -> CGFloat {
        let k = shellProgress(at: t, opening: opening, pace: pace)
        return from + (to - from) * CGFloat(k) + 2 * stretch(at: t, opening: opening, delta: to - from, intoRow: intoRow, pace: pace)
    }

    /// How far the shell has moved from one shape to the next, `t` seconds in: the open spring
    /// at once, or the close spring after `closeDelay`.
    public static func shellProgress(at t: Double, opening: Bool, pace: Double = 1) -> Double {
        opening ? open.paced(pace).value(at: t) : close.paced(pace).value(at: t - closeDelay * pace)
    }

    // MARK: Liquid bubbles

    /// How long a bubble takes to bud off the island.
    public static let splitDuration = 0.45
    /// How long a bubble takes to be pulled back in.
    public static let mergeDuration = 0.40
    /// Bubbles that leave as the shell changes shape (opening over them, a peek) fade this
    /// quickly instead of being absorbed.
    public static let bubbleFade = 0.12
    /// A bubble starts this size, inside the island.
    public static let budStartScale = 0.5
    /// The split's progress by which the bridge would have thinned to nothing.
    public static let snap = 0.5
    /// The bridge's thickest, against the bubble's diameter.
    public static let bridgeMax = 0.62
    /// The thinnest bridge, against the bubble's diameter. Any thinner and the goo's blur
    /// would leave only two spikes reaching for each other, so the bridge snaps instead, the
    /// way a thread of liquid does.
    public static let bridgeSnap = 0.16

    public enum BudKind: Sendable { case split, merge }

    /// A bubble part of the way through budding off the island or being pulled back into it.
    public struct BudPose: Equatable, Sendable {
        /// 0 with the bubble just inside the island's side, 1 at its resting place; a little
        /// past 1 while a split overshoots.
        public var travel: Double
        /// The bubble's size against its resting size. Never above 1, so it never grows
        /// taller than the menu bar row.
        public var scale: Double
        /// The gooey bridge to the island, against the bubble's diameter; 0 once it has snapped.
        public var bridge: Double
        /// How much of the bubble's icon shows.
        public var icon: Double

        public init(travel: Double, scale: Double, bridge: Double, icon: Double) {
            self.travel = travel
            self.scale = scale
            self.bridge = bridge
            self.icon = icon
        }

        /// A bubble at rest beside the island.
        public static let resting = BudPose(travel: 1, scale: 1, bridge: 0, icon: 1)
    }

    /// The bubble `progress` of the way (0 to 1, in time) through a split or a merge.
    public static func bud(_ kind: BudKind, progress: Double) -> BudPose {
        let p = min(1, max(0, progress))
        switch kind {
        case .split:
            let travel = settled(bud, at: p * splitDuration, over: splitDuration)
            let grow = EaseCurve.easeOut.value(min(1, p / 0.55))
            let scale = budStartScale + (1 - budStartScale) * grow
            // Never thicker than the bubble it feeds, so it stays inside the row too.
            return BudPose(travel: travel, scale: scale,
                           bridge: min(scale, bridgeWidth(.split, progress: p)),
                           icon: smoothstep(0.18, 0.55, p))
        case .merge:
            let pull = EaseCurve.easeIn.value(p)
            let scale = 1 - (1 - budStartScale) * smoothstep(0.35, 1, p)
            return BudPose(travel: 1 - pull, scale: scale,
                           bridge: min(scale, bridgeWidth(.merge, progress: p)),
                           icon: 1 - smoothstep(0.25, 0.65, p))
        }
    }

    /// The bridge's thickness, against the bubble's diameter. A split starts thick, stretches
    /// thin as the bubble moves out and snaps once it is down to `bridgeSnap`; a merge grows
    /// one once the bubble is close enough to the island for the goo to touch.
    public static func bridgeWidth(_ kind: BudKind, progress: Double) -> Double {
        let p = min(1, max(0, progress))
        switch kind {
        case .split:
            guard p < snap else { return 0 }
            let left = 1 - p / snap
            let width = bridgeMax * left.squareRoot() * (0.35 + 0.65 * left)
            return width < bridgeSnap ? 0 : width
        case .merge:
            guard p >= 0.5 else { return 0 }
            return bridgeSnap + (bridgeMax - bridgeSnap) * smoothstep(0.5, 0.9, p)
        }
    }

    /// Where a bubble's centre is, in points out from the island's side: `rest` at its resting
    /// place, and just inside the island (by its starting radius) at the start.
    public static func budCentre(travel: Double, rest: CGFloat, radius: CGFloat) -> CGFloat {
        let start = -radius * CGFloat(budStartScale)
        return start + (rest - start) * CGFloat(travel)
    }

    /// A new glyph waits this long, so the old one has mostly gone before it bounces in.
    public static let glyphDelay = 0.05

    /// A glyph arriving in a wing, `t` seconds in: how far the bounce spring has carried it
    /// (its scale goes from 0.6 with one soft bounce over 1, and it fades in with it).
    public static func glyphArrival(at t: Double, pace: Double = 1) -> Double {
        bounce.paced(pace).value(at: t - glyphDelay * pace)
    }

    /// Splitting bubbles wait this long when the island is closing, so they bud off it once
    /// it has nearly reached its closed shape.
    public static let budDelayClosing = 0.34

    /// A wing's value giving way to one of another kind, `t` seconds in: the old one shrinks
    /// and fades out quickly while the new one, a moment later, grows and fades in, so the two
    /// barely overlap.
    public static let morphOutLength = 0.14
    public static let morphInDelay = 0.08
    public static let morphInLength = 0.2

    /// How much of the old value is left (1 to 0).
    public static func morphOut(at t: Double, pace: Double = 1) -> Double {
        1 - eased(EaseCurve.easeIn, from: 0, length: morphOutLength * pace, at: t)
    }

    /// How far the new value has come in (0 to 1).
    public static func morphIn(at t: Double, pace: Double = 1) -> Double {
        eased(EaseCurve.easeOut, from: morphInDelay * pace, length: morphInLength * pace, at: t)
    }

    // MARK: Appearing and going

    /// The island appears from nothing at once on a notch (it grows out of the black hardware)
    /// and with this quick fade where there is no notch.
    public static let showFade = 0.12
    /// Going back to nothing, it fades only once the shell has closed onto the notch.
    public static let hideDelay = 0.38
    public static let hideFade = 0.1

    /// How opaque the whole island is `t` seconds after it starts to appear (`showing`) or
    /// to go.
    public static func presence(at t: Double, showing: Bool, notch: Bool, pace: Double = 1) -> Double {
        if showing { return notch ? 1 : eased(EaseCurve.easeOut, from: 0, length: showFade * pace, at: t) }
        return 1 - eased(EaseCurve.easeIn, from: hideDelay * pace, length: hideFade * pace, at: t)
    }

    // MARK: Helpers

    /// `spring` sampled at `t`, nudged so it lands exactly on 1 at `duration` (a spring never
    /// quite arrives; a transition that ends at `duration` must).
    public static func settled(_ spring: MotionSpring, at t: Double, over duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let x = min(1, max(0, t / duration))
        let miss = 1 - spring.value(at: duration)
        return spring.value(at: t) + miss * x * x * x
    }

    /// 0 before `from`, 1 after `from + length`, eased in between.
    public static func eased(_ curve: EaseCurve, from: Double, length: Double, at t: Double) -> Double {
        guard length > 0 else { return t >= from ? 1 : 0 }
        return curve.value(min(1, max(0, (t - from) / length)))
    }

    /// 0 outside `from...to`, rising to 1 in the middle and back: a squash's profile.
    static func bump(at t: Double, from: Double, to: Double) -> Double {
        guard t > from, t < to, to > from else { return 0 }
        let s = sin(Double.pi * (t - from) / (to - from))
        return s * s
    }

    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

/// The ease curves Core Animation and SwiftUI use (cubic Béziers from (0, 0) to (1, 1)).
public struct EaseCurve: Equatable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double

    public static let easeIn = EaseCurve(x1: 0.42, y1: 0, x2: 1, y2: 1)
    public static let easeOut = EaseCurve(x1: 0, y1: 0, x2: 0.58, y2: 1)
    public static let easeInOut = EaseCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    /// The curve's height at `x` (0 to 1).
    public func value(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        if x == 0 || x == 1 { return x }
        // Solve bezierX(s) = x for s by Newton's method, falling back to bisection.
        var s = x
        for _ in 0..<8 {
            let err = bezier(s, x1, x2) - x
            if abs(err) < 1e-7 { return bezier(s, y1, y2) }
            let d = slope(s, x1, x2)
            if abs(d) < 1e-6 { break }
            s -= err / d
        }
        var lo = 0.0, hi = 1.0
        s = x
        for _ in 0..<40 {
            let v = bezier(s, x1, x2)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return bezier(s, y1, y2)
    }

    private func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
    }

    private func slope(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * a + 6 * u * s * (b - a) + 3 * s * s * (1 - b)
    }
}

/// Whether the island's looping decorations (the playing indicator, spinners, the urgent glow,
/// the glass sheen) hold still. They stop for Reduce Motion (the system's or Islet's), with the
/// animation style Off, in Low Power Mode, and on content that is out of date.
public enum IslandLoops {
    public static func holdStill(reduceMotion: Bool, animationOff: Bool, lowPower: Bool, stale: Bool = false) -> Bool {
        reduceMotion || animationOff || lowPower || stale
    }
}
