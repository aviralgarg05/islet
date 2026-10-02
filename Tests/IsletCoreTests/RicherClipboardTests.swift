import Foundation
import Testing
@testable import IsletCore

/// Clipboard history that knows what it holds: links, colours, images and files shown as
/// themselves, found by search and filter, with the same privacy rules as text.
@Suite struct RicherClipboardTests {
    func image(_ bytes: Int, fill: UInt8 = 1) -> ClipImage {
        ClipImage(data: Data(repeating: fill, count: bytes), type: "public.png", width: 1440, height: 900)
    }

    @Test(arguments: [
        ("https://github.com/aviralgarg05/islet/releases", ClipKind.link),
        ("http://example.com", .link),
        ("www.example.co.uk/path?q=1", .link),
        ("  https://example.com/a  ", .link),
        ("#0A84FF", .colour),
        ("#fff", .colour),
        ("#0A84FF80", .colour),
        ("rgb(10, 132, 255)", .colour),
        ("rgba(10 132 255 / 50%)", .colour),
        ("hsl(211, 100%, 52%)", .colour),
        ("hsl(211deg 100% 52%)", .colour),
        ("Hello there", .text),
        ("example.com", .text),
        ("https://example.com and more", .text),
        ("https://localhost", .text),
        ("#12345", .text),
        // Issue and pull request numbers aren't colours, but a grey written in digits is.
        ("#123", .text),
        ("#4021", .text),
        (" #812 ", .text),
        ("#000", .colour),
        ("#999", .colour),
        ("#f00", .colour),
        ("#a1b", .colour),
        ("#336699", .colour),
        ("#121212", .colour),
        ("fff", .text),
        ("rgb(300, 0, 0)", .text),
        ("blue", .text),
        ("line one\nhttps://example.com", .text),
    ])
    func eachCopyIsSortedByWhatItIs(text: String, kind: ClipKind) {
        #expect(ClipKind.classify(text) == kind, "\(text)")
    }

    @Test func linksAreShownByWhereTheyGo() throws {
        let parts = try #require(ClipLink.parts("https://www.github.com/aviralgarg05/islet?tab=readme"))
        #expect(parts.host == "github.com")
        #expect(parts.rest == "/aviralgarg05/islet?tab=readme")
        #expect(ClipLink.parts("https://example.com/")?.rest == "")
        #expect(ClipLink.url("www.example.com")?.absoluteString == "https://www.example.com")
        #expect(ClipLink.url("not a link") == nil)
    }

    @Test func coloursAreReadAsCSSWritesThem() throws {
        let blue = try #require(ClipColour.parse("rgb(10, 132, 255)"))
        #expect(ClipColour.hex(blue) == "#0A84FF")
        #expect(ClipColour.hex(try #require(ClipColour.parse("#0a84ff"))) == "#0A84FF")
        #expect(ClipColour.hex(try #require(ClipColour.parse("#fff"))) == "#FFFFFF")
        #expect(ClipColour.hex(try #require(ClipColour.parse("#f008"))) == "#FF000088")
        #expect(ClipColour.hex(try #require(ClipColour.parse("rgba(255 0 0 / 50%)"))) == "#FF000080")
        #expect(ClipColour.hex(try #require(ClipColour.parse("hsl(0, 100%, 50%)"))) == "#FF0000")
        #expect(ClipColour.hex(try #require(ClipColour.parse("hsl(120 100% 25%)"))) == "#008000")
        #expect(ClipColour.hex(try #require(ClipColour.parse("hsl(-120, 100%, 50%)"))) == "#0000FF")
        var e = ClipboardEntry(text: "#0A84FF", date: t0)
        #expect(e.kind == .colour)
        #expect(e.colour.map(ClipColour.hex) == "#0A84FF")
        e = ClipboardEntry(text: "hello", date: t0)
        #expect(e.colour == nil)
    }

