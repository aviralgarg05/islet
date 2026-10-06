import Foundation
import Testing
@testable import CasementCore

@Suite struct ShortcutsCatalogTests {
    static let listing = """
    Morning routine (8A6C1F7E-3B2D-4C5E-9F10-112233445566)
    Log water (11111111-2222-3333-4444-555555555555)
    Text Sam (I'm late) (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)

    Plain name (not an id)
    Log water (11111111-2222-3333-4444-555555555555)
    """

    @Test func readsNamesAndIdentifiers() {
        let items = ShortcutsCatalog.parse(Self.listing)
        #expect(items.map(\.name) == ["Morning routine", "Log water", "Text Sam (I'm late)", "Plain name (not an id)"])
        #expect(items[0].id == "8A6C1F7E-3B2D-4C5E-9F10-112233445566")
        // Without an identifier, the name is what `shortcuts run` takes.
        #expect(items[3].id == "Plain name (not an id)")
        #expect(ShortcutsCatalog.parse("").isEmpty)
    }

    @Test func runsByIdentifier() {
        let item = ShortcutItem(id: "8A6C1F7E-3B2D-4C5E-9F10-112233445566", name: "Morning routine")
        #expect(ShortcutsCatalog.runArguments(item) == ["run", "8A6C1F7E-3B2D-4C5E-9F10-112233445566"])
        #expect(ShortcutsCatalog.listArguments == ["list", "--show-identifiers"])
    }

    let items = [
        ShortcutItem(id: "1", name: "Morning routine"),
        ShortcutItem(id: "2", name: "Log water"),
        ShortcutItem(id: "3", name: "Water the plants"),
        ShortcutItem(id: "4", name: "Turn on Focus"),
        ShortcutItem(id: "5", name: "Café order"),
    ]

    @Test func searchRanksNamesThatStartWithTheQueryFirst() {
        #expect(ShortcutsCatalog.search("water", in: items).map(\.id) == ["3", "2"])
        #expect(ShortcutsCatalog.search("log wat", in: items).map(\.id) == ["2"])
        #expect(ShortcutsCatalog.search("cafe", in: items).map(\.id) == ["5"])
        #expect(ShortcutsCatalog.search("outine", in: items).map(\.id) == ["1"], "three letters match inside a word")
        #expect(ShortcutsCatalog.search("xyz", in: items).isEmpty)
    }

    @Test func emptyQueryListsRecentFirstThenAToZ() {
        #expect(ShortcutsCatalog.search("", in: items, recent: ["4", "2"]).map(\.id) == ["4", "2", "5", "1", "3"])
        #expect(ShortcutsCatalog.search("  ", in: items).map(\.id) == ["5", "2", "1", "4", "3"])
    }

    @Test func askSuggestsOnlyStrongMatches() {
        #expect(ShortcutsCatalog.suggestions(for: "w", in: items).isEmpty, "one letter is too little")
        #expect(ShortcutsCatalog.suggestions(for: "wat", in: items).map(\.id) == ["3", "2"])
        #expect(ShortcutsCatalog.suggestions(for: "turn on", in: items).map(\.id) == ["4"])
        #expect(ShortcutsCatalog.suggestions(for: "what is the capital of France", in: items).isEmpty)
        #expect(ShortcutsCatalog.suggestions(for: "outine", in: items).isEmpty, "only starts of words")
    }

    @Test func failureReasonIsOneShortLine() {
        #expect(ShortcutsCatalog.failureReason("Error: The operation couldn’t be completed.\nmore") == "The operation couldn’t be completed.")
        #expect(ShortcutsCatalog.failureReason("\n  \n") == nil)
        #expect((ShortcutsCatalog.failureReason(String(repeating: "x", count: 200))?.count ?? 0) == 90)
    }

    @Test func returnRunsTheBestMatchOnlyOnceSomethingIsTyped() {
        let items = [ShortcutItem(id: "1", name: "Text Sam I'm late"), ShortcutItem(id: "2", name: "Lights off")]
        // A stray Return in an empty field runs nothing, not whichever shortcut is listed first.
        #expect(ShortcutsCatalog.returnTarget("", in: items, recent: ["1"]) == nil)
        #expect(ShortcutsCatalog.returnTarget("   ", in: items) == nil)
        #expect(ShortcutsCatalog.returnTarget("lig", in: items)?.id == "2")
        #expect(ShortcutsCatalog.returnTarget("zzz", in: items) == nil)
    }
}
