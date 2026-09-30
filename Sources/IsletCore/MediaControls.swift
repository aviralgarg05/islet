import Foundation

/// Seeking and scrubbing arithmetic for the Now Playing controls.
public enum MediaSeek {
    /// Jump used by the -15 s / +15 s buttons and `skipForward` / `skipBackward`.
    public static let skipInterval: Double = 15
    /// Jump used by horizontal swipes when they are set to seek.
    public static let swipeInterval: Double = 10

    /// Where a relative jump lands, kept inside the track (never past its last second, so a
    /// jump near the end doesn't skip to the next track). Nil when the position is unknown.
    public static func target(from position: Double?, by delta: Double, duration: Double?) -> Double? {
        guard let position, position.isFinite, delta.isFinite else { return nil }
        var t = max(0, position + delta)
        if let duration, duration > 0 { t = min(t, max(0, duration - 1)) }
        return t
    }

    /// Track position for a point on the scrubber.
    public static func position(fraction: Double, duration: Double) -> Double {
        guard fraction.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, fraction)) * duration
    }

    /// Fraction of the bar under `x` for a bar `width` points wide.
    public static func fraction(x: Double, width: Double) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return min(1, max(0, x / width))
    }

    /// True when a drag has just reached either end of the bar (a haptic detent).
    public static func reachedEnd(from old: Double?, to new: Double) -> Bool {
        let atEnd = new <= 0 || new >= 1
        guard atEnd else { return false }
        guard let old else { return true }
        return old > 0 && old < 1 || (old <= 0) != (new <= 0)
    }

    /// The right-hand time label: time remaining ("-2:51") or the track length ("4:03").
    public static func trailingLabel(position: Double, duration: Double, remaining: Bool) -> String {
        remaining ? "-" + Format.clock(max(0, duration - position)) : Format.clock(duration)
    }
}

/// Players take a moment to report a new position after a seek. For `window` seconds the
/// controls show the requested position (advancing while playing) so the bar doesn't jump back.
public struct SeekGrace: Equatable, Sendable {
    public var target: Double
    public var at: Date
    /// `NowPlaying.trackKey` of the track that was seeked; another track ignores the grace.
    public var track: String
    public var window: TimeInterval

    public init(target: Double, at: Date, track: String, window: TimeInterval = 1.5) {
        self.target = target
        self.at = at
        self.track = track
        self.window = window
    }

    public func isActive(now: Date) -> Bool {
        let age = now.timeIntervalSince(at)
        return age >= 0 && age < window
    }

    /// The position to show for `media` at `now`.
    public func position(for media: NowPlaying, now: Date) -> Double? {
        guard isActive(now: now), media.trackKey == track else { return media.position(at: now) }
        var p = target
        if media.isPlaying { p += now.timeIntervalSince(at) * media.playbackRate }
        if let d = media.duration, d > 0 { p = min(p, d) }
        return max(0, p)
    }
}

/// Shuffle and repeat, as MediaRemote encodes them in the Now Playing info and its setters.
public enum MediaModes {
    /// `kMRMediaRemoteNowPlayingInfoShuffleMode`: 0 unknown, 1 off, 2 albums, 3 songs.
    public static func shuffle(mediaRemote value: Int?) -> Bool? {
        guard let value, value > 0 else { return nil }
        return value != 1
    }

    /// Value for `MRMediaRemoteSetShuffleMode`.
    public static func mediaRemoteShuffle(_ on: Bool) -> Int { on ? 3 : 1 }

    /// `kMRMediaRemoteNowPlayingInfoRepeatMode`: 0 unknown, 1 off, 2 one, 3 all.
    public static func repeatMode(mediaRemote value: Int?) -> RepeatMode? {
        switch value {
        case 1: return .off
        case 2: return .one
        case 3: return .all
        default: return nil
        }
    }

    /// Value for `MRMediaRemoteSetRepeatMode`.
    public static func mediaRemoteRepeat(_ mode: RepeatMode) -> Int {
        switch mode {
        case .off: return 1
        case .one: return 2
        case .all: return 3
        }
    }

    /// The repeat button cycles off → all → one → off, like Music.
    public static func next(after mode: RepeatMode) -> RepeatMode {
        switch mode {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