    @Test func filesAreKeptAsTheirPathsAndShownByName() {
        var h = ClipboardHistory()
        let paths = ["/Users/sam/Desktop/Plan.pdf", "/Users/sam/Desktop/Budget.numbers"]
        #expect(h.add(.files(paths), types: ["public.file-url"], sourceBundleID: "com.apple.finder", now: t0) == .added)
        let e = h.entries[0]
        #expect(e.kind == .files)
        #expect(e.paths == paths)
        #expect(e.text == "Plan.pdf, Budget.numbers")
        // The same files again move to the top rather than being kept twice.
        h.add("other", types: [], sourceBundleID: nil, now: t0)
        #expect(h.add(.files(paths), types: [], sourceBundleID: "com.apple.finder", now: t0.addingTimeInterval(5)) == .moved)
        #expect(h.entries.count == 2)
        #expect(h.entries[0].kind == .files)
        // A whole folder's worth isn't kept, nor nothing.
        let many = (0...ClipboardHistory.maxFiles).map { "/tmp/\($0).txt" }
        #expect(h.add(.files(many), types: [], sourceBundleID: nil, now: t0) == .ignored)
        #expect(h.add(.files([]), types: [], sourceBundleID: nil, now: t0) == .ignored)
    }

    @Test func imagesAreKeptInMemoryUpToALimit() {
        var h = ClipboardHistory(limit: 50)
        #expect(h.add(.image(image(2_000_000)), types: ["public.png"], sourceBundleID: "com.apple.screencaptureui", now: t0) == .added)
        #expect(h.entries[0].kind == .image)
        #expect(h.entries[0].text == "Image 1440 × 900 PNG")
        // The same picture again moves up.
        #expect(h.add(.image(image(2_000_000)), types: [], sourceBundleID: nil, now: t0) == .moved)
        #expect(h.entries.count == 1)
        // Too big to keep.
        #expect(h.add(.image(image(ClipboardHistory.maxImageBytes + 1)), types: [], sourceBundleID: nil, now: t0) == .ignored)
        #expect(h.add(.image(image(0)), types: [], sourceBundleID: nil, now: t0) == .ignored)
        // Past the total, the oldest unpinned pictures go; text stays.
        h.add("some text", types: [], sourceBundleID: nil, now: t0)
        h.togglePin(id: h.entries.first { $0.kind == .image }!.id)
        for i in 2...6 { h.add(.image(image(10_000_000, fill: UInt8(i))), types: [], sourceBundleID: nil, now: t0) }
        let total = h.entries.compactMap(\.image).reduce(0) { $0 + $1.data.count }
        #expect(total <= ClipboardHistory.maxTotalImageBytes)
        #expect(h.entries.contains { $0.pinned && $0.kind == .image })
        #expect(h.entries.contains { $0.text == "some text" })
    }

    @Test func imagesAndFilesFollowThePrivacyRules() {
        var h = ClipboardHistory()
        #expect(h.add(.image(image(100)), types: ["public.png", "org.nspasteboard.ConcealedType"], sourceBundleID: nil, now: t0) == .ignored)
        #expect(h.add(.files(["/tmp/a"]), types: ["org.nspasteboard.TransientType"], sourceBundleID: nil, now: t0) == .ignored)
        #expect(h.add(.image(image(100)), types: [], sourceBundleID: "com.1password.1password", now: t0) == .ignored)
        h.ignoredApps = ["com.apple.Preview"]
        #expect(h.add(.image(image(100)), types: [], sourceBundleID: "com.apple.Preview", now: t0) == .ignored)
        #expect(h.entries.isEmpty)
    }

