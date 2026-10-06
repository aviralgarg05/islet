import Foundation

/// One line of time-synced lyrics.
public struct LyricLine: Codable, Equatable, Sendable {
    /// Seconds from the start of the song.
    public var time: Double
    /// The words. Empty for an instrumental break between verses.
    public var text: String

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

/// Lyrics for one song: lines with their times when LRCLIB has them, otherwise plain text.
public struct SongLyrics: Codable, Equatable, Sendable {
    /// Time-synced lines, in order. Empty when only plain text is known.
    public var lines: [LyricLine]
    public var plain: String?
    /// The song has no words.
    public var instrumental: Bool

    public init(lines: [LyricLine] = [], plain: String? = nil, instrumental: Bool = false) {
        self.lines = lines
        self.plain = plain
        self.instrumental = instrumental
    }

    public var isSynced: Bool { !lines.isEmpty }

    /// Whether there is anything to show.
    public var isEmpty: Bool { lines.isEmpty && (plain ?? "").isEmpty && !instrumental }

    /// The line being sung at `position`: the last one whose time has come. Nil before the first.
    public func index(at position: Double) -> Int? {
        // Lines are sorted, so a binary search finds the last start at or before the position.
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// When the next line after `position` starts, for the one wake-up that moves the lyrics on.
    /// Nil after the last line.
    public func nextTime(after position: Double) -> Double? {
        let next = (index(at: position) ?? -1) + 1
        return next < lines.count ? lines[next].time : nil
    }

    /// The moments the shown line changes while a song plays from `position` at `rate`, as dates
    /// counted from `now`. Paused (rate 0) there are none: the lyrics stand still.
    public func changes(from position: Double, rate: Double, now: Date) -> [Date] {
        guard rate > 0 else { return [] }
        return lines.lazy.filter { $0.time > position }.map { now.addingTimeInterval(($0.time - position) / rate) }
    }
}

/// The LRC format LRCLIB returns: "[mm:ss.xx] words" per line.
public enum LRC {
    /// Reads every timed line. A line may carry several time tags (a repeated chorus); an
    /// `[offset:±ms]` tag shifts them all ("+" shows the words sooner); word-level tags
    /// ("<mm:ss.xx>") and metadata tags ("[ar:…]") are dropped. Lines come back sorted by time.
    public static func parse(_ text: String) -> [LyricLine] {
        var offset = 0.0
        var lines: [(order: Int, line: LyricLine)] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = time(tag) {
                    times.append(t)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            let words = stripWordTags(String(rest)).trimmingCharacters(in: .whitespaces)
            for t in times {
                lines.append((lines.count, LyricLine(time: t, text: words)))
            }
        }
        return lines
            .sorted { $0.line.time != $1.line.time ? $0.line.time < $1.line.time : $0.order < $1.order }
            .map { LyricLine(time: max(0, $0.line.time - offset), text: $0.line.text) }
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss.xxx" (a colon before the fraction also occurs) in seconds.
    ///
    /// The minutes are capped at six digits, as the seconds are at two: these files come from
    /// LRCLIB, where anyone can upload one, and `minutes * 60` overflows and traps once the
    /// field is wide enough.
    static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts[0].count <= 6,
              let minutes = Int(parts[0]), minutes >= 0, parts[0].allSatisfy(\.isNumber) else { return nil }
        var secondsText = String(parts[1])
        if parts.count == 3 { secondsText += "." + parts[2] }
        let pieces = secondsText.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), pieces[0].count <= 2, let seconds = Int(pieces[0]), seconds < 60,
              pieces[0].allSatisfy(\.isNumber) else { return nil }
        var fraction = 0.0
        if pieces.count == 2 {
            guard !pieces[1].isEmpty, pieces[1].count <= 3, pieces[1].allSatisfy(\.isNumber),
                  let f = Double("0." + pieces[1]) else { return nil }
            fraction = f
        }
        return Double(minutes * 60 + seconds) + fraction
    }

