import Foundation

/// Where a now-playing snapshot came from. Several providers can report at once
/// (e.g. the system-wide MediaRemote bridge *and* Spotify's own notifications);
/// the arbiter below picks one.
public enum MediaSourceKind: String, Codable, Sendable, CaseIterable {
    /// System-wide now playing via the MediaRemote bridge (covers most apps and browsers).
    case system
    case appleMusic
    case spotify
    case browser
    /// Pushed through the local API (`POST /v1/media`) by any app or script.
    case external

    /// The dedicated integration for a player's bundle ID (Music, Spotify), if it has one.
    public static func player(bundleID: String?) -> MediaSourceKind? {
        switch bundleID {
        case "com.apple.Music": return .appleMusic
        case "com.spotify.client": return .spotify
        default: return nil
        }
    }
}

/// Islet's own Music and Spotify integrations: when they run, and what to say when their
/// controls can't reach the player.
public enum PlayerIntegration {
    /// Music or Spotify switched off in Settings runs not at all: it reads no notifications
    /// and sends no AppleScript, whether or not the system bridge is up.
    public static func runs(_ source: MediaSourceKind, disabled: Set<MediaSourceKind>) -> Bool {
        !disabled.contains(source)
    }

    /// Whether it fetches position and artwork itself (AppleScript, or Spotify's cover art):
    /// only while it runs and the system bridge, which already brings both, is down.
    public static func enriches(_ source: MediaSourceKind, disabled: Set<MediaSourceKind>, bridgeRunning: Bool) -> Bool {
        runs(source, disabled: disabled) && !bridgeRunning
    }

    /// The player to name in "Allow Islet to control …" after a control press went nowhere: the
    /// bridge is down and macOS hasn't allowed Apple Events to Music or Spotify. Nil otherwise.
    public static func controlHint(for source: MediaSourceKind, sent: Bool, bridgeRunning: Bool, canScript: Bool) -> String? {
        let route: MediaRoute = bridgeRunning ? .bridge : source == .spotify || source == .appleMusic ? .player(source) : .none
        return controlHint(route: route, sent: sent, canScript: canScript)
    }

    /// The same for a press routed to `route`: only Music's and Spotify's own integrations need
    /// Automation, so only a press that went to one of them, unsent and not allowed, asks.
    public static func controlHint(route: MediaRoute, sent: Bool, canScript: Bool) -> String? {
        guard !sent, !canScript, case .player(let source) = route else { return nil }
        switch source {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        default: return nil
        }
    }
}

/// Where a command for the player on show goes. The system bridge controls whichever app macOS
/// treats as now playing, so it is used only for that app: with a Chrome video and a Spotify
/// song both live, a press on Spotify must not pause the video.
public enum MediaRoute: Equatable, Sendable {
    /// The system bridge (no permission needed).
    case bridge
    /// Music's or Spotify's own integration: AppleScript, once Automation for it is allowed.
    case player(MediaSourceKind)
    /// Nothing would reach this player.
    case none

    /// - Parameters:
    ///   - bridgePlayer: the player the bridge last reported (`MediaArbiter.bridgePlayer`).
    public static func route(for np: NowPlaying, bridgeRunning: Bool, bridgePlayer: String?) -> MediaRoute {
        let id = MediaArbiter.playerID(np)
        if bridgeRunning, bridgePlayer == id { return .bridge }
        if let own = MediaSourceKind.player(bundleID: np.bundleID) ?? ([.spotify, .appleMusic].contains(np.source) ? np.source : nil) {
            return .player(own)
        }
        // A player only the bridge or the API knows about: the bridge reaches it unless it is
        // reporting another app.
        return bridgeRunning && bridgePlayer == nil ? .bridge : .none
    }
}

public enum PlaybackCommand: String, Codable, Sendable, CaseIterable {
    case play, pause, togglePlayPause, next, previous, seek
    /// Jump 15 s forward or back, computed from the current position so it works with any player.
    case skipForward, skipBackward
    /// Only offered when the player reports its shuffle or repeat state.
    case toggleShuffle, toggleRepeat
}

public enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off, one, all
}

public struct NowPlaying: Codable, Equatable, Sendable {
    public var source: MediaSourceKind
    /// Bundle id of the player app, when known (used for the app icon and "open player").
    public var bundleID: String?
    public var appName: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    /// Seconds.
    public var duration: Double?
    /// Elapsed seconds at `timestamp`.
    public var elapsed: Double?
    public var playbackRate: Double
    /// When `elapsed` was sampled; lets the UI extrapolate without polling.
    public var timestamp: Date
    public var artworkData: Data?
    public var artworkURL: URL?
    /// Shuffle state; nil when the player doesn't report it (no shuffle button then).
    public var shuffle: Bool?
    /// Repeat state; nil when the player doesn't report it (no repeat button then).
    public var repeatMode: RepeatMode?

    public init(
        source: MediaSourceKind, bundleID: String? = nil, appName: String? = nil, title: String,
        artist: String? = nil, album: String? = nil, isPlaying: Bool, duration: Double? = nil,
        elapsed: Double? = nil, playbackRate: Double = 1, timestamp: Date,
        artworkData: Data? = nil, artworkURL: URL? = nil, shuffle: Bool? = nil, repeatMode: RepeatMode? = nil
    ) {
        self.source = source; self.bundleID = bundleID; self.appName = appName; self.title = title
        self.artist = artist; self.album = album; self.isPlaying = isPlaying; self.duration = duration
        self.elapsed = elapsed; self.playbackRate = playbackRate; self.timestamp = timestamp
        self.artworkData = artworkData; self.artworkURL = artworkURL
        self.shuffle = shuffle; self.repeatMode = repeatMode
    }

    /// Elapsed time extrapolated to `now` (clamped to the duration).
    public func position(at now: Date) -> Double? {
        guard let elapsed else { return nil }
        var pos = elapsed
        if isPlaying { pos += now.timeIntervalSince(timestamp) * playbackRate }
        if let duration, duration > 0 { pos = min(pos, duration) }
        return max(0, pos)
    }

    public func fraction(at now: Date) -> Double? {
        guard let duration, duration > 0, let pos = position(at: now) else { return nil }
        return pos / duration
    }

    /// When a playing track reaches its end, extrapolated from the last report. Nil when it
    /// isn't playing or has no length (a live stream).
    public var endsAt: Date? {
        guard isPlaying, let duration, duration > 0, let elapsed, playbackRate > 0 else { return nil }
        return timestamp.addingTimeInterval(max(0, duration - elapsed) / playbackRate)
    }

    /// Identity of the track, ignoring position/playing state. Used to detect track changes.
    public var trackKey: String {
        [title, artist ?? "", album ?? ""].joined(separator: "\u{1F}")
    }
}

/// Chooses which player to show when several report state.
///
/// Rules, in order:
/// 1. Anything playing beats anything paused.
/// 2. Among equals, the most recently updated wins (the player you touched last).
/// 3. Direct app integrations beat the generic system bridge when they describe the same
///    track, because they carry richer data (artwork URL, reliable state).
/// 4. Paused players are forgotten after `pausedTimeout` so a stale track doesn't linger forever.
/// 4a. A track that still says it is playing well past its end (a browser often never reports
///     that a video finished) counts as paused from its end and goes after `endedTimeout`.
/// 5. Sources switched off in settings are ignored. Music and Spotify count as themselves even
///    when the system bridge reports them (`setting(for:)`).
/// 6. A player picked in the island (`pick(player:at:)`) is shown in the open island and
///    controlled instead, while it is live, until another player starts playing after the pick
///    or the picked one goes. The closed island keeps showing what plays (`closedIsland`).
/// 7. Apps the user hid (`hidden`, Settings → Now Playing → Ignore apps) never show.
/// 8. An app Islet doesn't know as a player, reporting nothing but a title (a voice note, a
///    sound in a chat app, a muted preview), shows only once it has played for `settle`
///    seconds, so a short clip doesn't take over.
///
/// Several players can be live at once, one per app (`available`): the bridge's (a Chrome video,
/// say), Spotify's and Music's own, and one pushed through the API.
public struct MediaArbiter: Sendable {
    public private(set) var snapshots: [MediaSourceKind: NowPlaying] = [:]
    /// The player chosen in the island, and when.
    public private(set) var pick: MediaPick?
    public var pausedTimeout: TimeInterval
    /// Seconds past a track's end before a player that still says "playing" is believed to have
    /// stopped, so a slow report of the next track doesn't flicker the island.
    public var endedGrace: TimeInterval
    /// Seconds after its end that such a track is forgotten.
    public var endedTimeout: TimeInterval
    /// Sources the user switched off in settings.
    public var disabled: Set<MediaSourceKind>
    /// Apps the user hid (bundle ids), whatever source reports them.
    public var hidden: Set<String> = []
    /// Seconds an unknown app's bare clip must play before it shows (rule 8).
    public static let settle: TimeInterval = 3
    /// Rule 8: when each bare clip from an unknown app started playing, by track.
    private var playingSince: [String: Date] = [:]
    /// Rule 8: bare clips that have played long enough, by track.
    private var settled: Set<String> = []