    @Test func searchLooksAtTextNamesPathsAndKinds() {
        var h = ClipboardHistory()
        h.add("Meeting notes for Thursday", types: [], sourceBundleID: nil, now: t0)
        h.add("https://example.com/islet", types: [], sourceBundleID: nil, now: t0)
        h.add(.files(["/Users/sam/Projects/Budget.numbers"]), types: [], sourceBundleID: nil, now: t0)
        h.add("#FF9F0A", types: [], sourceBundleID: nil, now: t0)
        #expect(h.filtered("thursday").map(\.text) == ["Meeting notes for Thursday"])
        #expect(h.filtered("budget").map(\.kind) == [.files])
        #expect(h.filtered("projects").map(\.kind) == [.files])
        #expect(h.filtered("example islet").map(\.kind) == [.link])
        #expect(h.filtered("colours").map(\.kind) == [.colour])
        #expect(h.filtered("").count == 4)
        #expect(h.filtered("nothing like it").isEmpty)
    }

    @Test func filtersOfferOnlyWhatThereIs() {
        var h = ClipboardHistory()
        #expect(h.filters == [.all])
        h.add("plain", types: [], sourceBundleID: nil, now: t0)
        h.add("https://example.com", types: [], sourceBundleID: nil, now: t0)
        #expect(h.filters == [.all, .kind(.text), .kind(.link)])
        h.togglePin(id: h.entries[1].id)
        #expect(h.filters == [.all, .pinned, .kind(.text), .kind(.link)])
        #expect(h.filtered("", filter: .pinned).map(\.text) == ["plain"])
        #expect(h.filtered("", filter: .kind(.link)).map(\.text) == ["https://example.com"])
        #expect(ClipFilter.kind(.colour).title == "Colours")
    }

    @Test func copyingFromThePageMovesItToTheTop() {
        var h = ClipboardHistory()
        h.add(.files(["/tmp/a.txt"]), types: [], sourceBundleID: "com.apple.finder", now: t0)
        h.add("newer", types: [], sourceBundleID: nil, now: t0.addingTimeInterval(1))
        let id = h.entries[1].id
        h.touch(id: id, now: t0.addingTimeInterval(2))
        #expect(h.entries[0].id == id)
        #expect(h.entries[0].date == t0.addingTimeInterval(2))
        #expect(h.entries[0].sourceBundleID == "com.apple.finder")
    }

    @Test func entriesFromBeforeKindsReadAsText() throws {
        let json = #"{"id": "1", "text": "https://example.com", "date": 0, "pinned": true}"#
        let e = try JSONDecoder().decode(ClipboardEntry.self, from: Data(json.utf8))
        #expect(e.kind == .link)
        #expect(e.paths.isEmpty && e.image == nil)
        #expect(e.pinned)
    }

    // MARK: Shelf

    @Test func shelfFilesGoAfterTheChosenTimeButTheFilesStay() {
        var shelf = Shelf()
        shelf.add(paths: ["/tmp/old.txt"], now: t0)
        shelf.add(paths: ["/tmp/new.txt"], now: t0.addingTimeInterval(3600))
        #expect(shelf.nextExpiry(keepFor: 86400) == t0.addingTimeInterval(86400))
        #expect(shelf.expire(now: t0.addingTimeInterval(86399), keepFor: 86400).isEmpty)
        let gone = shelf.expire(now: t0.addingTimeInterval(86400), keepFor: 86400)
        #expect(gone.map(\.path) == ["/tmp/old.txt"])
        #expect(shelf.items.map(\.path) == ["/tmp/new.txt"])
        #expect(shelf.nextExpiry(keepFor: 86400) == t0.addingTimeInterval(3600 + 86400))
        // Kept until removed: nothing goes, and there is nothing to wake for.
        #expect(shelf.expire(now: t0.addingTimeInterval(1_000_000), keepFor: 0).isEmpty)
        #expect(shelf.nextExpiry(keepFor: 0) == nil)
        #expect(Shelf().nextExpiry(keepFor: 3600) == nil)
    }

