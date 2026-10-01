import IsletCore
import SwiftUI

// The island's transitions. Each one is a modifier with a progress value, used two ways: as a
// SwiftUI transition, where SwiftUI animates the progress once and then stops, and directly
// with a progress worked out from `IslandMotion` when `Islet --snapshot-motion` draws a
// transition frozen part of the way through. So the contact sheets show the frames the island
// draws. Nothing here runs at rest: no timers, no display links, no perpetual animations.

/// A transition frozen part of the way through, for the motion contact sheets.
struct MotionFrame {
    /// Where the island is coming from (the model's presentation is where it is going).
    var from: IslandPresentation
    /// Seconds since the change began.
    var t: Double
    /// The bubbles beside `from` and beside the new presentation, when they differ from what
    /// the model would give (a bubble arriving or leaving while the island stays the same).
    var fromBubbles: BubbleSet? = nil
    var toBubbles: BubbleSet? = nil
}

/// The shell part of the way through a change, for surfaces that change with it (the Glass
/// theme's black melting into glass) when the motion sheets freeze it.
struct ShellClock: Equatable {
    var t: Double
    var wasExpanded: Bool
}

private struct ShellClockKey: EnvironmentKey {
    static let defaultValue: ShellClock? = nil
}

extension EnvironmentValues {
    var shellClock: ShellClock? {
        get { self[ShellClockKey.self] }
        set { self[ShellClockKey.self] = newValue }
    }
}

// MARK: - Content

/// Content fading and scaling in once the shell has made room for it.
struct ContentReveal: ViewModifier {
    /// 0 hidden, 1 in place.
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(IslandMotion.contentScale + (1 - IslandMotion.contentScale) * progress, anchor: .top)
    }

    static var transition: AnyTransition {
        .modifier(active: ContentReveal(progress: 0), identity: ContentReveal(progress: 1))
    }
}

// MARK: - The page switcher

private struct SwitcherTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// Seconds since the page switcher started rising, while it does (nil once it is in place).
    var switcherTime: Double? {
        get { self[SwitcherTimeKey.self] }
        set { self[SwitcherTimeKey.self] = newValue }
    }
}

/// Drives the page switcher's staggered entrance. SwiftUI animates `progress` from 0 to 1, in
/// step with time, over `IslandMotion.switcherSpan`; each part of the switcher (`RiseIn`)
/// works out where it is from that.
struct SwitcherReveal: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.switcherTime, progress >= 1 ? nil : progress * IslandMotion.switcherSpan * Motion.pace)
    }

    /// The switcher buds off the island after the content, its parts rising in turn, and goes
    /// first when the island closes.
    static func transition(_ style: AnimationStyle) -> AnyTransition {
        let k = Motion.pace
        switch style {
        case .off: return .identity
        case .minimal: return .opacity
        default:
            return .asymmetric(
                insertion: AnyTransition.modifier(active: SwitcherReveal(progress: 0), identity: SwitcherReveal(progress: 1))
                    .animation(.linear(duration: IslandMotion.switcherSpan * k).delay(IslandMotion.switcherDelay * k)),
                removal: AnyTransition.opacity.combined(with: .offset(y: IslandMotion.switcherRise / 2))
                    .animation(.easeIn(duration: IslandMotion.switcherExit * k))
            )
        }
    }
}

/// One part of the page switcher (0 the capsule, 1 the discs beside it) rising 6 points into
/// place as it fades in.
struct RiseIn: ViewModifier {
    var index: Int
    @Environment(\.switcherTime) private var time

    func body(content: Content) -> some View {
        let part = time.map { IslandMotion.switcherPart(index, at: $0, pace: Motion.pace) } ?? (rise: 1, opacity: 1)
        content
            .opacity(part.opacity)
            .offset(y: IslandMotion.switcherRise * CGFloat(1 - part.rise))
    }
}

// MARK: - Glyphs in the wings

/// A glyph arriving in a wing: it grows in from 0.6 with one soft bounce. As a transition the
/// bounce spring carries `progress` a little past 1 and back.
struct GlyphArrival: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(min(1, max(0, progress)))
    }
}

/// A wing's value giving way to one of another kind (a waveform becoming a timer): the old one
/// shrinks and fades out as the new one grows and fades in, in the same place.
struct CrossMorph: ViewModifier {
    /// 0 out, 1 in.
    var progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(progress)
    }

    static var transition: AnyTransition {
        .modifier(active: CrossMorph(progress: 0), identity: CrossMorph(progress: 1))
    }
}

