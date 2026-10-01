import Foundation

/// Decides when the closed island shows a new song for a moment, below the notch. A value
/// type with an injected clock, like `ActivityCenter`: the app feeds it every Now Playing
/// change and calls `advance` at `nextDeadline`, so nothing runs while the music plays on.
///
/// - A new song is a new title, artist or album, from the same player or another. Pausing,
///   resuming, seeking and a player filling in details it sent late (the artist, the album)
///   are not.
/// - The song must play for `settle` seconds first, so skipping through several tracks shows
///   only the one you stop on.
/// - A song is shown once. One of the last few songs (skipping back, or two players taking
///   turns) isn't shown again, and neither is the first song after launch.
/// - It isn't shown while the island is open, hidden (a fullscreen app or an app rule), busy
///   with a HUD or an activity's sneak peek, or with the setting off. A song that settles at
///   such a moment counts as shown: it never appears late.
/// - While a peek is up, a newer song takes its place at once and the peek starts again.
public struct SongPeek: Sendable {
    /// What the island is doing when a new song settles.
    public struct Context: Equatable, Sendable {
        /// "Show the new song for a moment" (and Now Playing) is on.
        public var enabled: Bool
        public var isOpen: Bool
        /// Every island is hidden for a fullscreen app or an app rule.
        public var isHidden: Bool
        /// A HUD or an activity's sneak peek is on screen.
        public var isBusy: Bool

        public init(enabled: Bool = true, isOpen: Bool = false, isHidden: Bool = false, isBusy: Bool = false) {
            self.enabled = enabled
            self.isOpen = isOpen
            self.isHidden = isHidden
            self.isBusy = isBusy
        }

        public var allowsPeek: Bool { enabled && !isOpen && !isHidden && !isBusy }
    }

    /// The song on show, and until when.
    public struct Peek: Equatable, Sendable {
        public var track: NowPlaying
        public var until: Date
    }

    /// A new song, and when it will have played long enough to show.
    struct Waiting: Equatable, Sendable {
        var track: NowPlaying
        var settles: Date
    }

    /// Seconds a new song must keep playing before it is shown.
    public var settle: TimeInterval
    /// Seconds the peek stays.
    public var duration: TimeInterval
    public private(set) var peek: Peek?

    /// The song last shown, or accepted without a peek.
    private var shown: NowPlaying?
    /// A playing song other than `shown`, waiting to settle.
    private var candidate: Waiting?
    /// The last few songs that settled, newest last.
    private var recent: [NowPlaying] = []
    /// Whether any song has been seen since launch (or since media was switched back on).
    private var sawFirst = false

    /// Songs remembered as recently shown.
    static let memory = 3

    public init(settle: TimeInterval = 0.6, duration: TimeInterval = 2.5) {
        self.settle = settle
        self.duration = duration
    }

    /// The song to show at `now`, if any.
    public func current(now: Date) -> NowPlaying? {
        guard let peek, peek.until > now else { return nil }
        return peek.track
    }

    /// Feed every change to what is playing (nil when nothing is).
    public mutating func ingest(_ playing: NowPlaying?, now: Date) {
        guard let np = playing, !np.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Nothing playing: a song waiting to settle is gone, and so is one on show.
            candidate = nil
            peek = nil
            return
        }
        guard sawFirst else {
            sawFirst = true
            accept(np)
            return
        }
        if let p = peek, p.until > now {
            if Self.sameTrack(np, p.track) {
                peek?.track = np
                shown = np
                return
            }
            guard np.isPlaying else {
                // The player moved to another song without playing it: the peek is out of date.
                peek = nil
                candidate = nil
                return
            }
            // Skipping while the song is on show: follow along instead of closing and reopening.
            peek = Peek(track: np, until: now.addingTimeInterval(duration))
            candidate = nil
            accept(np)
            return
        }
        if let s = shown, Self.sameTrack(np, s) {
            shown = np
            candidate = nil
            return
        }
        guard np.isPlaying else {
            candidate = nil
            return
        }
        if let c = candidate, Self.sameTrack(np, c.track) {
            candidate?.track = np
        } else {
            candidate = Waiting(track: np, settles: now.addingTimeInterval(settle))
        }
    }

    /// Settle a waiting song and end a finished peek. Returns whether a peek started.
    @discardableResult
    public mutating func advance(now: Date, context: Context) -> Bool {
        if let p = peek, p.until <= now { peek = nil }
        guard let c = candidate, c.settles <= now else { return false }
        candidate = nil
        let seen = recent.contains { Self.sameTrack($0, c.track) }
        accept(c.track)
        guard !seen, context.allowsPeek else { return false }
        peek = Peek(track: c.track, until: now.addingTimeInterval(duration))
        return true
    }

    /// The next moment `advance` has something to do: a song settling or a peek ending. One
    /// already due comes back as `now`.
    public func nextDeadline(now: Date) -> Date? {
        [candidate?.settles, peek?.until].compactMap { $0 }.map { max(now, $0) }.min()
    }

    /// The island opened: it shows the song itself, so the peek goes.
    public mutating func cancel() {
        peek = nil
    }

    /// Now Playing was switched off: start over, so switching it back on shows nothing.
    public mutating func reset() {
        self = SongPeek(settle: settle, duration: duration)
    }

    private mutating func accept(_ np: NowPlaying) {
        shown = np
        recent.removeAll { Self.sameTrack($0, np) }
        recent.append(np)
        if recent.count > Self.memory { recent.removeFirst(recent.count - Self.memory) }
    }

    /// The same song: the same title, with the same artist and album, or ones that were
    /// missing on either side (players often send the title first and the rest a moment later).
    public static func sameTrack(_ a: NowPlaying, _ b: NowPlaying) -> Bool {
        guard a.title == b.title else { return false }
        func fits(_ x: String?, _ y: String?) -> Bool {
            let x = x ?? "", y = y ?? ""
            return x == y || x.isEmpty || y.isEmpty
        }
        return fits(a.artist, b.artist) && fits(a.album, b.album)
    }
}
