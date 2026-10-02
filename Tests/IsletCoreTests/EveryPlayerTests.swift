import Foundation
import Testing
@testable import IsletCore

/// Every player macOS lists, as the system bridge reports them: each is offered as a chip, the
/// closed island shows what plays, and commands go through the bridge only for the player macOS
/// gives the controls to.
@Suite struct EveryPlayerTests {
    static let chromeID = "com.google.Chrome"
    static let spotifyID = "com.spotify.client"
    static let safariID = "com.apple.Safari"

    static func chrome(_ playing: Bool = true, at t: Date = t0) -> NowPlaying {
        NowPlaying(source: .browser, bundleID: chromeID, appName: "Google Chrome", title: "Live", artist: "Channel",
                   isPlaying: playing, elapsed: 0, timestamp: t)
    }

    /// Spotify as macOS lists it (through the bridge, not Spotify's own notifications).
    static func spotify(_ playing: Bool = false, at t: Date = t0.addingTimeInterval(-3600)) -> NowPlaying {
        NowPlaying(source: .system, bundleID: spotifyID, appName: "Spotify", title: "Song", artist: "Band", album: "Record",
                   isPlaying: playing, duration: 300, elapsed: 105, timestamp: t)
    }

    static func safari(_ playing: Bool = false, at t: Date = t0.addingTimeInterval(-60)) -> NowPlaying {
        NowPlaying(source: .browser, bundleID: safariID, appName: "Safari", title: "Bread at home", artist: "Kitchen notes",
                   isPlaying: playing, duration: 840, elapsed: 125, timestamp: t)
    }

    static func report(_ players: [NowPlaying], current: String?) -> BridgeReport {
        BridgeReport(players: players, current: current)
    }

    static func ids(_ list: [NowPlaying]) -> [String] { list.map(MediaArbiter.playerID) }

