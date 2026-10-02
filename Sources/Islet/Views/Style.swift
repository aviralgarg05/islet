import AppKit
import IsletCore
import QuartzCore
import SwiftUI

// MARK: - Haptics

/// Trackpad haptics. macOS only plays them while a finger rests on a Force Touch trackpad.
/// By default they fire only for direct actions on the island, never for passive arrivals
/// (the hand on the trackpad may be busy with something else).
@MainActor
enum Haptics {
    static var mode: HapticsMode = .direct

    enum Kind {
        /// Island expands because you hovered, clicked or dragged onto it.
        case open
        /// Button, tab or control.
        case tap
        /// Crossing a detent (volume 0/100, pin).
        case snap
        /// Files dropped onto the shelf.
        case drop
        /// Something important arrived on its own (passive; only in `.all` mode).
        case alert
    }

    static func play(_ kind: Kind) {
        switch mode {
        case .off: return
        case .direct where kind == .alert: return
        default: break
        }
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch kind {
        case .open: performer.perform(.levelChange, performanceTime: .now)
        case .tap: performer.perform(.generic, performanceTime: .now)
        case .snap: performer.perform(.alignment, performanceTime: .now)
        case .drop: performer.perform(.generic, performanceTime: .now)
        case .alert:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                performer.perform(.alignment, performanceTime: .now)
            }
        }
    }
}

// MARK: - Motion

extension AnimationStyle {
    /// The style the island actually uses: Off stays off; Reduce Motion (the system's or
    /// Islet's) gets plain short fades. Low Power Mode keeps the style: a spring that runs once
    /// costs next to nothing, and its loops slow down instead (`IslandLoops.frameRate`).
    static func effective(_ setting: AnimationStyle, reduceMotion: Bool) -> AnimationStyle {
        if setting == .off { return .off }
        return reduceMotion ? .minimal : setting
    }

    /// Every duration below is scaled by "Animation speed" (`Motion.pace`).
    private var k: Double { Motion.pace }

    /// The shell growing into a bigger shape (opening, a peek dropping down).
    var morph: Animation? {
        switch self {
        case .fluid: return Motion.open
        case .snappy: return .snappy(duration: 0.26 * k, extraBounce: 0.04)
        case .smooth: return .smooth(duration: 0.38 * k)
        case .minimal: return .easeInOut(duration: 0.16 * k)
        case .off: return nil
        }
    }

    /// A floating pill appearing from nothing, growing out of the middle of the menu bar row:
    /// no overshoot, so its ends never reach towards the menu bar items beside it.
    var grow: Animation? {
        switch self {
        case .fluid: return Motion.spring(IslandMotion.appear)
        case .snappy: return .smooth(duration: 0.26 * k)
        case .smooth: return .smooth(duration: 0.38 * k)
        case .minimal: return .easeInOut(duration: 0.16 * k)
        case .off: return nil
        }
    }

    /// The shell shrinking back: once the content has faded, on a calmer spring.
    var collapse: Animation? {
        switch self {
        case .fluid: return Motion.close.delay(IslandMotion.closeDelay * k)
        case .snappy: return .snappy(duration: 0.22 * k).delay(0.03 * k)
        case .smooth: return .smooth(duration: 0.3 * k).delay(IslandMotion.closeDelay * k)
        case .minimal: return .easeInOut(duration: 0.14 * k)
        case .off: return nil
        }
    }

    /// The richer motion (liquid bubbles, the staggered switcher, glyphs that bounce in):
    /// every style but Minimal and Off.
    var isRich: Bool { self == .fluid || self == .snappy || self == .smooth }

    /// The shell squashes and stretches only with the springy style.
    var stretches: Bool { self == .fluid }

    /// How content enters and leaves. Shape first, content after: new content fades and scales
    /// in once the shell has made room, and outgoing content is gone before the shell closes.
    func contentTransition(opening: Bool, appearing: Bool = false) -> AnyTransition {
        switch self {
        case .fluid, .smooth, .snappy:
            let quick = self == .snappy ? 0.7 : 1
            let delay = IslandMotion.contentStart(opening: opening, appearing: appearing)
            return .asymmetric(
                insertion: ContentReveal.transition
                    .animation(.easeOut(duration: IslandMotion.contentFade * quick * k).delay(delay * quick * k)),
                removal: .opacity.animation(.easeIn(duration: IslandMotion.contentExit * quick * k))
            )
        case .minimal:
            return .opacity
        case .off:
            return .identity
        }
    }

