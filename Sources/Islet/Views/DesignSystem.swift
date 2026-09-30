import AppKit
import IsletCore
import SwiftUI

// The island's design tokens: spacing, corners, type, ink on black and motion. Views take
// their numbers from here rather than inventing their own, so the island reads as one object.
//
// Rules of thumb:
// - The shell is the background. Content sits straight on it: no bordered cards, no boxes in
//   boxes. Group with space and, at most, a hairline.
// - Everything is on a 4 pt grid. `Space.hair` (2) is only for the gap inside a text stack.
// - Corners are continuous, and a shape inset in another is concentric with it
//   (`Radius.concentric`).
// - One primary thing per view gets `title` or `display`; everything else is `body` or quieter.

/// Spacing on a 4 pt grid.
enum Space {
    /// Between two lines of one text stack (title and subtitle). Nothing else.
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Corner radii. Every rounded rectangle on the island uses `.continuous` corners.
enum Radius {
    /// Bars, keylines, the smallest marks.
    static let xs: CGFloat = 4
    /// Hover washes, code boxes, small tiles.
    static let s: CGFloat = 8
    /// Artwork, file tiles, the drop zone: the shell's corner less the content inset.
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    /// The expanded island's bottom corners.
    static let shell: CGFloat = 32
    /// The expanded island's outward flare where it meets the top of the screen.
    static let flare: CGFloat = 14

    /// The corner for a shape inset `inset` inside one with `outer` corners, so the two curves
    /// stay parallel.
    static func concentric(_ outer: CGFloat, inset: CGFloat) -> CGFloat { max(xs, outer - inset) }
}

/// Text and glyph colours on the island's black (or dark glass). A ladder, not a palette:
/// each step is quieter than the one before.
enum Ink {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.42)
    /// Disabled glyphs and the faintest labels.
    static let quaternary = Color.white.opacity(0.24)
}

/// Fills on the island. Deliberately not adaptive: on the black shell they must never turn dark.
enum Wash {
    /// Hover, and the track under a bar.
    static let subtle = Color.white.opacity(0.06)
    /// A control at rest.
    static let regular = Color.white.opacity(0.10)
    /// Selected or pressed.
    static let strong = Color.white.opacity(0.16)
    /// Dividers and keylines.
    static let hairline = Color.white.opacity(0.09)
}

/// Five text styles. `emphasized` is the same size one weight heavier; `numeric` switches to
/// rounded, tabular digits so ticking values don't jitter.
enum TextStyle {
    /// 28 pt: the one big number (the clock, a timer).
    case display
    /// 15 pt semibold: the primary item's name.
    case title
    /// 13 pt semibold: section and row titles.
    case headline
    /// 12 pt: most text.
    case body
    /// 11 pt: times, captions, small buttons.
    case caption

    var size: CGFloat {
        switch self {
        case .display: return 28
        case .title: return 15
        case .headline: return 13
        case .body: return 12
        case .caption: return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title, .headline: return .semibold
        case .body: return .regular
        case .caption: return .medium
        }
    }

    func font(emphasized: Bool = false, numeric: Bool = false) -> Font {
        let w: Font.Weight = emphasized ? (weight == .regular ? .semibold : weight == .medium ? .semibold : .bold) : weight
        return .system(size: size, weight: w, design: numeric || self == .display ? .rounded : .default)
    }
}

extension View {
    /// Applies one of the island's text styles (and tabular digits for `numeric`).
    func textStyle(_ style: TextStyle, emphasized: Bool = false, numeric: Bool = false) -> some View {
        font(style.font(emphasized: emphasized, numeric: numeric))
            .monospacedDigit()
    }
}

/// One spring family for everything that moves on the island. Opening is lively; closing
/// starts quicker and settles without overshoot. Small in-place changes (the page highlight
/// sliding, a row arriving) use `settle`, the same spring with a shorter response.
enum Motion {
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.80)
    static let close = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// Pressed controls give a little.
    static let pressScale: CGFloat = 0.94
}

/// Where things sit inside the expanded island.
struct ExpandedLayout {
    let metrics: IslandMetrics

    /// The menu bar row, level with the hardware notch. It stays black in every theme.
    var row: CGFloat { max(metrics.notch.height, 28) }
    /// Content inset from the shell's sides. Shell corner − inset = `Radius.m`.
    static let inset: CGFloat = Space.xl
    /// Gap between the menu bar row and the content.
    static let top: CGFloat = Space.m
    /// Content inset from the shell's bottom. A little less than the sides: controls along the
    /// bottom carry their own hit area, so they already sit optically higher.
    static let bottom: CGFloat = Space.l

    /// The area left for a page's content.
    var content: CGSize {
        CGSize(width: metrics.expanded.width - 2 * Self.inset,
               height: metrics.expanded.height - row - Self.top - Self.bottom)
    }
}

// MARK: - Shared controls

/// A round, borderless icon button: a wash appears on hover and it gives a little when pressed.
struct IconButton: View {
    let symbol: String
    let help: String
    /// Diameter of the hit area and hover wash.
    var size: CGFloat = 28
    var glyph: CGFloat = 12
    var ink: Color = Ink.secondary
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(HoverButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A small text capsule. Without a tint it is a quiet white wash. With one it is a wash of that
/// colour with tinted text (0.18 at rest, 0.24 under the pointer, 0.30 pressed); `filled` makes
/// it solid, for the one primary action in a view.
struct CapsuleButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var filled = false
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.caption.font(emphasized: true))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Space.m)
            .frame(height: 24)
            .background(Capsule().fill(fill(pressed: configuration.isPressed)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.settle, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }

    private var ink: Color {
        guard let tint else { return Ink.primary }
        return filled ? .white : tint.readableOnBlack
    }

    private func fill(pressed: Bool) -> Color {
        guard let tint else { return pressed || hovering ? Wash.strong : Wash.regular }
        if filled { return tint.opacity(pressed ? 0.62 : hovering ? 0.95 : 0.82) }
        return tint.opacity(pressed ? 0.30 : hovering ? 0.24 : 0.18)
    }
}

/// A caption-sized section label in sentence case, with an optional count.
struct SectionLabel: View {
    let title: String
    var count: Int = 0

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(title).foregroundStyle(Ink.tertiary)
            if count > 0 { Text("\(count)").foregroundStyle(Ink.secondary) }
        }
        .textStyle(.caption, emphasized: true, numeric: true)
        .lineLimit(1)
    }
}

/// A one-point vertical rule between two columns.
struct ColumnRule: View {
    var body: some View {
        Rectangle().fill(Wash.hairline).frame(width: 1)
    }
}

/// Liquid Glass for controls that float over the desktop (the page switcher). A dark fill in
/// snapshots, with Reduce Transparency and before macOS 26.
struct FloatingGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.snapshotMode) private var snapshotMode

    func body(content: Content) -> some View {
        if reduceTransparency || snapshotMode {
            content
                .background(shape.fill(Color(white: 0.07).opacity(0.92)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.35)).interactive(), in: shape)
        } else {
            content
                .background(shape.fill(Color.black.opacity(0.35)))
                .background(shape.fill(.ultraThinMaterial))
        }
    }
}

extension View {
    func floatingGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(FloatingGlass(shape: shape)) }
}

/// Groups floating glass shapes so they sample the desktop once and merge as they move.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
