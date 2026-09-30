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
    /// Shape morphing between island states (expanding).
    var morph: Animation? {
        switch self {
        case .fluid: return .spring(response: 0.42, dampingFraction: 0.78)
        case .snappy: return .snappy(duration: 0.26, extraBounce: 0.04)
        case .smooth: return .smooth(duration: 0.38)
        case .minimal: return .easeInOut(duration: 0.16)
        case .off: return nil
        }
    }

    /// Collapsing is quicker and settles without overshoot.
    var collapse: Animation? {
        switch self {
        case .fluid: return .spring(response: 0.34, dampingFraction: 0.92)
        case .snappy: return .snappy(duration: 0.22)
        case .smooth: return .smooth(duration: 0.3)
        case .minimal: return .easeInOut(duration: 0.14)
        case .off: return nil
        }
    }

    /// How content enters and leaves.
    var contentTransition: AnyTransition {
        switch self {
        case .fluid, .smooth:
            return .asymmetric(
                insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.94, anchor: .top)).animation(.easeOut(duration: 0.26).delay(0.05)),
                removal: .opacity.animation(.easeIn(duration: 0.08))
            )
        case .snappy:
            return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.14).delay(0.03)), removal: .opacity.animation(.linear(duration: 0.06)))
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
    @ViewBuilder
    func background(expanded: Bool, shape: IslandShape, row: CGFloat = 0, height: CGFloat = 0) -> some View {
        switch self {
        case .graphite where expanded:
            shape.fill(Color(white: 0.105)).overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        case .glass:
            GlassBody(shape: shape, expanded: expanded, row: row, height: height)
        default:
            shape.fill(Color.black)
        }
    }
}

/// The Glass theme's surface. Glass sits only below the menu bar row: beside the hardware notch
/// it would show the wallpaper at the notch's edges. It fades in once the island has grown
/// clear of the notch and the black comes back first when it closes.
private struct GlassBody: View {
    let shape: IslandShape
    let expanded: Bool
    let row: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if expanded {
                GlassSurface(shape: shape, tint: Color.black.opacity(0.5))
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0.12))))
                if row > 0, height > row + 14 {
                    shape.fill(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: row / height),
                        .init(color: .black.opacity(0), location: (row + 14) / height),
                    ], startPoint: .top, endPoint: .bottom))
                }
            }
            shape.fill(Color.black)
                .opacity(expanded ? 0 : 1)
                .animation(expanded ? .easeOut(duration: 0.18).delay(0.15) : .easeIn(duration: 0.08), value: expanded)
        }
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

extension View {
    /// Background for a card inside the expanded island. On the Glass theme it is a plain
    /// translucent fill with a hairline, not more glass: glass can't sample glass behind it,
    /// and every glass card would cost another sampling pass.
    func islandCard(_ theme: IslandTheme, cornerRadius: CGFloat = 12) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if theme == .glass {
                shape.fill(Color.white.opacity(0.07)).overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            } else {
                shape.fill(Color.islandFill)
            }
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
        view.configure(color: color, cornerRadius: cornerRadius, animate: !context.environment.accessibilityReduceMotion)
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
        if animate, glow.animation(forKey: "pulse") == nil {
            let a = CABasicAnimation(keyPath: "shadowOpacity")
            a.fromValue = 0.15
            a.toValue = 0.85
            a.duration = 0.9
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(a, forKey: "pulse")
        } else if !animate {
            glow.removeAnimation(forKey: "pulse")
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

    func tint(for a: Activity) -> Color {
        if a.tint == nil, let t = settings.rule(for: a.source)?.tint { return Color(tint: t) }
        return Color(tint: a.tintName(smart: settings.smartIcons))
    }

    /// Accent for media UI: the user's choice, or derived from album art.
    func mediaAccent(_ np: NowPlaying?) -> Color {
        settings.accentColor == "auto" ? ArtworkCache.accent(for: np) : Color(tint: settings.accentColor)
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
