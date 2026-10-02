import Testing
@testable import IsletCore

/// Code in Settings wraps at spaces only, and copies exactly as it was written.
@Suite struct CodeWrapTests {
    private func lines(_ s: String) -> [Substring] { s.split(separator: CodeWrap.lineBreak, omittingEmptySubsequences: false) }

    @Test func pathsStayWhole() {
        let line = "ln -sf '/Applications/Islet.app/Contents/MacOS/isletctl' /opt/homebrew/bin/isletctl"
        let shown = CodeWrap.wrapped(line, columns: 72)
        // Both paths whole, the second on a line of its own; nothing broken at a slash.
        #expect(lines(shown) == ["ln -sf '/Applications/Islet.app/Contents/MacOS/isletctl'", "/opt/homebrew/bin/isletctl"])
        #expect(CodeWrap.copied(shown) == line)
    }

    @Test func wrappedLinesFitWithTheirIndent() {
        let line = "        \"command\" : \"/Applications/Islet.app/Contents/MacOS/isletctl hook claude --wait 300\","
        let columns = 60
        let shown = CodeWrap.wrapped(line, columns: columns)
        let indent = CodeWrap.hangingIndent(line[...], columns: columns)
        #expect(indent == 12)
        let pieces = lines(shown)
        #expect(pieces.count > 1)
        #expect(pieces[0].count <= columns)
        for piece in pieces.dropFirst() { #expect(indent + piece.count <= columns, "\(piece)") }
        #expect(!pieces.contains { $0.hasPrefix("/") && $0 != pieces.first && !$0.hasPrefix("/Applications") })
        #expect(CodeWrap.copied(shown) == line)
    }

    @Test func shortCodeAndOddWidthsAreLeftAlone() {
        let json = "{\n  \"type\" : \"command\"\n}"
        #expect(CodeWrap.wrapped(json, columns: 80) == json)
        // Too narrow to wrap sensibly: as it is.
        #expect(CodeWrap.wrapped("a b c d e f g h i j", columns: 4) == "a b c d e f g h i j")
        // A word longer than the line stays whole.
        let long = "x" + String(repeating: "y", count: 40) + " z"
        #expect(lines(CodeWrap.wrapped(long, columns: 20)) == [Substring("x" + String(repeating: "y", count: 40)), "z"])
        #expect(CodeWrap.wrapped("", columns: 40) == "")
    }

    @Test func copyingGivesBackTheCode() {
        let json = "{\n  \"command\" : \"/Applications/Islet.app/Contents/MacOS/isletctl hook claude\"\n}"
        for columns in [20, 30, 45, 200] {
            #expect(CodeWrap.copied(CodeWrap.wrapped(json, columns: columns)) == json)
        }
    }
}