    var bounces: Bool { self == .fluid || self == .snappy }

    /// A small change in place (one icon giving way to the next, a percentage ticking, the
    /// island answering the pointer): the settle spring with the richer styles, a plain short
    /// ease with less motion, nothing with Off. Glyphs and numbers swap with `symbolSwap` and
    /// `numberSwap` under it.
    var inPlace: Animation? {
        switch self {
        case .off: return nil
        case .minimal: return .easeInOut(duration: 0.14 * k)
        default: return Motion.settle
        }
    }

    /// How a changed symbol swaps: SF Symbols' replace, or a plain fade with less motion.
    var symbolSwap: ContentTransition { isRich ? .symbolEffect(.replace) : .opacity }

    /// How a changed number swaps: rolling digits, or a plain fade with less motion.
    func numberSwap(value: Double? = nil) -> ContentTransition {
        guard isRich else { return .opacity }
        return value.map { .numericText(value: $0) } ?? .numericText()
    }
}

// MARK: - Theme

extension IslandTheme {
    /// Fill for the island in a given presentation. Closed states stay black so they merge
    /// with the hardware notch; themes only change the expanded surface.
    /// - Parameters:
    ///   - row: height of the menu bar row, which stays black in every theme.
    ///   - height: the island's current height, to place the seam below that row.
    ///   - closedGlass: the closed island is glass too ("Glass on displays without a notch").
    ///   - stemmed: the open island has the stem-and-body shape. Passed while the island is
    ///     closed too, so a closing island keeps the look it had open while its glass fades.
    @ViewBuilder
    func background(expanded: Bool, shape: IslandShape, row: CGFloat = 0, height: CGFloat = 0, glassLevel: Double = 0.6,
                    closedGlass: Bool = false, stemmed: Bool = false) -> some View {
        switch self {
        case .graphite:
            GraphiteBody(shape: shape, expanded: expanded, row: row, height: height)
        case .glass:
            GlassBody(shape: shape, expanded: expanded, row: row, height: height, level: glassLevel, closedGlass: closedGlass,
                      stemmed: stemmed)
        default:
            shape.fill(Color.black)
        }
    }

    /// The open Graphite surface below the menu bar row.
    static let graphite = Color(white: 0.105)
}

/// "Subtle outline": a faint edge round the island so black shows on a dark wallpaper. The
/// system's Increase Contrast always draws it, firmer. The top edge, at the top of the screen,
/// is left out.
struct IslandOutline: View {
    let shape: IslandShape
    let on: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    /// The edge with Increase Contrast, which bubbles share.
    static let increasedEdge = Color.white.opacity(0.25)
    static let increasedWidth: CGFloat = 1
    /// "Subtle outline": faint, but firm enough to find on a busy wallpaper. Bubbles share it.
    static let edge = Color.white.opacity(0.22)
    static let width: CGFloat = 1

    var body: some View {
        let increased = contrast == .increased
        if on || increased {
            IslandEdge(shape: shape)
                .stroke(increased ? Self.increasedEdge : Self.edge, lineWidth: increased ? Self.increasedWidth : Self.width)
                .allowsHitTesting(false)
        }
    }
}

/// How much of each layer of the open island shows: at rest, or in a transition frozen for the
/// motion sheets.
private func shellLayers(expanded: Bool, clock: ShellClock?) -> GlassLayers {
    guard let clock, clock.wasExpanded != expanded else { return GlassMelt.layers(expanded: expanded) }
    return GlassMelt.layers(at: clock.t, opening: expanded, pace: Motion.pace)
}

/// Graphite: dark grey below a black menu bar row while open, black closed. The grey is drawn
/// over the black at every size and only its opacity changes, so closing is one shape
/// shrinking into the notch rather than a grey slab fading where the open island was.
private struct GraphiteBody: View {
    let shape: IslandShape
    let expanded: Bool
    let row: CGFloat
    let height: CGFloat
    @Environment(\.shellClock) private var clock
    @Environment(\.islandMotion) private var motion

