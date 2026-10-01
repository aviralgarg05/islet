import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

private func writtenKeys(_ s: IsletSettings) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] ?? [:]
}

private func track(_ title: String = "Midnight City", playing: Bool, at t: Double = 0, elapsed: Double = 60) -> NowPlaying {
    NowPlaying(source: .spotify, title: title, artist: "M83", isPlaying: playing, duration: 240, elapsed: elapsed,
               timestamp: t0.addingTimeInterval(t))
}

private func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }

@Suite struct PausedMusicSettingTests {
    @Test func tenSecondsByDefault() {
        #expect(IsletSettings().pausedMusicTimeout == 10)
        #expect(IsletSettings.pausedMusicChoices == [0, 5, 10, 30, 60, 300, IsletSettings.neverHide])
        #expect(!IsletSettings().keepsPausedMusic)
    }

    @Test func showPausedMediaMigrates() throws {
        // true kept paused music for good: that is "Never".
        let kept = decode(#"{"showPausedMedia": true}"#)
        #expect(kept.pausedMusicTimeout == IsletSettings.neverHide)
        #expect(kept.keepsPausedMusic)
        // false, or no key, becomes the new default.
        #expect(decode(#"{"showPausedMedia": false}"#).pausedMusicTimeout == 10)
        #expect(decode(#"{}"#).pausedMusicTimeout == 10)
        #expect(decode(#"{"showPausedMedia": "yes"}"#).pausedMusicTimeout == 10)
        // The new key wins when both are there.
        #expect(decode(#"{"showPausedMedia": true, "pausedMusicTimeout": 30}"#).pausedMusicTimeout == 30)
        #expect(decode(#"{"showPausedMedia": false, "pausedMusicTimeout": -1}"#).pausedMusicTimeout == IsletSettings.neverHide)
        // A new key that can't be read doesn't count: the old choice still carries over.
        #expect(decode(#"{"showPausedMedia": true, "pausedMusicTimeout": "soon"}"#).pausedMusicTimeout == IsletSettings.neverHide)
        #expect(decode(#"{"showPausedMedia": true, "pausedMusicTimeout": null}"#).pausedMusicTimeout == IsletSettings.neverHide)
        // The old key isn't written back, and the migration runs once.
        let keys = try writtenKeys(kept)
        #expect(keys["showPausedMedia"] == nil)
        #expect(keys["pausedMusicTimeout"] as? Double == -1)
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(kept)) == kept)
    }

    @Test func handEditedValuesAreTidied() {
        #expect(decode(#"{"pausedMusicTimeout": -30}"#).pausedMusicTimeout == IsletSettings.neverHide)
        #expect(decode(#"{"pausedMusicTimeout": 100000}"#).pausedMusicTimeout == IsletSettings.pausedMusicTimeoutRange.upperBound)
        #expect(decode(#"{"pausedMusicTimeout": 15}"#).pausedMusicTimeout == 15)
        #expect(decode(#"{"pausedMusicTimeout": "soon"}"#).pausedMusicTimeout == 10)
        #expect(decode(#"{"pausedMusicTimeout": 0}"#).pausedMusicTimeout == 0)
        // Whole seconds, as the menu offers and names them.
        #expect(decode(#"{"pausedMusicTimeout": 7.4}"#).pausedMusicTimeout == 7)
        #expect(decode(#"{"pausedMusicTimeout": 0.3}"#).pausedMusicTimeout == 0)
        #expect(decode(#"{"pausedMusicTimeout": -0.3}"#).pausedMusicTimeout == IsletSettings.neverHide)
    }
}

