import Foundation
import Testing
@testable import IsletCore

private func song(_ title: String, artist: String? = "M83", album: String? = "Hurry Up", playing: Bool = true,
                  source: MediaSourceKind = .spotify, elapsed: Double = 0, at time: Date = t0) -> NowPlaying {
    NowPlaying(source: source, title: title, artist: artist, album: album, isPlaying: playing, duration: 240,
               elapsed: elapsed, timestamp: time)
}

private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

/// A tracker that has already seen the first song after launch.
private func started(with first: NowPlaying = song("Intro")) -> SongPeek {
    var p = SongPeek()
    p.ingest(first, now: t0)
    return p
}

@Suite struct SongPeekTests {
    let free = SongPeek.Context()

    @Test func showsANewSongOnceItHasPlayedForAMoment() {
        var p = started()
        p.ingest(song("Midnight City"), now: at(10))
        #expect(p.current(now: at(10)) == nil)
        #expect(p.nextDeadline(now: at(10)) == at(10.6))
        do { let shown = p.advance(now: at(10.3), context: free); #expect(!shown) }
        do { let shown = p.advance(now: at(10.6), context: free); #expect(shown) }
        #expect(p.current(now: at(11))?.title == "Midnight City")
        // It stays for 2.5 s, then goes, and nothing is left to do.
        #expect(p.nextDeadline(now: at(11)) == at(13.1))
        p.advance(now: at(13.1), context: free)
        #expect(p.current(now: at(13.1)) == nil)
        #expect(p.peek == nil)
        #expect(p.nextDeadline(now: at(13.1)) == nil)
    }

    @Test func neverTheFirstSongAfterLaunch() {
        var p = SongPeek()
        #expect(p.nextDeadline(now: t0) == nil)
        p.ingest(nil, now: t0)
        p.ingest(song("Intro"), now: at(1))
        #expect(p.nextDeadline(now: at(1)) == nil)
        do { let shown = p.advance(now: at(5), context: free); #expect(!shown) }
        #expect(p.current(now: at(5)) == nil)
        // Even when the first song arrives paused and then plays.
        var q = SongPeek()
        q.ingest(song("Intro", playing: false), now: t0)
        q.ingest(song("Intro"), now: at(1))
        #expect(q.nextDeadline(now: at(1)) == nil)
    }

    @Test func pauseResumeAndSeekAreNotANewSong() {
        var p = started(with: song("Intro", elapsed: 30))
        p.ingest(song("Intro", playing: false, elapsed: 31), now: at(1))
        p.ingest(song("Intro", elapsed: 31), now: at(5))
        p.ingest(song("Intro", elapsed: 120, at: at(6)), now: at(6))
        #expect(p.nextDeadline(now: at(6)) == nil)
        do { let shown = p.advance(now: at(10), context: free); #expect(!shown) }
    }

    @Test func anotherPlayerWithTheSameSongIsNotANewSong() {
        var p = started(with: song("Intro", source: .system))
        p.ingest(song("Intro", source: .spotify), now: at(1))
        #expect(p.nextDeadline(now: at(1)) == nil)
    }

    @Test func anotherPlayerWithAnotherSongIs() {
        var p = started(with: song("Intro", source: .spotify))
        p.ingest(song("Podcast episode", artist: "Some show", album: nil, source: .browser), now: at(1))
        do { let shown = p.advance(now: at(1.6), context: free); #expect(shown) }
        #expect(p.current(now: at(2))?.source == .browser)
    }

    @Test func detailsArrivingLateAreTheSameSong() {
        var p = started()
        // The title first, the artist and album a moment later: still due when the title came.
        p.ingest(song("Wait", artist: nil, album: nil), now: at(10))
        p.ingest(song("Wait"), now: at(10.3))
        #expect(p.nextDeadline(now: at(10.3)) == at(10.6))
        do { let shown = p.advance(now: at(10.6), context: free); #expect(shown) }
        #expect(p.current(now: at(11))?.artist == "M83")
        // After the peek, a late artwork or album doesn't bring it back.
        p.ingest(song("Wait", album: nil), now: at(12))
        p.advance(now: at(13.5), context: free)
        p.ingest(song("Wait"), now: at(14))
        #expect(p.nextDeadline(now: at(14)) == nil)
        // A different album is a different recording.
        p.ingest(song("Wait", album: "Live at Brixton"), now: at(20))
        do { let shown = p.advance(now: at(20.6), context: free); #expect(shown) }
    }

    @Test func refinementUpdatesThePeekInPlace() {
        var p = started()
        p.ingest(song("Wait", artist: nil, album: nil), now: at(10))
        p.advance(now: at(10.6), context: free)
        p.ingest(song("Wait"), now: at(11))
        #expect(p.current(now: at(11))?.artist == "M83")
        #expect(p.peek?.until == at(13.1))
    }

    @Test func rapidSkippingShowsOnlyTheSongYouStopOn() {
        var p = started()
        var peeks = 0
        for (i, title) in ["One", "Two", "Three", "Four"].enumerated() {
            let now = at(10 + Double(i) * 0.3)
            p.ingest(song(title), now: now)
            if p.advance(now: now, context: free) { peeks += 1 }
        }
        #expect(p.nextDeadline(now: at(11)) == at(10.9 + 0.6))
        if p.advance(now: at(11.5), context: free) { peeks += 1 }
        #expect(peeks == 1)
        #expect(p.current(now: at(11.5))?.title == "Four")
    }

    @Test func skippingAwayAndBackBeforeItSettlesShowsNothing() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.ingest(song("Intro"), now: at(10.3))
        #expect(p.nextDeadline(now: at(10.3)) == nil)
        do { let shown = p.advance(now: at(11), context: free); #expect(!shown) }
    }

    @Test func pausingBeforeItSettlesShowsNothing() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.ingest(song("Two", playing: false), now: at(10.2))
        #expect(p.nextDeadline(now: at(10.2)) == nil)
        // It shows once it plays again for a moment.
        p.ingest(song("Two"), now: at(30))
        do { let shown = p.advance(now: at(30.6), context: free); #expect(shown) }
    }

    @Test func aSongIsShownOnlyOnce() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        do { let shown = p.advance(now: at(10.6), context: free); #expect(shown) }
        p.advance(now: at(13.1), context: free)
        // A gap in Now Playing and the same song again: nothing.
        p.ingest(nil, now: at(20))
        p.ingest(song("Two"), now: at(21))
        do { let shown = p.advance(now: at(22), context: free); #expect(!shown) }
        // Skipping back to the song before, or two players taking turns: nothing either.
        p.ingest(song("Intro"), now: at(30))
        do { let shown = p.advance(now: at(30.6), context: free); #expect(!shown) }
        p.ingest(song("Two"), now: at(40))
        do { let shown = p.advance(now: at(40.6), context: free); #expect(!shown) }
        // A song further back is new again.
        for (i, title) in ["Three", "Four", "Five"].enumerated() {
            let now = at(50 + Double(i) * 10)
            p.ingest(song(title), now: now)
            do { let shown = p.advance(now: now.addingTimeInterval(0.6), context: free); #expect(shown) }
        }
        p.ingest(song("Two"), now: at(90))
        do { let shown = p.advance(now: at(90.6), context: free); #expect(shown) }
    }

    @Test func notWhileOpenHiddenOrBusyAndNeverLate() {
        for context in [SongPeek.Context(isOpen: true), SongPeek.Context(isHidden: true),
                        SongPeek.Context(isBusy: true), SongPeek.Context(enabled: false)] {
            var p = started()
            p.ingest(song("Two"), now: at(10))
            do { let shown = p.advance(now: at(10.6), context: context); #expect(!shown) }
            #expect(p.current(now: at(10.6)) == nil)
            // Once the island is free again, the song that settled meanwhile isn't shown late.
            #expect(p.nextDeadline(now: at(10.6)) == nil)
            do { let shown = p.advance(now: at(12), context: free); #expect(!shown) }
            // The next new song is.
            p.ingest(song("Three"), now: at(20))
            do { let shown = p.advance(now: at(20.6), context: free); #expect(shown) }
        }
    }

    @Test func openingTheIslandEndsThePeek() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.advance(now: at(10.6), context: free)
        p.cancel()
        #expect(p.current(now: at(11)) == nil)
        #expect(p.nextDeadline(now: at(11)) == nil)
    }

    @Test func skippingDuringThePeekFollowsAlong() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.advance(now: at(10.6), context: free)
        p.ingest(song("Three"), now: at(12))
        #expect(p.current(now: at(12))?.title == "Three")
        #expect(p.peek?.until == at(14.5))
        #expect(p.nextDeadline(now: at(12)) == at(14.5))
        p.advance(now: at(14.5), context: free)
        #expect(p.current(now: at(14.5)) == nil)
        // The song it followed to counts as shown.
        p.ingest(song("Four"), now: at(20))
        do { let shown = p.advance(now: at(20.6), context: free); #expect(shown) }
        p.ingest(song("Three"), now: at(30))
        do { let shown = p.advance(now: at(30.6), context: free); #expect(!shown) }
    }

    @Test func thePeekGoesWhenTheMusicDoes() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.advance(now: at(10.6), context: free)
        p.ingest(nil, now: at(11))
        #expect(p.current(now: at(11)) == nil)
        // Or when the player moves to another song without playing it.
        p.ingest(song("Three"), now: at(20))
        p.advance(now: at(20.6), context: free)
        p.ingest(song("Four", playing: false), now: at(21))
        #expect(p.current(now: at(21)) == nil)
        // Pausing the song on show keeps it, paused.
        p.ingest(song("Five"), now: at(30))
        p.advance(now: at(30.6), context: free)
        p.ingest(song("Five", playing: false), now: at(31))
        #expect(p.current(now: at(31))?.isPlaying == false)
    }

    @Test func anEmptyTitleIsNotASong() {
        var p = started()
        p.ingest(song(" "), now: at(10))
        #expect(p.nextDeadline(now: at(10)) == nil)
    }

    @Test func resetForgetsEverything() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        p.reset()
        #expect(p.nextDeadline(now: at(10)) == nil)
        // The song playing when Now Playing comes back is the first one again.
        p.ingest(song("Three"), now: at(20))
        do { let shown = p.advance(now: at(21), context: free); #expect(!shown) }
    }

    @Test func dueDeadlinesComeBackAsNow() {
        var p = started()
        p.ingest(song("Two"), now: at(10))
        #expect(p.nextDeadline(now: at(15)) == at(15))
    }

    @Test func customTimings() {
        var p = SongPeek(settle: 1, duration: 4)
        p.ingest(song("Intro"), now: t0)
        p.ingest(song("Two"), now: at(10))
        do { let shown = p.advance(now: at(10.6), context: free); #expect(!shown) }
        do { let shown = p.advance(now: at(11), context: free); #expect(shown) }
        #expect(p.peek?.until == at(15))
    }
}

@Suite struct SongPeekSettingTests {
    @Test func onByDefaultAndSavedToTheConfig() throws {
        let s = IsletSettings()
        #expect(s.songChangePeek)
        #expect(!IsletSettings.decodeLenient(Data(#"{"songChangePeek": false}"#.utf8)).songChangePeek)
        // A bad value falls back to the default without touching the other keys.
        let bad = IsletSettings.decodeLenient(Data(#"{"songChangePeek": "sometimes", "pausedMusicTimeout": 30}"#.utf8))
        #expect(bad.songChangePeek)
        #expect(bad.pausedMusicTimeout == 30)
        let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        #expect(keys?["songChangePeek"] as? Bool == true)
    }
}

@Suite struct SongPeekPresenterTests {
    let np = song("Midnight City")

    @Test func showsBelowTheNotchWhenNothingOutranksIt() {
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), nowPlaying: np, songPeek: np)) == .songPeek(np))
        // Over a high-priority activity in the wings too: it only lasts a moment.
        var c = ActivityCenter()
        _ = try? c.apply(ActivitySpec(id: "h", title: "Build", priority: .high, sneak: false), now: t0)
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, nowPlaying: np, songPeek: np)) == .songPeek(np))
    }

    @Test func givesWayToAHUDASneakAndTheOpenIsland() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "done", title: "Deploy finished", state: .success), now: t0)
        if case .sneak = Presenter.present(PresenterInputs(now: t0, center: c, nowPlaying: np, songPeek: np)) {} else {
            Issue.record("an activity's sneak peek comes first")
        }
        var h = ActivityCenter()
        h.showHUD(.volume, value: 0.4, now: t0)
        if case .hud = Presenter.present(PresenterInputs(now: t0, center: h, nowPlaying: np, songPeek: np)) {} else {
            Issue.record("the HUD comes first")
        }
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), nowPlaying: np, isExpanded: true, songPeek: np)) == .expanded)
    }

    @Test func notWhileHidden() {
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), nowPlaying: np, isSuppressed: true, songPeek: np)) == .hidden)
    }

    @Test func swipingSidewaysOverItChangesTrack() {
        #expect(GestureSurface.from(.songPeek(np), homeShowsMedia: false) == .compactMedia)
        #expect(GestureMap.action(for: .left, on: .compactMedia, settings: IsletSettings()) == .nextTrack)
    }
}