    var body: some View {
        // The menu bar row stays black, so the hardware notch never shows as a dark bite in a
        // grey bar; the grey starts just below it. The edge leaves out the top, at the top of
        // the screen.
        let h = max(height, row + Space.m, 1)
        let fade: Animation? = motion == .off || expanded ? nil : .linear(duration: GlassMelt.glassOut * Motion.pace)
        ZStack {
            shape.fill(Color.black)
            shape.fill(LinearGradient(stops: [.init(color: .black, location: 0),
                                              .init(color: .black, location: row / h),
                                              .init(color: IslandTheme.graphite, location: (row + Space.m) / h)],
                                      startPoint: .top, endPoint: .bottom))
                .overlay(IslandEdge(shape: shape).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .animation(fade) { $0.opacity(shellLayers(expanded: expanded, clock: clock).glass) }
        }
        // One shape for the open island's shadow, not one for the black and one for the grey.
        .compositingGroup()
    }
}

/// Dynamic Glass: one piece of Liquid Glass that is black where it meets the notch and melts
/// into glass below the menu bar row. Beside the hardware notch glass would show the wallpaper
/// at the notch's edges, so the row stays black. A faint smoke stays under the content so text
/// never loses contrast, and a slow sheen drifts across while the island is open.
///
/// The glass fades in once the island has grown clear of the notch, and the black comes back
/// first when it closes. Every layer is always drawn, in the shell's own shape, and only its
/// opacity changes: a layer removed with a transition keeps the size it had when it went, so
/// the open island's glass faded as a full-size slab under a black island shrinking into the
/// notch. Each fade is scoped to its opacity, so the layers keep the shell's own spring.
private struct GlassBody: View {
    let shape: IslandShape
    let expanded: Bool
    let row: CGFloat
    let height: CGFloat
    /// 0 keeps the island mostly black, 1 turns it to glass right below the row.
    let level: Double
    /// Closed, the island is glass as well (a display without a notch).
    var closedGlass = false
    /// The open island has the stem-and-body shape: then only the stem is black, and the glass
    /// starts right at the bottom of the menu bar, with a short melt under the stem whose depth
    /// follows the glass level (`GlassMelt`). Otherwise the black fades down from the row.
    var stemmed = false

    /// The least black left over the glass, so text always has a floor of contrast.
    static let smoke = GlassMelt.standardSmoke
    /// The stem-and-body look and the full-width one cross-fade over this, under the shell
    /// morphing between them (an approval card arriving on the open island, or answered).
    static let restyle = 0.3
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.shellClock) private var clock
    @Environment(\.islandMotion) private var motion
    @Environment(\.reduceMotionAnywhere) private var reduceMotion

