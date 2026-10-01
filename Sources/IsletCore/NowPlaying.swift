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
public struct MediaArbiter: Sendable {
    public private(set) var snapshots: [MediaSourceKind: NowPlaying] = [:]
    public var pausedTimeout: TimeInterval
    /// Seconds past a track's end before a player that still says "playing" is believed to have
    /// stopped, so a slow report of the next track doesn't flicker the island.
    public var endedGrace: TimeInterval
    /// Seconds after its end that such a track is forgotten.
    public var endedTimeout: TimeInterval
    /// Sources the user switched off in settings.
    public var disabled: Set<MediaSourceKind>

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
        snapshots[snapshot.source] = snapshot
    }

    /// A provider reports that its player quit or has nothing loaded.
    public mutating func clear(_ source: MediaSourceKind) {
        snapshots[source] = nil
    }

    /// A report from the system-wide bridge: what plays now, or nil for nothing. It replaces
    /// whatever the bridge said before, under either kind, so a browser video doesn't stay
    /// "playing" after its window closes because the bridge's "nothing" was filed under the
    /// other kind.
    public mutating func updateFromBridge(_ snapshot: NowPlaying?) {
        for source in Self.bridgeSources { snapshots[source] = nil }
        if let snapshot { snapshots[snapshot.source] = snapshot }
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
        return !dead.isEmpty
    }

    public func current(now: Date) -> NowPlaying? {
        let live = snapshots.values.filter { s in
            guard !disabled.contains(Self.setting(for: s)) else { return false }
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
        guard !live.isEmpty else { return nil }
        let best = live.max { a, b in
            if a.isPlaying != b.isPlaying { return !a.isPlaying }
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return Self.rank(a.source) < Self.rank(b.source)
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
