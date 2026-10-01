import Foundation
import Testing
@testable import IsletCore

/// Several players at once (a Chrome video and a Spotify song): the island lists them, shows the
/// one you pick, and sends its commands to that player only.
@Suite struct PlayerSwitchTests {
    static func chrome(_ playing: Bool = true, at t: Date = t0, title: String = "Talk") -> NowPlaying {
        NowPlaying(source: .browser, bundleID: "com.google.Chrome", appName: "Chrome", title: title, isPlaying: playing,
                   duration: 3600, elapsed: 10, timestamp: t)
    }

    static func spotify(_ playing: Bool = true, at t: Date = t0, title: String = "Song", source: MediaSourceKind = .spotify) -> NowPlaying {
        NowPlaying(source: source, bundleID: "com.spotify.client", appName: "Spotify", title: title, artist: "Band",
                   isPlaying: playing, duration: 200, elapsed: 5, timestamp: t)
    }

    static let chromeID = "com.google.Chrome"
    static let spotifyID = "com.spotify.client"

    @Test func listsOnePlayerPerAppNewestFirst() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.chrome(false, at: t0))
        m.update(Self.spotify(true, at: t0.addingTimeInterval(5)))
        #expect(m.available(now: t0.addingTimeInterval(6)).map(MediaArbiter.playerID) == [Self.spotifyID, Self.chromeID])
        // The bridge reporting Spotify too is still one Spotify (and Chrome, no longer reported, goes).
        m.updateFromBridge(Self.spotify(true, at: t0.addingTimeInterval(7), source: .system))
        #expect(m.available(now: t0.addingTimeInterval(8)).map(MediaArbiter.playerID) == [Self.spotifyID])
        #expect(m.bridgePlayer == Self.spotifyID)
    }

    @Test func aPlayerWithoutAnAppJoinsTheOneOnTheSameTrack() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.chrome(true, at: t0))
        m.update(NowPlaying(source: .external, title: "Talk", isPlaying: true, timestamp: t0.addingTimeInterval(1)))
        let players = m.available(now: t0.addingTimeInterval(2))
        #expect(players.count == 1)
        #expect(players.first?.bundleID == Self.chromeID)
        // On another track it is a player of its own.
        m.update(NowPlaying(source: .external, title: "Radio", isPlaying: true, timestamp: t0.addingTimeInterval(3)))
        #expect(m.available(now: t0.addingTimeInterval(4)).map(MediaArbiter.playerID) == ["source:external", Self.chromeID])
    }

    @Test func thePickShowsWhileItIsLive() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.chrome(false, at: t0))
        m.update(Self.spotify(true, at: t0.addingTimeInterval(5)))
        let now = t0.addingTimeInterval(10)
        #expect(m.current(now: now)?.bundleID == Self.spotifyID)
        m.pick(player: Self.chromeID, at: now)
        #expect(m.pick?.player == Self.chromeID)
        #expect(m.current(now: now)?.bundleID == Self.chromeID)
        // Spotify carrying on (a new song while playing) doesn't take over.
        m.update(Self.spotify(true, at: now.addingTimeInterval(60), title: "Next song"))
        #expect(m.current(now: now.addingTimeInterval(61))?.bundleID == Self.chromeID)
        // Playing the picked one keeps it.
        m.updateFromBridge(Self.chrome(true, at: now.addingTimeInterval(70)))
        #expect(m.current(now: now.addingTimeInterval(71))?.bundleID == Self.chromeID)
    }

    @Test func anotherPlayerStartingAfterThePickTakesOver() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.chrome(true, at: t0))
        m.update(Self.spotify(false, at: t0.addingTimeInterval(1)))
        m.pick(player: Self.spotifyID, at: t0.addingTimeInterval(2))
        #expect(m.current(now: t0.addingTimeInterval(3))?.bundleID == Self.spotifyID)
        // Chrome was already playing: a fresh report from it changes nothing.
        m.updateFromBridge(Self.chrome(true, at: t0.addingTimeInterval(4)))
        #expect(m.current(now: t0.addingTimeInterval(5))?.bundleID == Self.spotifyID)
        // Paused, then playing again: that is a start, after the pick.
        m.updateFromBridge(Self.chrome(false, at: t0.addingTimeInterval(6)))
        m.updateFromBridge(Self.chrome(true, at: t0.addingTimeInterval(7)))
        #expect(m.pick == nil)
        #expect(m.current(now: t0.addingTimeInterval(8))?.bundleID == Self.chromeID)
    }

    @Test func thePickEndsWhenThePlayerGoes() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.chrome(false, at: t0))
        m.update(Self.spotify(true, at: t0.addingTimeInterval(1)))
        m.pick(player: Self.chromeID, at: t0.addingTimeInterval(2))
        // The bridge now reports Spotify: the Chrome video isn't known any more.
        m.updateFromBridge(Self.spotify(true, at: t0.addingTimeInterval(3), source: .system))
        #expect(m.pick == nil)
        #expect(m.current(now: t0.addingTimeInterval(4))?.bundleID == Self.spotifyID)

        var quit = MediaArbiter()
        quit.updateFromBridge(Self.chrome(true, at: t0))
        quit.update(Self.spotify(false, at: t0.addingTimeInterval(1)))
        quit.pick(player: Self.spotifyID, at: t0.addingTimeInterval(2))
        quit.clear(.spotify)
        #expect(quit.pick == nil)

        // A paused pick that times out goes too.
        var timeout = MediaArbiter(pausedTimeout: 60)
        timeout.updateFromBridge(Self.chrome(true, at: t0))
        timeout.update(Self.spotify(false, at: t0))
        timeout.pick(player: Self.spotifyID, at: t0.addingTimeInterval(1))
        timeout.expire(now: t0.addingTimeInterval(61))
        #expect(timeout.pick == nil)
    }

    @Test func aPlayerThatIsNotLiveCantBePicked() {
        var m = MediaArbiter()
        m.update(Self.spotify(true, at: t0))
        m.pick(player: Self.chromeID, at: t0)
        #expect(m.pick == nil)
        // A source switched off isn't live either.
        m.updateFromBridge(Self.chrome(true, at: t0))
        m.disabled = [.browser]
        m.pick(player: Self.chromeID, at: t0)
        #expect(m.pick == nil)
        #expect(m.available(now: t0).map(MediaArbiter.playerID) == [Self.spotifyID])
    }

    // MARK: Commands

    @Test func commandsGoToThePickedPlayer() {
        // Chrome is the bridge's: Chrome's commands go there, Spotify's to Spotify itself.
        #expect(MediaRoute.route(for: Self.chrome(), bridgeRunning: true, bridgePlayer: Self.chromeID) == .bridge)
        #expect(MediaRoute.route(for: Self.spotify(), bridgeRunning: true, bridgePlayer: Self.chromeID) == .player(.spotify))
        // The bridge reporting Spotify reaches it without Automation.
        #expect(MediaRoute.route(for: Self.spotify(), bridgeRunning: true, bridgePlayer: Self.spotifyID) == .bridge)
        #expect(MediaRoute.route(for: Self.spotify(source: .system), bridgeRunning: true, bridgePlayer: Self.spotifyID) == .bridge)
        // Music reported by the bridge while the bridge has moved on: its own integration.
        let music = NowPlaying(source: .system, bundleID: "com.apple.Music", title: "x", isPlaying: false, timestamp: t0)
        #expect(MediaRoute.route(for: music, bridgeRunning: true, bridgePlayer: Self.chromeID) == .player(.appleMusic))
        // Bridge down: only Music and Spotify can still be reached.
        #expect(MediaRoute.route(for: Self.spotify(), bridgeRunning: false, bridgePlayer: nil) == .player(.spotify))
        #expect(MediaRoute.route(for: Self.chrome(), bridgeRunning: false, bridgePlayer: Self.chromeID) == .none)
        // A player pushed through the API: the bridge, unless it is reporting another app.
        let pushed = NowPlaying(source: .external, title: "Radio", isPlaying: true, timestamp: t0)
        #expect(MediaRoute.route(for: pushed, bridgeRunning: true, bridgePlayer: nil) == .bridge)
        #expect(MediaRoute.route(for: pushed, bridgeRunning: true, bridgePlayer: Self.chromeID) == .none)
    }

    @Test func askingForAutomationOnlyWhenItWouldHelp() {
        #expect(PlayerIntegration.controlHint(route: .player(.spotify), sent: false, canScript: false) == "Spotify")
        #expect(PlayerIntegration.controlHint(route: .player(.appleMusic), sent: false, canScript: false) == "Music")
        #expect(PlayerIntegration.controlHint(route: .player(.spotify), sent: true, canScript: false) == nil)
        #expect(PlayerIntegration.controlHint(route: .player(.spotify), sent: false, canScript: true) == nil)
        #expect(PlayerIntegration.controlHint(route: .bridge, sent: false, canScript: false) == nil)
        #expect(PlayerIntegration.controlHint(route: .none, sent: false, canScript: false) == nil)
    }
}