    /// The kinds the system-wide bridge reports. It describes one player at a time, so each of
    /// its reports replaces all of them.
    public static let bridgeSources: Set<MediaSourceKind> = [.system, .browser]

    public init(pausedTimeout: TimeInterval = 15 * 60, endedGrace: TimeInterval = 5, endedTimeout: TimeInterval = 120,
                disabled: Set<MediaSourceKind> = []) {
        self.pausedTimeout = pausedTimeout
        self.endedGrace = endedGrace
        self.endedTimeout = endedTimeout
        self.disabled = disabled
    }

    public mutating func update(_ snapshot: NowPlaying) {
        let id = Self.playerID(snapshot)
        let was = reportsPlaying(id)
        snapshots[snapshot.source] = snapshot
        noteSettling(snapshot)
        noteReport(from: id, wasPlaying: was)
    }

    /// A provider reports that its player quit or has nothing loaded.
    public mutating func clear(_ source: MediaSourceKind) {
        snapshots[source] = nil
        dropPickIfGone()
    }

    /// A report from the system-wide bridge: what plays now, or nil for nothing. It replaces
    /// whatever the bridge said before, under either kind, so a browser video doesn't stay
    /// "playing" after its window closes because the bridge's "nothing" was filed under the
    /// other kind.
    public mutating func updateFromBridge(_ snapshot: NowPlaying?) {
        let id = snapshot.map(Self.playerID)
        let was = id.map(reportsPlaying) ?? false
        for source in Self.bridgeSources { snapshots[source] = nil }
        if let snapshot {
            snapshots[snapshot.source] = snapshot
            noteSettling(snapshot)
        }
        if let id { noteReport(from: id, wasPlaying: was) }
        dropPickIfGone()
    }

    // MARK: Bare clips from unknown apps (rule 8)

    /// A snapshot rule 8 holds back until it has played a moment: reported by the system bridge
    /// for an app that isn't a known player or a browser, with no artist and no album.
    public static func needsSettling(_ s: NowPlaying) -> Bool {
        guard s.source == .system, MediaSourceKind.player(bundleID: s.bundleID) == nil else { return false }
        let bare = (s.artist ?? "").isEmpty && (s.album ?? "").isEmpty
        return bare
    }

    private static func settleKey(_ s: NowPlaying) -> String { playerID(s) + "\n" + s.trackKey }

    /// Keeps track of how long each bare clip has played without a break.
    private mutating func noteSettling(_ s: NowPlaying) {
        let live = Set(snapshots.values.filter(Self.needsSettling).map(Self.settleKey))
        playingSince = playingSince.filter { live.contains($0.key) }
        settled = settled.intersection(live)
        guard Self.needsSettling(s) else { return }
        let key = Self.settleKey(s)
        if let since = playingSince[key], s.timestamp.timeIntervalSince(since) >= Self.settle { settled.insert(key) }
        if s.isPlaying {
            if playingSince[key] == nil { playingSince[key] = s.timestamp }
        } else {
            playingSince[key] = nil
        }
    }

