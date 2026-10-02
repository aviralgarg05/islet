import Foundation
import IsletCore
import Testing
@testable import IsletSystem

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// The helper's `players` line: every player macOS lists, which one has the controls, and each
/// player's artwork sent only when it changes.
@Suite struct BridgePlayersTests {
    static func line(_ players: [Any]) -> [String: Any] {
        ["type": "players", "players": players]
    }

    static let chrome: [String: Any] = [
        "title": "Live", "artist": "Channel", "elapsed": 0.0, "rate": 1.0, "timestamp": 1_800_000_000.0,
        "playing": true, "bundleID": "com.google.Chrome", "appName": "Google Chrome", "current": true,
    ]
    static let spotify: [String: Any] = [
        "title": "Song", "artist": "Band", "album": "Record", "duration": 301.2, "elapsed": 105.7,
        "timestamp": 1_799_990_000.0, "playing": false, "bundleID": "com.spotify.client", "appName": "Spotify",
    ]
    static let probe: [String: Any] = [
        "title": "Probe", "duration": 200.0, "elapsed": 10.0, "rate": 0.0, "timestamp": 1_800_000_000.0,
        "playing": false, "bundleID": "dev.islet.probe-player", "appName": "IsletProbePlayer",
    ]

    @Test func everyPlayerAndTheOneWithTheControls() throws {
        var art = BridgeArtwork()
        let report = try #require(SystemNowPlayingBridge.report(from: Self.line([Self.chrome, Self.spotify, Self.probe]), artwork: &art))
        #expect(report.players.map(MediaArbiter.playerID) == ["com.google.Chrome", "com.spotify.client", "dev.islet.probe-player"])
        #expect(report.current == "com.google.Chrome")
        #expect(report.players[0].source == .browser)
        #expect(report.players[0].isPlaying)
        #expect(report.players[0].duration == nil)
        // Spotify through the bridge is the system's, as before; Spotify's own provider is separate.
        #expect(report.players[1].source == .system)
        #expect(report.players[1].isPlaying == false)
        #expect(report.players[1].timestamp == Date(timeIntervalSince1970: 1_799_990_000))
        #expect(report.players[1].album == "Record")
        #expect(report.players[2].appName == "IsletProbePlayer")
    }

    @Test func noPlayerWithTheControls() throws {
        var art = BridgeArtwork()
        var paused = Self.chrome
        paused["current"] = nil
        let report = try #require(SystemNowPlayingBridge.report(from: Self.line([paused, Self.spotify]), artwork: &art))
        #expect(report.current == nil)
        #expect(report.players.count == 2)
        let empty = try #require(SystemNowPlayingBridge.report(from: Self.line([]), artwork: &art))
        #expect(empty.players.isEmpty)
        #expect(empty.current == nil)
    }

