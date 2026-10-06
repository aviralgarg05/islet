import AppKit
import Foundation
import ImageIO
import CasementCore

/// Runs AppleScript off the main thread on one serial queue.
public enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "casement.applescript", qos: .userInitiated)

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
/// Controlling them uses AppleScript, which needs Automation for that app. Casement never raises
/// that prompt itself: it sends Apple Events only once macOS says they are allowed, which the
/// user grants with Allow in Settings → Permissions.
public class ScriptablePlayerProvider {
    public let source: MediaSourceKind
    public let bundleID: String
    public let appName: String
    /// The Automation permission Apple Events to this player need.
    public let permission: PermissionKind
    let notificationName: String
    public var onUpdate: ((NowPlaying?) -> Void)?
    /// Fetch position/artwork with AppleScript or the network. Turned off while the system
    /// bridge is running, since it already delivers both without extra permissions.
    public var enrich = true {
        didSet { if enrich, !oldValue, observer != nil { beginEnriching() } }
    }
    /// Where scripts go once allowed; tests swap it so nothing reaches a real player.
    var scriptRunner: (String, ((NSAppleEventDescriptor?) -> Void)?) -> Void = AppleScriptRunner.run
    private var automation = AutomationGate()
    private var observer: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?
    private var openObservers: [NSObjectProtocol] = []
    private var permissionObserver: NSObjectProtocol?

