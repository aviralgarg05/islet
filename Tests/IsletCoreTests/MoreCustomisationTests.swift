import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

private func writtenKeys(_ s: IsletSettings) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] ?? [:]
}

private func song(playing: Bool, elapsed: Double? = 60, duration: Double? = 240, rate: Double = 1, at t: Double = 0) -> NowPlaying {
    NowPlaying(source: .spotify, title: "Midnight City", artist: "M83", isPlaying: playing, duration: duration,
               elapsed: elapsed, playbackRate: rate, timestamp: t0.addingTimeInterval(t))
}

@Suite struct MusicColourTests {
    @Test func artworkByDefaultWithTheRingOff() {
        #expect(IsletSettings().musicColour == .artwork)
        #expect(IsletSettings().songProgressRing == false)
        #expect(decode(#"{"songProgressRing": true}"#).songProgressRing)
        #expect(decode(#"{"musicColour": "accent"}"#).musicColour == .accent)
        #expect(decode(#"{"musicColour": "plaid"}"#).musicColour == .artwork)
    }

    @Test func visualiserColourCarriesOver() throws {
        // The indicator's own colour becomes the colour of all the music.
        let old = decode(#"{"visualiserColour": "white"}"#)
        #expect(old.musicColour == .white)
        #expect(decode(#"{"visualiserColour": "accent"}"#).musicColour == .accent)
        // A value that can't be read leaves the default.
        #expect(decode(#"{"visualiserColour": "neon"}"#).musicColour == .artwork)
        #expect(decode(#"{"visualiserColour": 3}"#).musicColour == .artwork)
        // The new key wins, and the old one isn't written back.
        #expect(decode(#"{"visualiserColour": "white", "musicColour": "accent"}"#).musicColour == .accent)
        // A new key that can't be read doesn't count: the old choice still carries over.
        #expect(decode(#"{"visualiserColour": "white", "musicColour": "neon"}"#).musicColour == .white)
        let keys = try writtenKeys(old)
        #expect(keys["visualiserColour"] == nil)
        #expect(keys["musicColour"] as? String == "white")
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(old)) == old)
    }
}

@Suite struct SongProgressTests {
    @Test func fillsFromWhereTheSongIsToItsEnd() {
        let p = SongProgress(song(playing: true), now: t0.addingTimeInterval(20))
        #expect(p?.fraction == 80.0 / 240)
        #expect(p?.remaining == 160)
    }

    @Test func pausedHoldsStill() {
        let p = SongProgress(song(playing: false), now: t0.addingTimeInterval(20))
        #expect(p?.fraction == 0.25)
        #expect(p?.remaining == nil)
    }

    @Test func followsThePlayersRate() {
        let p = SongProgress(song(playing: true, rate: 2), now: t0)
        #expect(p?.remaining == 90)
        // A rate of nothing doesn't move.
        #expect(SongProgress(song(playing: true, rate: 0), now: t0)?.remaining == nil)
    }

    @Test func nothingToFillWithoutALength() {
        #expect(SongProgress(song(playing: true, duration: nil), now: t0) == nil)
        #expect(SongProgress(song(playing: true, duration: 0), now: t0) == nil)
        #expect(SongProgress(song(playing: true, duration: .infinity), now: t0) == nil)
        #expect(SongProgress(song(playing: true, elapsed: nil), now: t0) == nil)
    }

    @Test func staysInsideTheRing() {
        // A report from long ago, or past the end, is full and has nothing left.
        let late = SongProgress(song(playing: true), now: t0.addingTimeInterval(10_000))
        #expect(late?.fraction == 1)
        #expect(late?.remaining == 0)
        #expect(SongProgress(song(playing: false, elapsed: -5), now: t0)?.fraction == 0)
    }
}

