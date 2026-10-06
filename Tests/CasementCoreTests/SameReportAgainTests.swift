import Foundation
import Testing
@testable import CasementCore

/// Rule 9: a media report that says nothing new gives back the very same value, so the island
/// has no reason to draw again, while every real change still comes straight through.
@Suite struct SameReportAgainTests {
    static let spotifyID = "com.spotify.client"

    static func song(_ playing: Bool = true, elapsed: Double = 10, at seconds: TimeInterval = 0,
                     title: String = "Song", rate: Double = 1, duration: Double? = 300) -> NowPlaying {
        NowPlaying(source: .system, bundleID: spotifyID, appName: "Spotify", title: title, artist: "Band", album: "Record",
                   isPlaying: playing, duration: duration, elapsed: elapsed, playbackRate: rate,
                   timestamp: t0.addingTimeInterval(seconds))
    }

    static func report(_ players: [NowPlaying], current: String? = spotifyID) -> BridgeReport {
        BridgeReport(players: players, current: current)
    }

    // MARK: Nothing new

    /// The helper reports a playing track about once a second with an advanced position. Each
    /// report describes the same playback, so the arbiter gives back what it gave before and
    /// `AppModel`'s `next != nowPlaying` guard holds: the island stays as it is.
    @Test func aPlayingTrackReportedAgainGivesTheSameValue() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        let first = m.current(now: t0.addingTimeInterval(0.1))
        #expect(first?.elapsed == 10)
        for second in 1...20 {
            m.updateFromBridge(Self.report([Self.song(elapsed: 10 + Double(second), at: TimeInterval(second))]))
            #expect(m.current(now: t0.addingTimeInterval(Double(second) + 0.1)) == first)
        }
        // The position still reads correctly: it is worked out from the one report that stands.
        #expect(m.current(now: t0.addingTimeInterval(20))?.position(at: t0.addingTimeInterval(20)) == 30)
    }

    /// Small wobble either way (the helper samples, players round) is not a seek.
    @Test func aLittleWobbleIsNotASeek() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        let first = m.current(now: t0)
        m.updateFromBridge(Self.report([Self.song(elapsed: 11.4, at: 1)]))
        #expect(m.current(now: t0.addingTimeInterval(1)) == first)
        m.updateFromBridge(Self.report([Self.song(elapsed: 11.6, at: 2)]))
        #expect(m.current(now: t0.addingTimeInterval(2)) == first)
    }

    /// A player stopped at a half rate advances half as fast, and that is still nothing new.
    @Test func halfSpeedCountsAtHalfSpeed() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0, rate: 0.5)]))
        let first = m.current(now: t0)
        m.updateFromBridge(Self.report([Self.song(elapsed: 15, at: 10, rate: 0.5)]))
        #expect(m.current(now: t0.addingTimeInterval(10)) == first)
    }

    /// The API's own reports (`POST /v1/media`) go the same way.
    @Test func theAPIsOwnReportsAreCarriedOnToo() {
        var m = MediaArbiter()
        var pushed = Self.song(elapsed: 1, at: 0)
        pushed.source = .external
        pushed.bundleID = nil
        m.update(pushed)
        let first = m.current(now: t0)
        for second in 1...10 {
            var again = pushed
            again.elapsed = 1 + Double(second)
            again.timestamp = t0.addingTimeInterval(TimeInterval(second))
            m.update(again)
            #expect(m.current(now: t0.addingTimeInterval(Double(second))) == first)
        }
    }

    /// A paused player reported again keeps the moment it paused, as it did before: it neither
    /// becomes the newest nor outstays "Hide paused music after".
    @Test func aPausedPlayerKeepsItsMoment() {
        var m = MediaArbiter(pausedTimeout: 60)
        m.updateFromBridge(Self.report([Self.song(false, elapsed: 10, at: 0)]))
        for second in 1...30 {
            m.updateFromBridge(Self.report([Self.song(false, elapsed: 10, at: TimeInterval(second))]))
        }
        #expect(m.bridge[Self.spotifyID]?.timestamp == t0)
        #expect(m.current(now: t0.addingTimeInterval(61)) == nil)
    }

    // MARK: Every real change still comes through

    @Test func aSeekComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        m.updateFromBridge(Self.report([Self.song(elapsed: 120, at: 1)]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.elapsed == 120)
        // And backwards, which no amount of playing explains.
        m.updateFromBridge(Self.report([Self.song(elapsed: 5, at: 2)]))
        #expect(m.current(now: t0.addingTimeInterval(2))?.elapsed == 5)
    }

    /// Just past the window: a short nudge on the bar.
    @Test func aNudgePastTheToleranceComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        m.updateFromBridge(Self.report([Self.song(elapsed: 12, at: 1)]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.elapsed == 12)
    }

    @Test func aPauseComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        m.updateFromBridge(Self.report([Self.song(false, elapsed: 11, at: 1)]))
        let paused = m.current(now: t0.addingTimeInterval(1))
        #expect(paused?.isPlaying == false)
        #expect(paused?.elapsed == 11)
        #expect(m.changedAt[Self.spotifyID] == t0.addingTimeInterval(1))
        // And playing again.
        m.updateFromBridge(Self.report([Self.song(elapsed: 11, at: 2)]))
        #expect(m.current(now: t0.addingTimeInterval(2))?.isPlaying == true)
        #expect(m.changedAt[Self.spotifyID] == t0.addingTimeInterval(2))
    }

    @Test func aTrackChangeComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 290, at: 0)]))
        m.updateFromBridge(Self.report([Self.song(elapsed: 0, at: 10, title: "Next")]))
        #expect(m.current(now: t0.addingTimeInterval(10))?.title == "Next")
        #expect(m.changedAt[Self.spotifyID] == t0.addingTimeInterval(10))
    }

    @Test func aRateChangeComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        m.updateFromBridge(Self.report([Self.song(elapsed: 11, at: 1, rate: 2)]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.playbackRate == 2)
    }

    @Test func aChangedLengthComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0, duration: 300)]))
        m.updateFromBridge(Self.report([Self.song(elapsed: 11, at: 1, duration: 301)]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.duration == 301)
    }

    /// Artwork that arrives a moment after the track did shows at once.
    @Test func artworkArrivingComesThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        var withArt = Self.song(elapsed: 11, at: 1)
        withArt.artworkData = Data([1, 2, 3])
        m.updateFromBridge(Self.report([withArt]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.artworkData == Data([1, 2, 3]))
    }

    /// Shuffle and repeat pressed on the player itself show on the island's own buttons.
    @Test func shuffleAndRepeatComeThrough() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        var shuffled = Self.song(elapsed: 11, at: 1)
        shuffled.shuffle = true
        shuffled.repeatMode = .one
        m.updateFromBridge(Self.report([shuffled]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.shuffle == true)
        #expect(m.current(now: t0.addingTimeInterval(1))?.repeatMode == .one)
    }

    /// A browser often leaves a finished video listed as still playing at its very end. The
    /// island already shows the position clamped to the length, so those reports say nothing new,
    /// and rule 4a still shows the track stopped where it ended.
    @Test func aTrackStuckAtItsEndIsCarriedOnAndRule4aStillHolds() {
        var m = MediaArbiter(endedGrace: 1, endedTimeout: 30)
        m.updateFromBridge(Self.report([Self.song(elapsed: 290, at: 0, duration: 300)]))
        #expect(m.current(now: t0.addingTimeInterval(1))?.isPlaying == true)
        for second in stride(from: 10.0, through: 20.0, by: 1) {
            m.updateFromBridge(Self.report([Self.song(elapsed: 300, at: second, duration: 300)]))
        }
        #expect(m.bridge[Self.spotifyID]?.timestamp == t0)
        #expect(m.current(now: t0.addingTimeInterval(20))?.isPlaying == false)
        // Played again from the start: that is a change.
        m.updateFromBridge(Self.report([Self.song(elapsed: 0, at: 25, duration: 300)]))
        #expect(m.current(now: t0.addingTimeInterval(25))?.isPlaying == true)
        #expect(m.current(now: t0.addingTimeInterval(25))?.elapsed == 0)
    }

    /// Rule 8 still holds across a deduped stream: a bare clip from an unknown app shows once it
    /// has played long enough, and stays when it stops.
    @Test func aBareClipStillSettlesAndStays() {
        func clip(_ playing: Bool, elapsed: Double, at seconds: TimeInterval) -> NowPlaying {
            NowPlaying(source: .system, bundleID: "com.example.chat", appName: "Chat", title: "Voice note",
                       isPlaying: playing, duration: 60, elapsed: elapsed, timestamp: t0.addingTimeInterval(seconds))
        }
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([clip(true, elapsed: 0, at: 0)], current: "com.example.chat"))
        #expect(m.current(now: t0) == nil)
        for second in 1...8 {
            m.updateFromBridge(Self.report([clip(true, elapsed: Double(second), at: TimeInterval(second))],
                                           current: "com.example.chat"))
        }
        #expect(m.current(now: t0.addingTimeInterval(8))?.title == "Voice note")
        // Stopped: it has played long enough, so it keeps its place rather than vanishing.
        m.updateFromBridge(Self.report([clip(false, elapsed: 8, at: 8)], current: "com.example.chat"))
        #expect(m.current(now: t0.addingTimeInterval(9))?.title == "Voice note")
    }

    /// Carrying a report on never lets a position drift away: the check is always against the
    /// report that stands, so a player running slow re-anchors as soon as it is a fraction out.
    @Test func aSlowPlayerReanchorsRatherThanDrifting() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.song(elapsed: 10, at: 0)]))
        // Losing a fifth of a second each report: inside the window at first, past it at the
        // fourth, where it anchors again rather than drifting any further.
        var elapsed = 10.0
        for second in 1...5 {
            elapsed += 0.8
            m.updateFromBridge(Self.report([Self.song(elapsed: elapsed, at: TimeInterval(second))]))
        }
        #expect(abs((m.bridge[Self.spotifyID]?.elapsed ?? 0) - 13.2) < 0.001)
        #expect(m.bridge[Self.spotifyID]?.timestamp == t0.addingTimeInterval(4))
    }

    // MARK: The rule itself

    @Test func theRuleIsAboutOnePlayerAtATime() {
        let a = Self.song(elapsed: 10, at: 0)
        #expect(MediaArbiter.saysNothingNew(Self.song(elapsed: 11, at: 1), as: a))
        #expect(!MediaArbiter.saysNothingNew(Self.song(elapsed: 11, at: 1, title: "Other"), as: a))
        // A report from before the one that stands is not "carrying on".
        #expect(!MediaArbiter.saysNothingNew(Self.song(elapsed: 9, at: -1), as: a))
        // A live stream with no position at all: nothing new either way.
        var stream = Self.song(elapsed: 0, at: 0, duration: nil)
        stream.elapsed = nil
        var again = stream
        again.timestamp = t0.addingTimeInterval(5)
        #expect(MediaArbiter.saysNothingNew(again, as: stream))
        // One that starts reporting a position does say something new.
        again.elapsed = 4
        #expect(!MediaArbiter.saysNothingNew(again, as: stream))
    }
}
