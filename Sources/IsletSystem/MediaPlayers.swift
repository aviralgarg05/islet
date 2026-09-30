import AppKit
import Foundation
import IsletCore

/// Runs AppleScript off the main thread on one serial queue.
public enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "islet.applescript", qos: .userInitiated)

    public static func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let completion {
                DispatchQueue.main.async { completion(error == nil ? result : nil) }
            }
        }
    }

    public static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Common shape of the Music.app and Spotify integrations: both broadcast a distributed
/// notification on every state change, so no polling and no permissions are needed to read.
/// Controlling them uses AppleScript (one-time Automation consent).
public class ScriptablePlayerProvider {
    public let source: MediaSourceKind
    public let bundleID: String
    public let appName: String
    let notificationName: String
    public var onUpdate: ((NowPlaying?) -> Void)?
    /// Fetch position/artwork with AppleScript or the network. Turned off while the system
    /// bridge is running, since it already delivers both without extra permissions.
    public var enrich = true
    private var observer: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?

    init(source: MediaSourceKind, bundleID: String, appName: String, notificationName: String) {
        self.source = source
        self.bundleID = bundleID
        self.appName = appName
        self.notificationName = notificationName
    }

    deinit { stop() }

    public func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(notificationName), object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let info = note.userInfo as? [String: Any] ?? [:]
            self.handle(self.parse(info, now: Date()))
        }
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.bundleID else { return }
            self.onUpdate?(nil)
        }
        if enrich, AppleScriptRunner.isRunning(bundleID) { refresh() }
    }

    public func stop() {
        if let o = observer { DistributedNotificationCenter.default().removeObserver(o) }
        if let o = quitObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observer = nil
        quitObserver = nil
    }

    /// Subclasses convert the notification payload.
    func parse(_ info: [String: Any], now: Date) -> NowPlaying? { nil }

    /// Subclasses may enrich (artwork, position) before publishing.
    func handle(_ np: NowPlaying?) { onUpdate?(np) }

    /// Ask the player for its current state (used at launch, before any notification).
    public func refresh() {}

    /// Send a transport command. Never launches the player.
    public func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        guard AppleScriptRunner.isRunning(bundleID) else { return false }
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek:
            guard let position else { return false }
            verb = "set player position to \(max(0, position))"
        }
        AppleScriptRunner.run("tell application id \"\(bundleID)\" to \(verb)")
        return true
    }

    static func string(_ info: [String: Any], _ key: String) -> String? {
        guard let s = info[key] as? String, !s.isEmpty else { return nil }
        return s
    }

    static func number(_ info: [String: Any], _ key: String) -> Double? {
        if let d = info[key] as? Double { return d }
        if let i = info[key] as? Int { return Double(i) }
        if let n = info[key] as? NSNumber { return n.doubleValue }
        return nil
    }
}

public final class AppleMusicProvider: ScriptablePlayerProvider {
    public init() {
        super.init(source: .appleMusic, bundleID: "com.apple.Music", appName: "Music", notificationName: "com.apple.Music.playerInfo")
    }

    /// `com.apple.Music.playerInfo` payload → NowPlaying. Pure, for tests.
    public static func parse(_ info: [String: Any], now: Date) -> NowPlaying? {
        let state = string(info, "Player State") ?? ""
        guard state != "Stopped", let title = string(info, "Name") else { return nil }
        return NowPlaying(
            source: .appleMusic, bundleID: "com.apple.Music", appName: "Music", title: title,
            artist: string(info, "Artist"), album: string(info, "Album"), isPlaying: state == "Playing",
            duration: number(info, "Total Time").map { $0 / 1000 },
            elapsed: nil, timestamp: now
        )
    }

    override func parse(_ info: [String: Any], now: Date) -> NowPlaying? { Self.parse(info, now: now) }

    override func handle(_ np: NowPlaying?) {
        guard let np else { onUpdate?(nil); return }
        onUpdate?(np)
        // The notification carries no position or artwork; fetch both once per change.
        if enrich { fetchDetails(base: np) }
    }

    public override func refresh() {
        let script = """
        tell application id "com.apple.Music"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & (ASCII character 31) & (artist of t) & (ASCII character 31) & (album of t) & (ASCII character 31) & (duration of t) & (ASCII character 31) & (player position) & (ASCII character 31) & (player state as string)
        end tell
        """
        AppleScriptRunner.run(script) { [weak self] result in
            guard let self, let s = result?.stringValue, !s.isEmpty else { return }
            let p = s.components(separatedBy: "\u{1F}")
            guard p.count == 6 else { return }
            let np = NowPlaying(
                source: .appleMusic, bundleID: self.bundleID, appName: self.appName, title: p[0],
                artist: p[1].isEmpty ? nil : p[1], album: p[2].isEmpty ? nil : p[2], isPlaying: p[5] == "playing",
                duration: Double(p[3].replacingOccurrences(of: ",", with: ".")),
                elapsed: Double(p[4].replacingOccurrences(of: ",", with: ".")), timestamp: Date()
            )
            self.onUpdate?(np)
            self.fetchArtwork(base: np)
        }
    }

