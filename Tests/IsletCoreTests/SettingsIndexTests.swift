import Foundation
import Testing
@testable import IsletCore

@Suite struct SettingsIndexTests {
    @Test func everyPageHasEntries() {
        for page in SettingsPage.allCases {
            #expect(SettingsIndex.entries.contains { $0.page == page }, "no search entries for \(page.title)")
        }
    }

    @Test func idsAreUniqueAndAnchorsPointAtRowsOnTheSamePage() {
        let ids = SettingsIndex.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        let byID = Dictionary(uniqueKeysWithValues: SettingsIndex.entries.map { ($0.id, $0) })
        for entry in SettingsIndex.entries {
            #expect(!entry.title.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(byID[entry.anchor]?.page == entry.page, "\(entry.id) scrolls to \(entry.anchor)")
        }
    }

    @Test func sidebarGroupsAreInOrder() {
        let grouped = SettingsPageGroup.allCases.flatMap(\.pages)
        #expect(grouped == SettingsPage.allCases)
        #expect(SettingsPageGroup.basics.pages == [.general, .appearance, .shortcuts])
        #expect(SettingsPageGroup.features.title == "Features")
        #expect(SettingsPageGroup.system.pages == [.apps, .permissions, .about])
        #expect(SettingsPage.allCases.last == .advanced)
        #expect(SettingsPageGroup.advanced.title == nil)
        for page in SettingsPage.allCases {
            #expect(!page.symbol.isEmpty && !page.title.isEmpty && page.summary.hasSuffix("."))
        }
    }

    @Test func plainWordsAndBritishSpelling() {
        // Pages and rows say "colour"; "color" is only a search keyword.
        for page in SettingsPage.allCases {
            #expect(!page.title.lowercased().contains("color") && !page.summary.lowercased().contains("color"))
        }
        for entry in SettingsIndex.entries {
            #expect(!entry.title.lowercased().contains("color"), "\(entry.id)")
            #expect(!entry.title.contains("—"), "\(entry.id)")
        }
    }

    /// Messages that send people to Settings name a page that exists ("Settings → Ask & AI").
    @Test func messagesNamePagesThatExist() {
        let messages = [
            AskProviderStatus.needsKey.message(for: .anthropic),
            AskProviderStatus.needsKey.message(for: .openai),
            AskErrorText.http(status: 401, body: Data(), retryAfter: nil, provider: .anthropic),
            AskErrorText.http(status: 404, body: Data(), retryAfter: nil, provider: .openai),
        ]
        for message in messages {
            #expect(Self.pagesNamed(in: message) == ["Ask & AI"], "\(message)")
        }
        #expect(Self.pagesNamed(in: "Settings → AI and Settings → Integrations → iPhone bridge") == [nil, nil])
    }

    /// The page each "Settings → " in `text` leads to: the longest page title the rest starts with.
    static func pagesNamed(in text: String) -> [String?] {
        text.components(separatedBy: "Settings → ").dropFirst().map { rest in
            SettingsPage.allCases.map(\.title).filter { rest.hasPrefix($0) }.max { $0.count < $1.count }
        }
    }

    /// The Permissions page lists what uses each permission by the names those rows have on
    /// their own pages.
    @Test func permissionsNameFeaturesAsTheirPagesDo() {
        let titles = Set(SettingsIndex.entries.map(\.title))
        let settings = IsletSettings()
        let named = PermissionKind.accessibility.uses(settings).map(\.feature) + PermissionKind.reminders.uses(settings).map(\.feature)
        for feature in ["Replace the system volume and brightness display", "Mirror notifications from every app",
                        "Show Live Activities", "Reminders due today"] {
            #expect(named.contains(feature), "\(feature)")
            #expect(titles.contains(feature), "\(feature)")
        }
    }

    @Test func permissionRowsFollowThePermissionList() {
        let titles = SettingsIndex.entries.filter { $0.page == .permissions }.map(\.title)
        #expect(titles == PermissionKind.allCases.map(\.title))
    }