    /// Numbers JSON can't hold come through as missing whichever player sends them, and a player
    /// with nothing loaded is left out rather than ending the report.
    @Test func strangeNumbersAndMissingFields() throws {
        var art = BridgeArtwork()
        let odd: [String: Any] = [
            "title": "Odd", "duration": Double.infinity, "elapsed": Double.nan, "rate": -Double.infinity,
            "timestamp": Double.nan, "bundleID": "com.apple.Safari", "shuffleMode": Double.nan, "repeatMode": 1e300,
        ]
        let bare: [String: Any] = ["title": "Bare", "elapsed": 3]
        let report = try #require(SystemNowPlayingBridge.report(from: Self.line([
            odd, bare, ["artist": "No title"], ["title": ""], "not a player", ["title": "Late", "bundleID": ""],
        ]), artwork: &art))
        #expect(report.players.map(\.title) == ["Odd", "Bare", "Late"])
        let o = report.players[0]
        #expect(o.source == .browser)
        #expect(o.duration == nil)
        #expect(o.elapsed == nil)
        #expect(o.playbackRate == 1)
        // No "playing": read from the rate, which isn't a number it can trust.
        #expect(o.isPlaying)
        #expect(o.shuffle == nil)
        #expect(o.repeatMode == nil)
        #expect(abs(o.timestamp.timeIntervalSinceNow) < 60)
        // No app: the system's, under its source's name.
        #expect(MediaArbiter.playerID(report.players[1]) == "source:system")
        #expect(report.players[1].elapsed == 3)
        #expect(report.players[2].bundleID == nil)
        // A line without its list is an empty report.
        #expect(SystemNowPlayingBridge.report(from: ["type": "players"], artwork: &art)?.players.isEmpty == true)
    }

    @Test func artworkIsSentOnlyWhenAPlayersArtChanges() throws {
        var art = BridgeArtwork()
        func with(_ base: [String: Any], hash: Int, bytes: [UInt8]? = nil) -> [String: Any] {
            var p = base
            p["artworkHash"] = hash
            if let bytes { p["artwork"] = Data(bytes).base64EncodedString() }
            return p
        }
        // First sight: bytes for both.
        var r = try #require(SystemNowPlayingBridge.report(from: Self.line([
            with(Self.chrome, hash: 1, bytes: [1]), with(Self.spotify, hash: 2, bytes: [2]),
        ]), artwork: &art))
        #expect(r.players.map(\.artworkData) == [Data([1]), Data([2])])
        // Unchanged: hashes alone, and the artwork still shows.
        r = try #require(SystemNowPlayingBridge.report(from: Self.line([with(Self.chrome, hash: 1), with(Self.spotify, hash: 2)]), artwork: &art))
        #expect(r.players.map(\.artworkData) == [Data([1]), Data([2])])
        // Spotify's changes: new bytes for it only.
        r = try #require(SystemNowPlayingBridge.report(from: Self.line([with(Self.chrome, hash: 1), with(Self.spotify, hash: 3, bytes: [3])]), artwork: &art))
        #expect(r.players.map(\.artworkData) == [Data([1]), Data([3])])
        #expect(Set(art.byHash.keys) == [1, 3])
        // A report that leaves Chrome's artwork out keeps it for the same video: Chrome names its
        // artwork a moment before it sends the picture.
        r = try #require(SystemNowPlayingBridge.report(from: Self.line([Self.chrome, with(Self.spotify, hash: 3)]), artwork: &art))
        #expect(r.players[0].artworkData == Data([1]))
        #expect(Set(art.byHash.keys) == [1, 3])
        // Another video without artwork has none, and a picture goes with the player that had it.
        var next = Self.chrome
        next["title"] = "Next"
        r = try #require(SystemNowPlayingBridge.report(from: Self.line([next, with(Self.spotify, hash: 3)]), artwork: &art))
        #expect(r.players[0].artworkData == nil)
        #expect(Set(art.byHash.keys) == [3])
        r = try #require(SystemNowPlayingBridge.report(from: Self.line([with(Self.chrome, hash: 1)]), artwork: &art))
        #expect(r.players[0].artworkData == nil)
    }

    /// The commands each player takes, as macOS says (Chrome: no next or previous outside a
    /// playlist). A player without the list takes everything.
    @Test func theCommandsEachPlayerTakes() throws {
        var art = BridgeArtwork()
        var chrome = Self.chrome
        chrome["commands"] = [0, 1, 2, 3, 24]
        var spotify = Self.spotify
        spotify["commands"] = [0, 1, 2, 4, 5, 24]
        let r = try #require(SystemNowPlayingBridge.report(from: Self.line([chrome, spotify, Self.probe]), artwork: &art))
        #expect(r.players[0].commands == [.play, .pause, .togglePlayPause, .seek])
        #expect(!r.players[0].takes(.next) && !r.players[0].takes(.previous))
        #expect(r.players[1].takes(.next) && r.players[1].takes(.previous))
        #expect(r.players[2].commands == nil)
        #expect(r.players[2].takes(.next))
    }

    /// A helper on a macOS that can't list players sends the current one alone, as before.
    @Test func theSinglePlayerLineStillWorks() throws {
        var art = BridgeArtwork()
        var single = Self.spotify
        single["type"] = "nowPlaying"
        single["artworkHash"] = 9
        single["artwork"] = Data([9]).base64EncodedString()
        let r = try #require(SystemNowPlayingBridge.report(from: single, artwork: &art))
        #expect(r.players.count == 1)
        #expect(r.current == "com.spotify.client")
        #expect(r.players[0].artworkData == Data([9]))
        let empty = try #require(SystemNowPlayingBridge.report(from: ["type": "nowPlaying", "empty": true], artwork: &art))
        #expect(empty.players.isEmpty)
        #expect(empty.current == nil)
        #expect(art.byHash.isEmpty)
    }

    @Test func otherLinesAreNotReports() {
        var art = BridgeArtwork()
        for type in ["ready", "ack", "error", "unknown"] {
            #expect(SystemNowPlayingBridge.report(from: ["type": type, "title": "T"], artwork: &art) == nil)
        }
        #expect(SystemNowPlayingBridge.report(from: ["title": "T"], artwork: &art) == nil)
    }

    /// What the helper wrote on the owner's Mac (titles changed): read from the JSON text itself,
    /// so the numbers arrive as JSONSerialization gives them.
    @Test func aRealLine() throws {
        let text = """
        {"type":"players","players":[{"album":"A","appName":"Spotify","artist":"B","artworkHash":123006014,"artwork":"AQI=",\
        "bundleID":"com.spotify.client","current":true,"duration":301.224,"elapsed":132.679,"playing":false,\
        "timestamp":1790964100.5,"title":"T1"},{"appName":"Google Chrome","artist":"C","bundleID":"com.google.Chrome",\
        "elapsed":0,"playing":true,"rate":1,"timestamp":1790964150,"title":"T2"},{"appName":"IsletProbePlayer",\
        "artist":"Probe Artist","bundleID":"dev.islet.probe-player","duration":200,"elapsed":10,"playing":false,"rate":0,\
        "timestamp":1790964160,"title":"Probe Song"}]}
        """
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var art = BridgeArtwork()
        let r = try #require(SystemNowPlayingBridge.report(from: obj, artwork: &art))
        #expect(r.current == "com.spotify.client")
        #expect(r.players.map(\.isPlaying) == [false, true, false])
        #expect(r.players[0].artworkData == Data([1, 2]))
        #expect(art.byHash.keys.contains(123_006_014))
        #expect(r.players[1].duration == nil)
        #expect(r.players[1].elapsed == 0)
        #expect(r.players[2].duration == 200)
        #expect(r.players[2].timestamp == Date(timeIntervalSince1970: 1_790_964_160))
    }
}
