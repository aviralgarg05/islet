import Testing
@testable import CasementCore

/// Code in Settings wraps at spaces only, and copies exactly as it was written.
@Suite struct CodeWrapTests {
    private func lines(_ s: String) -> [Substring] { s.split(separator: CodeWrap.lineBreak, omittingEmptySubsequences: false) }

    @Test func pathsStayWhole() {
        let line = "ln -sf '/Applications/Casement.app/Contents/MacOS/casementctl' /opt/homebrew/bin/casementctl"
        let shown = CodeWrap.wrapped(line, columns: 72)
        // Both paths whole, the second on a line of its own; nothing broken at a slash.
        #expect(lines(shown) == ["ln -sf '/Applications/Casement.app/Contents/MacOS/casementctl'", "/opt/homebrew/bin/casementctl"])
        #expect(CodeWrap.copied(shown) == line)
    }

    @Test func wrappedLinesFitWithTheirIndent() {
        let line = "        \"command\" : \"/Applications/Casement.app/Contents/MacOS/casementctl hook claude --wait 300\","
        let columns = 60
        let shown = CodeWrap.wrapped(line, columns: columns)
        let indent = CodeWrap.hangingIndent(line[...], columns: columns)
        #expect(indent == 12)
        let pieces = lines(shown)
        #expect(pieces.count > 1)
        #expect(pieces[0].count <= columns)
        // A piece that is one unbreakable token can exceed the width: `CodeWrap` leaves a word
        // longer than a line whole rather than splitting it, which is why the path is not broken at
        // a slash. That carve-out is the point of the wrapper, so only pieces that COULD have been
        // broken are held to the width. This assertion used to hold for every piece, but only
        // because /Applications/Islet.app/Contents/MacOS/isletctl was 47 characters and fitted the
        // 48 available; the same path under the current name is 53 and cannot.
        for piece in pieces.dropFirst() where piece.contains(" ") {
            #expect(indent + piece.count <= columns, "\(piece)")
        }
        // And anything that DOES exceed the width must be unbreakable, so the wrapper is never
        // just giving up on a line it could have split.
        for piece in pieces.dropFirst() where indent + piece.count > columns {
            #expect(!piece.contains(" "), "over-wide piece that could have been split: \(piece)")
        }
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
        let json = "{\n  \"command\" : \"/Applications/Casement.app/Contents/MacOS/casementctl hook claude\"\n}"
        for columns in [20, 30, 45, 200] {
            #expect(CodeWrap.copied(CodeWrap.wrapped(json, columns: columns)) == json)
        }
    }
}