@Suite struct SongPeekLengthTests {
    @Test func peekLastsTheGivenTime() {
        // AppModel builds the peek with "New activities stay open for".
        var peek = SongPeek(settle: 0.6, duration: IsletSettings().alertDuration)
        peek.ingest(song(playing: true), now: t0)
        var next = song(playing: true)
        next.title = "Wait"
        peek.ingest(next, now: t0.addingTimeInterval(1))
        let first = peek.advance(now: t0.addingTimeInterval(1.6), context: .init())
        #expect(first)
        #expect(peek.current(now: t0.addingTimeInterval(1.6 + 2.4)) != nil)
        #expect(peek.current(now: t0.addingTimeInterval(1.6 + 2.5)) == nil)
        peek.duration = 5
        var third = song(playing: true)
        third.title = "Outro"
        peek.ingest(third, now: t0.addingTimeInterval(10))
        let second = peek.advance(now: t0.addingTimeInterval(10.6), context: .init())
        #expect(second)
        #expect(peek.current(now: t0.addingTimeInterval(15.5)) != nil)
        #expect(peek.current(now: t0.addingTimeInterval(15.6)) == nil)
    }
}

@Suite struct HoverPeekTests {
    private var clickToOpen: IsletSettings {
        var s = IsletSettings()
        s.hoverToOpen = false
        return s
    }

    @Test func onByDefaultForClickToOpen() {
        #expect(IsletSettings().peekOnHover)
        #expect(decode(#"{"peekOnHover": false}"#).peekOnHover == false)
        let np = song(playing: true)
        #expect(Presenter.hoverPeek(np, hovering: true, settings: clickToOpen) == np)
        // Paused music is still what's playing.
        #expect(Presenter.hoverPeek(song(playing: false), hovering: true, settings: clickToOpen) != nil)
    }

    @Test func onlyWhileHoveringAndOnlyWhenHoverDoesNotOpen() {
        let np = song(playing: true)
        #expect(Presenter.hoverPeek(np, hovering: false, settings: clickToOpen) == nil)
        // Hovering opens the island, so there is nothing to peek at.
        #expect(Presenter.hoverPeek(np, hovering: true, settings: IsletSettings()) == nil)
        var off = clickToOpen
        off.peekOnHover = false
        #expect(Presenter.hoverPeek(np, hovering: true, settings: off) == nil)
        var noMedia = clickToOpen
        noMedia.mediaEnabled = false
        #expect(Presenter.hoverPeek(np, hovering: true, settings: noMedia) == nil)
        #expect(Presenter.hoverPeek(nil, hovering: true, settings: clickToOpen) == nil)
    }

    @Test func showsAsASongPeekBelowAHUD() {
        let np = song(playing: true)
        var center = ActivityCenter()
        let peek = Presenter.present(PresenterInputs(now: t0, center: center, nowPlaying: np, songPeek: np))
        #expect(peek == .songPeek(np))
        center.showHUD(.volume, value: 0.5, now: t0)
        let hud = Presenter.present(PresenterInputs(now: t0, center: center, nowPlaying: np, songPeek: np))
        if case .hud = hud {} else { Issue.record("expected the HUD, got \(hud)") }
    }
}

@Suite struct HUDChoiceTests {
    @Test func compactAndEveryKindByDefault() {
        let s = IsletSettings()
        #expect(s.hudStyle == .compact)
        #expect(HUDKind.allCases.allSatisfy(s.showsHUD))
        #expect(s.showsAnyHUD)
        #expect(decode(#"{"hudStyle": "detailed"}"#).hudStyle == .detailed)
        #expect(decode(#"{"hudStyle": "huge"}"#).hudStyle == .compact)
    }

    @Test func eachKindHasItsOwnSwitch() {
        let s = decode(#"{"keyboardHUDEnabled": false, "microphoneHUDEnabled": false}"#)
        #expect(s.showsHUD(.volume))
        #expect(s.showsHUD(.brightness))
        #expect(!s.showsHUD(.keyboardBrightness))
        #expect(!s.showsHUD(.microphone))
        let none = decode(#"{"hudEnabled": false, "brightnessHUDEnabled": false, "keyboardHUDEnabled": false, "microphoneHUDEnabled": false}"#)
        #expect(!none.showsAnyHUD)
    }
}