    /// Whether a snapshot may show under rule 8 at `now`.
    func hasSettled(_ s: NowPlaying, now: Date) -> Bool {
        guard Self.needsSettling(s) else { return true }
        let key = Self.settleKey(s)
        if settled.contains(key) { return true }
        guard s.isPlaying, let since = playingSince[key] else { return false }
        return now.timeIntervalSince(since) >= Self.settle
    }

    // MARK: Several players

    /// One app's player: its bundle id, or the source's name for a player that didn't say
    /// (`source:external`). The system bridge's report of Spotify and Spotify's own are one player.
    public static func playerID(_ s: NowPlaying) -> String {
        s.bundleID ?? "source:\(s.source.rawValue)"
    }

    /// The player the bridge last reported, which is the one its commands reach. A report that
    /// doesn't name its app is the player on the same track (as in `grouped`), so Spotify stays
    /// on the bridge, needing no Automation, even when macOS leaves the app out.
    public var bridgePlayer: String? {
        guard let b = snapshots[.system] ?? snapshots[.browser] else { return nil }
        if b.bundleID == nil, let same = snapshots.values.first(where: { $0.bundleID != nil && $0.trackKey == b.trackKey }) {
            return Self.playerID(same)
        }
        return Self.playerID(b)
    }

    /// The live players, one per app, newest first. The island offers the others as chips.
    public func available(now: Date) -> [NowPlaying] {
        Self.grouped(liveSnapshots(now: now)).values.compactMap(Self.best).sorted { a, b in
            a.timestamp != b.timestamp ? a.timestamp > b.timestamp : Self.playerID(a) < Self.playerID(b)
        }
    }

    /// Show and control `player` (a `playerID`) rather than the most recent one. Ignored for a
    /// player that isn't live.
    public mutating func pick(player: String, at now: Date) {
        guard available(now: now).contains(where: { Self.playerID($0) == player }) else { return }
        pick = MediaPick(player: player, at: now)
    }

    public mutating func clearPick() { pick = nil }

    /// Snapshots by player. One without a bundle id joins a player describing the same track
    /// (a browser extension reporting the video the bridge reports).
    static func grouped(_ live: [NowPlaying]) -> [String: [NowPlaying]] {
        var groups: [String: [NowPlaying]] = [:]
        for s in live {
            let key = s.bundleID
                ?? live.first(where: { $0.bundleID != nil && $0.trackKey == s.trackKey })?.bundleID
                ?? playerID(s)
            groups[key, default: []].append(s)
        }
        return groups
    }

    /// Whether any report from `player` says it is playing.
    private func reportsPlaying(_ player: String) -> Bool {
        snapshots.values.contains { Self.playerID($0) == player && $0.isPlaying }
    }

    /// Another player starting to play ends the pick; so does the picked player going.
    private mutating func noteReport(from player: String, wasPlaying: Bool) {
        if let p = pick, p.player != player, !wasPlaying, reportsPlaying(player) { pick = nil }
        dropPickIfGone()
    }

    private mutating func dropPickIfGone() {
        guard let p = pick, !snapshots.values.contains(where: { Self.playerID($0) == p.player }) else { return }
        pick = nil
    }

    /// Whether a snapshot is really playing at `now`: it says so and hasn't run past its end.
    public func isPlaying(_ s: NowPlaying, now: Date) -> Bool {
        guard s.isPlaying else { return false }
        guard let end = s.endsAt else { return true }
        return now < end.addingTimeInterval(endedGrace)
    }

    /// When a snapshot stops counting: paused ones `pausedTimeout` after their last report,
    /// ones stuck at their end `endedTimeout` after it, playing ones never.
    func forgetAt(_ s: NowPlaying) -> Date? {
        if !s.isPlaying { return s.timestamp.addingTimeInterval(pausedTimeout) }
        return s.endsAt?.addingTimeInterval(endedTimeout)
    }