    private static func stripWordTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: ">") else {
                out += rest[open...]
                return out
            }
            let tag = rest[rest.index(after: open)..<close]
            if time(tag) == nil { out += rest[open...close] }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}

/// What Casement asks LRCLIB for one song: its title, artist, album and length, and nothing else.
public struct LyricsQuery: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    /// Seconds.
    public var duration: Double?
    /// From a web browser, whose length may be a video's rather than the recording's: a match
    /// whose length differs a little shows its words without their times (`LRCLIB.lyrics(from:for:)`).
    public var fromBrowser = false
    /// What LRCLIB's search gets in place of the title and artist, when a browser's report leaves
    /// the artist in doubt (`BrowserSong.Song.unsure`).
    public var searchText: String?
    /// Another title a found song may have: "A - B" read the other way round.
    public var otherTitle: String?

    public init(title: String, artist: String, album: String? = nil, duration: Double? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Players whose songs have lyrics worth looking up: Music and Spotify.
    public static let players: Set<String> = ["com.apple.Music", "com.spotify.client"]

    /// How long a song is: half a minute to a quarter of an hour. Shorter is an advert or a
    /// clip, longer a mix, a live stream or an audiobook.
    public static let songLength: ClosedRange<Double> = 30...(15 * 60)

    /// Where a track plays, for lyrics.
    public enum Origin: Equatable, Sendable {
        /// Music or Spotify.
        case player
        /// A web browser: YouTube, YouTube Music, Spotify's or Apple Music's web player and so on.
        case browser
    }

    /// Whether `np` is the song a lookup was made for, with the `trackKey` and `length` it had
    /// then. For a browser the length counts too: Chrome can send a new video's title a moment
    /// before its length, or with the last video's, so a length that arrives or changes after
    /// the title is looked up again.
    public static func isSameLookup(_ np: NowPlaying, trackKey: String?, length: Double?) -> Bool {
        guard np.trackKey == trackKey else { return false }
        guard origin(of: np) == .browser else { return true }
        switch (np.duration, length) {
        case (nil, nil): return true
        case let (now?, then?): return abs(now - then) < 2
        default: return false
        }
    }

    /// A browser's track whose length hasn't come yet: not settled as having no lyrics on its
    /// own, since the length usually follows a moment later.
    public static func awaitsLength(_ np: NowPlaying, includeBrowsers: Bool) -> Bool {
        includeBrowsers && origin(of: np) == .browser && np.duration == nil
    }

    /// Music and Spotify, or a web browser; nil for every other app (a podcast app, a video call).
    public static func origin(of np: NowPlaying) -> Origin? {
        if np.source == .appleMusic || np.source == .spotify || np.bundleID.map(players.contains) == true { return .player }
        if np.source == .browser || np.bundleID.flatMap(Browsers.browser(for:)) != nil { return .browser }
        return nil
    }

    /// The query for what's playing, or nil when it doesn't look like a song, so nothing about it
    /// is sent. A song has a title and an artist and lasts `songLength`; only Music and Spotify
    /// may leave the length out. A browser's track counts only with `includeBrowsers`, and only
    /// once its title reads as a song (`BrowserSong`), which also leaves out live streams.
    public init?(_ np: NowPlaying, includeBrowsers: Bool = false) {
        guard let origin = Self.origin(of: np), origin == .player || includeBrowsers else { return nil }
        let title = np.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (np.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let duration = np.duration.flatMap { $0 > 0 ? $0 : nil }
        if let duration {
            guard Self.songLength.contains(duration) else { return nil }
        } else if origin == .browser {
            return nil
        }
        let trimmedAlbum = np.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = trimmedAlbum?.isEmpty == false ? trimmedAlbum : nil
        guard origin == .browser else {
            self.init(title: title, artist: artist, album: album, duration: duration)
            return
        }
        guard let song = BrowserSong.song(title: title, artist: artist, album: album) else { return nil }
        self.init(title: song.title, artist: song.artist, album: album, duration: duration)
        fromBrowser = true
        if song.unsure {
            searchText = [song.otherTitle, song.title].compactMap { $0 }.joined(separator: " ")
            otherTitle = song.otherTitle
        }
    }

    /// Whether the song on show could have lyrics with every lyrics switch on: the lyrics button
    /// shows for these.
    public static func couldHaveLyrics(_ np: NowPlaying) -> Bool {
        LyricsQuery(np, includeBrowsers: true) != nil
    }

    /// One cache entry per song: the same title, artist, album and whole seconds.
    public var cacheKey: String {
        [title, artist, album ?? "", duration.map { String(Int($0.rounded())) } ?? ""]
            .map { $0.lowercased() }
            .joined(separator: "\u{1F}")
    }
}

/// One record from LRCLIB's API.
public struct LRCLIBRecord: Decodable, Equatable, Sendable {
    public var id: Int?
    public var trackName: String?
    public var artistName: String?
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool?
    public var plainLyrics: String?
    public var syncedLyrics: String?

    public init(id: Int? = nil, trackName: String? = nil, artistName: String? = nil, albumName: String? = nil, duration: Double? = nil,
                instrumental: Bool? = nil, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id; self.trackName = trackName; self.artistName = artistName; self.albumName = albumName
        self.duration = duration; self.instrumental = instrumental; self.plainLyrics = plainLyrics; self.syncedLyrics = syncedLyrics
    }
}

/// lrclib.net, a free library of time-synced lyrics that needs no account or key.
public enum LRCLIB {
    public static let host = "lrclib.net"

    /// LRCLIB asks apps to say who they are.
    public static func userAgent(version: String) -> String {
        "Casement \(version) (https://github.com/aviralgarg05/casement)"
    }

    /// The exact match: `/api/get` with the title, artist, album and length.
    public static func getURL(_ q: LyricsQuery) -> URL {
        var items = [URLQueryItem(name: "track_name", value: q.title), URLQueryItem(name: "artist_name", value: q.artist)]
        if let album = q.album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let d = q.duration { items.append(URLQueryItem(name: "duration", value: String(Int(d.rounded())))) }
        return url("/api/get", items)
    }

    /// When the exact match fails: `/api/search` with the same title, artist and album, or, when a
    /// browser's report leaves the artist in doubt, with the words of its title (`searchText`).
    public static func searchURL(_ q: LyricsQuery) -> URL {
        if let text = q.searchText { return url("/api/search", [URLQueryItem(name: "q", value: text)]) }
        var items = [URLQueryItem(name: "track_name", value: q.title), URLQueryItem(name: "artist_name", value: q.artist)]
        if let album = q.album { items.append(URLQueryItem(name: "album_name", value: album)) }
        return url("/api/search", items)
    }

    private static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = path
        c.queryItems = items
        // `+` would read as a space on the server; URLComponents leaves it alone.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url ?? URL(string: "https://\(host)")!
    }

    /// What one record says about the song, or nil when it holds nothing to show.
    public static func lyrics(from r: LRCLIBRecord) -> SongLyrics? {
        let lines = LRC.parse(r.syncedLyrics ?? "")
        let plain = r.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lyrics = SongLyrics(lines: lines.contains { !$0.text.isEmpty } ? lines : [],
                                plain: plain?.isEmpty == false ? plain : nil, instrumental: r.instrumental == true)
        return lyrics.isEmpty ? nil : lyrics
    }

    /// What a record says about `q`'s song. A browser's track whose length differs from the
    /// record's by more than `sameLength` is most likely a video with an intro, so its words show
    /// without their times, which would run early.
    public static func lyrics(from r: LRCLIBRecord, for q: LyricsQuery) -> SongLyrics? {
        guard var found = lyrics(from: r) else { return nil }
        if q.fromBrowser, found.isSynced, !isSameLength(r, q) {
            if found.plain == nil { found.plain = found.lines.map(\.text).joined(separator: "\n") }
            found.lines = []
        }
        return found
    }

    /// Seconds two lengths may differ by and still be one recording.
    public static let sameLength: Double = 2.5
    /// How much longer or shorter a browser's video may be than the song it plays.
    public static let videoLength: Double = 60

    /// The best of a search's records for the song: the same length within a couple of seconds
    /// (any length when the song's is unknown), synced lyrics before plain, then the closest length.
    /// A browser's video may run up to `videoLength` longer or shorter than the song, if the record
    /// has the same title; and when its artist is in doubt, only a record with one of its titles
    /// counts.
    public static func best(_ records: [LRCLIBRecord], for q: LyricsQuery) -> LRCLIBRecord? {
        let candidates = records.filter { r in
            guard lyrics(from: r) != nil else { return false }
            let titled = titleMatch(r, q) > 0
            if q.searchText != nil, !titled { return false }
            guard let d = q.duration, let rd = r.duration else { return true }
            return abs(d - rd) <= sameLength || q.fromBrowser && titled && abs(d - rd) <= videoLength
        }
        return candidates.enumerated().min { a, b in
            let la = isSameLength(a.element, q), lb = isSameLength(b.element, q)
            if la != lb { return la }
            let sa = a.element.syncedLyrics?.isEmpty == false, sb = b.element.syncedLyrics?.isEmpty == false
            if sa != sb { return sa }
            let ta = titleMatch(a.element, q), tb = titleMatch(b.element, q)
            if ta != tb { return ta > tb }
            let da = distance(a.element, q), db = distance(b.element, q)
            return da != db ? da < db : a.offset < b.offset
        }?.element
    }

    private static func isSameLength(_ r: LRCLIBRecord, _ q: LyricsQuery) -> Bool {
        guard let d = q.duration, let rd = r.duration else { return true }
        return abs(d - rd) <= sameLength
    }

    /// How well the record's title is the song's (or its other title): 2 the same, ignoring
    /// case and accents; 1 the same once what follows in brackets or after a dash is left out
    /// ("Kesariya (From \"Brahmastra\")", "Midnight City (Live)"); 0 another title.
    static func titleMatch(_ r: LRCLIBRecord, _ q: LyricsQuery) -> Int {
        guard let name = r.trackName else { return 0 }
        let full = BrowserSong.key(name), bare = BrowserSong.key(BrowserSong.bareTitle(name))
        var best = 0
        for title in [q.title, q.otherTitle].compactMap({ $0 }) {
            let k = BrowserSong.key(title)
            guard !k.isEmpty else { continue }
            if k == full { return 2 }
            if k == bare || BrowserSong.key(BrowserSong.bareTitle(title)) == bare { best = 1 }
        }
        return best
    }

    private static func distance(_ r: LRCLIBRecord, _ q: LyricsQuery) -> Double {
        guard let d = q.duration, let rd = r.duration else { return 0 }
        return abs(d - rd)
    }
}

