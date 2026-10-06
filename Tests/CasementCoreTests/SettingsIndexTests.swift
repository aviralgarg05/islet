import Foundation
import Testing
@testable import CasementCore

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
        // A missing or refused key has a button to the key instead of words about where it is.
        let messages = [
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
        let settings = CasementSettings()
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
        ("hide paused", .nowPlaying),
        ("artwork corners", .appearance),
        ("rounded artwork", .appearance),
        ("fit to the notch", .appearance),
        ("notch height", .appearance),
        ("wave", .nowPlaying),
        ("pulse", .nowPlaying),
        ("colourful", .notifications),
        ("closed island width", .appearance),
        ("airdrop", .shelf),
        ("music colour", .nowPlaying),
        ("song progress", .nowPlaying),
        ("peek", .general),
        ("keyboard brightness", .notifications),
        ("hud style", .notifications),
        ("animation speed", .appearance),
        ("full screen", .general),
        ("floating pill", .general),
        ("outline", .appearance),
        ("reset appearance", .appearance),
        ("invert swipe", .general),
        ("app priority", .apps),
        ("two HUDs", .notifications),
        ("ignore apps", .nowPlaying),
        ("to-do", .tools),
        ("quick note", .tools),
        ("convert", .tools),
        ("emoji", .tools),
        ("reorder tabs", .general),
        ("pages in the switcher", .general),
        ("keep files", .shelf),
        ("bug", .about),
        ("feedback", .about),
    ])
    func queryFindsPage(query: String, page: SettingsPage) {
        let groups = SettingsIndex.search(query)
        #expect(groups.first?.page == page, "\(query) → \(groups.map(\.page.title))")
    }

    @Test func technicalWordsStayInAdvanced() {
        // Feature pages never answer for the plumbing.
        for query in ["port", "token", "casementctl", "plugins", "casement://", "settings.json"] {
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

    /// A result's section shows under it only when the title doesn't already say it.
    @Test func subtitlesDontRepeatTheTitle() {
        let port = SettingsEntry("x.port", .advanced, "Local API port", section: "Local API")
        #expect(SettingsIndex.subtitle(for: port) == nil)
        let same = SettingsEntry("x.same", .ai, "Apple Intelligence", section: "Apple Intelligence")
        #expect(SettingsIndex.subtitle(for: same) == nil)
        let other = SettingsEntry("x.other", .shelf, "Items kept", section: "Clipboard")
        #expect(SettingsIndex.subtitle(for: other) == "Clipboard")
        // A word that only starts the same isn't the section.
        let partial = SettingsEntry("x.partial", .timers, "Timers list", section: "Timer")
        #expect(SettingsIndex.subtitle(for: partial) == "Timer")
        #expect(SettingsIndex.subtitle(for: SettingsEntry("x.none", .about, "Version")) == nil)
    }

    /// The keyboard page and the Shortcuts tool have different names, and the island is "the
    /// island" on every page.
    @Test func pagesNameThingsOneWay() {
        #expect(SettingsPage.shortcuts.title == "Keyboard shortcuts")
        #expect(SettingsIndex.search("keyboard shortcuts").first?.page == .shortcuts)
        for page in SettingsPage.allCases {
            #expect(!page.summary.contains("in the notch"), "\(page)")
        }
        for entry in SettingsIndex.entries {
            #expect(!entry.title.contains("in the notch"), "\(entry.id)")
        }
    }

    @Test func tiedPagesKeepSidebarOrder() {
        #expect(SettingsIndex.search("frontmost").map(\.page) == [.apps])
        // "colour" is a whole title word on four pages: they come in sidebar order.
        let colour = SettingsIndex.search("colour").map(\.page)
        #expect(colour.prefix(4) == [.appearance, .nowPlaying, .notifications, .apps])
    }
}
