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
    static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
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

/// What Islet asks LRCLIB for one song: its title, artist, album and length, and nothing else.
public struct LyricsQuery: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    /// Seconds.
    public var duration: Double?

    public init(title: String, artist: String, album: String? = nil, duration: Double? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Players whose songs have lyrics worth looking up: Music and Spotify.
    public static let players: Set<String> = ["com.apple.Music", "com.spotify.client"]

    /// The query for what's playing, or nil when it isn't a song from Music or Spotify (a video,
    /// a podcast in a browser, an advert), so nothing about it is sent.
    public init?(_ np: NowPlaying) {
        let fromPlayer = np.source == .appleMusic || np.source == .spotify || np.bundleID.map(Self.players.contains) == true
        let title = np.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (np.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard fromPlayer, !title.isEmpty, !artist.isEmpty else { return nil }
        // Spotify's adverts and very long tracks (mixes, audiobooks) have no lyrics to find.
        if let d = np.duration, d > 0, d < 15 || d > 20 * 60 { return nil }
        let album = np.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(title: title, artist: artist, album: album?.isEmpty == false ? album : nil,
                  duration: np.duration.flatMap { $0 > 0 ? $0 : nil })
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
        "Islet \(version) (https://github.com/aviralgarg05/islet)"
    }

    /// The exact match: `/api/get` with the title, artist, album and length.
    public static func getURL(_ q: LyricsQuery) -> URL {
        var items = [URLQueryItem(name: "track_name", value: q.title), URLQueryItem(name: "artist_name", value: q.artist)]
        if let album = q.album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let d = q.duration { items.append(URLQueryItem(name: "duration", value: String(Int(d.rounded())))) }
        return url("/api/get", items)
    }

    /// When the exact match fails: `/api/search` with the same title, artist and album.
    public static func searchURL(_ q: LyricsQuery) -> URL {
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

    /// The best of a search's records for the song: the same length within a couple of seconds
    /// (any length when the song's is unknown), synced lyrics before plain, then the closest length.
    public static func best(_ records: [LRCLIBRecord], for q: LyricsQuery) -> LRCLIBRecord? {
        let candidates = records.filter { r in
            guard lyrics(from: r) != nil else { return false }
            guard let d = q.duration, let rd = r.duration else { return true }
            return abs(d - rd) <= 2.5
        }
        return candidates.enumerated().min { a, b in
            let sa = a.element.syncedLyrics?.isEmpty == false, sb = b.element.syncedLyrics?.isEmpty == false
            if sa != sb { return sa }
            let ta = sameTitle(a.element, q), tb = sameTitle(b.element, q)
            if ta != tb { return ta }
            let da = distance(a.element, q), db = distance(b.element, q)
            return da != db ? da < db : a.offset < b.offset
        }?.element
    }

    private static func sameTitle(_ r: LRCLIBRecord, _ q: LyricsQuery) -> Bool {
        r.trackName?.compare(q.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func distance(_ r: LRCLIBRecord, _ q: LyricsQuery) -> Double {
        guard let d = q.duration, let rd = r.duration else { return 0 }
        return abs(d - rd)
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
