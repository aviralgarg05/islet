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
    /// Every duration below is scaled by "Animation speed" (`Motion.pace`).
    private var k: Double { Motion.pace }

    /// Shape morphing between island states (expanding).
    var morph: Animation? {
        switch self {
        case .fluid: return Motion.open
        case .snappy: return .snappy(duration: 0.26 * k, extraBounce: 0.04)
        case .smooth: return .smooth(duration: 0.38 * k)
        case .minimal: return .easeInOut(duration: 0.16 * k)
        case .off: return nil
        }
    }

    /// Collapsing is quicker and settles without overshoot.
    var collapse: Animation? {
        switch self {
        case .fluid: return Motion.close
        case .snappy: return .snappy(duration: 0.22 * k)
        case .smooth: return .smooth(duration: 0.3 * k)
        case .minimal: return .easeInOut(duration: 0.14 * k)
        case .off: return nil
        }
    }

    /// How content enters and leaves.
    var contentTransition: AnyTransition {
        switch self {
        case .fluid, .smooth:
            return .asymmetric(
                insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.94, anchor: .top))
                    .animation(.easeOut(duration: 0.26 * k).delay(0.05 * k)),
                removal: .opacity.animation(.easeIn(duration: 0.08 * k))
            )
        case .snappy:
            return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.14 * k).delay(0.03 * k)),
                               removal: .opacity.animation(.linear(duration: 0.06 * k)))
        case .minimal:
            return .opacity
        case .off:
            return .identity
        }
    }

    var bounces: Bool { self == .fluid || self == .snappy }
}

// MARK: - Theme

extension IslandTheme {
    /// Fill for the island in a given presentation. Closed states stay black so they merge
    /// with the hardware notch; themes only change the expanded surface.
    /// - Parameters:
    ///   - row: height of the menu bar row, which stays black in every theme.
    ///   - height: the island's current height, to place the seam below that row.
    ///   - closedGlass: the closed island is glass too ("Glass on displays without a notch").
    @ViewBuilder
    func background(expanded: Bool, shape: IslandShape, row: CGFloat = 0, height: CGFloat = 0, glassLevel: Double = 0.6,
                    closedGlass: Bool = false) -> some View {
        switch self {
        case .graphite where expanded:
            shape.fill(Color(white: 0.105)).overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        case .glass:
            GlassBody(shape: shape, expanded: expanded, row: row, height: height, level: glassLevel, closedGlass: closedGlass)
        default:
            shape.fill(Color.black)
        }
    }
}

/// "Subtle outline": a faint edge round the island so black shows on a dark wallpaper. The
/// system's Increase Contrast always draws it, firmer. The top edge, at the top of the screen,
/// is left out.
struct IslandOutline: View {
    let shape: IslandShape
    let on: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        if on || increased {
            IslandEdge(shape: shape)
                .stroke(Color.white.opacity(increased ? 0.25 : 0.14), lineWidth: increased ? 1 : 0.75)
                .allowsHitTesting(false)
        }
    }
}

/// Dynamic Glass: one piece of Liquid Glass that is black where it meets the notch and melts
/// into glass below the menu bar row. Beside the hardware notch glass would show the wallpaper
/// at the notch's edges, so the row stays black. A faint smoke stays under the content so text
/// never loses contrast, and a slow sheen drifts across while the island is open.
///
/// The glass fades in once the island has grown clear of the notch, and the black comes back
/// first when it closes.
private struct GlassBody: View {
    let shape: IslandShape
    let expanded: Bool
    let row: CGFloat
    let height: CGFloat
    /// 0 keeps the island mostly black, 1 turns it to glass right below the row.
    let level: Double
    /// Closed, the island is glass as well (a display without a notch).
    var closedGlass = false

    /// The least black left over the glass, so text always has a floor of contrast.
    static let smoke = 0.3
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        ZStack {
            if expanded {
                GlassSurface(shape: shape, tint: Color.black.opacity(0.2), fallback: Color(white: 0.13).opacity(0.78))
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0.12))))
                shape.fill(LinearGradient(stops: Self.stops(row: row, height: height, level: level), startPoint: .top, endPoint: .bottom))
                // An AppKit view, which offline snapshots can't draw.
                if !snapshotMode { GlassSheen().clipShape(shape).allowsHitTesting(false) }
            } else if closedGlass {
                // No hardware to match: glass under the same smoke, and no sheen on something
                // that is always there.
                GlassSurface(shape: shape, tint: Color.black.opacity(0.2), fallback: Color(white: 0.13).opacity(0.78))
                shape.fill(Color.black.opacity(Self.smoke))
            }
            shape.fill(Color.black)
                .opacity(expanded || closedGlass ? 0 : 1)
                .animation(expanded ? .easeOut(duration: 0.18 * Motion.pace).delay(0.15 * Motion.pace)
                                    : .easeIn(duration: 0.08 * Motion.pace), value: expanded)
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

/// A faint diagonal reflection that drifts slowly across the glass. Core Animation runs it, so
/// the app does no per-frame work. It stays still with Reduce Motion and in Low Power Mode.
private struct GlassSheen: NSViewRepresentable {
    @Environment(\.reduceMotionAnywhere) private var reduceMotion

    func makeNSView(context: Context) -> GlassSheenView { GlassSheenView() }

    func updateNSView(_ view: GlassSheenView, context: Context) {
        view.setMoving(!reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
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
/// Reduce Transparency is on or when rendering offline snapshots.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var tint: Color = .clear
    var fallback: Color = Color(white: 0.09)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if reduceTransparency || snapshotMode {
            shape.fill(fallback)
        } else if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(.ultraThinMaterial).overlay(shape.fill(tint))
        }
    }
}

// MARK: - Urgent glow

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
            let a = CABasicAnimation(keyPath: "shadowOpacity")
            a.fromValue = 0.15
            a.toValue = 0.85
            a.duration = 0.9
            a.autoreverses = true
            // A few pulses to catch the eye, then a steady glow: something left waiting
            // overnight shouldn't keep the window server busy.
            a.repeatCount = 6
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.capFrameRate()
            glow.shadowOpacity = 0.5
            glow.add(a, forKey: "pulse")
        } else if !animate {
            glow.removeAnimation(forKey: "pulse")
            glow.shadowOpacity = 0.5
        }
    }
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
            guard let np = nowPlaying, np.artworkData != nil else { return Color.accentColor.readableOnBlack }
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