    @Test func droppingAFileAgainStartsItsTimeAgain() {
        var shelf = Shelf()
        shelf.add(paths: ["/tmp/a.txt", "/tmp/b.txt"], now: t0)
        shelf.add(paths: ["/tmp/a.txt"], now: t0.addingTimeInterval(7200))
        #expect(shelf.items.first?.path == "/tmp/a.txt")
        #expect(shelf.items.first?.addedAt == t0.addingTimeInterval(7200))
        #expect(shelf.expire(now: t0.addingTimeInterval(3600 + 1), keepFor: 3600).map(\.path) == ["/tmp/b.txt"])
    }

    @Test func keepTimesReadPlainly() {
        #expect(Shelf.keepTitle(0) == "Until I remove them")
        #expect(Shelf.keepTitle(600) == "10 minutes")
        #expect(Shelf.keepTitle(60) == "1 minute")
        #expect(Shelf.keepTitle(3600) == "1 hour")
        #expect(Shelf.keepTitle(7200) == "2 hours")
        #expect(Shelf.keepTitle(86400) == "1 day")
        #expect(Shelf.keepTitle(3 * 86400) == "3 days")
        #expect(Shelf.keepTitle(604_800) == "1 week")
        #expect(Shelf.keepTitle(14 * 86400) == "2 weeks")
        for choice in IsletSettings.shelfKeepChoices { #expect(!Shelf.keepTitle(choice).isEmpty) }
        #expect(Shelf.keepPhrase(86400) == "a day")
        #expect(Shelf.keepPhrase(3600) == "an hour")
        #expect(Shelf.keepPhrase(604_800) == "a week")
        #expect(Shelf.keepPhrase(3 * 86400) == "3 days")
        #expect(Shelf.keepPhrase(0) == nil)
    }

    @Test func aDayByDefaultAndWhatWasOnTheShelfStaysForOlderSetups() {
        #expect(IsletSettings().shelfKeepFor == 86400)
        // A config.json from before the choice keeps files until they are removed, as it did.
        #expect(IsletSettings.decodeLenient(Data(#"{"shelfEnabled": true}"#.utf8)).shelfKeepFor == 0)
        #expect(IsletSettings.decodeLenient(Data(#"{"shelfKeepFor": 3600}"#.utf8)).shelfKeepFor == 3600)
        // Out of range is brought into it; nothing, or less, keeps files for good.
        #expect(IsletSettings.decodeLenient(Data(#"{"shelfKeepFor": 5}"#.utf8)).shelfKeepFor == 60)
        #expect(IsletSettings.decodeLenient(Data(#"{"shelfKeepFor": 99999999}"#.utf8)).shelfKeepFor == 2_592_000)
        #expect(IsletSettings.decodeLenient(Data(#"{"shelfKeepFor": -1}"#.utf8)).shelfKeepFor == 0)
    }

    // MARK: Feedback

    @Test func feedbackOpensTheIssueFormWithOnlyTheVersionsFilledIn() throws {
        let url = Feedback.url(.bug, version: "0.2.0", macOS: "macOS 27.0 (26A123)")
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.host == "github.com")
        #expect(c.path == "/aviralgarg05/islet/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items == ["template": "bug_report.yml", "islet-version": "0.2.0", "macos-version": "macOS 27.0 (26A123)"])
        let idea = Feedback.url(.idea, version: "0.2.0\nextra", macOS: "macOS 27.0")
        #expect(idea.absoluteString.contains("template=feature_request.yml"))
        #expect(!idea.absoluteString.contains("%0A"))
    }

    @Test func theFormsFilledInExist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for kind in Feedback.Kind.allCases {
            let form = try String(contentsOf: root.appendingPathComponent(".github/ISSUE_TEMPLATE/\(kind.template)"), encoding: .utf8)
            #expect(form.contains("id: islet-version"), "\(kind.template)")
            #expect(form.contains("id: macos-version"), "\(kind.template)")
        }
    }

    @Test func macOSVersionAsAboutThisMacWritesIt() {
        #expect(Feedback.macOSVersion(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1), build: "26A123")
                == "macOS 27.0.1 (26A123)")
        #expect(Feedback.macOSVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0), build: nil)
                == "macOS 26.4")
    }
}
