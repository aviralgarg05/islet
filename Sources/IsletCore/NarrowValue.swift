import Foundation

/// How a value is shown when the closed island's wing is narrow: words become a glyph, numbers
/// take their short form ("18m"), and nothing is ever shrunk or cut.
public enum NarrowValue {
    /// Below this width a long word no longer reads, so it becomes a glyph.
    public static let wordRoom: CGFloat = 34

    /// The glyph for work under way. The wing draws it as a small spinner, since three dots
    /// read as text that was cut short.
    public static let working = "ellipsis"

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
        case .running: return working
        case .info: return text.isEmpty ? nil : "info.circle.fill"
        }
    }

    /// Whether `glyph` would only repeat the activity's own symbol on the other side of the
    /// notch: the same mark, whatever its shape or fill ("checkmark.circle.fill" beside
    /// "checkmark.seal"). The wing then shows nothing rather than the same thing twice.
    public static func repeats(_ glyph: String, leading symbol: String?) -> Bool {
        guard let symbol, glyph != working else { return false }
        func mark(_ name: String) -> Substring { name.split(separator: ".").first ?? Substring(name) }
        return mark(glyph) == mark(symbol)
    }
}

extension ActivityIcon {
    /// A round dial (a timer, stopwatch or clock face). Inside a countdown ring it would be a
    /// circle in a circle, so the ring stands alone.
    public var isDial: Bool {
        guard case .symbol(let name) = self else { return false }
        return ["timer", "stopwatch", "clock", "alarm", "deskclock"].contains { name == $0 || name.hasPrefix($0 + ".") }
    }
}