extension AnimationStyle {
    /// A new activity's glyph in the leading wing: one soft bounce, a moment after the old
    /// one starts to go.
    var glyphTransition: AnyTransition {
        let k = Motion.pace
        switch self {
        case .off: return .identity
        case .minimal: return .opacity
        default:
            return .asymmetric(
                insertion: AnyTransition.modifier(active: GlyphArrival(progress: 0), identity: GlyphArrival(progress: 1))
                    .animation((bounces ? Motion.bounce : Motion.settle).delay(IslandMotion.glyphDelay * k)),
                removal: CrossMorph.transition.animation(.easeIn(duration: IslandMotion.morphOutLength * k))
            )
        }
    }

    /// A trailing value swapping for another kind: a cross-morph rather than a pop. The old
    /// one shrinks away quickly and the new one grows in just behind it.
    var valueTransition: AnyTransition {
        let k = Motion.pace
        switch self {
        case .off: return .identity
        case .minimal: return .opacity
        default:
            return .asymmetric(
                insertion: CrossMorph.transition
                    .animation(.easeOut(duration: IslandMotion.morphInLength * k).delay(IslandMotion.morphInDelay * k)),
                removal: CrossMorph.transition.animation(.easeIn(duration: IslandMotion.morphOutLength * k))
            )
        }
    }
}

// MARK: - Squash and stretch

/// What the shell is doing: which way it moves and by how much it changes width. Two moves
/// are the same move while the presentation is (`key`), so the squash plays once per change
/// and not again when the pointer's hover nudges the width.
struct ShellMove: Equatable {
    var key: String
    var opening: Bool
    var delta: CGFloat
    var stretches: Bool
    /// The shape it moves to sits in the menu bar row (the closed island).
    var intoRow: Bool

    static func == (a: ShellMove, b: ShellMove) -> Bool { a.key == b.key }
}

/// The shell squashing and stretching as it opens or closes: a few points of extra width on
/// each side (`IslandMotion.stretch`), played as keyframes sampled from the same function the
/// motion sheets draw, once per change. Nothing runs at rest.
struct ShellStretch<Content: View>: View {
    let move: ShellMove
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        KeyframeAnimator(initialValue: CGFloat(0), trigger: move) { stretch in
            content(stretch)
        } keyframes: { _ in
            KeyframeTrack {
                if move.stretches && IslandMotion.squashes(opening: move.opening, delta: move.delta, intoRow: move.intoRow) {
                    for (t, dt) in Self.samples() {
                        LinearKeyframe(IslandMotion.stretch(at: t, opening: move.opening, delta: move.delta, intoRow: move.intoRow,
                                                            pace: Motion.pace),
                                       duration: dt)
                    }
                } else {
                    LinearKeyframe(CGFloat(0), duration: 0.01)
                }
            }
        }
    }

    /// Sample times (and the time to each) at 60 per second over the change.
    private static func samples() -> [(Double, Double)] {
        let dt = Motion.pace / 60
        let count = Int((IslandMotion.stretchSpan * Motion.pace / dt).rounded(.up))
        return (1...max(1, count)).map { (Double($0) * dt, dt) }
    }
}

// MARK: - Liquid bubbles

/// What a bubble's goo grows from and flows back into.
enum GooAnchor: Equatable {
    /// The island's side, with its end drawn in.
    case island(GooCap)
    /// The bubble nearer the island, a disc the size of this one.
    case bubble
}

/// The island's end, where a bubble's goo joins it.
struct GooCap: Equatable {
    /// Corner radii of the island's end beside the bubble, top and bottom.
    var top: CGFloat
    var bottom: CGFloat
    /// The island's end shows what is under it (a glass pill), so the goo is cut away where
    /// it would be under the island: it flows out of the glass's edge instead of showing
    /// through it.
    var seeThrough = false
}

