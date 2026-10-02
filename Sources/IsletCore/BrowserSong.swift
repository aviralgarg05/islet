import Foundation

/// What a web browser says is playing, read as a song LRCLIB could know. YouTube puts the artist
/// in a video's title ("Adele - Hello (Official Music Video)") and the channel in the artist
/// ("AdeleVEVO", "Adele - Topic", or a label such as "T-Series"); YouTube Music and the web
/// players of Spotify and Apple Music report the song itself, with its album. A title that reads
/// as something other than a song (a podcast, a trailer, a live stream) gives nil, so nothing
/// about it is sent.
public enum BrowserSong {
    public struct Song: Equatable, Sendable {
        public var title: String
        public var artist: String
        /// The artist is a guess: the title was "A - B" and the channel is neither, or credits
        /// followed a "|" without naming the channel. LRCLIB is then searched by the title's words.
        public var unsure: Bool
        /// For "A - B" in doubt, the half taken for the artist, which may be the song's title.
        public var otherTitle: String?

        public init(title: String, artist: String, unsure: Bool = false, otherTitle: String? = nil) {
            self.title = title
            self.artist = artist
            self.unsure = unsure
            self.otherTitle = otherTitle
        }
    }

    /// The song in a browser's report, or nil when it doesn't read as one.
    public static func song(title rawTitle: String, artist rawArtist: String, album: String? = nil) -> Song? {
        let fullTitle = squash(rawTitle)
        var artist = squash(rawArtist)
        guard !fullTitle.isEmpty, !artist.isEmpty, !notASong(fullTitle) else { return nil }

        // The channel: YouTube's own "Artist - Topic" names the artist for sure; "ArtistVEVO" and
        // "Artist Official" name the artist with the title carrying "Artist - Song".
        var topic = false, vevo = false
        if artist.hasSuffix(" - Topic") {
            artist = squash(String(artist.dropLast(8)))
            topic = true
        } else if artist.count > 4, artist.hasSuffix("VEVO") {
            artist = spaced(String(artist.dropLast(4)))
            vevo = true
        } else {
            for suffix in [" Official Channel", " Official"] where artist.count > suffix.count
                && artist.lowercased().hasSuffix(suffix.lowercased()) {
                artist = squash(String(artist.dropLast(suffix.count)))
                break
            }
        }
        guard !artist.isEmpty else { return nil }
        // A music service's own report: the song as it is, less a video's labels.
        let tagged = topic || !(album ?? "").trimmingCharacters(in: .whitespaces).isEmpty

        // Credits after "|": the first part that isn't a label ("Lyrical", "Song") is the song's.
        let parts = fullTitle.components(separatedBy: "|").map { stripLabels(squash($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let kept = parts.firstIndex { !isLabel($0) } ?? 0
        let credits = parts.indices.filter { $0 != kept && !isLabel(parts[$0]) }.map { parts[$0] }
        var title = parts[kept]
        if !tagged { title = dropFeaturing(title) }
        title = unquote(title)
        guard !title.isEmpty else { return nil }
        if tagged { return Song(title: title, artist: artist) }
        title = dropVersion(title)

        if let (left, right) = split(title, artist: artist, vevo: vevo) {
            if vevo || same(left, artist) { return Song(title: unquote(right), artist: left) }
            if same(right, artist) { return Song(title: unquote(left), artist: right) }
            // "A - B" with a channel that is neither: most often "Artist - Song", but labels
            // also write "Song - Film" or "Song - Singer", so the search takes both halves.
            return Song(title: unquote(right), artist: left, unsure: true, otherTitle: unquote(left))
        }
        let named = credits.isEmpty || credits.contains { same($0, artist) }
        return Song(title: title, artist: artist, unsure: !named)
    }

    // MARK: Comparing names

    /// A name folded for comparing: lowercase, without accents, letters and digits only.
    public static func key(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The title without what follows in brackets or after a dash: "Kesariya (From
    /// \"Brahmastra\")" is "Kesariya".
    public static func bareTitle(_ text: String) -> String {
        var cut = text.endIndex
        for mark in [" (", " [", " - ", " – ", " — "] {
            if let r = text.range(of: mark), r.lowerBound < cut { cut = r.lowerBound }
        }
        let bare = text[..<cut].trimmingCharacters(in: .whitespaces)
        return bare.isEmpty ? text : bare
    }

    static func same(_ a: String, _ b: String) -> Bool {
        let ka = key(a)
        return !ka.isEmpty && ka == key(b)
    }

    // MARK: Not a song

    /// Words that mark a video as something other than a song.
    static let notSongPhrases: [[String]] = [
        ["podcast"], ["episode"], ["trailer"], ["interview"], ["reaction"], ["reacts"], ["tutorial"],
        ["review"], ["gameplay"], ["walkthrough"], ["unboxing"], ["vlog"], ["full", "movie"], ["lecture"], ["webinar"],
        ["keynote"], ["asmr"], ["explained"], ["documentary"], ["recipe"], ["live", "stream"], ["livestream"],
        ["live", "streaming"], ["live", "now"], ["news", "live"],
    ]

    static func notASong(_ title: String) -> Bool {
        let lower = title.lowercased()
        if ["24/7", "🔴", "#shorts"].contains(where: lower.contains) { return true }
        let words = tokens(title)
        return notSongPhrases.contains { phrase in
            guard words.count >= phrase.count else { return false }
            return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
        }
    }

    // MARK: Labels

    /// Words a video's title adds to a song's: "(Official Music Video)", "[Lyric Video]",
    /// "Full Video Song", "Latest Punjabi Songs 2024".
    static let labelWords: Set<String> = [
        "official", "music", "video", "videos", "audio", "lyric", "lyrics", "lyrical", "full", "song", "songs", "new",
        "latest", "hd", "hq", "4k", "8k", "visualizer", "visualiser", "mv", "m", "v", "clip", "punjabi", "hindi",
        "bollywood", "tamil", "telugu", "english", "romantic", "sad", "party", "hit", "hits", "best", "top", "trending",
        "old", "evergreen", "classic", "remastered", "remaster", "explicit", "clean", "color", "colour", "coded", "out",
        "now", "version", "subtitles", "sub", "subs", "teaser",
    ]

    /// Whether `text` is nothing but such words (and a year).
    static func isLabel(_ text: String) -> Bool {
        let words = tokens(text)
        return words.allSatisfy { labelWords.contains($0) || isYear($0) }
    }

    /// Drops a label before a colon ("Full Video: …", "Lyrical: …"), the first label in brackets
    /// with whatever follows it ("(Official Video) Karan Aujla | …"), and a label of two words or
    /// more at the end ("Tum Hi Ho Full Video Song").
    static func stripLabels(_ text: String) -> String {
        var t = text
        if let colon = t.firstIndex(of: ":"), isLabel(String(t[..<colon])), !t[..<colon].trimmingCharacters(in: .whitespaces).isEmpty {
            t = squash(String(t[t.index(after: colon)...]))
        }
        if let group = brackets(in: t).first(where: { isLabel($0.content) }) {
            let before = squash(String(t[..<group.range.lowerBound]))
            t = before.isEmpty ? squash(String(t[group.range.upperBound...])) : before
        }
        let words = t.split(separator: " ").map(String.init)
        for count in stride(from: min(4, words.count - 1), through: 2, by: -1) {
            let tail = words.suffix(count).joined(separator: " ")
            let tailWords = tokens(tail)
            if isLabel(tail), tailWords.contains(where: ["video", "audio", "lyric", "lyrics", "lyrical"].contains) {
                t = words.dropLast(count).joined(separator: " ")
                break
            }
        }
        return squash(t.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:")))
    }

    /// "(feat. X)", "[ft. X]", "(with X)" and "(prod. X)" go, and an unbracketed " ft. X" or
    /// " feat. X" up to a dash or the end.
    static func dropFeaturing(_ text: String) -> String {
        var t = text
        while let group = brackets(in: t).first(where: { g in
            let c = g.content.lowercased()
            return ["feat", "ft.", "ft ", "featuring", "with ", "prod"].contains { c.hasPrefix($0) }
        }) {
            t = squash(String(t[..<group.range.lowerBound]) + " " + String(t[group.range.upperBound...]))
        }
        if let r = t.range(of: #"\s(ft|feat|featuring)\.?\s"#, options: [.regularExpression, .caseInsensitive]) {
            let rest = t[r.upperBound...]
            let end = [" - ", " – ", " — "].compactMap { rest.range(of: $0)?.lowerBound }.min() ?? t.endIndex
            t = squash(String(t[..<r.lowerBound]) + (end == t.endIndex ? "" : " " + String(t[end...]).trimmingCharacters(in: .whitespaces)))
        }
        return t
    }

    /// "Song - Remastered 2011", "Song - Live", "Song - Radio Edit": the song.
    static func dropVersion(_ text: String) -> String {
        let marks = [" - ", " – ", " — "]
        guard let last = marks.compactMap({ text.range(of: $0, options: .backwards) }).max(by: { $0.lowerBound < $1.lowerBound })
        else { return text }
        let tail = text[last.upperBound...].lowercased()
        let versions = ["remaster", "live", "radio edit", "single version", "mono", "stereo", "acoustic", "edit", "bonus track",
                        "demo", "extended", "original mix", "slowed", "sped up", "reverb"]
        guard versions.contains(where: tail.hasPrefix) else { return text }
        return squash(String(text[..<last.lowerBound]))
    }

    // MARK: Splitting

    /// "A - B" (any dash), or "A: B" when A is the artist.
    static func split(_ title: String, artist: String, vevo: Bool) -> (String, String)? {
        let dashes = [" - ", " – ", " — "].compactMap { title.range(of: $0) }
        if let dash = dashes.min(by: { $0.lowerBound < $1.lowerBound }) {
            let left = squash(String(title[..<dash.lowerBound])), right = squash(String(title[dash.upperBound...]))
            if !left.isEmpty, !right.isEmpty { return (left, right) }
        }
        if let colon = title.firstIndex(of: ":") {
            let left = squash(String(title[..<colon])), right = squash(String(title[title.index(after: colon)...]))
            if !right.isEmpty, vevo || same(left, artist) { return (left, right) }
        }
        return nil
    }

    // MARK: Text

    private struct Group {
        var range: Range<String.Index>
        var content: String
    }

    /// Each "(…)" and "[…]" in `text`, in order.
    private static func brackets(in text: String) -> [Group] {
        var groups: [Group] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "(" || c == "[", let close = text[i...].firstIndex(of: c == "(" ? ")" : "]") {
                groups.append(Group(range: i..<text.index(after: close),
                                    content: String(text[text.index(after: i)..<close]).trimmingCharacters(in: .whitespaces)))
                i = text.index(after: close)
            } else {
                i = text.index(after: i)
            }
        }
        return groups
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func isYear(_ word: String) -> Bool {
        word.count == 4 && (word.hasPrefix("19") || word.hasPrefix("20")) && word.allSatisfy(\.isNumber)
    }

    private static func squash(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Without quotes around it: `"Hello"` is Hello.
    private static func unquote(_ text: String) -> String {
        let t = squash(text)
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")] where t.count > 2 && t.hasPrefix(open) && t.hasSuffix(close) {
            return squash(String(t.dropFirst().dropLast()))
        }
        return t
    }

    /// "TaylorSwift" is "Taylor Swift".
    private static func spaced(_ text: String) -> String {
        var out = ""
        var previous: Character?
        for c in text {
            if let p = previous, p.isLowercase, c.isUppercase { out.append(" ") }
            out.append(c)
            previous = c
        }
        return squash(out)
    }
}