@Suite struct PausedMusicTests {
    @Test func aPauseShowsForTheTimeoutThenHides() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        #expect(p.show(timeout: 10, now: at(1)) == .hidden)
        p.ingest(track(playing: false), now: at(5))
        #expect(p.since == at(5))
        #expect(p.show(timeout: 10, now: at(5)) == .recent)
        #expect(p.show(timeout: 10, now: at(14.9)) == .recent)
        #expect(p.show(timeout: 10, now: at(15)) == .hidden)
        // One deadline: the moment it hides. None once that has passed.
        #expect(p.nextDeadline(timeout: 10, now: at(6)) == at(15))
        #expect(p.nextDeadline(timeout: 10, now: at(15)) == nil)
    }

    @Test func rightAwayHidesAtOnce() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        p.ingest(track(playing: false), now: at(1))
        #expect(p.show(timeout: 0, now: at(1)) == .hidden)
        #expect(p.nextDeadline(timeout: 0, now: at(1)) == nil)
    }

    @Test func neverKeepsItAfterTheDefaultMoment() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        p.ingest(track(playing: false), now: at(1))
        #expect(p.show(timeout: -1, now: at(2)) == .recent)
        #expect(p.nextDeadline(timeout: -1, now: at(2)) == at(11))
        #expect(p.show(timeout: -1, now: at(11)) == .kept)
        #expect(p.show(timeout: -1, now: at(3600)) == .kept)
    }

    @Test func playingAgainEndsThePause() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        p.ingest(track(playing: false), now: at(1))
        p.ingest(track(playing: true), now: at(2))
        #expect(p.since == nil)
        #expect(p.show(timeout: 10, now: at(3)) == .hidden)
        #expect(p.nextDeadline(timeout: 10, now: at(3)) == nil)
    }

    @Test func musicThatArrivesPausedIsNotBroughtBack() {
        // At launch, or a player reporting a paused track: nothing was paused just now.
        var p = PausedMusic()
        p.ingest(track(playing: false), now: at(0))
        #expect(p.show(timeout: 10, now: at(1)) == .hidden)
        // Unless paused music is kept for good.
        #expect(p.show(timeout: -1, now: at(1)) == .kept)
    }

    @Test func laterReportsWhilePausedDontRestartTheClock() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        p.ingest(track(playing: false), now: at(1))
        // The player fills in artwork, or the track changes while paused.
        p.ingest(track("Wait", playing: false), now: at(4))
        #expect(p.since == at(1))
        #expect(p.show(timeout: 5, now: at(6)) == .hidden)
    }

    @Test func thePlayerGoingAwayEndsIt() {
        var p = PausedMusic()
        p.ingest(track(playing: true), now: at(0))
        p.ingest(track(playing: false), now: at(1))
        p.ingest(nil, now: at(2))
        #expect(p.since == nil)
        // A paused track that comes back later wasn't paused just now.
        p.ingest(track(playing: false), now: at(3))
        #expect(p.show(timeout: 10, now: at(4)) == .hidden)
    }

    @Test func thePresenterFollowsIt() {
        var p = PausedMusic()
        let paused = track(playing: false, at: 1)
        p.ingest(track(playing: true), now: at(0))
        p.ingest(paused, now: at(1))
        let shown = Presenter.present(PresenterInputs(now: at(2), center: ActivityCenter(), nowPlaying: paused,
                                                      pausedMedia: p.show(timeout: 10, now: at(2))))
        #expect(shown == .compact(.nowPlaying(paused)))
        let later = Presenter.present(PresenterInputs(now: at(12), center: ActivityCenter(), nowPlaying: paused,
                                                      pausedMedia: p.show(timeout: 10, now: at(12))))
        #expect(later == .idle)
    }

    @Test func aBubbleKeepsMusicPausedAMomentAgo() {
        // Beside an activity, music shows as a bubble while it plays and for the moment after a
        // pause, like the island itself; music kept for good doesn't take a bubble.
        let playing = track(playing: true)
        let paused = track(playing: false)
        #expect(Presenter.mediaInView(playing, pausedMedia: .hidden) == playing)
        #expect(Presenter.mediaInView(paused, pausedMedia: .recent) == paused)
        #expect(Presenter.mediaInView(paused, pausedMedia: .hidden) == nil)
        #expect(Presenter.mediaInView(paused, pausedMedia: .kept) == nil)
        #expect(Presenter.mediaInView(nil, pausedMedia: .recent) == nil)
    }
}

@Suite struct PlaybackIntentTests {
    @Test func theButtonFlipsAtOnce() throws {
        let np = track(playing: true)
        let intent = try #require(PlaybackIntent.intended(.togglePlayPause, on: np, at: at(10)))
        #expect(!intent.isPlaying)
        let shown = intent.applied(to: np, now: at(10.2))
        #expect(!shown.isPlaying)
        // The position stops where it was at the click.
        #expect(shown.position(at: at(11)) == 70)
        #expect(PlaybackIntent.intended(.play, on: np, at: at(0))?.isPlaying == true)
        #expect(PlaybackIntent.intended(.pause, on: np, at: at(0))?.isPlaying == false)
        #expect(PlaybackIntent.intended(.next, on: np, at: at(0)) == nil)
        #expect(PlaybackIntent.intended(.seek, on: np, at: at(0)) == nil)
    }

    @Test func thePlayerTakesOverOnceItAgrees() throws {
        let np = track(playing: true)
        let intent = try #require(PlaybackIntent.intended(.togglePlayPause, on: np, at: at(10)))
        // A late report that still says playing: the click wins.
        #expect(!intent.isSettled(by: track(playing: true, at: 10.1), now: at(10.3)))
        // The player says paused: done.
        let confirmed = track(playing: false, at: 10.4, elapsed: 70.4)
        #expect(intent.isSettled(by: confirmed, now: at(10.5)))
        #expect(intent.applied(to: confirmed, now: at(10.5)) == confirmed)
    }