    /// The switch in settings a snapshot answers to. Music and Spotify reported by the system
    /// bridge follow their own switch rather than "Other apps", so a player that is switched off
    /// stays hidden whichever path reports it.
    public static func setting(for s: NowPlaying) -> MediaSourceKind {
        guard s.source == .system, let player = MediaSourceKind.player(bundleID: s.bundleID) else { return s.source }
        return player
    }

    /// The next moment a paused player is forgotten. The app arms its one deadline timer for this,
    /// so the track goes on time instead of at the next media update. One already due and not yet
    /// forgotten comes back as `now`: another input can replace the timer just before it fires,
    /// and the track must still go.
    ///
    /// A track still "playing" past its end also has a deadline: when it starts to show as
    /// paused, then when it goes.
    public func nextDeadline(now: Date) -> Date? {
        var dates: [Date] = []
        for s in snapshots.values {
            // Due and not yet forgotten: now. `expire` removes it, so this can't repeat.
            if let forget = forgetAt(s) { dates.append(max(now, forget)) }
            // A bare clip that keeps playing shows once it has settled.
            if s.isPlaying, !hasSettled(s, now: now), let since = playingSince[Self.settleKey(s)] {
                dates.append(max(now, since.addingTimeInterval(Self.settle)))
            }
            // Showing as stopped changes nothing stored, so only a moment still ahead counts.
            if let end = s.endsAt, end.addingTimeInterval(endedGrace) > now { dates.append(end.addingTimeInterval(endedGrace)) }
        }
        return dates.min()
    }

    /// Forget paused players that have timed out, and ones stuck past their end. Returns
    /// whether any were forgotten.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let dead = snapshots.filter { forgetAt($0.value).map { $0 <= now } == true }.keys
        for source in dead { snapshots[source] = nil }
        dropPickIfGone()
        return !dead.isEmpty
    }

    /// What the open island shows and its controls reach: the picked player while it is live,
    /// otherwise the best of all (rules 1 to 3).
    public func current(now: Date) -> NowPlaying? {
        let live = liveSnapshots(now: now)
        if let picked = picked(in: live) { return picked }
        return Self.best(live)
    }

    /// What the closed island shows: what is playing. A pick steers the open island and the
    /// controls; the closed island follows it only while the picked player plays. So a paused
    /// video picked while a song plays leaves the song beside the notch, rather than the video
    /// showing there paused and then going after "Hide paused music after".
    public func closedIsland(now: Date) -> NowPlaying? {
        let live = liveSnapshots(now: now)
        if let picked = picked(in: live), picked.isPlaying { return picked }
        return Self.best(live)
    }

    private func picked(in live: [NowPlaying]) -> NowPlaying? {
        guard let pick, let group = Self.grouped(live)[pick.player] else { return nil }
        return Self.best(group)
    }

    /// Snapshots still counting at `now`, from sources that are on, each past its end shown as stopped.
    func liveSnapshots(now: Date) -> [NowPlaying] {
        snapshots.values.filter { s in
            guard !disabled.contains(Self.setting(for: s)) else { return false }
            if let app = s.bundleID, hidden.contains(app) { return false }
            guard hasSettled(s, now: now) else { return false }
            guard let forget = forgetAt(s) else { return true }
            return now < forget
        }.map { s -> NowPlaying in
            // Past its end: show it as stopped where it ended.
            guard s.isPlaying, !isPlaying(s, now: now), let end = s.endsAt else { return s }
            var stopped = s
            stopped.isPlaying = false
            stopped.elapsed = s.duration
            stopped.timestamp = end
            return stopped
        }
    }

    /// The one to show among `live`, with gaps filled from others describing the same track.
    static func best(_ live: [NowPlaying]) -> NowPlaying? {
        guard !live.isEmpty else { return nil }
        let best = live.max { a, b in
            if a.isPlaying != b.isPlaying { return !a.isPlaying }
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return rank(a.source) < rank(b.source)
        }!
        var result = best
        // Prefer a direct integration's identity (reliable state, controls) for the same track.
        if best.source == .system,
           let direct = live.first(where: { $0.source != .system && $0.trackKey == best.trackKey && $0.isPlaying == best.isPlaying }) {
            result = direct
        }
        // Fill gaps from any other source describing the same track (e.g. artwork from the system bridge).
        for other in live where other.source != result.source && other.trackKey == result.trackKey {
            if result.artworkData == nil { result.artworkData = other.artworkData }
            if result.artworkURL == nil { result.artworkURL = other.artworkURL }
            if result.duration == nil { result.duration = other.duration }
            if result.bundleID == nil { result.bundleID = other.bundleID }
            if result.shuffle == nil { result.shuffle = other.shuffle }
            if result.repeatMode == nil { result.repeatMode = other.repeatMode }
            if result.elapsed == nil, other.elapsed != nil {
                result.elapsed = other.elapsed
                result.timestamp = other.timestamp
            }
        }
        // The position from whichever report of this track is newest: Spotify's own can lag the
        // bridge's after a seek, and the older one would make the progress bar drift.
        if let newer = live.filter({ $0.trackKey == result.trackKey && $0.isPlaying == result.isPlaying && $0.elapsed != nil })
            .max(by: { $0.timestamp < $1.timestamp }), newer.timestamp > result.timestamp || result.elapsed == nil {
            result.elapsed = newer.elapsed
            result.timestamp = newer.timestamp
            result.playbackRate = newer.playbackRate
        }
        return result
    }

    static func rank(_ s: MediaSourceKind) -> Int {
        switch s {
        case .system: return 0
        case .browser: return 1
        case .external: return 2
        case .spotify: return 3
        case .appleMusic: return 3
        }
    }
}

