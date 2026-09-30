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
/// 5. Sources switched off in settings are ignored. Music and Spotify count as themselves even
///    when the system bridge reports them (`setting(for:)`).
public struct MediaArbiter: Sendable {
    public private(set) var snapshots: [MediaSourceKind: NowPlaying] = [:]
    public var pausedTimeout: TimeInterval
    /// Sources the user switched off in settings.
    public var disabled: Set<MediaSourceKind>

    public init(pausedTimeout: TimeInterval = 15 * 60, disabled: Set<MediaSourceKind> = []) {
        self.pausedTimeout = pausedTimeout
        self.disabled = disabled
    }

    public mutating func update(_ snapshot: NowPlaying) {
        snapshots[snapshot.source] = snapshot
    }

    /// A provider reports that its player quit or has nothing loaded.
    public mutating func clear(_ source: MediaSourceKind) {
        snapshots[source] = nil
    }

    /// The switch in settings a snapshot answers to. Music and Spotify reported by the system
    /// bridge follow their own switch rather than "Other apps", so a player that is switched off
    /// stays hidden whichever path reports it.
    public static func setting(for s: NowPlaying) -> MediaSourceKind {
        guard s.source == .system, let player = MediaSourceKind.player(bundleID: s.bundleID) else { return s.source }
        return player
    }

    /// The next moment a paused player is forgotten. The app arms its one deadline timer for this,
    /// so the track goes on time instead of at the next media update.
    public func nextDeadline(now: Date) -> Date? {
        snapshots.values
            .filter { !$0.isPlaying }
            .map { $0.timestamp.addingTimeInterval(pausedTimeout) }
            .filter { $0 > now }
            .min()
    }

    /// Forget paused players that have timed out. Returns whether any were forgotten.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let dead = snapshots.filter { !$0.value.isPlaying && now.timeIntervalSince($0.value.timestamp) >= pausedTimeout }.keys
        for source in dead { snapshots[source] = nil }
        return !dead.isEmpty
    }

    public func current(now: Date) -> NowPlaying? {
        let live = snapshots.values.filter { s in
            guard !disabled.contains(Self.setting(for: s)) else { return false }
            if s.isPlaying { return true }
            return now.timeIntervalSince(s.timestamp) < pausedTimeout
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
