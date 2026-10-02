import Foundation
import Testing
@testable import IsletCore

/// Settings rows that stand for more than one stored value, and where a few of them live.
@Suite struct SettingsChoicesTests {
    /// "Swipe sideways over music" is one choice: off, a song, or ten seconds.
    @Test func swipingOverMusicIsOneChoice() {
        var s = IsletSettings()
        #expect(s.mediaSwipe == .track)
        s.mediaSwipe = .seek
        #expect(s.swipeMedia && s.swipeMediaAction == .seek)
        s.mediaSwipe = nil
        #expect(!s.swipeMedia)
        // Off keeps what it did, for when it comes back on.
        #expect(s.swipeMediaAction == .seek)
        #expect(GestureMap.action(for: .left, on: .expanded(media: true), settings: s) == nil)
        s.mediaSwipe = .track
        #expect(s.swipeMedia && s.swipeMediaAction == .track)
    }

    /// The choice is made of the stored fields, so config.json is unchanged.
    @Test func theChoiceIsNotStoredItself() throws {
        var s = IsletSettings()
        s.mediaSwipe = nil
        let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!json.contains("mediaSwipe"))
        #expect(IsletSettings.decodeLenient(Data(json.utf8)).mediaSwipe == nil)
    }

    /// Now Playing lists the players by name first and the catch-all last. What scripts send is
    /// switched in Advanced, beside the local API.
    @Test func nowPlayingSourcesReadPlayersFirst() {
        #expect(MediaSourceKind.settingsOrder == [.appleMusic, .spotify, .browser, .system])
        #expect(Set(MediaSourceKind.settingsOrder + [.external]) == Set(MediaSourceKind.allCases))
        #expect(SettingsIndex.entries.contains { $0.id == "advanced.mediaScripts" && $0.page == .advanced })
    }

    /// The System page is a tool like the others: off at first, and switched on Tools.
    @Test func theSystemPageStartsOffOnTools() {
        let s = IsletSettings()
        #expect(!s.systemStatsEnabled)
        #expect(!IslandPage.stats.isAvailable(s))
        #expect(SettingsIndex.entries.first { $0.id == "tools.stats" }?.page == .tools)
        #expect(!SettingsIndex.entries.contains { $0.id == "general.stats" })
    }
}