    /// The owner's case: a live video playing in Chrome and a song paused in Spotify an hour ago.
    @Test func aSongPausedLongAgoIsStillOffered() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify()], current: Self.chromeID))
        let now = t0.addingTimeInterval(1)
        #expect(Set(Self.ids(m.available(now: now))) == [Self.chromeID, Self.spotifyID])
        #expect(m.current(now: now)?.bundleID == Self.chromeID)
        #expect(m.closedIsland(now: now)?.bundleID == Self.chromeID)
        #expect(m.bridgePlayer == Self.chromeID)
    }

    @Test func aPlayerMacOSNoLongerListsGoes() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify(), Self.safari()], current: Self.chromeID))
        #expect(m.available(now: t0).count == 3)
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(15)), Self.safari()], current: Self.chromeID))
        #expect(Set(Self.ids(m.available(now: t0.addingTimeInterval(16)))) == [Self.chromeID, Self.safariID])
        // Nothing listed at all: nothing left.
        m.updateFromBridge(Self.report([], current: nil))
        #expect(m.available(now: t0.addingTimeInterval(17)).isEmpty)
        #expect(m.bridgePlayer == nil)
        #expect(m.isEmpty)
    }

    @Test func pickingTheLongPausedSongShowsIt() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify()], current: Self.chromeID))
        let now = t0.addingTimeInterval(2)
        m.pick(player: Self.spotifyID, at: now)
        #expect(m.pick?.player == Self.spotifyID)
        #expect(m.current(now: now)?.bundleID == Self.spotifyID)
        #expect(m.current(now: now)?.isPlaying == false)
        // The closed island keeps the video that plays.
        #expect(m.closedIsland(now: now)?.bundleID == Self.chromeID)
        // Chrome's next report, still playing, doesn't take the pick away.
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(15)), Self.spotify()], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(16))?.bundleID == Self.spotifyID)
        // Gone from macOS's list: the pick goes with it.
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(30))], current: Self.chromeID))
        #expect(m.pick == nil)
        #expect(m.current(now: t0.addingTimeInterval(31))?.bundleID == Self.chromeID)
    }

    @Test func theCurrentPlayerChanges() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify()], current: Self.chromeID))
        #expect(m.bridgePlayer == Self.chromeID)
        // Spotify played from its own window: macOS gives it the controls.
        let playing = Self.spotify(true, at: t0.addingTimeInterval(5))
        m.updateFromBridge(Self.report([playing, Self.chrome(false, at: t0.addingTimeInterval(5))], current: Self.spotifyID))
        #expect(m.bridgePlayer == Self.spotifyID)
        #expect(MediaRoute.route(for: playing, bridgeRunning: true, bridgePlayer: m.bridgePlayer) == .bridge)
        #expect(MediaRoute.route(for: Self.chrome(), bridgeRunning: true, bridgePlayer: m.bridgePlayer) == .none)
        #expect(m.closedIsland(now: t0.addingTimeInterval(6))?.bundleID == Self.spotifyID)
        // A current player macOS doesn't list (nothing loaded) has no controls to give.
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(7))], current: Self.spotifyID))
        #expect(m.bridgePlayer == nil)
    }

    /// The owner's Mac at the time of writing: Spotify, paused, has the controls while Chrome plays.
    @Test func aPausedPlayerCanHoldTheControls() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.spotify(), Self.chrome()], current: Self.spotifyID))
        let now = t0.addingTimeInterval(1)
        // The video plays, so it shows; a press on it must not reach Spotify.
        let shown = m.current(now: now)
        #expect(shown?.bundleID == Self.chromeID)
        #expect(MediaRoute.route(for: shown!, bridgeRunning: true, bridgePlayer: m.bridgePlayer) == .none)
        #expect(Self.ids(m.available(now: now)).contains(Self.spotifyID))
    }

    // MARK: Commands

    @Test func onlyThePlayerWithTheControlsGoesThroughTheBridge() {
        let bridge = Self.chromeID
        #expect(MediaRoute.route(for: Self.chrome(), bridgeRunning: true, bridgePlayer: bridge) == .bridge)
        // Spotify and Music that aren't current: their own integrations.
        #expect(MediaRoute.route(for: Self.spotify(), bridgeRunning: true, bridgePlayer: bridge) == .player(.spotify))
        let music = NowPlaying(source: .system, bundleID: "com.apple.Music", title: "x", isPlaying: false, timestamp: t0)
        #expect(MediaRoute.route(for: music, bridgeRunning: true, bridgePlayer: bridge) == .player(.appleMusic))
        // Any other: nothing, since the bridge would reach Chrome.
        #expect(MediaRoute.route(for: Self.safari(), bridgeRunning: true, bridgePlayer: bridge) == .none)
        #expect(MediaRoute.route(for: Self.safari(true), bridgeRunning: true, bridgePlayer: bridge) == .none)
        // With no app holding the controls, a command could start Music: nothing either.
        #expect(MediaRoute.route(for: Self.safari(), bridgeRunning: true, bridgePlayer: nil) == .none)
        let pushed = NowPlaying(source: .external, title: "Radio", isPlaying: true, timestamp: t0)
        #expect(MediaRoute.route(for: pushed, bridgeRunning: true, bridgePlayer: nil) == .none)
        // Safari once it has the controls.
        #expect(MediaRoute.route(for: Self.safari(), bridgeRunning: true, bridgePlayer: Self.safariID) == .bridge)
        #expect(MediaRoute.route(for: Self.safari(), bridgeRunning: false, bridgePlayer: Self.safariID) == .none)
    }

    @Test func aPressThatWentNowhereSaysWhy() {
        let safari = Self.safari()
        let hint = PlayerIntegration.hint(for: safari, route: .none, sent: false, canScript: false, bridgeRunning: true,
                                          holder: "Google Chrome")
        #expect(hint == .otherApp(OtherAppHint(app: "Safari", bundleID: Self.safariID, holder: "Google Chrome")))
        if case .otherApp(let h)? = hint {
            #expect(h.message == "Google Chrome has the controls")
            #expect(h.button == "Open Safari")
        }
        // Nobody holds them: it says where the player is controlled instead.
        let alone = PlayerIntegration.hint(for: safari, route: .none, sent: false, canScript: false, bridgeRunning: true)
        if case .otherApp(let h)? = alone { #expect(h.message == "Safari plays in its own window") } else { Issue.record("no hint") }
        // The report names no app: the installed app's name.
        var unnamed = safari
        unnamed.appName = nil
        #expect(PlayerIntegration.hint(for: unnamed, route: .none, sent: false, canScript: false, bridgeRunning: true,
                                       appName: "Safari") == alone)
        #expect(PlayerIntegration.hint(for: unnamed, route: .none, sent: false, canScript: false, bridgeRunning: true) == nil)
        // Sent, the bridge down, or no app to open: nothing to say.
        #expect(PlayerIntegration.hint(for: safari, route: .bridge, sent: true, canScript: false, bridgeRunning: true) == nil)
        #expect(PlayerIntegration.hint(for: safari, route: .none, sent: false, canScript: false, bridgeRunning: false) == nil)
        let pushed = NowPlaying(source: .external, title: "Radio", isPlaying: true, timestamp: t0)
        #expect(PlayerIntegration.hint(for: pushed, route: .none, sent: false, canScript: false, bridgeRunning: true) == nil)
        // Spotify without Automation still asks for it.
        #expect(PlayerIntegration.hint(for: Self.spotify(), route: .player(.spotify), sent: false, canScript: false,
                                       bridgeRunning: true) == .allowControl(player: "Spotify"))
        #expect(PlayerIntegration.hint(for: Self.spotify(), route: .player(.spotify), sent: false, canScript: true,
                                       bridgeRunning: true) == nil)
    }

    // MARK: The rules still hold

    /// Rule 8: a bare clip from an app that isn't a player waits its moment even among others.
    @Test func aBareClipStillWaits() {
        let clip = NowPlaying(source: .system, bundleID: "com.example.chat", title: "Voice message", isPlaying: true,
                              duration: 4, elapsed: 0, timestamp: t0)
        let song = Self.spotify(false, at: t0.addingTimeInterval(-10))
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([song, clip], current: "com.example.chat"))
        #expect(!Self.ids(m.available(now: t0.addingTimeInterval(1))).contains("com.example.chat"))
        #expect(m.current(now: t0.addingTimeInterval(1))?.bundleID == Self.spotifyID)
        #expect(m.nextDeadline(now: t0.addingTimeInterval(1)) == t0.addingTimeInterval(MediaArbiter.settle))
        // A short one that stopped never shows.
        var stopped = clip
        stopped.isPlaying = false
        stopped.timestamp = t0.addingTimeInterval(2)
        m.updateFromBridge(Self.report([song, stopped], current: Self.spotifyID))
        #expect(!Self.ids(m.available(now: t0.addingTimeInterval(4))).contains("com.example.chat"))
        // One that keeps playing does.
        var n = MediaArbiter()
        n.updateFromBridge(Self.report([Self.spotify(), clip], current: "com.example.chat"))
        #expect(n.current(now: t0.addingTimeInterval(3))?.bundleID == "com.example.chat")
    }

    @Test func hiddenAppsAndSourcesSwitchedOffAreNotOffered() {
        var m = MediaArbiter()
        m.hidden = [Self.safariID]
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify(), Self.safari()], current: Self.chromeID))
        #expect(!Self.ids(m.available(now: t0)).contains(Self.safariID))
        m.disabled = [.spotify]
        #expect(Self.ids(m.available(now: t0)) == [Self.chromeID])
        m.pick(player: Self.spotifyID, at: t0)
        #expect(m.pick == nil)
    }

    /// Rule 4 for a listed player: it stops showing by itself on time, once, and stays a chip.
    @Test func aListedPlayerRunsOutOnceAndStaysOffered() {
        var m = MediaArbiter(pausedTimeout: 60)
        let video = Self.safari(false, at: t0)
        m.updateFromBridge(Self.report([video], current: Self.safariID))
        #expect(m.current(now: t0.addingTimeInterval(59))?.bundleID == Self.safariID)
        #expect(m.nextDeadline(now: t0.addingTimeInterval(10)) == t0.addingTimeInterval(60))
        // Due: the timer comes now, not later.
        #expect(m.nextDeadline(now: t0.addingTimeInterval(61)) == t0.addingTimeInterval(61))
        let ranOut = m.expire(now: t0.addingTimeInterval(61))
        #expect(ranOut)
        #expect(m.current(now: t0.addingTimeInterval(61)) == nil)
        #expect(m.closedIsland(now: t0.addingTimeInterval(61)) == nil)
        // Noted once: no deadline loop, and nothing more to forget.
        #expect(m.nextDeadline(now: t0.addingTimeInterval(62)) == nil)
        let again = m.expire(now: t0.addingTimeInterval(62))
        #expect(!again)
        #expect(Self.ids(m.available(now: t0.addingTimeInterval(62))) == [Self.safariID])
        // The same report again changes nothing; played again, it shows.
        m.updateFromBridge(Self.report([Self.safari(false, at: t0.addingTimeInterval(70))], current: Self.safariID))
        #expect(m.current(now: t0.addingTimeInterval(71)) == nil)
        #expect(m.nextDeadline(now: t0.addingTimeInterval(71)) == nil)
        m.updateFromBridge(Self.report([Self.safari(true, at: t0.addingTimeInterval(80))], current: Self.safariID))
        #expect(m.current(now: t0.addingTimeInterval(81))?.isPlaying == true)
    }

    /// A paused player reported again unchanged keeps the moment it paused: it doesn't become
    /// the newest, and doesn't outstay "Hide paused music after" by being reported again.
    @Test func anUnchangedPausedPlayerKeepsItsMoment() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(false, at: t0), Self.safari(false, at: t0.addingTimeInterval(5))], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(6))?.bundleID == Self.safariID)
        // Chrome's info posted again, nothing changed.
        m.updateFromBridge(Self.report([Self.chrome(false, at: t0.addingTimeInterval(20)), Self.safari(false, at: t0.addingTimeInterval(5))],
                                       current: Self.chromeID))
        #expect(m.bridge[Self.chromeID]?.timestamp == t0)
        #expect(m.current(now: t0.addingTimeInterval(21))?.bundleID == Self.safariID)
        // Moved while paused (a seek): that is a change.
        var moved = Self.chrome(false, at: t0.addingTimeInterval(30))
        moved.elapsed = 40
        m.updateFromBridge(Self.report([moved, Self.safari(false, at: t0.addingTimeInterval(5))], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(31))?.bundleID == Self.chromeID)
    }

    /// Two reports from one app (two tabs): one player, the one playing.
    @Test func oneAppIsOnePlayer() {
        var m = MediaArbiter()
        var otherTab = Self.chrome(false, at: t0.addingTimeInterval(9))
        otherTab.title = "Another tab"
        m.updateFromBridge(Self.report([otherTab, Self.chrome(true, at: t0)], current: Self.chromeID))
        #expect(m.available(now: t0.addingTimeInterval(10)).count == 1)
        #expect(m.current(now: t0.addingTimeInterval(10))?.title == "Live")
    }

    /// Spotify's own notifications and macOS's listing of Spotify are one chip; the own
    /// integration's report still wins for the same song (rule 3), and still times out alone.
    @Test func spotifysOwnReportAndTheListingAreOnePlayer() {
        var m = MediaArbiter(pausedTimeout: 60)
        let own = NowPlaying(source: .spotify, bundleID: Self.spotifyID, appName: "Spotify", title: "Song", artist: "Band",
                             album: "Record", isPlaying: false, duration: 300, elapsed: 105, timestamp: t0)
        m.update(own)
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify(false, at: t0)], current: Self.chromeID))
        let offered = m.available(now: t0.addingTimeInterval(1))
        #expect(offered.count == 2)
        #expect(offered.first { $0.bundleID == Self.spotifyID }?.source == .spotify)
        m.expire(now: t0.addingTimeInterval(61))
        #expect(m.snapshots[.spotify] == nil)
        // macOS still lists it: still a chip.
        #expect(Self.ids(m.available(now: t0.addingTimeInterval(62))).contains(Self.spotifyID))
        // Known only from its own notifications, it goes on time.
        var alone = MediaArbiter(pausedTimeout: 60)
        alone.update(own)
        #expect(alone.available(now: t0.addingTimeInterval(61)).isEmpty)
    }

    /// A browser posting its info again every quarter of a minute, nothing changed, doesn't take
    /// the island back from a song that started after it: rule 2 counts changes, not reports.
    @Test func aBrowserPostingAgainDoesNotTakeTheIsland() {
        var m = MediaArbiter()
        let song = Self.spotify(true, at: t0)
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(-60)), song], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(1))?.bundleID == Self.spotifyID)
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(15)), song], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(16))?.bundleID == Self.spotifyID)
        #expect(m.closedIsland(now: t0.addingTimeInterval(16))?.bundleID == Self.spotifyID)
        #expect(Self.ids(m.available(now: t0.addingTimeInterval(16))) == [Self.spotifyID, Self.chromeID])
        #expect(m.changedAt[Self.chromeID] == t0.addingTimeInterval(-60))
        // Another video is a change: it shows.
        var video = Self.chrome(at: t0.addingTimeInterval(30))
        video.title = "Next"
        m.updateFromBridge(Self.report([video, song], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(31))?.bundleID == Self.chromeID)
        // And Spotify's next song takes it back, however often Chrome posts.
        var next = Self.spotify(true, at: t0.addingTimeInterval(40))
        next.title = "Song 2"
        video.timestamp = t0.addingTimeInterval(45)
        m.updateFromBridge(Self.report([video, next], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(46))?.bundleID == Self.spotifyID)
        // A player that goes is forgotten.
        m.updateFromBridge(Self.report([next], current: Self.spotifyID))
        #expect(m.changedAt[Self.chromeID] == nil)
    }

    /// The bridge stopping for good (given up, or unable to start) reports nothing: the live
    /// video it reported last doesn't stay "playing" with controls that reach nothing, and
    /// Spotify's own paused song is what is left.
    @Test func aBridgeThatStoppedLeavesNoVideoBehind() {
        var m = MediaArbiter()
        m.update(NowPlaying(source: .spotify, bundleID: Self.spotifyID, appName: "Spotify", title: "Song", artist: "Band",
                            isPlaying: false, duration: 300, elapsed: 105, timestamp: t0))
        m.updateFromBridge(Self.report([Self.chrome(at: t0.addingTimeInterval(10))], current: Self.chromeID))
        #expect(m.current(now: t0.addingTimeInterval(11))?.bundleID == Self.chromeID)
        m.updateFromBridge(Self.report([], current: nil))
        let later = t0.addingTimeInterval(3600 * 5)
        #expect(m.current(now: t0.addingTimeInterval(12))?.source == .spotify)
        #expect(m.closedIsland(now: t0.addingTimeInterval(12))?.isPlaying == false)
        #expect(!m.available(now: t0.addingTimeInterval(12)).contains { $0.bundleID == Self.chromeID })
        #expect(m.bridgePlayer == nil)
        #expect(m.current(now: later) == nil)
    }

    /// Spotify's own report shows, with the commands macOS lists for it.
    @Test func theCommandsComeFromTheListing() {
        var m = MediaArbiter()
        m.update(NowPlaying(source: .spotify, bundleID: Self.spotifyID, appName: "Spotify", title: "Song", artist: "Band",
                            album: "Record", isPlaying: true, duration: 300, elapsed: 105, timestamp: t0))
        var listed = Self.spotify(true, at: t0)
        listed.commands = [.play, .pause, .next, .previous, .seek]
        m.updateFromBridge(Self.report([listed], current: Self.spotifyID))
        let shown = m.current(now: t0.addingTimeInterval(1))
        #expect(shown?.source == .spotify)
        #expect(shown?.commands == [.play, .pause, .next, .previous, .seek])
    }

    /// The single-report convenience still replaces everything the bridge said.
    @Test func aSingleReportReplacesTheList() {
        var m = MediaArbiter()
        m.updateFromBridge(Self.report([Self.chrome(), Self.spotify(), Self.safari()], current: Self.chromeID))
        m.updateFromBridge(Self.safari(true, at: t0.addingTimeInterval(5)))
        #expect(Self.ids(m.available(now: t0.addingTimeInterval(6))) == [Self.safariID])
        #expect(m.bridgePlayer == Self.safariID)
        m.updateFromBridge(nil)
        #expect(m.isEmpty)
    }
}