/// A bubble budding off the island's side like liquid (`split`), or pulled back and absorbed
/// (`merge`). While it runs, a Canvas under the bubble draws the island's end, the bubble and
/// the bridge between them, blurred and thresholded so they flow into each other; the bubble's
/// own view (its black disc and icon) rides on top, outside the blur. At rest the Canvas is
/// gone and the bubble is its plain view again.
struct GooBud: ViewModifier, Animatable {
    /// A split runs 0 (inside the island) to 1 (at rest). A merge, as a removal, runs from 1
    /// (at rest) to 0 (absorbed).
    var progress: Double
    var kind: IslandMotion.BudKind
    var diameter: CGFloat
    /// From the anchor's edge to the bubble's resting centre.
    var rest: CGFloat
    /// The bubble sits to the island's left.
    var left: Bool
    /// What the goo grows from: the island's side, its end drawn in unless that would show
    /// through glass, or the bubble nearer the island.
    var anchor: GooAnchor

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // The goo only while it moves: before a delayed split starts, and once a merge has
        // finished, the bubble is hidden inside the island and there is nothing to draw.
        let moving = progress > 0 && progress < 1
        let pose = progress >= 1 ? IslandMotion.BudPose.resting
                                 : IslandMotion.bud(kind, progress: kind == .split ? progress : 1 - progress)
        let centre = IslandMotion.budCentre(travel: pose.travel, rest: rest, radius: diameter / 2)
        content
            .scaleEffect(pose.scale)
            .opacity(pose.icon)
            .offset(x: (left ? -1 : 1) * (centre - rest))
            .background {
                if moving {
                    GooCanvas(pose: pose, centre: centre, rest: rest, diameter: diameter, left: left, anchor: anchor)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The goo: the island's end, the bubble and the bridge, drawn black, blurred and cut at half
/// opacity (the metaball technique), so where they come close they merge like liquid.
struct GooCanvas: View {
    let pose: IslandMotion.BudPose
    /// The bubble's centre and its resting centre, out from the island's side.
    let centre: CGFloat
    let rest: CGFloat
    let diameter: CGFloat
    let left: Bool
    let anchor: GooAnchor

    /// Room round the shapes for the blur.
    static let margin: CGFloat = 8
    /// How far the island's end (or the bubble beside) in the goo stays inside its edges.
    static let capInset: CGFloat = 1
    /// How far the goo reaches under a see-through island's edge, so no hairline shows between.
    static let seam: CGFloat = 0.5

    /// How soft the goo is: how far apart two edges can be and still flow together.
    static func blur(_ diameter: CGFloat) -> CGFloat { max(2, diameter * 0.11) }

    var body: some View {
        let m = Self.margin
        Canvas { context, size in
            if case .island(let cap) = anchor, cap.seeThrough {
                // Nothing under the glass: only the goo outside the island's end is drawn.
                var outside = Path(CGRect(origin: .zero, size: size))
                outside.addPath(end(cap, size: size, inset: Self.seam, reach: size.width))
                context.clip(to: outside, style: FillStyle(eoFill: true))
            }
            // Blur the shapes, then cut at half opacity: where they come close their blurs add
            // up past the cut and they flow together. The cut is made twice, because one leaves
            // a soft edge as wide as the blur is steep.
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.drawLayer { cut in
                cut.addFilter(.alphaThreshold(min: 0.5, color: .black))
                cut.drawLayer { blurred in
                    blurred.addFilter(.blur(radius: Self.blur(diameter)))
                    blurred.drawLayer { layer in shapes(in: &layer, size: size) }
                }
            }
        }
        .frame(width: 2 * (rest + diameter + m), height: diameter + 2 * m)
    }

    /// The anchor, the bubble and the bridge, in black.
    private func shapes(in layer: inout GraphicsContext, size: CGSize) {
        let dir: CGFloat = left ? -1 : 1
        let midY = size.height / 2
        let side = size.width / 2 - dir * rest
        if anchor == .bubble, pose.bridge > 0 {
            // The bubble nearer the island, at rest, a point smaller so the blur's soft edge
            // stays inside it. It is drawn over this one's goo, so only where the goo flows
            // out of it shows.
            let r = diameter / 2 - Self.capInset, x = side - dir * diameter / 2
            layer.fill(Path(ellipseIn: CGRect(x: x - r, y: midY - r, width: 2 * r, height: 2 * r)), with: .color(.black))
        } else if case .island(let cap) = anchor, pose.bridge > 0 {
            // A block reaching into the island, its outer corners rounded as the island's are.
            // It sits under the island, so only where it flows into the bridge shows. It is
            // there only while the bridge is (the goo has nothing else to join), and it stays a
            // point inside the row, so the blur's soft edge never shows below the island.
            layer.fill(end(cap, size: size, inset: Self.capInset, reach: diameter), with: .color(.black))
        }
        let r = diameter / 2 * CGFloat(pose.scale)
        let x = side + dir * centre
        layer.fill(Path(ellipseIn: CGRect(x: x - r, y: midY - r, width: 2 * r, height: 2 * r)), with: .color(.black))
        let w = diameter * CGFloat(pose.bridge)
        if w > 0.25 {
            let from = side - dir * 2
            layer.fill(Path(CGRect(x: min(from, x), y: midY - w / 2, width: abs(x - from), height: w)), with: .color(.black))
        }
    }

    /// The island's end beside the bubble, `inset` inside its edges, reaching `reach` points
    /// back into the island: a block level with the bubble, its outer corners rounded as the
    /// island's are.
    private func end(_ cap: GooCap, size: CGSize, inset: CGFloat, reach: CGFloat) -> Path {
        let dir: CGFloat = left ? -1 : 1
        let side = size.width / 2 - dir * rest
        let rect = CGRect(x: dir > 0 ? side - reach : side, y: Self.margin + inset, width: reach,
                          height: diameter - 2 * inset)
        let top = min(cap.top, rect.height / 2), bottom = min(cap.bottom, rect.height / 2)
        let radii = dir > 0
            ? RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: bottom, topTrailing: top)
            : RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: 0, topTrailing: 0)
        return UnevenRoundedRectangle(cornerRadii: radii).path(in: rect)
    }
}
