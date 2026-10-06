import Foundation

/// How code in Settings wraps: only at spaces, so a path like
/// `/Applications/Casement.app/Contents/MacOS/casementctl` moves to the next line whole rather than
/// splitting at a slash, and a wrapped line goes on a little further in than it started.
///
/// Text layout would break at slashes too, so the code is wrapped here, for a monospaced font
/// `columns` characters wide: each space a line breaks at becomes a line separator (U+2028),
/// which keeps the line one paragraph, so its hanging indent applies. Copying turns the
/// separators back into spaces.
public enum CodeWrap {
    /// U+2028, which ends a line without ending the paragraph.
    public static let lineBreak: Character = "\u{2028}"

    /// How far in, in characters, the rest of a wrapped `line` goes: a little past its own indent.
    public static func hangingIndent(_ line: Substring, columns: Int) -> Int {
        min(line.prefix { $0 == " " }.count + 4, 24, max(0, columns / 2))
    }

    /// `code` with the spaces its lines wrap at, `columns` characters wide, turned into line
    /// separators. A word longer than a line is left whole.
    public static func wrapped(_ code: String, columns: Int) -> String {
        guard columns > 8 else { return code }
        return code.split(separator: "\n", omittingEmptySubsequences: false)
            .map { wrap($0, columns: columns) }
            .joined(separator: "\n")
    }

    private static func wrap(_ line: Substring, columns: Int) -> String {
        var chars = Array(line)
        let indent = hangingIndent(line, columns: columns)
        // Where the line on screen starts, and the columns before it there (its indent).
        var start = 0, before = 0
        var lastSpace: Int?
        var i = chars.prefix { $0 == " " }.count
        while i < chars.count {
            if chars[i] == " " { lastSpace = i }
            if before + (i - start + 1) > columns, let space = lastSpace, space > start {
                chars[space] = lineBreak
                start = space + 1
                before = indent
                lastSpace = nil
                continue
            }
            i += 1
        }
        return String(chars)
    }

    /// Text as copied: the code, with its spaces back.
    public static func copied(_ shown: String) -> String {
        String(shown.map { $0 == lineBreak ? " " : $0 })
    }
}
