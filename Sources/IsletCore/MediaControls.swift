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

    /// Where a relative jump on `np` lands from `position`. Nil without a length too: a player
    /// that doesn't know how long it is (a live stream) doesn't reliably know where it is either
    /// (Chrome says 0 again every quarter of a minute), so the jump is left to the player.
    public static func target(for np: NowPlaying, from position: Double?, by delta: Double) -> Double? {
        guard let duration = np.duration, duration > 0 else { return nil }
        return target(from: position, by: delta, duration: duration)
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

    /// A position in the track as typed for `isletctl media seek`: "90" or "90s", "2m",
    /// "1m 30s", "1:30", "1:02:03", and "0" for the start. Nil for a negative position, a time
    /// of day ("at 18:30") or anything with words left over.
    public static func parsePosition(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let v = Double(t) {
            return v.isFinite ? v : nil
        }
        let clock = t.split(separator: ":", omittingEmptySubsequences: false)
        if clock.count > 1 {
            guard clock.count <= 3,
                  clock.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  clock.dropFirst().allSatisfy({ $0.count == 2 && Int($0)! < 60 }) else { return nil }
            return clock.reduce(0) { $0 * 60 + Double($1)! }
        }
        let words = t.split(whereSeparator: \.isWhitespace).map(String.init)
        let scanner = DurationParser.Scanner(tokens: DurationParser.tokenize(words), now: Date(), calendar: .current)
        guard let (seconds, end) = scanner.duration(at: 0), end == scanner.tokens.count,
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// The right-hand time label: time remaining ("−2:51", with a real minus sign, as other
    /// negative figures have) or the track length ("4:03").
    public static func trailingLabel(position: Double, duration: Double, remaining: Bool) -> String {
        remaining ? "\u{2212}" + Format.clock(max(0, duration - position)) : Format.clock(duration)
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

/// The row beside Now Playing's artwork on Home: the title, the other players' chips, the
/// volume button and the lyrics button. The title keeps `titleRoom` points, about a dozen
/// characters, and what doesn't fit beside it gives way in order: the lyrics button moves under
/// the others (`LyricsSpot.below`, in the height of the artwork), the other players fold into one
/// chip that counts them (a menu picks one), then the volume button goes, so another player can
/// always be picked. At the compact size beside the glances, one chip and the button together
/// would cut "Midnight City" to "Midnight…", so there the button makes way; the volume keys still
/// work, and a card tall enough for the volume row has no button at all.
public enum NowPlayingTitleRow {
    public static let titleRoom: Double = 96
    public static let chip: Double = 22
    public static let volumeButton: Double = 24
    /// The lyrics button beside the others; under them it takes no width.
    public static let lyricsButton: Double = 24
    /// Between the chips and the buttons.
    public static let gap: Double = 4
    /// The most chips shown, however wide the card.
    public static let maxChips = 3

    /// Where the lyrics button sits.
    public enum LyricsSpot: Equatable, Sendable {
        case none
        /// In the row, after the chips and the volume button.
        case beside
        /// Under them, at the row's trailing edge.
        case below
    }

    public struct Layout: Equatable, Sendable {
        /// Chips shown. When there are more players than chips, the last chip stands for the
        /// rest (`folded`).
        public var chips: Int
        public var showsVolume: Bool
        public var lyrics: LyricsSpot

        public init(chips: Int, showsVolume: Bool, lyrics: LyricsSpot = .none) {
            self.chips = chips
            self.showsVolume = showsVolume
            self.lyrics = lyrics
        }

        /// Whether anything sits beside the title.
        public var isEmpty: Bool { chips == 0 && !showsVolume && lyrics == .none }

        /// How many players the last chip stands for when `otherPlayers` are live: 1 when
        /// every player has a chip of its own, more when the rest are folded into it.
        public func folded(otherPlayers: Int) -> Int {
            guard chips > 0 else { return 0 }
            return max(1, otherPlayers - (chips - 1))
        }
    }

    /// - Parameters:
    ///   - width: the row's width beside the artwork.
    ///   - spacing: the space the row puts between the title and what sits beside it.
    ///   - otherPlayers: players live beside the one on show.
    ///   - volumeRow: the card is tall enough to show the volume row all the time.
    ///   - lyrics: the song could have lyrics, so the lyrics button shows.
    public static func layout(width: Double, spacing: Double, otherPlayers: Int, volumeRow: Bool, lyrics: Bool = false) -> Layout {
        let wanted = Layout(chips: min(max(otherPlayers, 0), maxChips), showsVolume: !volumeRow, lyrics: lyrics ? .beside : .none)
        func fits(_ l: Layout) -> Bool { l.isEmpty || width - spacing - beside(l) >= titleRoom }
        var l = wanted
        // The lyrics button goes under the others before anything else gives way.
        if l.lyrics == .beside, !fits(l), l.chips > 0 || l.showsVolume { l.lyrics = .below }
        // Players fold into one chip before the volume button goes.
        while l.chips > 1, !fits(l) { l.chips -= 1 }
        if fits(l) { return l }
        l.showsVolume = false
        if l.lyrics == .below, l.chips == 0 { l.lyrics = .beside }
        if fits(l) { return l }
        if l.lyrics == .beside { l.lyrics = l.chips > 0 ? .below : .none }
        return l
    }

    /// The width of what sits beside the title.
    static func beside(_ l: Layout) -> Double {
        let lyricsBeside = l.lyrics == .beside
        let items = l.chips + (l.showsVolume ? 1 : 0) + (lyricsBeside ? 1 : 0)
        guard items > 0 else { return 0 }
        return Double(l.chips) * chip + (l.showsVolume ? volumeButton : 0) + (lyricsBeside ? lyricsButton : 0) + Double(items - 1) * gap
    }
}