    @Test func aCommandThatFailedIsForgottenAfterTheWindow() throws {
        let np = track(playing: true)
        let intent = try #require(PlaybackIntent.intended(.togglePlayPause, on: np, at: at(10)))
        #expect(intent.expires == at(12))
        #expect(intent.isSettled(by: np, now: at(12)))
        #expect(intent.applied(to: np, now: at(12)) == np)
    }

    @Test func anotherTrackIgnoresIt() throws {
        let intent = try #require(PlaybackIntent.intended(.togglePlayPause, on: track(playing: true), at: at(10)))
        let other = track("Wait", playing: true, at: 10.2)
        #expect(intent.isSettled(by: other, now: at(10.3)))
        #expect(intent.applied(to: other, now: at(10.3)).isPlaying)
    }
}

@Suite struct ClosedIslandLookTests {
    @Test func artworkCornersGoFromSquareToRound() {
        var s = IsletSettings()
        #expect(s.artworkCornerRadius == 5)
        // The closed island's 20 pt artwork: the setting is the corner.
        #expect(s.artworkCorner(size: 20, standard: 5) == 5)
        // Bigger artwork keeps its own designed corner at the default.
        #expect(s.artworkCorner(size: 72, standard: 12) == 12)
        s.artworkCornerRadius = 0
        #expect(s.artworkCorner(size: 20, standard: 5) == 0)
        #expect(s.artworkCorner(size: 72, standard: 12) == 0)
        s.artworkCornerRadius = 10
        #expect(s.artworkCorner(size: 20, standard: 5) == 10)
        #expect(s.artworkCorner(size: 72, standard: 12) == 36)
        s.artworkCornerRadius = 7.5
        #expect(s.artworkCorner(size: 20, standard: 5) == 7.5)
        #expect(s.artworkCorner(size: 72, standard: 12) == 24)
        // Out of range counts as the nearest end.
        s.artworkCornerRadius = 40
        #expect(s.artworkCorner(size: 20, standard: 5) == 10)
        #expect(decode(#"{"artworkCornerRadius": 40}"#).artworkCornerRadius == 10)
        #expect(decode(#"{"artworkCornerRadius": -3}"#).artworkCornerRadius == 0)
    }

    @Test func waveAndPulseAreIndicatorStyles() {
        #expect(VisualiserStyle.allCases.starts(with: [.bars, .slim, .dots, .wave, .pulse]))
        #expect(decode(#"{"visualiserStyle": "wave"}"#).visualiserStyle == .wave)
        #expect(decode(#"{"visualiserStyle": "pulse"}"#).visualiserStyle == .pulse)
    }

    @Test func hudColour() {
        #expect(IsletSettings().hudColour == .white)
        #expect(decode(#"{"hudColour": "colourful"}"#).hudColour == .colourful)
        #expect(decode(#"{"hudColour": "accent"}"#).hudColour == .accent)
        #expect(decode(#"{"hudColour": "rainbow"}"#).hudColour == .white)
        // Volume green, brightness yellow, keyboard light blue: each distinct and readable on black.
        let tints = HUDKind.allCases.map(HUDColour.colourful)
        #expect(Set(tints).count == HUDKind.allCases.count)
        for hex in tints {
            let c = RGBA.parse(hex)
            #expect(c != nil)
            #expect((c?.contrastOnBlack ?? 0) >= 3)
        }
        #expect(HUDColour.colourful(.volume) == "#30D158")
        #expect(HUDColour.colourful(.brightness) == "#FFD60A")
        #expect(HUDColour.colourful(.keyboardBrightness) == "#64D2FF")
    }

    @Test func notchAdjustmentsLoadAndAreClamped() {
        #expect(IsletSettings().notchWidthAdjust == 0)
        #expect(IsletSettings().notchHeightAdjust == 0)
        let s = decode(#"{"notchWidthAdjust": 6, "notchHeightAdjust": -2}"#)
        #expect(s.notchAdjust == CGSize(width: 6, height: -2))
        let wild = decode(#"{"notchWidthAdjust": 90, "notchHeightAdjust": -30}"#)
        #expect(wild.notchWidthAdjust == 20)
        #expect(wild.notchHeightAdjust == -4)
        // Whole points, so the island's edges never fall between pixels.
        let fractional = decode(#"{"notchWidthAdjust": 2.7, "notchHeightAdjust": -3.6}"#)
        #expect(fractional.notchAdjust == CGSize(width: 3, height: -4))
        #expect(decode(#"{"notchWidthAdjust": "wide"}"#).notchWidthAdjust == 0)
    }
}