/// A player chosen in the island's player chips.
public struct MediaPick: Equatable, Sendable {
    /// `MediaArbiter.playerID`.
    public var player: String
    public var at: Date

    public init(player: String, at: Date) {
        self.player = player
        self.at = at
    }
}

/// When music was paused, so the closed island can keep it for a while (`pausedMusicTimeout`)
/// and the pause can be seen: the indicator springs down and the artwork dims before it goes.
/// The app feeds it every Now Playing change; the hiding moment is one of its deadlines, so
/// nothing runs while the music stays paused.
///
/// Only a pause counts: music that was already paused when it appeared (at launch, or a player
/// reporting a paused track) isn't brought back, unless paused music is kept for good.
public struct PausedMusic: Equatable, Sendable {
    /// When the music last went from playing to paused; nil while it plays or after it went.
    public private(set) var since: Date?
    private var wasPlaying = false

    public init() {}

    /// Feed every change to what is playing (nil when nothing is).
    public mutating func ingest(_ np: NowPlaying?, now: Date) {
        guard let np else {
            since = nil
            wasPlaying = false
            return
        }
        if np.isPlaying {
            since = nil
            wasPlaying = true
        } else if wasPlaying {
            since = now
            wasPlaying = false
        }
    }

    /// How paused music shows at `now`. `timeout` is `pausedMusicTimeout`.
    public func show(timeout: Double, now: Date) -> PausedMediaShow {
        if let since, now < since.addingTimeInterval(Self.window(timeout)) { return .recent }
        return timeout < 0 ? .kept : .hidden
    }

    /// The next moment `show` changes: when the pause stops being recent.
    public func nextDeadline(timeout: Double, now: Date) -> Date? {
        guard let since else { return nil }
        let end = since.addingTimeInterval(Self.window(timeout))
        return end > now ? end : nil
    }

    /// How long a pause counts as recent. Music kept for good is recent for the default time,
    /// then waits behind other activities, as paused music always did.
    static func window(_ timeout: Double) -> TimeInterval {
        timeout < 0 ? IsletSettings.standardPausedMusicTimeout : timeout
    }
}

/// How paused music shows in the closed island.
public enum PausedMediaShow: Equatable, Sendable {
    /// Not at all: the island goes back to whatever else there is, or to the bare notch.
    case hidden
    /// Paused a moment ago: it keeps the place it had while playing, so the pause is seen.
    case recent
    /// Kept for good (`pausedMusicTimeout` is never), behind any other activity.
    case kept
}

