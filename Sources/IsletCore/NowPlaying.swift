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
}

public enum PlaybackCommand: String, Codable, Sendable, CaseIterable {
    case play, pause, togglePlayPause, next, previous, seek
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

    public init(
        source: MediaSourceKind, bundleID: String? = nil, appName: String? = nil, title: String,
        artist: String? = nil, album: String? = nil, isPlaying: Bool, duration: Double? = nil,
        elapsed: Double? = nil, playbackRate: Double = 1, timestamp: Date,
        artworkData: Data? = nil, artworkURL: URL? = nil
    ) {
        self.source = source; self.bundleID = bundleID; self.appName = appName; self.title = title
        self.artist = artist; self.album = album; self.isPlaying = isPlaying; self.duration = duration
        self.elapsed = elapsed; self.playbackRate = playbackRate; self.timestamp = timestamp
        self.artworkData = artworkData; self.artworkURL = artworkURL
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

    public func current(now: Date) -> NowPlaying? {
        let live = snapshots.values.filter { s in
            guard !disabled.contains(s.source) else { return false }
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
