import Foundation
import Testing
@testable import IsletCore

/// The helper's output arrives in pieces: its lines come out whole, and a line a helper left
/// unfinished never joins the next helper's first.
@Suite struct HelperLinesTests {
    static func bytes(_ text: String) -> Data { Data(text.utf8) }

    static let ready = bytes(#"{"type":"ready"}"#)
    static let players = bytes(#"{"type":"players","players":[]}"#)

    @Test func linesSplitAcrossReadsComeOutWhole() {
        var lines = HelperLines()
        #expect(lines.append(Self.bytes(#"{"type":"rea"#)).isEmpty)
        #expect(lines.append(Self.bytes("dy\"}\n{\"type\":\"players\",\"players\":[]}\n{\"type\":\"pl")) == [Self.ready, Self.players])
        #expect(lines.append(Self.bytes("ayers\",\"players\":[]}\n")) == [Self.players])
        #expect(lines.append(Data()).isEmpty)
    }

    /// The helper exited part-way through a long artwork line and was started again. Joined to
    /// what was left, the new helper's "ready" was lost, and Islet went on treating Now Playing
    /// as failed while it worked.
    @Test func anUnfinishedLineGoesBeforeTheNextHelperStarts() {
        var lines = HelperLines()
        #expect(lines.append(Self.bytes(#"{"type":"players","players":[{"title":"Song","artwork":"iVBORw0KGgo"#)).isEmpty)
        lines.reset()
        #expect(lines.append(Self.bytes("{\"type\":\"ready\"}\n")) == [Self.ready])
    }

    /// A line too long to be the helper's is dropped whole, its end included, and the next line
    /// still comes out.
    @Test func aRunawayLineIsDroppedWhole() {
        var lines = HelperLines(limit: 16)
        #expect(lines.append(Self.bytes(String(repeating: "x", count: 40))).isEmpty)
        #expect(lines.append(Self.bytes(String(repeating: "x", count: 40))).isEmpty)
        #expect(lines.append(Self.bytes("xx\n{\"type\":\"ready\"}\n")) == [Self.ready])
        // A line arriving whole is never too long: only what waits for its end is limited.
        let long = Self.bytes(String(repeating: "y", count: 40))
        #expect(lines.append(long + Self.bytes("\n")) == [long])
    }
}