    var body: some View {
        // A glass pill has no black to come and go: it stays glass, closed or open.
        let l = closedGlass ? GlassMelt.layers(expanded: expanded) : shellLayers(expanded: expanded, clock: clock)
        let black = closedGlass ? 0 : l.black
        let k = Motion.pace
        let off = motion == .off
        // Opening, the glass is there at once under the black, which melts away after a moment
        // (a glass pill has no black over it, so its open look fades in); closing, the black
        // comes back first, the glass fades under it, and the row's black goes last.
        let appear: Animation? = closedGlass ? .easeOut(duration: GlassMelt.melt * k) : nil
        let glassFade: Animation? = off ? nil : expanded ? appear : .linear(duration: GlassMelt.glassOut * k)
        let rowFade: Animation? = off ? nil : expanded ? appear
            : .easeIn(duration: GlassMelt.glassOut * k).delay(GlassMelt.unmelt * k)
        let blackFade: Animation? = off ? nil
            : expanded ? .easeOut(duration: GlassMelt.melt * k).delay(GlassMelt.meltDelay * k)
            : .easeIn(duration: GlassMelt.unmelt * k)
        let restyle: Animation? = off ? nil : .easeInOut(duration: Self.restyle * k)
        ZStack {
            GlassSurface(shape: shape, tint: Color.black.opacity(0.2), fallback: Color(white: 0.13).opacity(0.78))
                .animation(glassFade) { $0.opacity(closedGlass ? 1 : l.glass) }
            if closedGlass {
                // No hardware to match: glass under the same smoke, and no sheen on something
                // that is always there.
                shape.fill(Color.black.opacity(Self.smoke))
                    .animation(off ? nil : .easeInOut(duration: GlassMelt.melt * k)) { $0.opacity(expanded ? 0 : 1) }
            }
            // The stem-and-body look: the smoke over the glass, and the black melting a little
            // way down into it under the stem.
            ZStack {
                shape.fill(Color.black.opacity(GlassMelt.smoke(level: level)))
                StemMelt(stem: shape.stemWidth, row: row, depth: GlassMelt.depth(body: height - row, level: level))
                    .clipShape(shape)
            }
            .animation(restyle) { $0.opacity(stemmed ? 1 : 0) }
            .animation(glassFade) { $0.opacity(l.glass) }
            // The full-width look: black down to the row, then a fade to the smoke. Its black is
            // the row's, so it goes with the row's, once the black over the whole shape is back.
            shape.fill(LinearGradient(stops: Self.stops(row: row, height: height, level: level), startPoint: .top, endPoint: .bottom))
                .animation(restyle) { $0.opacity(stemmed ? 0 : 1) }
                .animation(rowFade) { $0.opacity(l.row) }
            // In the stem-and-body look the whole menu bar row is black, not just the stem: at
            // rest the shape is only the stem there, but while it morphs from a closed island or
            // a peek its shoulders haven't formed, and glass beside the notch would frame the
            // stem as a black box.
            Color.black.frame(height: row).frame(maxHeight: .infinity, alignment: .top).clipShape(shape)
                .animation(restyle) { $0.opacity(stemmed ? 1 : 0) }
                .animation(rowFade) { $0.opacity(l.row) }
            // An AppKit view, which offline snapshots can't draw. It drifts only while open.
            if !snapshotMode {
                GlassSheen(moving: expanded && !reduceMotion)
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .animation(glassFade) { $0.opacity(l.glass) }
            }
            shape.fill(Color.black)
                .animation(blackFade) { $0.opacity(black) }
        }
    }

    /// Black down to the row, then a fade to the smoke. The fade is short at level 1 and runs
    /// to the bottom at level 0.
    static func stops(row: CGFloat, height: CGFloat, level: Double) -> [Gradient.Stop] {
        guard height > row, height > 0 else { return [.init(color: .black, location: 0), .init(color: .black, location: 1)] }
        let body = height - row
        let span = max(14, body * CGFloat(1 - min(1, max(0, level))))
        let rowEnd = row / height
        let fadeEnd = min(1, (row + span) / height)
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: rowEnd),
            .init(color: .black.opacity(smoke), location: max(rowEnd, fadeEnd)),
            .init(color: .black.opacity(smoke), location: 1),
        ]
    }
}

/// The stem-and-body glass: the stem in the menu bar row is black, over the notch, and the
/// black melts a little way down into the glass right under it, fading to the sides as well,
/// so the body is glass from its top edge out to its shoulders.
private struct StemMelt: View {
    let stem: CGFloat
    let row: CGFloat
    let depth: CGFloat

    var body: some View {
        let width = stem + 2 * depth
        let side = depth / max(width, 1)
        // An overlay, so the melt never sizes the glass: while the stem is the island's whole
        // width (closed, or closing) the melt is wider than the island, and laid out it would
        // widen every layer beside it.
        Color.clear
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Color.black.frame(height: row)
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.55), location: 0.35),
                                           .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: width, height: depth)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: side),
                                                     .init(color: .black, location: 1 - side), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .offset(y: row)
                }
            }
            .allowsHitTesting(false)
    }
}

/// A faint diagonal reflection that drifts slowly across the glass while the island is open.
/// Core Animation runs it, so the app does no per-frame work. It stays still with Reduce
/// Motion; in Low Power Mode it drifts at a lower frame rate, like the island's other loops.
private struct GlassSheen: NSViewRepresentable {
    var moving: Bool

    func makeNSView(context: Context) -> GlassSheenView { GlassSheenView() }

    func updateNSView(_ view: GlassSheenView, context: Context) {
        view.setMoving(moving)
    }
}