/// Where the lookup for the song on show stands.
public enum LyricsState: Equatable, Sendable {
    case idle
    case loading
    case found(SongLyrics)
    /// LRCLIB has nothing for the song, or it doesn't read as a song.
    case missing
    /// The network failed; asked again a minute later at the soonest.
    case failed

    /// Seconds before a failed lookup is tried again on its own.
    public static let retryAfter: Double = 60

    /// Whether to look the song up, with this state for the song shown before (`sameSong`).
    /// Another song always; the same one never while its lookup is on its way, so a click on the
    /// lyrics button then sends nothing more; when the button asks (`force`, answered from the
    /// cache when it can be); or on its own a minute after a failure.
    public func needsLookUp(sameSong: Bool, force: Bool, sinceFailure: Double) -> Bool {
        guard sameSong else { return true }
        if self == .loading { return false }
        return force || self == .failed && sinceFailure > Self.retryAfter
    }
}

/// The two lyrics switches in Settings ("Show lyrics" and "Also for music in a web browser"),
/// as the island last applied them.
public struct LyricsSwitches: Equatable, Sendable {
    public var enabled: Bool
    public var browsers: Bool

    public init(enabled: Bool, browsers: Bool) {
        self.enabled = enabled
        self.browsers = browsers
    }

    public enum Change: Equatable, Sendable {
        /// Nothing the lyrics on show depend on.
        case none
        /// Lyrics went off: forget them, and which song's were hidden.
        case off
        /// Lyrics came on, or the browsers switch moved while they are on: forget what was
        /// worked out and look the song on show up again, without waiting for the next song.
        case lookAgain
    }