    @Test(arguments: [
        ("hover", SettingsPage.general),
        ("pomodoro", .timers),
        ("api key", .ai),
        ("port", .advanced),
        ("token", .advanced),
        ("bridge", .advanced),
        ("mcp", .advanced),
        ("config.json", .advanced),
        ("clipboard", .shelf),
        ("accessibility", .permissions),
        ("shortcut", .shortcuts),
        ("hotkey", .shortcuts),
        ("battery", .notifications),
        ("volume", .notifications),
        ("Spotify", .nowPlaying),
        ("colour", .appearance),
        ("color", .appearance),
        ("glass", .appearance),
        ("wing width", .appearance),
        ("usage limits", .agents),
        ("connect codex", .agents),
        ("iphone shortcuts", .advanced),
        ("uber", .liveActivities),
        ("zoom", .notifications),
        ("downloads", .downloads),
        ("reset", .advanced),
        ("api guide", .advanced),
        ("paused music", .nowPlaying),
        ("closed island width", .appearance),
        ("airdrop", .shelf),
    ])
    func queryFindsPage(query: String, page: SettingsPage) {
        let groups = SettingsIndex.search(query)
        #expect(groups.first?.page == page, "\(query) → \(groups.map(\.page.title))")
    }

    @Test func technicalWordsStayInAdvanced() {
        // Feature pages never answer for the plumbing.
        for query in ["port", "token", "isletctl", "plugins", "islet://", "settings.json"] {
            let pages = Set(SettingsIndex.search(query).map(\.page))
            #expect(pages == [.advanced], "\(query) → \(pages)")
        }
    }

    @Test func titleMatchesComeFirstWithinAPage() {
        let general = SettingsIndex.search("delay").first { $0.page == .general }
        #expect(general?.entries.map(\.id) == ["general.hoverDelay", "general.closeDelay"])
        // A row titled with the word ranks above rows that only have it as a keyword.
        let hud = SettingsIndex.search("brightness").first { $0.page == .notifications }
        #expect(hud?.entries.first?.id == "notifications.brightness")
    }

    @Test func wholeWordsRankAbovePartsOfWords() {
        #expect(SettingsIndex.quality("port", ["port"]) == 3)
        #expect(SettingsIndex.quality("por", ["port"]) == 2)
        #expect(SettingsIndex.quality("ort", ["port"]) == 1)
        #expect(SettingsIndex.quality("or", ["port"]) == 0)
    }

    @Test func everyWordMustMatch() {
        let hits = SettingsIndex.search("swipe music").flatMap(\.entries).map(\.id)
        #expect(hits == ["general.swipeMedia"])
    }

    @Test func matchesInsideWordsFromThreeLetters() {
        #expect(SettingsIndex.search("board").contains { $0.page == .shelf })
        #expect(SettingsIndex.search("ar").flatMap(\.entries).allSatisfy { entry in
            SettingsIndex.tokens([entry.title, entry.section ?? "", entry.page.title].joined(separator: " ") + " " + entry.keywords.joined(separator: " "))
                .contains { $0.hasPrefix("ar") }
        })
    }

    @Test func ignoresCaseAccentsAndAmpersands() {
        #expect(SettingsIndex.search("CALENDAR and reminders").first?.page == .calendar)
        #expect(SettingsIndex.search("welcome").flatMap(\.entries).map(\.id) == ["notifications.welcome"])
        #expect(SettingsIndex.search("Pomodoro ").first?.page == .timers)
        #expect(SettingsIndex.search("shelf & clipboard").first?.page == .shelf)
    }

    @Test func emptyOrUnknownQueriesFindNothing() {
        #expect(SettingsIndex.search("").isEmpty)
        #expect(SettingsIndex.search("   ").isEmpty)
        #expect(SettingsIndex.search("xyzzy").isEmpty)
    }

    @Test func tiedPagesKeepSidebarOrder() {
        #expect(SettingsIndex.search("frontmost").map(\.page) == [.apps])
        // "colour" is a whole title word on three pages: they come in sidebar order.
        let colour = SettingsIndex.search("colour").map(\.page)
        #expect(colour.prefix(3) == [.appearance, .nowPlaying, .apps])
    }
}
