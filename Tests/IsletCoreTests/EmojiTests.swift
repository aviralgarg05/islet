import Foundation
import Testing
@testable import IsletCore

/// Every emoji macOS can name, found by its name or the words people use, with the ones used
/// lately first. Nothing is downloaded.
@Suite struct EmojiTests {
    @Test func theCatalogueHasEveryKind() throws {
        let all = EmojiCatalog.all
        #expect(all.count > 1_500)
        #expect(Set(all.map(\.emoji)).count == all.count)
        let grinning = try #require(all.first { $0.emoji == "😀" })
        #expect(grinning.name == "Grinning face")
        #expect(all.contains { $0.emoji == "🇯🇵" && $0.name == "Flag: Japan" })
        #expect(all.contains { $0.emoji == "🇬🇧" && $0.name == "Flag: United Kingdom" })
        #expect(all.contains { $0.name == "Flag: England" })
        #expect(all.contains { $0.emoji == "🧑‍💻" })
        #expect(all.contains { $0.emoji == "1️⃣" })
        // Text-style symbols carry the emoji selector, so they draw as emoji.
        #expect(all.contains { $0.emoji == "\u{2764}\u{FE0F}" })
        #expect(!all.contains { $0.emoji == "\u{2764}" })
    }

    @Test func partsOfEmojiAreNotListedOnTheirOwn() {
        let scalars = Set(EmojiCatalog.all.filter { $0.emoji.unicodeScalars.count == 1 }.map { $0.emoji.unicodeScalars.first!.value })
        for part in [0x1F3FB, 0x1F3FF, 0x1F1E6, 0x1F1FF, 0x1F9B0, 0x200D, 0xFE0F, 0x20E3] as [UInt32] {
            #expect(!scalars.contains(part), "\(String(part, radix: 16))")
        }
        // Plain digits and # are keycaps, not emoji of their own.
        #expect(!EmojiCatalog.all.contains { $0.emoji == "1" || $0.emoji == "#" })
    }

    @Test func facesComeFirstAndFlagsLast() {
        let all = EmojiCatalog.all
        #expect(all.first?.emoji == "😀")
        #expect(all.last?.name.hasPrefix("Flag: ") == true)
    }

    @Test func everyExtraWordBelongsToAnEmojiInTheCatalogue() {
        let emoji = Set(EmojiCatalog.all.map(\.emoji))
        for key in EmojiCatalog.aliases.keys { #expect(emoji.contains(key), "\(key)") }
        for key in EmojiCatalog.names.keys { #expect(emoji.contains(key), "\(key)") }
        for e in EmojiCatalog.favourites { #expect(emoji.contains(e), "\(e)") }
    }

    @Test(arguments: [
        ("lol", "😂"),
        ("tada", "🎉"),
        ("thumbs up", "👍"),
        ("party", "🎉"),
        ("partying", "🥳"),
        ("heart", "\u{2764}\u{FE0F}"),
        ("rocket", "🚀"),
        ("flag japan", "🇯🇵"),
        ("shrug", "🤷"),
        ("Grinning face", "😀"),
        ("GRIN", "😁"),
        ("coffee", "☕"),
    ])
    func findsByNameAndCommonWords(query: String, expected: String) {
        let found = EmojiCatalog.search(query)
        #expect(found.first?.emoji == expected, "\(query) → \(found.prefix(5).map(\.emoji))")
    }

    @Test func everyWordMustMatchTheStartOfAWord() {
        #expect(EmojiCatalog.search("smiling cat").allSatisfy { $0.name.lowercased().contains("cat") })
        #expect(EmojiCatalog.search("xylophonequartz").isEmpty)
        // "art" starts "artist", but isn't found inside "heart".
        #expect(!EmojiCatalog.search("art").contains { $0.emoji == "\u{2764}\u{FE0F}" })
    }

    @Test func anEmojiPastedInFindsItself() {
        #expect(EmojiCatalog.search("🚀").map(\.emoji) == ["🚀"])
        #expect(EmojiCatalog.search(" \u{2764} ").map(\.emoji) == ["\u{2764}\u{FE0F}"])
    }

    @Test func recentOnesComeFirst() {
        let none = EmojiCatalog.search("")
        #expect(none.first?.emoji == EmojiCatalog.all.first?.emoji)
        let recent = EmojiCatalog.search("", recent: ["🚀", "🍕"])
        #expect(recent.prefix(2).map(\.emoji) == ["🚀", "🍕"])
        #expect(recent.filter { $0.emoji == "🚀" }.count == 1)
        // Among equals, the one used lately wins.
        let hearts = EmojiCatalog.search("heart", recent: ["💜"])
        #expect(hearts.first?.emoji == "💜")
        #expect(EmojiCatalog.search("", limit: 10).count == 10)
    }

    @Test func recentsAreShortAndSaved() throws {
        var r = EmojiRecents()
        for e in ["😀", "🚀", "😀"] { r.use(e) }
        #expect(r.emoji == ["😀", "🚀"])
        for i in 0..<40 { r.use(EmojiCatalog.all[i].emoji) }
        #expect(r.emoji.count == EmojiRecents.limit)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-emoji-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("emoji.json")
        try r.save(to: url)
        #expect(EmojiRecents.load(from: url) == r)
        // Only what could be an emoji is read back.
        try Data(#"["🚀", "hello", "", "1️⃣", "\#(String(repeating: "😀", count: 20))"]"#.utf8).write(to: url)
        #expect(EmojiRecents.load(from: url).emoji == ["🚀", "1️⃣"])
        try Data("not json".utf8).write(to: url)
        #expect(EmojiRecents.load(from: url).emoji.isEmpty)
    }
}