    /// What moving the switches from `old` (nil before the first look) to `new` asks of the
    /// lyrics on show.
    public static func change(from old: LyricsSwitches?, to new: LyricsSwitches) -> Change {
        guard let old, old != new else { return .none }
        if !new.enabled { return old.enabled ? .off : .none }
        return .lookAgain
    }
}

/// What a lookup found: lyrics, or that LRCLIB has none for the song.
public enum LyricsLookup: Equatable, Sendable {
    case found(SongLyrics)
    case missing
}

/// Lyrics already fetched, one small file per song, so a song is looked up once. Songs LRCLIB
/// had nothing for are asked about again after a week, in case someone has added them.
public struct LyricsCache: Sendable {
    public let directory: URL
    public var missingLifetime: TimeInterval
    /// Files kept; the oldest go first.
    public var limit: Int

    public init(directory: URL, missingLifetime: TimeInterval = 7 * 86_400, limit: Int = 400) {
        self.directory = directory
        self.missingLifetime = missingLifetime
        self.limit = limit
    }

    private struct Entry: Codable {
        var key: String
        var fetchedAt: Date
        var lyrics: SongLyrics?
    }

    /// The saved answer for `key`, or nil when there is none, or only an old "none".
    public func load(_ key: String, now: Date) -> LyricsLookup? {
        guard let data = try? Data(contentsOf: file(key)),
              let entry = try? Self.decoder.decode(Entry.self, from: data), entry.key == key else { return nil }
        if let lyrics = entry.lyrics { return .found(lyrics) }
        return now.timeIntervalSince(entry.fetchedAt) < missingLifetime ? .missing : nil
    }

