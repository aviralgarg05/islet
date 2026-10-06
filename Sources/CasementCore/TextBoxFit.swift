import CoreGraphics

/// How a box of text on an approval card fits the room it has. Text that fits makes the box
/// just as tall, and so does text short of the room by no more than some of its bottom
/// padding. Text that doesn't scrolls, and the box stops between two lines (when the lines
/// are all one height): the lines above the cut whole, and only the top of the next one,
/// fading out, below it. "More below" gets a strip of its own under the text only when at
/// least three whole lines still show beside it; a smaller box says so with the fade alone.
public struct TextBoxFit: Equatable, Sendable {
    /// Above the first line, and below the last.
    public static let pad: CGFloat = 8
    /// The least of the next line's top that shows under the whole ones.
    public static let peek: CGFloat = 3
    /// The strip under the text that holds "More below".
    public static let strip: CGFloat = 20

    /// The height for the text, the strip not included.
    public var text: CGFloat
    /// The text runs on past the box: it scrolls, and fades out at the bottom.
    public var overflows: Bool
    /// There is room for the "More below" strip.
    public var hint: Bool

    /// `content` is the text's whole height with `pad` above and below; `line` the height of
    /// one line, or 0 for text of mixed sizes.
    public init(content: CGFloat, room: CGFloat, line: CGFloat, pad: CGFloat = pad, strip: CGFloat = strip) {
        let room = max(0, room)
        // Only the bottom padding cut, and a little of it left: all the text shows.
        overflows = content > room + 0.5 && content - room > pad - Self.peek
        guard overflows else {
            text = min(content, max(room, content - pad + Self.peek))
            hint = false
            return
        }
        let lines = line > 0 ? line : 13
        hint = room - strip >= 2 * pad + 3 * lines
        let space = room - (hint ? strip : 0)
        if line > 0 {
            let whole = max(1, ((space - pad - Self.peek) / line).rounded(.down))
            text = min(space, pad + whole * line + pad)
        } else {
            text = space
        }
    }
}
