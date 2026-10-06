import Foundation

/// The Now Playing helper's output cut into its JSON lines, however the pipe delivers it.
///
/// A helper can exit part-way through a line (an artwork line takes several reads), or leave the
/// end of one unread when it goes. `reset` drops such a line before the next helper starts, so it
/// can't run into that helper's first line, which says it is up, and spoil both. An unfinished
/// line longer than `limit` is dropped whole, so a runaway helper can't grow memory without bound.
public struct HelperLines: Sendable {
    public let limit: Int
    private var pending = Data()
    /// The rest of a line too long to keep is still to come, and goes too.
    private var dropping = false

    public init(limit: Int = 8 * 1024 * 1024) {
        self.limit = limit
    }

    /// The lines `data` completes, without their newlines.
    public mutating func append(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var rest = data[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            if dropping {
                dropping = false
            } else {
                pending.append(rest[rest.startIndex..<newline])
                lines.append(pending)
            }
            pending = Data()
            rest = rest[rest.index(after: newline)...]
        }
        if !dropping { pending.append(rest) }
        if pending.count > limit {
            pending = Data()
            dropping = true
        }
        return lines
    }

    /// Drops an unfinished line: whatever was writing it has gone.
    public mutating func reset() {
        pending = Data()
        dropping = false
    }
}
