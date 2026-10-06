import Foundation

/// Which rows of a list fit the room a page gives it, and how many a quiet "+3 more" line
/// counts when they don't all fit, as the closed island counts what it can't show. A list
/// never drops rows without saying so.
public enum ListFit {
    /// The "+3 more" line: its height and the gap above it.
    public static let moreHeight: Double = 12
    public static let moreGap: Double = 4

    public struct Result: Equatable, Sendable {
        /// Rows drawn, from the top.
        public var shown: Int
        /// Rows the "+N more" line counts; 0 when every row is drawn and there is no line.
        public var more: Int

        public init(shown: Int, more: Int) {
            self.shown = shown
            self.more = more
        }
    }

    /// - Parameters:
    ///   - heights: each row's height, in order.
    ///   - spacing: the gap between two rows.
    ///   - room: the height the list may take.
    ///   - slack: how far past `room` the last line may reach (heights are estimates).
    public static func fit(_ heights: [Double], spacing: Double, in room: Double, slack: Double = 2) -> Result {
        func height(of count: Int) -> Double {
            guard count > 0 else { return 0 }
            return heights.prefix(count).reduce(0, +) + Double(count - 1) * spacing
        }
        if height(of: heights.count) <= room + slack { return Result(shown: heights.count, more: 0) }
        // The rows that leave room for the line under them.
        var shown = heights.count - 1
        while shown > 0, height(of: shown) + moreGap + moreHeight > room + slack { shown -= 1 }
        return Result(shown: shown, more: heights.count - shown)
    }

    /// The line's words: "+3 more".
    public static func moreText(_ count: Int) -> String { "+\(count) more" }
}

/// A glance's title, split so the part that matters stays whole: "Grey Prius · 7ABC123" keeps
/// the plate and lets "Grey Prius" truncate. The part after the last " · " is kept when it is
/// short; anything longer, or a title without one, truncates as a whole.
public enum GlanceTitle {
    /// The longest kept part, in characters.
    public static let longestTail = 16

    /// (the part that may truncate, the part kept whole with its " · ", or nil).
    public static func split(_ title: String) -> (head: String, tail: String?) {
        guard let range = title.range(of: " · ", options: .backwards), range.lowerBound > title.startIndex else {
            return (title, nil)
        }
        let tail = title[range.upperBound...]
        guard !tail.trimmingCharacters(in: .whitespaces).isEmpty, tail.count <= longestTail else { return (title, nil) }
        return (String(title[..<range.lowerBound]), String(title[range.lowerBound...]))
    }
}