    private func fetchDetails(base: NowPlaying) {
        AppleScriptRunner.run("tell application id \"com.apple.Music\" to return player position") { [weak self] result in
            guard let self, let s = result?.stringValue, let pos = Double(s.replacingOccurrences(of: ",", with: ".")) else { return }
            var np = base
            np.elapsed = pos
            np.timestamp = Date()
            self.onUpdate?(np)
            self.fetchArtwork(base: np)
        }
    }

    private func fetchArtwork(base: NowPlaying) {
        let script = "tell application id \"com.apple.Music\" to if (count of artworks of current track) > 0 then return data of artwork 1 of current track"
        AppleScriptRunner.run(script) { [weak self] result in
            guard let self, let data = result?.data, !data.isEmpty, NSImage(data: data) != nil else { return }
            var np = base
            np.artworkData = data
            self.onUpdate?(np)
        }
    }
}

public final class SpotifyProvider: ScriptablePlayerProvider {
    private var artworkCache: [String: URL] = [:]

    public init() {
        super.init(source: .spotify, bundleID: "com.spotify.client", appName: "Spotify", notificationName: "com.spotify.client.PlaybackStateChanged")
    }

    /// `com.spotify.client.PlaybackStateChanged` payload → NowPlaying. Pure, for tests.
    public static func parse(_ info: [String: Any], now: Date) -> NowPlaying? {
        let state = string(info, "Player State") ?? ""
        guard state != "Stopped", let title = string(info, "Name") else { return nil }
        return NowPlaying(
            source: .spotify, bundleID: "com.spotify.client", appName: "Spotify", title: title,
            artist: string(info, "Artist"), album: string(info, "Album"), isPlaying: state == "Playing",
            duration: number(info, "Duration").map { $0 / 1000 },
            elapsed: number(info, "Playback Position"), timestamp: now
        )
    }

    /// `spotify:track:ID` → oEmbed URL that returns the cover art without auth or AppleScript.
    public static func oEmbedURL(trackID: String) -> URL? {
        let parts = trackID.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track" else { return nil }
        var c = URLComponents(string: "https://open.spotify.com/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(parts[2])")]
        return c.url
    }

    private var lastTrackID: String?

    override func parse(_ info: [String: Any], now: Date) -> NowPlaying? {
        lastTrackID = Self.string(info, "Track ID")
        return Self.parse(info, now: now)
    }

    override func handle(_ np: NowPlaying?) {
        guard var np else { onUpdate?(nil); return }
        if let id = lastTrackID, let cached = artworkCache[id] {
            np.artworkURL = cached
            onUpdate?(np)
            return
        }
        onUpdate?(np)
        guard enrich, let id = lastTrackID, let url = Self.oEmbedURL(trackID: id) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = (obj["thumbnail_url"] as? String).flatMap(URL.init(string:)) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.artworkCache.count >= 100 { self.artworkCache.removeAll() }
                self.artworkCache[id] = thumb
                var enriched = np
                enriched.artworkURL = thumb
                self.onUpdate?(enriched)
            }
        }.resume()
    }

    public override func refresh() {
        let script = """
        tell application id "com.spotify.client"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & (ASCII character 31) & (artist of t) & (ASCII character 31) & (album of t) & (ASCII character 31) & (duration of t) & (ASCII character 31) & (player position) & (ASCII character 31) & (player state as string) & (ASCII character 31) & (artwork url of t)
        end tell
        """
        AppleScriptRunner.run(script) { [weak self] result in
            guard let self, let s = result?.stringValue, !s.isEmpty else { return }
            let p = s.components(separatedBy: "\u{1F}")
            guard p.count == 7 else { return }
            let np = NowPlaying(
                source: .spotify, bundleID: self.bundleID, appName: self.appName, title: p[0],
                artist: p[1].isEmpty ? nil : p[1], album: p[2].isEmpty ? nil : p[2], isPlaying: p[5] == "playing",
                duration: Double(p[3]).map { $0 / 1000 },
                elapsed: Double(p[4].replacingOccurrences(of: ",", with: ".")), timestamp: Date(),
                artworkURL: URL(string: p[6])
            )
            self.onUpdate?(np)
        }
    }
}
