import AppKit
import IsletCore
import SwiftUI

// VoiceOver for the island. A group reads as one element with a label from `SpokenText`, and
// takes its value from the child that draws it: a countdown sets its value inside its own
// timeline, so it is read as it stands rather than as it was when the group last changed.
//
// Increase Contrast firms up the ink and washes (`IslandInk`, `IslandWash`, read through
// `IslandContrast`) and draws a clear edge round controls and boxes (`contrastEdge`); without it
// nothing changes.

extension View {
    /// One element for a group: `label` in place of what the children say, then `value`, or
    /// the values the children report when it is nil.
    func spokenGroup(_ label: String, value: String? = nil) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            // A checkmark glyph among the children would otherwise make the group "selected".
            .accessibilityRemoveTraits(.isSelected)
            .modifier(SpokenAttachment(value: value))
    }

    /// As `spokenGroup`, pressed like a button. With `isButton` false (a HUD, which a click
    /// doesn't open) it is read the same way but isn't a button.
    func spokenButton(_ label: String, value: String? = nil, hint: String? = nil, isButton: Bool = true,
                      action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isButton ? .isButton : [])
            .accessibilityRemoveTraits(.isSelected)
            .modifier(SpokenAttachment(value: value, hint: hint))
            .accessibilityAction { if isButton { action() } }
    }

    /// The value a group takes from this view: "4 minutes 32 seconds left". Nil adds nothing.
    func spokenValue(_ value: String?) -> some View {
        accessibilityElement(children: .combine).accessibilityValue(value ?? "")
    }

    /// A ring or bar as an element of its own: "Progress, 46%".
    func spokenProgress(_ fraction: Double?, label: String = "Progress") -> some View {
        accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(fraction.map(SpokenText.percent) ?? "in progress")
            .accessibilityAddTraits(.isImage)
    }

    /// A clear edge round a control or box with Increase Contrast; `normal` (nothing by
    /// default) without it.
    func contrastEdge<S: InsettableShape>(_ shape: S, normal: Color = .clear) -> some View {
        modifier(ContrastEdge(shape: shape, normal: normal))
    }
}

/// A label, value or hint set only when there is one, so the children's show through
/// otherwise. The view stays the same view either way: a modifier that is there one moment and
/// gone the next would make the island's row a new view, and lose its morph from one state to
/// the next, each time an activity's value came or went.
struct SpokenAttachment: ViewModifier {
    var label: String?
    var value: String?
    var hint: String?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .accessibilityLabel(label ?? "", isEnabled: label != nil)
                .accessibilityValue(value ?? "", isEnabled: value != nil)
                .accessibilityHint(hint ?? "", isEnabled: hint != nil)
        } else {
            // macOS 14 can't switch a modifier off: the label and value stay as given, so the
            // children's show through only where nothing is set at all.
            content
                .modifier(Macos14Label(label: label))
                .accessibilityValue(value ?? "")
                .accessibilityHint(hint ?? "")
        }
    }
}

/// On macOS 14, a label only where there is one. Only a glance passes nil, and it switches
/// only when its activity gains or loses a button, not as values tick.
private struct Macos14Label: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

extension AppModel {
    /// What VoiceOver says for the closed island: "Claude, islet, waiting for you".
    /// - Parameter counted: other activities the wing counts ("+2").
    func spokenLabel(for p: IslandPresentation, counted: Int = 0) -> String {
        let more = counted > 0 ? ", \(counted) more" : ""
        switch p {
        case .compact(.activity(let a, _)): return SpokenText.label(a) + more
        case .compact(.nowPlaying(let np)): return SpokenText.media(np) + more
        case .songPeek(let np): return "Now playing, " + SpokenText.media(np)
        case .compact(.battery(let ev)): return "Battery"
            + (ev.kind == .low || ev.kind == .critical ? ", low" : ev.kind == .lowPowerOn ? ", Low Power Mode on" : "")
        case .compact(.sticker): return "Islet"
        case .sneak(let a): return SpokenText.label(a, detail: true)
        case .hud(let h): return SpokenText.hud(h).label
        case .hidden, .idle, .expanded: return "Islet"
        }
    }

    /// The closed island's value when no child draws one; nil lets an activity's own value through.
    func spokenValue(for p: IslandPresentation) -> String? {
        switch p {
        case .compact(.nowPlaying(let np)): return np.isPlaying ? "playing" : "paused"
        case .compact(.battery(let ev)):
            return SpokenText.battery(level: ev.state.level, charging: ev.state.isCharging, pluggedIn: ev.state.isPluggedIn)
        case .hud(let h): return SpokenText.hud(h).value
        default: return nil
        }
    }
}

extension IslandBubble {
    /// "Release build", with how many more are hidden behind the last bubble.
    func spokenLabel(overflow: Int) -> String {
        let label: String
        switch self {
        case .media(let np): label = SpokenText.media(np)
        case .activity(let a): label = SpokenText.label(a)
        }
        return label + (overflow > 0 ? ", \(overflow) more" : "")
    }

    /// Media says whether it plays; an activity's value comes from the bubble's drawing.
    var spokenValue: String? {
        if case .media(let np) = self { return np.isPlaying ? "playing" : "paused" }
        return nil
    }
}

// MARK: - Increase Contrast

/// Increase Contrast as the island's ink reads it. SwiftUI doesn't pass the setting on to the
/// colours themselves, so the app sets this at launch and when the setting changes, and then
/// draws the island afresh; the snapshots set it for the shots that stand in for it. Views
/// that only need an edge read `colorSchemeContrast` instead.
@MainActor
enum IslandContrast {
    static var increased = false
}

extension Color {
    /// White at `normal` opacity, or at `increased` while Increase Contrast is on.
    @MainActor
    static func islandWhite(_ normal: Double, increased: Double) -> Color {
        .white.opacity(IslandContrast.increased ? increased : normal)
    }

    @MainActor
    static func island(_ ink: IslandInk) -> Color {
        .white.opacity(ink.opacity(increasedContrast: IslandContrast.increased))
    }

    @MainActor
    static func island(_ wash: IslandWash) -> Color {
        .white.opacity(wash.opacity(increasedContrast: IslandContrast.increased))
    }
}

/// The edge round a control or box: `normal` by default, a clear line with Increase Contrast.
struct ContrastEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    var normal: Color = .clear
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            shape.strokeBorder(contrast == .increased ? Wash.edge : normal, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
