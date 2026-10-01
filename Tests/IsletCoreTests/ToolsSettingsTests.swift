import Foundation
import Testing
@testable import IsletCore

@Suite struct ToolsSettingsTests {
    @Test func everyToolStartsOff() {
        let s = IsletSettings()
        #expect(!s.lyricsEnabled)
        #expect(!s.shortcutsEnabled)
        #expect(!s.weatherEnabled)
        #expect(!s.weatherUsesLocation)
        #expect(!s.monthCalendar)
        #expect(!s.stopwatchEnabled)
        #expect(s.focusSound == .off)
    }

    @Test func toolSwitchesRoundTripThroughTheConfigFile() throws {
        var s = IsletSettings()
        s.lyricsEnabled = true
        s.shortcutsEnabled = true
        s.monthCalendar = true
        s.stopwatchEnabled = true
        s.focusSound = .music
        s.temperatureUnit = .fahrenheit
        s.weatherPlace = WeatherPlace(name: "Oslo", country: "Norway", latitude: 59.91, longitude: 10.75)
        let again = IsletSettings.decodeLenient(try JSONEncoder().encode(s))
        #expect(again == s)
    }

    @Test(arguments: [
        ("lyrics", SettingsPage.nowPlaying),
        ("karaoke", .nowPlaying),
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

    @Test func toolsPageIsAFeatureWithItsOwnEntries() {
        #expect(SettingsPage.tools.group == .features)
        let ids = Set(SettingsIndex.entries.filter { $0.page == .tools }.map(\.id))
        #expect(ids == ["tools.shortcuts", "tools.weather", "tools.weatherLocation", "tools.temperature"])
        // Plain words on the page: no developer terms in titles.
        for entry in SettingsIndex.entries where entry.page == .tools {
            for word in ["API", "port", "token", "MCP", "hook", "script"] {
                #expect(!entry.title.localizedCaseInsensitiveContains(word), "\(entry.id)")
            }
        }
    }

    @Test func toolPagesAreListedUnderMoreOnlyOnceOn() {
        var s = IsletSettings()
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
        var s = IsletSettings()
        #expect(PermissionKind.location.uses(s).allSatisfy { !$0.isOn })
        s.weatherEnabled = true
        #expect(PermissionKind.location.uses(s).allSatisfy { !$0.isOn }, "a typed city needs no location")
        s.weatherUsesLocation = true
        #expect(PermissionKind.location.uses(s).contains { $0.isOn })
    }
}