    public func save(_ key: String, _ result: LyricsLookup, now: Date) {
        var lyrics: SongLyrics?
        if case .found(let l) = result { lyrics = l }
        guard let data = try? Self.encoder.encode(Entry(key: key, fetchedAt: now, lyrics: lyrics)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
        prune()
    }

    /// The file for a song: a hash of its key, so titles never become file names.
    public func file(_ key: String) -> URL {
        directory.appendingPathComponent(Self.hash(key) + ".json")
    }

    /// FNV-1a, 64-bit, as hex: stable across launches, unlike `hashValue`.
    static func hash(_ text: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", h)
    }

    private func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > limit else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - limit) {
            try? fm.removeItem(at: url)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Whether Home's right-hand column shows the lyrics or the glances, when lyrics are found for
/// the song on show. Lyrics take the column, but a timer or the stopwatch the user started stays
/// above them, so a Pomodoro with music playing is still on Home. Anything that needs the user,
/// or more counting than fits above the lyrics, gives the column back to the glances.
public enum LyricsPlacement {
    public enum Glance: Equatable, Sendable {
        /// Waiting on the user, or failing loudly.
        case needsYou
        /// A timer or the stopwatch, counting.
        case counting
        /// The next event, usage figures, other activities.
        case quiet
    }

    public enum Column: Equatable, Sendable {
        case glances
        /// The lyrics, under the glances at these positions.
        case lyrics(keeping: [Int])
    }

    /// `room` is how many glances fit above the lyrics while leaving them a few lines.
    public static func column(_ glances: [Glance], room: Int) -> Column {
        if glances.contains(.needsYou) { return .glances }
        let counting = glances.indices.filter { glances[$0] == .counting }
        return counting.count > max(0, room) ? .glances : .lyrics(keeping: counting)
    }

    /// One glance above the lyrics on a short island, two on a taller one.
    public static func room(height: Double) -> Int { height >= 140 ? 2 : 1 }

    /// The lyrics button's offer takes the whole column, but never over something that needs
    /// you (an approval, a loud failure): it waits until that is answered.
    public static func offerFits(_ glances: [Glance]) -> Bool { !glances.contains(.needsYou) }
}
