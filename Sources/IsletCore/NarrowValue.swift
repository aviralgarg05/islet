import Foundation

/// How a value is shown when the closed island's wing is narrow: words become a glyph, numbers
/// shrink.
public enum NarrowValue {
    /// Below this width a long word no longer reads, so it becomes a glyph.
    public static let wordRoom: CGFloat = 34

    /// A glyph for a status word ("Waiting", "Done", "Failed") or for no word at all; nil for
    /// anything with digits, and for a word of three letters or fewer ("Now", "On"), which fits
    /// as well as a number does: a meeting that has started says "Now", not a symbol that could
    /// mean anything waiting.
    public static func glyph(for text: String, state: ActivityState) -> String? {
        guard !text.contains(where: \.isNumber) else { return nil }
        if !text.isEmpty, text.count <= 3 { return nil }
        switch state {
        case .waiting: return "exclamationmark.bubble.fill"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .running: return "ellipsis"
        case .info: return text.isEmpty ? nil : "info.circle.fill"
        }
    }
}
