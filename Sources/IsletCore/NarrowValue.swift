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

/// The leading glyph and the count of other activities beside it ("+2") in a closed wing: both
/// at the glyph's size when they fit, else the glyph a little smaller and closer to the count,
/// else the glyph alone (nothing goes under the notch, where it can't be seen). One answer for
/// the wing, so the glyph keeps its place and identity as the count comes and goes, and the
/// count changes in place instead of swapping with the glyph.
public enum WingCount {
    /// How much smaller the glyph may be drawn to make room for the count, in turn.
    public static let shrinks: [CGFloat] = [0, 3, 5, 8]
    /// The smallest the glyph is ever drawn.
    public static let smallest: CGFloat = 8

    public struct Fit: Equatable, Sendable {
        /// The glyph's size.
        public var size: CGFloat
        /// The space between the glyph and the count.
        public var gap: CGFloat
        /// Whether the count is shown.
        public var counts: Bool

        public init(size: CGFloat, gap: CGFloat, counts: Bool) {
            self.size = size
            self.gap = gap
            self.counts = counts
        }
    }

    /// - Parameters:
    ///   - room: the wing's room for its content.
    ///   - size: the glyph's size with no count.
    ///   - extra: how much wider than its size the glyph is drawn (a ring round a timer).
    ///   - count: the count's width, or 0 with nothing to count.
    ///   - gap: the space before the count at the full size; `tightGap` once the glyph shrinks.
    public static func fit(room: CGFloat, size: CGFloat, extra: CGFloat = 0, count: CGFloat,
                           gap: CGFloat, tightGap: CGFloat) -> Fit {
        guard count > 0 else { return Fit(size: size, gap: gap, counts: false) }
        for shrink in shrinks {
            let s = max(smallest, size - shrink)
            let g = shrink == 0 ? gap : tightGap
            if s + extra + g + count <= room + 0.5 { return Fit(size: s, gap: g, counts: true) }
            if s == smallest { break }
        }
        return Fit(size: size, gap: gap, counts: false)
    }
}