final class GlassSheenView: NSView {
    private let sheen = CAGradientLayer()
    private var moving = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.06).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        sheen.locations = [0.35, 0.5, 0.65]
        sheen.startPoint = CGPoint(x: 0, y: 0.2)
        sheen.endPoint = CGPoint(x: 1, y: 0.8)
        layer?.addSublayer(sheen)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Wider than the island so the band can travel in from one side and out of the other.
        sheen.frame = bounds.insetBy(dx: -bounds.width * 0.6, dy: 0)
        CATransaction.commit()
    }

    func setMoving(_ on: Bool) {
        guard on != moving else { return }
        moving = on
        // Stopping (the island closing), the band stays where it had drifted to while the glass
        // fades, rather than jumping back to the middle.
        if !on, let here = sheen.presentation()?.locations {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sheen.locations = here
            CATransaction.commit()
        }
        sheen.removeAnimation(forKey: "drift")
        guard on else { return }
        let drift = CABasicAnimation(keyPath: "locations")
        drift.fromValue = [-0.3, -0.15, 0.0]
        drift.toValue = [1.0, 1.15, 1.3]
        drift.duration = 9
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        drift.capFrameRate()
        sheen.add(drift, forKey: "drift")
    }
}

/// Liquid Glass on macOS 26 and later, a blurred material before that, and a solid fill when
/// Reduce Transparency is on, when the island is hidden from screenshots, or when rendering
/// offline snapshots.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var tint: Color = .clear
    var fallback: Color = Color(white: 0.09)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.hiddenFromCapture) private var hiddenFromCapture

    var body: some View {
        if reduceTransparency || snapshotMode || hiddenFromCapture {
            shape.fill(fallback)
        } else if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(.ultraThinMaterial).overlay(shape.fill(tint))
        }
    }
}

// MARK: - Urgent glow

/// The urgent glow on the closed island: a soft rim just inside its sides and bottom, so it
/// stays in the menu bar row and never tints the status items beside it. It pulses a few times
/// to catch the eye, then holds; with less motion it simply holds.
struct InnerGlow: View {
    let shape: IslandShape
    let color: Color
    @Environment(\.reduceMotionAnywhere) private var reduceMotion
    @Environment(\.snapshotMode) private var snapshotMode
    @ViewState private var bright = false

    var body: some View {
        // A lit edge with a soft haze inside it: bright where it meets the edge, so it reads
        // as light rather than as a dull border.
        ZStack {
            IslandEdge(shape: shape).stroke(color.opacity(0.55), lineWidth: 10).blur(radius: 4)
            IslandEdge(shape: shape).stroke(color, lineWidth: 2).blur(radius: 0.5)
        }
        .clipShape(shape)
        .opacity(bright || snapshotMode ? 1 : 0.55)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion, !snapshotMode else {
                    bright = true
                    return
                }
                // An odd count, so the last swing lands on the steady glow.
                withAnimation(.easeInOut(duration: 0.9).repeatCount(5, autoreverses: true)) { bright = true }
            }
    }
}

/// Soft pulsing glow behind the island while something needs attention. Animated by
/// Core Animation (shadow opacity), so it costs the app no CPU per frame.
struct GlowPulse: NSViewRepresentable {
    var color: NSColor
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> GlowNSView { GlowNSView() }

    func updateNSView(_ view: GlowNSView, context: Context) {
        view.configure(color: color, cornerRadius: cornerRadius, animate: !context.environment.reduceMotionAnywhere)
    }
}

