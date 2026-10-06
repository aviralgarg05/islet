import Foundation
import Testing
@testable import CasementCore

@Suite struct ToolsSettingsTests {
    @Test func everyToolStartsOff() {
        let s = CasementSettings()
        #expect(!s.lyricsEnabled)
        #expect(!s.lyricsIncludeBrowsers)
        #expect(!s.shortcutsEnabled)
        #expect(!s.weatherEnabled)
        #expect(!s.weatherUsesLocation)
        #expect(!s.monthCalendar)
        #expect(!s.stopwatchEnabled)
        #expect(s.focusSound == .off)
    }

    /// A config written before browsers had lyrics, with lyrics on, keeps browsers off.
    @Test func browserLyricsStayOffForOldConfigs() throws {
        let old = CasementSettings.decodeLenient(Data(#"{"lyricsEnabled": true, "mediaEnabled": true}"#.utf8))
        #expect(old.lyricsEnabled)
        #expect(!old.lyricsIncludeBrowsers)
        let wrong = CasementSettings.decodeLenient(Data(#"{"lyricsEnabled": true, "lyricsIncludeBrowsers": "yes"}"#.utf8))
        #expect(wrong.lyricsEnabled)
        #expect(!wrong.lyricsIncludeBrowsers)
        #expect(SettingsIndex.entries.contains { $0.id == "nowPlaying.lyricsBrowsers" && $0.anchor == "nowPlaying.lyricsBrowsers" })
    }

    @Test func toolSwitchesRoundTripThroughTheConfigFile() throws {
        var s = CasementSettings()
        s.lyricsEnabled = true
        s.lyricsIncludeBrowsers = true
        s.shortcutsEnabled = true
        s.monthCalendar = true
        s.stopwatchEnabled = true
        s.focusSound = .music
        s.temperatureUnit = .fahrenheit
        s.weatherPlace = WeatherPlace(name: "Oslo", country: "Norway", latitude: 59.91, longitude: 10.75)
        let again = CasementSettings.decodeLenient(try JSONEncoder().encode(s))
        #expect(again == s)
    }

    @Test(arguments: [
        ("lyrics", SettingsPage.nowPlaying),
        ("karaoke", .nowPlaying),
        ("YouTube Music", .nowPlaying),
        ("lyrics browser", .nowPlaying),
        ("weather", .tools),
        ("fahrenheit", .tools),
        ("forecast", .tools),
        ("run shortcut", .tools),
        ("month", .calendar),
        ("stopwatch", .timers),
        ("laps", .timers),
        ("brown noise", .timers),
        ("focus sound", .timers),
        ("50/10", .timers),
        ("location", .permissions),
    ])
    func toolsAreFound(query: String, page: SettingsPage) {
        let groups = SettingsIndex.search(query)
        #expect(groups.first?.page == page, "\(query) → \(groups.map(\.page.title))")
    }

    /// The browser switch is the first thing these searches find, not just a row on its page.
    @Test(arguments: ["lyrics browser", "YouTube lyrics", "lyrics Chrome"])
    func browserLyricsAreFoundByName(query: String) {
        #expect(SettingsIndex.search(query).first?.entries.first?.id == "nowPlaying.lyricsBrowsers", "\(query)")
    }

    @Test func toolsPageIsAFeatureWithItsOwnEntries() {
        #expect(SettingsPage.tools.group == .features)
        let ids = Set(SettingsIndex.entries.filter { $0.page == .tools }.map(\.id))
        #expect(ids.isSuperset(of: ["tools.shortcuts", "tools.weather", "tools.weatherLocation", "tools.temperature"]))
        // Plain words on the page: no developer terms in titles. (A teleprompter's script is the
        // words you read, not a program.)
        for entry in SettingsIndex.entries where entry.page == .tools && entry.id != "tools.script" {
            for word in ["API", "port", "token", "MCP", "hook", "script"] {
                #expect(!entry.title.localizedCaseInsensitiveContains(word), "\(entry.id)")
            }
        }
    }

    @Test func toolPagesAreListedUnderMoreOnlyOnceOn() {
        var s = CasementSettings()
        let off = IslandPage.switcher(s, current: .home)
        #expect(!off.more.contains(.shortcuts) && !off.more.contains(.weather))
        s.shortcutsEnabled = true
        s.weatherEnabled = true
        let on = IslandPage.switcher(s, current: .home)
        #expect(on.more.suffix(2) == [.shortcuts, .weather])
        // Never in the capsule: nothing new crowds it.
        #expect(on.main == off.main)
    }

    @Test func locationIsAskedForOnlyByWeatherWhereYouAre() {
        var s = CasementSettings()
        #expect(PermissionKind.location.uses(s).allSatisfy { !$0.isOn })
        s.weatherEnabled = true
        #expect(PermissionKind.location.uses(s).allSatisfy { !$0.isOn }, "a typed city needs no location")
        s.weatherUsesLocation = true
        #expect(PermissionKind.location.uses(s).contains { $0.isOn })
    }
}