/// Play and pause show at once when clicked, before the player confirms. For `window` seconds
/// the intended state wins over reports that still say otherwise; once the player agrees, or the
/// window ends, the player's own state shows again (the command may have failed).
public struct PlaybackIntent: Equatable, Sendable {
    public var isPlaying: Bool
    /// `NowPlaying.trackKey` of the track clicked; another track ignores the intent.
    public var track: String
    public var at: Date
    public var window: TimeInterval

    public init(isPlaying: Bool, track: String, at: Date, window: TimeInterval = 2) {
        self.isPlaying = isPlaying
        self.track = track
        self.at = at
        self.window = window
    }

    public var expires: Date { at.addingTimeInterval(window) }

    /// The intended state of `play`/`pause`/`togglePlayPause` on `np`; nil for other commands.
    public static func intended(_ command: PlaybackCommand, on np: NowPlaying, at now: Date) -> PlaybackIntent? {
        switch command {
        case .play: return PlaybackIntent(isPlaying: true, track: np.trackKey, at: now)
        case .pause: return PlaybackIntent(isPlaying: false, track: np.trackKey, at: now)
        case .togglePlayPause: return PlaybackIntent(isPlaying: !np.isPlaying, track: np.trackKey, at: now)
        default: return nil
        }
    }

    /// Whether `np` shows the player has done what was asked (or moved on to another track).
    public func isSettled(by np: NowPlaying?, now: Date) -> Bool {
        guard let np, now < expires, now >= at else { return true }
        return np.trackKey != track || np.isPlaying == isPlaying
    }

    /// `np` with the intended state, its position held where it was at the click.
    public func applied(to np: NowPlaying, now: Date) -> NowPlaying {
        guard !isSettled(by: np, now: now) else { return np }
        var shown = np
        shown.elapsed = np.position(at: at) ?? np.elapsed
        shown.timestamp = at
        shown.isPlaying = isPlaying
        return shown
    }
}

/// How far through the song the progress ring round the closed artwork is, and how long it
/// has left to fill at the player's rate. The ring is drawn by Core Animation from this, so
/// the app does nothing while the song plays on: it starts again only when the player reports.
public struct SongProgress: Equatable, Sendable {
    /// 0 at the start of the song, 1 at its end.
    public var fraction: Double
    /// Seconds until the ring is full; nil while paused (the ring holds still).
    public var remaining: Double?

    /// Nil for a song without a length (a live stream): there is nothing to fill.
    public init?(_ np: NowPlaying, now: Date) {
        guard let duration = np.duration, duration.isFinite, duration > 0, let pos = np.position(at: now) else { return nil }
        fraction = min(1, max(0, pos / duration))
        if np.isPlaying, np.playbackRate > 0, np.playbackRate.isFinite {
            remaining = max(0, duration - pos) / np.playbackRate
        } else {
            remaining = nil
        }
    }

    public init(fraction: Double, remaining: Double?) {
        self.fraction = fraction
        self.remaining = remaining
    }
}

/// When the Now Playing helper is started again after it exits. It restarts after a growing
/// delay; one that ran for a while earns a fresh set of tries, and one that keeps dying is given
/// up on after `limit` tries until the user asks again (Try again) or the Mac wakes.
public struct HelperRestarts: Equatable, Sendable {
    /// Restarts in a row before giving up.
    public static let limit = 5
    /// A helper that ran this long before exiting wasn't failing: the count starts again.
    public static let healthyRun: TimeInterval = 60

    public private(set) var count = 0
    public private(set) var gaveUp = false

    public init() {}

    /// The helper exited after running `ranFor` seconds: the delay before starting it again, or
    /// nil when it has been given up on.
    public mutating func exited(ranFor: TimeInterval) -> TimeInterval? {
        if ranFor > Self.healthyRun { count = 0 }
        count += 1
        guard count <= Self.limit else {
            gaveUp = true
            return nil
        }
        return TimeInterval(count * count)
    }

    /// A fresh set of tries: the user pressed Try again, or the Mac woke.
    public mutating func reset() {
        count = 0
        gaveUp = false
    }
}