final class GlowNSView: NSView {
    private let glow = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        glow.backgroundColor = NSColor.clear.cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = 9
        glow.shadowOpacity = 0.35
        layer?.addSublayer(glow)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var radius: CGFloat = 12
    /// Pulse once per appearance; later SwiftUI updates leave the steady glow alone.
    private var didPulse = false

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        glow.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }

    func configure(color: NSColor, cornerRadius: CGFloat, animate: Bool) {
        glow.shadowColor = color.cgColor
        radius = cornerRadius
        needsLayout = true
        if animate, !didPulse {
            didPulse = true
            // A few pulses to catch the eye, then a steady glow: something left waiting
            // overnight shouldn't keep the window server busy. It starts and ends on the steady
            // glow, so it never jumps brighter when the pulse stops.
            let a = CAKeyframeAnimation(keyPath: "shadowOpacity")
            a.values = Self.pulse
            a.duration = Self.swing * Double(Self.pulse.count - 1)
            a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: Self.pulse.count - 1)
            a.capFrameRate()
            glow.shadowOpacity = Self.steady
            glow.add(a, forKey: "pulse")
        } else if !animate {
            glow.removeAnimation(forKey: "pulse")
            glow.shadowOpacity = Self.steady
        }
    }

    /// The glow it settles on.
    static let steady: Float = 0.5
    /// From the steady glow, swings bright and dim, and back to the steady glow: 10.8 s in all.
    static let pulse: [Float] = [steady] + (0..<11).map { $0.isMultiple(of: 2) ? 0.85 : 0.15 } + [steady]
    /// Each swing, bright to dim or back.
    static let swing: CFTimeInterval = 0.9
}

// MARK: - Activity appearance (smart icons + per-app rules)

@MainActor
extension AppModel {
    func icon(for a: Activity) -> ActivityIcon {
        if a.icon == nil, let rule = settings.rule(for: a.source), let icon = rule.icon { return icon }
        if a.icon == nil, settings.smartIcons, a.state != .success, a.state != .failure,
           a.source.contains("."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.source) != nil {
            return .app(bundleID: a.source)
        }
        return a.icon(smart: settings.smartIcons)
    }

    /// Lifted until it reads on the island's black (a brand black or navy would vanish).
    func tint(for a: Activity) -> Color {
        if a.tint == nil, let t = settings.rule(for: a.source)?.tint { return Color(tint: t).readableOnBlack }
        return Color(tint: a.tintName(smart: settings.smartIcons)).readableOnBlack
    }

    /// Accent for media UI: the user's choice, or derived from album art.
    func mediaAccent(_ np: NowPlaying?) -> Color {
        settings.accentColor == "auto" ? ArtworkCache.accent(for: np) : Color(tint: settings.accentColor)
    }

    /// The music's colour (Settings → Now Playing → Music colour): the playing indicator, the
    /// progress ring, and the open island's progress bar, shuffle and repeat. "Accent" follows
    /// the accent colour, which, set to "auto", means the artwork's colour here as everywhere else.
    func musicTint(_ np: NowPlaying?) -> Color {
        switch settings.musicColour {
        case .artwork: return ArtworkCache.accent(for: np)
        case .accent: return mediaAccent(np)
        case .white: return .white
        }
    }

    /// The colour of a volume, brightness or other HUD (Settings → Notifications & HUDs),
    /// lifted until it reads on black. With the accent on "auto" it takes the playing artwork's
    /// colour, and the Mac's accent colour when nothing with artwork is playing.
    func hudTint(_ kind: HUDKind) -> Color {
        switch settings.hudColour {
        case .white:
            return .white
        case .accent:
            if settings.accentColor != "auto" { return Color(tint: settings.accentColor).readableOnBlack }
            guard let np = closedNowPlaying, np.artworkData != nil else { return Color.accentColor.readableOnBlack }
            return ArtworkCache.accent(for: np).readableOnBlack
        case .colourful:
            return Color(tint: HUDColour.colourful(kind)).readableOnBlack
        }
    }

    /// The corner for artwork `size` points wide whose designed corner is `standard`
    /// (Settings → Appearance → Artwork corners).
    func artworkCorner(size: CGFloat, standard: CGFloat) -> CGFloat {
        CGFloat(settings.artworkCorner(size: Double(size), standard: Double(standard)))
    }

    /// Whether the given presentation deserves the urgent glow, and in which color.
    func urgentGlow(for p: IslandPresentation) -> Color? {
        guard settings.urgentGlow else { return nil }
        switch p {
        case .compact(.activity(let a, _)), .sneak(let a):
            if a.state == .waiting || a.priority == .critical || a.state == .failure && a.priority >= .high { return tint(for: a) }
        case .compact(.battery(let ev)) where ev.kind == .critical:
            return .red
        default:
            break
        }
        return nil
    }
}