    init(source: MediaSourceKind, bundleID: String, appName: String, permission: PermissionKind, notificationName: String) {
        self.source = source
        self.bundleID = bundleID
        self.appName = appName
        self.permission = permission
        self.notificationName = notificationName
        // Posted on the main thread, so it is handled there too. Kept while stopped, so an
        // Allow in Settings is known when the integration starts again.
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .casementAutomationStatus, object: nil, queue: nil
        ) { [weak self] note in
            guard let self, note.object as? String == self.bundleID,
                  let status = note.userInfo?["status"] as? PermissionStatus else { return }
            self.automationAnswered(status)
        }
    }

    deinit {
        stop()
        if let o = permissionObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Whether macOS allows Casement to send this player Apple Events.
    public var canScript: Bool { automation.allowsEvents }

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
        // macOS can only say whether Automation is allowed while the player is open, so ask again
        // when it opens (it may never come to the front) or comes to the front, as long as there's
        // no lasting answer.
        openObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification].map { name in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, self.enrich, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == self.bundleID else { return }
                self.checkAutomation(.appActivated)
            }
        }
        if enrich { beginEnriching() }
    }

    public func stop() {
        if let o = observer { DistributedNotificationCenter.default().removeObserver(o) }
        if let o = quitObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        openObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observer = nil
        quitObserver = nil
        openObservers = []
    }

    /// Catch up now if Automation is allowed; otherwise ask macOS (without a prompt) whether it is.
    private func beginEnriching() {
        if canScript {
            if AppleScriptRunner.isRunning(bundleID) { refresh() }
        } else {
            checkAutomation(.firstUse)
        }
    }

    /// Ask macOS, without a prompt, whether Apple Events may go to this player, when it's due.
    private func checkAutomation(_ trigger: AutomationGate.Trigger) {
        guard automation.shouldCheck(trigger) else { return }
        PermissionProbe.status(of: permission, readDownloads: false) { [weak self] in self?.automationAnswered($0) }
    }

    /// An answer from macOS: one of our checks, or the user's in Settings → Permissions.
    private func automationAnswered(_ status: PermissionStatus) {
        // Just allowed: catch up on what's playing.
        if automation.record(status), enrich, observer != nil, AppleScriptRunner.isRunning(bundleID) { refresh() }
    }

    /// Run AppleScript against this player, only once Automation for it is allowed. The script
    /// runs only if the player is still open when it starts (`whileRunning`): `tell application`
    /// would launch a player that quit between its notification and the script.
    /// - Returns: false when nothing was sent.
    @discardableResult
    func runScript(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) -> Bool {
        guard canScript else { return false }
        scriptRunner(Self.whileRunning(source, bundleID: bundleID), completion)
        return true
    }

    /// `source` inside a check that the player is open. Asking whether an app is running sends
    /// it nothing and never launches it.
    static func whileRunning(_ source: String, bundleID: String) -> String {
        "if application id \"\(bundleID)\" is running then\n\(source)\nend if"
    }

    /// Subclasses convert the notification payload.
    func parse(_ info: [String: Any], now: Date) -> NowPlaying? { nil }

    /// Subclasses may enrich (artwork, position) before publishing.
    func handle(_ np: NowPlaying?) { onUpdate?(np) }

    /// Ask the player for its current state (used at launch, before any notification).
    public func refresh() {}

    /// Send a transport command. Never launches the player, and sends nothing (returning false)
    /// until Automation for it is allowed.
    public func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        guard AppleScriptRunner.isRunning(bundleID) else { return false }
        guard let verb = Self.verb(for: command, position: position, bundleID: bundleID) else { return false }
        guard runScript("tell application id \"\(bundleID)\"\n\(verb)\nend tell") else {
            // macOS may not have been asked yet (the system bridge was doing the work), or not
            // while the player was open: ask now (silently), so the next press can go through.
            checkAutomation(.control)
            return false
        }
        return true
    }

    /// The AppleScript statements for a command. Pure, for tests.
    static func verb(for command: PlaybackCommand, position: Double?, bundleID: String) -> String? {
        let music = bundleID == "com.apple.Music"
        switch command {
        case .play: return "play"
        case .pause: return "pause"
        case .togglePlayPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        case .seek:
            guard let position else { return nil }
            return "set player position to \(max(0, position))"
        case .skipForward: return "set player position to (player position + \(Int(MediaSeek.skipInterval)))"
        case .skipBackward: return "set player position to (player position - \(Int(MediaSeek.skipInterval)))"
        case .toggleShuffle:
            return music ? "set shuffle enabled to not shuffle enabled" : "set shuffling to not shuffling"
        case .toggleRepeat:
            return music
                ? "if song repeat is off then\nset song repeat to all\nelse if song repeat is all then\nset song repeat to one\nelse\nset song repeat to off\nend if"
                : "set repeating to not repeating"
        }
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
        super.init(source: .appleMusic, bundleID: "com.apple.Music", appName: "Music", permission: .automationMusic,
                   notificationName: "com.apple.Music.playerInfo")
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
        runScript(script) { [weak self] result in
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
        guard AppleScriptRunner.isRunning(bundleID) else { return }
        runScript("tell application id \"com.apple.Music\" to return player position") { [weak self] result in
            guard let self, let s = result?.stringValue, let pos = Double(s.replacingOccurrences(of: ",", with: ".")) else { return }
            var np = base
            np.elapsed = pos
            np.timestamp = Date()
            self.onUpdate?(np)
            self.fetchArtwork(base: np)
        }
    }

    private func fetchArtwork(base: NowPlaying) {
        guard AppleScriptRunner.isRunning(bundleID) else { return }
        let script = "tell application id \"com.apple.Music\" to if (count of artworks of current track) > 0 then return data of artwork 1 of current track"
        runScript(script) { [weak self] result in
            // Read the header only. `NSImage(data:)` decoded the whole cover (a lossless track's
            // can be 3000 pixels square, tens of megabytes of bitmap) just to say whether the
            // bytes were a picture, and then threw it away; the island decodes it again, capped,
            // when it draws it (`ArtworkDecode`).
            guard let self, let data = result?.data, !data.isEmpty, Self.isImage(data) else { return }
            var np = base
            np.artworkData = data
            self.onUpdate?(np)
        }
    }

    /// Whether `data` is a picture, from its header alone: nothing is decoded.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }
}

public final class SpotifyProvider: ScriptablePlayerProvider {
    private var artworkCache: [String: URL] = [:]

    /// The cover-art lookup, on an ephemeral session like every other request Casement sends: no
    /// cookies, no cache and no credential store, so open.spotify.com can't leave anything
    /// behind between songs or on disk.
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    public init() {
        super.init(source: .spotify, bundleID: "com.spotify.client", appName: "Spotify", permission: .automationSpotify,
                   notificationName: "com.spotify.client.PlaybackStateChanged")
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
        session.dataTask(with: url) { [weak self] data, _, _ in
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
        runScript(script) { [weak self] result in
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
