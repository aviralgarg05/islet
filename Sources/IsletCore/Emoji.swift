import Foundation

/// One emoji and the words it is found by.
public struct EmojiItem: Sendable, Hashable, Identifiable {
    public let emoji: String
    /// "Grinning face", "Flag: Japan".
    public let name: String
    /// Folded, lower-case words: the name's, then other words people search for.
    let words: [String]
    /// Where it sits in the catalogue (faces first, flags last).
    let rank: Int
    /// How many of `words` are the name's own.
    let nameWordCount: Int

    public var id: String { emoji }
}

/// Every emoji macOS knows a name for: each single emoji from the system's Unicode tables,
/// the flags of every region, and the commonest sequences (people at work, families, the
/// rainbow flag). Searched by name and by the words people use ("lol", "tada", "yes").
/// Nothing is downloaded.
public enum EmojiCatalog {
    public static let all: [EmojiItem] = build()

    /// The ones shown before anything is typed or used.
    public static let favourites = ["😀", "😂", "🥲", "😍", "🤔", "😅", "👍", "🙏", "👏", "🎉", "❤️", "🔥", "✅", "👀", "🚀", "✨"]
    static let popular = Set(favourites)

    /// - Parameter recent: emoji used lately, most recent first; they come first among equals.
    public static func search(_ query: String, in items: [EmojiItem] = all, recent: [String] = [], limit: Int = 400) -> [EmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            let used = recent.compactMap { e in items.first { $0.emoji == e } }
            let seen = Set(used.map(\.emoji))
            return Array((used + items.filter { !seen.contains($0.emoji) }).prefix(limit))
        }
        // An emoji pasted into the field finds itself.
        if let exact = items.first(where: { $0.emoji == trimmed || $0.emoji == trimmed + "\u{FE0F}" }) { return [exact] }
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        let recency = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        var scored: [(item: EmojiItem, score: Int, order: Int)] = []
        for (i, item) in items.enumerated() {
            guard let score = score(item, words) else { continue }
            let bonus = recency[item.emoji].map { max(0, 20 - $0) } ?? 0
            scored.append((item, score + bonus, i))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(limit).map(\.item)
    }

    /// nil unless every typed word starts a word of the emoji's. The whole name scores
    /// highest, then whole words, then the starts of words.
    static func score(_ item: EmojiItem, _ words: [String]) -> Int? {
        var total = 0
        for word in words {
            var best = 0
            for (i, w) in item.words.enumerated() {
                // The name's own words count a little more than the extra ones.
                let own = i < item.nameWordCount ? 1 : 0
                if w == word { best = max(best, 6 + own) } else if w.hasPrefix(word) { best = max(best, 3 + own) }
            }
            guard best > 0 else { return nil }
            total += best
        }
        // The whole name typed wins; a name that starts with the words typed comes next.
        let name = tokens(item.name).joined(separator: " ")
        let typed = words.joined(separator: " ")
        if name == typed { total += 20 } else if name.hasPrefix(typed + " ") { total += 1 }
        // Shorter names are the likelier answer: "heart" before "heart with arrow". Only the
        // name counts, so the extra words that help find an emoji don't push it down. The
        // everyday ones come first among close answers: "heart" is the red one, "lol" the
        // tears of joy.
        return total * 10 - min(9, item.nameWordCount / 2) + (popular.contains(item.emoji) ? 15 : 0)
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // MARK: Building the catalogue

    static func build() -> [EmojiItem] {
        var items: [EmojiItem] = []
        var seen: Set<String> = []
        func add(_ emoji: String, _ name: String, rank: Int, extra: [String] = []) {
            guard seen.insert(emoji).inserted else { return }
            let own = tokens(name)
            let more = (aliases[emoji] ?? []) + extra
            items.append(EmojiItem(emoji: emoji, name: name, words: own + more.flatMap(tokens).filter { !own.contains($0) },
                                   rank: rank, nameWordCount: own.count))
        }
        // The emoji blocks first, so the faces start with 😀 rather than ☺️.
        for range in [0x1F000...0x1FAFF, 0x00A9...0x00AE, 0x203C...0x3299] {
            for value in range {
                guard let scalar = Unicode.Scalar(value), isStandalone(scalar), let raw = scalar.properties.name else { continue }
                // Text-style symbols (©, ♥, ✔) need the emoji selector to draw as emoji.
                let emoji = scalar.properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
                let name = names[emoji] ?? plainName(raw)
                add(emoji, name, rank: rank(name, value: UInt32(value)))
            }
        }
        for (emoji, name, extra) in sequences { add(emoji, name, rank: 3, extra: extra) }
        let english = Locale(identifier: "en_GB")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isUppercase }),
                  let place = english.localizedString(forRegionCode: code), place != code else { continue }
            let flag = code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }.map(String.init).joined()
            add(flag, "Flag: \(place)", rank: 5, extra: ["flag", code.lowercased()])
        }
        return items.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map(\.element)
    }

    /// An emoji that stands alone: not a skin tone, hair style, flag letter or keycap part.
    static func isStandalone(_ s: Unicode.Scalar) -> Bool {
        let p = s.properties
        guard p.isEmoji, !p.isEmojiModifier, s.value > 0x7F else { return false }
        switch s.value {
        case 0x1F1E6...0x1F1FF, 0x1F3FB...0x1F3FF, 0x1F9B0...0x1F9B3, 0x20E3, 0x200D, 0xFE0F: return false
        default: return true
        }
    }

    /// "GRINNING FACE WITH SMILING EYES" as "Grinning face with smiling eyes".
    static func sentenceCase(_ raw: String) -> String {
        let lower = raw.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// The Unicode name as people say it: "THUMBS UP SIGN" is "Thumbs up", as the emoji
    /// picker calls it. A one-word name keeps its "sign" ("Warning sign").
    static func plainName(_ raw: String) -> String {
        var words = raw.split(separator: " ")
        if words.count > 2, let last = words.last, last == "SIGN" || last == "SYMBOL" { words.removeLast() }
        return sentenceCase(words.joined(separator: " "))
    }

    /// Faces first (the smileys, not the animals or the moon), then hands and people, hearts,
    /// everything else, then flags.
    static func rank(_ name: String, value: UInt32 = 0) -> Int {
        let words = Set(tokens(name))
        let smileys = [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F9D0...0x1F9D0, 0x1FAE0...0x1FAEF,
                       0x2639...0x263A] as [ClosedRange<UInt32>]
        if words.contains("face"), smileys.contains(where: { $0.contains(value) }) { return 0 }
        if !words.isDisjoint(with: ["hand", "hands", "thumbs", "finger", "fist", "person", "man", "woman", "boy", "girl", "baby", "people"]) {
            return 1
        }
        if words.contains("heart") { return 2 }
        return 4
    }

    /// Names the Unicode tables give in an older form, as the emoji picker says them.
    static let names: [String: String] = [
        "❤️": "Red heart", "♥️": "Heart suit", "😃": "Grinning face with big eyes", "😄": "Grinning face with smiling eyes", "😁": "Beaming face with smiling eyes",
        "😆": "Grinning squinting face", "😅": "Grinning face with sweat", "😍": "Smiling face with heart-eyes",
        "😘": "Face blowing a kiss", "😜": "Winking face with tongue", "😝": "Squinting face with tongue",
        "🥳": "Partying face", "🤔": "Thinking face", "😎": "Smiling face with sunglasses", "😭": "Loudly crying face",
        "😱": "Face screaming in fear", "😡": "Enraged face", "🙏": "Folded hands", "✅": "Check mark button",
        "✔️": "Check mark", "☀️": "Sun", "⭐": "Star", "⚡": "High voltage", "🔥": "Fire", "🙂": "Slightly smiling face",
        "🙃": "Upside-down face", "🤗": "Smiling face with open hands", "🤩": "Star-struck", "🤯": "Exploding head",
        "🫡": "Saluting face", "👋": "Waving hand", "👌": "OK hand", "👏": "Clapping hands", "💪": "Flexed biceps",
    ]

    /// Other words people look for an emoji by.
    static let aliases: [String: [String]] = [
        "😀": ["smile", "happy"], "😃": ["smile", "happy"], "😄": ["smile", "happy"], "😁": ["grin"], "😆": ["laugh"],
        "😅": ["phew", "nervous"], "🤣": ["lol", "rofl", "laugh"], "😂": ["lol", "laugh", "haha", "crying laughing"],
        "🙂": ["smile"], "😉": ["wink"], "😊": ["blush", "happy", "smile"], "😇": ["angel", "innocent"],
        "🥰": ["love", "hearts"], "😍": ["love", "heart eyes"], "😘": ["kiss"], "😋": ["yum", "tasty"],
        "😜": ["silly", "joke"], "🤪": ["crazy", "silly"], "🤔": ["think", "hmm"], "🤐": ["secret", "quiet"],
        "😐": ["meh"], "😑": ["meh"], "🙄": ["eye roll", "whatever"], "😬": ["awkward", "oops"],
        "😌": ["relief", "calm"], "😔": ["sad"], "😴": ["sleep", "tired", "zzz"], "🤒": ["ill", "sick"],
        "🤢": ["sick"], "🤮": ["sick"], "🥵": ["hot"], "🥶": ["cold"], "🤯": ["mind blown", "shock"],
        "🥳": ["party", "birthday", "celebrate"], "😎": ["cool"], "🤓": ["geek", "glasses"], "😕": ["confused"],
        "😮": ["wow", "surprised"], "😲": ["wow", "shock"], "🥺": ["please", "puppy eyes"], "😢": ["sad", "cry", "tear"],
        "😭": ["sob", "cry", "sad"], "😱": ["scream", "scared"], "😩": ["tired", "weary"], "😤": ["annoyed", "huff"],
        "😡": ["angry", "mad", "rage"], "😠": ["angry", "mad"], "🤬": ["swear", "angry"], "💀": ["dead", "lol"],
        "💩": ["poop"], "🤡": ["clown"], "👻": ["ghost", "boo"], "👽": ["alien"], "🤖": ["robot", "bot"],
        "🥲": ["grateful", "smile tear"], "🫠": ["melt"], "🫡": ["salute", "yes sir"], "🫶": ["love", "heart hands"],
        "👋": ["hi", "hello", "bye", "wave"], "👌": ["ok", "okay", "perfect"], "✌️": ["peace", "victory"],
        "🤞": ["luck", "hope", "fingers crossed"], "👍": ["yes", "ok", "like", "approve", "agree", "thumbs up"],
        "👎": ["no", "dislike", "disagree"], "👏": ["clap", "applause", "bravo"], "🙌": ["hooray", "praise", "yay"],
        "🙏": ["please", "thanks", "thank you", "pray", "high five"], "💪": ["strong", "muscle", "flex"],
        "🤝": ["deal", "handshake", "agreement"], "👀": ["look", "eyes", "watching"], "🤷": ["shrug", "dunno"],
        "🤦": ["facepalm"], "🙋": ["hi", "question"], "🙇": ["sorry", "bow"],
        "❤️": ["love", "heart", "red heart"], "💔": ["heartbreak", "sad"], "💖": ["love", "sparkle"], "💯": ["hundred", "perfect", "100"],
        "🔥": ["fire", "lit", "hot"], "✨": ["sparkle", "magic", "new", "shiny"], "⭐": ["star", "favourite"],
        "🌟": ["star", "shine"], "⚡": ["zap", "lightning", "fast"], "🎉": ["party", "tada", "celebrate", "hooray"],
        "🎊": ["party", "confetti"], "🎂": ["birthday", "cake"], "🎁": ["gift", "present"], "🏆": ["winner", "trophy", "award"],
        "🥇": ["first", "gold", "winner"], "✅": ["done", "tick", "check", "yes"], "☑️": ["done", "tick", "check"],
        "✔️": ["tick", "check", "done"], "❌": ["no", "cross", "wrong", "cancel"], "❎": ["cross"], "⚠️": ["warning", "caution"],
        "🚫": ["no", "forbidden"], "⛔": ["stop", "no entry"], "❓": ["question"], "❗": ["exclamation", "important"],
        "💡": ["idea", "bulb"], "📌": ["pin"], "📎": ["attachment", "clip"], "📅": ["date", "calendar"], "🗓️": ["calendar"],
        "⏰": ["alarm", "time"], "⌛": ["wait", "hourglass", "time"], "⏳": ["wait", "loading"], "📝": ["note", "memo", "write"],
        "✏️": ["edit", "pencil"], "📣": ["announce"], "📢": ["announce", "loud"], "🔔": ["bell", "notification"],
        "🔒": ["lock", "secure", "private"], "🔑": ["key"], "🐛": ["bug"], "🚀": ["launch", "ship", "rocket", "fast"],
        "💻": ["laptop", "computer", "mac"], "🖥️": ["desktop", "computer"], "📱": ["phone", "iphone", "mobile"],
        "☕": ["coffee", "tea"], "🍵": ["tea"], "🍺": ["beer", "pub"], "🍻": ["cheers", "beers"], "🥂": ["cheers", "toast"],
        "🍷": ["wine"], "🍕": ["pizza"], "🍔": ["burger"], "🍰": ["cake"], "🍩": ["doughnut", "donut"],
        "🌈": ["rainbow"], "☀️": ["sun", "sunny", "weather"], "🌧️": ["rain", "weather"], "❄️": ["snow", "cold"],
        "🌙": ["moon", "night"], "🌍": ["world", "earth", "globe"], "🐶": ["dog", "puppy"], "🐱": ["cat", "kitten"],
        "🦄": ["unicorn"], "🌸": ["flower", "blossom"], "🌹": ["rose", "flower"], "🍀": ["luck", "clover"],
        "💰": ["money", "cash"], "💸": ["money", "spend"], "📈": ["up", "growth", "chart"], "📉": ["down", "chart"],
        "🎵": ["music", "note"], "🎶": ["music", "notes"], "🎧": ["headphones", "music"], "📷": ["camera", "photo"],
        "✈️": ["plane", "flight", "travel"], "🏠": ["home", "house"], "🚗": ["car"], "🧠": ["brain", "think", "smart"],
        "👑": ["king", "queen", "crown"], "💤": ["sleep", "zzz"], "🆗": ["ok"], "🆕": ["new"], "🔗": ["link"],
    ]

    /// Sequences that aren't a single character, so the Unicode tables don't name them.
    static let sequences: [(String, String, [String])] = [
        ("🧑‍💻", "Technologist", ["developer", "programmer", "coder", "computer"]),
        ("👩‍💻", "Woman technologist", ["developer", "programmer", "coder"]),
        ("👨‍💻", "Man technologist", ["developer", "programmer", "coder"]),
        ("🧑‍🔬", "Scientist", ["lab", "science"]), ("🧑‍🎨", "Artist", ["painter"]), ("🧑‍🍳", "Cook", ["chef"]),
        ("🧑‍🏫", "Teacher", ["school"]), ("🧑‍🎓", "Student", ["graduate"]), ("🧑‍⚕️", "Health worker", ["doctor", "nurse"]),
        ("🧑‍🚀", "Astronaut", ["space"]), ("🧑‍🚒", "Firefighter", ["fire"]), ("🧑‍✈️", "Pilot", ["plane"]),
        ("🧑‍🔧", "Mechanic", ["repair"]), ("🧑‍💼", "Office worker", ["business", "work"]), ("🧑‍🌾", "Farmer", []),
        ("🧑‍⚖️", "Judge", ["law"]), ("🧑‍🎤", "Singer", ["music", "star"]),
        ("🤷‍♀️", "Woman shrugging", ["shrug", "dunno"]), ("🤷‍♂️", "Man shrugging", ["shrug", "dunno"]),
        ("🤦‍♀️", "Woman facepalming", ["facepalm"]), ("🤦‍♂️", "Man facepalming", ["facepalm"]),
        ("🙋‍♀️", "Woman raising hand", ["hi", "question"]), ("🙋‍♂️", "Man raising hand", ["hi", "question"]),
        ("🙆‍♀️", "Woman gesturing OK", ["ok", "yes"]), ("🙅‍♀️", "Woman gesturing no", ["no"]),
        ("🏃‍♀️", "Woman running", ["run", "exercise"]), ("🏃‍♂️", "Man running", ["run", "exercise"]),
        ("🚶‍♀️", "Woman walking", ["walk"]), ("🧘‍♀️", "Woman in lotus position", ["yoga", "meditate", "calm"]),
        ("👨‍👩‍👧", "Family: man, woman, girl", ["family", "parents"]), ("👨‍👩‍👧‍👦", "Family: man, woman, girl, boy", ["family"]),
        ("👩‍👩‍👦", "Family: woman, woman, boy", ["family"]), ("👨‍👨‍👧", "Family: man, man, girl", ["family"]),
        ("🧑‍🤝‍🧑", "People holding hands", ["friends", "together"]), ("💑", "Couple with heart", ["love", "couple"]),
        ("❤️‍🔥", "Heart on fire", ["love", "passion", "burning"]), ("❤️‍🩹", "Mending heart", ["heal", "better"]),
        ("😮‍💨", "Face exhaling", ["sigh", "relief", "phew"]), ("😵‍💫", "Face with spiral eyes", ["dizzy"]),
        ("😶‍🌫️", "Face in clouds", ["foggy", "absent"]), ("🏳️‍🌈", "Rainbow flag", ["pride", "lgbt", "lgbtq"]),
        ("🏳️‍⚧️", "Transgender flag", ["pride", "trans"]), ("🏴‍☠️", "Pirate flag", ["pirate", "skull"]),
        ("🐕‍🦺", "Service dog", ["dog", "assistance"]), ("🐈‍⬛", "Black cat", ["cat"]), ("🐻‍❄️", "Polar bear", ["bear", "arctic"]),
        ("🐦‍🔥", "Phoenix", ["bird", "fire", "rebirth"]), ("🍄‍🟫", "Brown mushroom", ["mushroom", "fungus"]),
        ("🍋‍🟩", "Lime", ["fruit", "citrus"]), ("⛓️‍💥", "Broken chain", ["free", "break"]),
        ("👁️‍🗨️", "Eye in speech bubble", ["witness"]), ("🧑‍🧑‍🧒", "Family: adult, adult, child", ["family"]),
        ("#️⃣", "Keycap: #", ["hash", "number sign"]), ("*️⃣", "Keycap: *", ["asterisk"]),
        ("0️⃣", "Keycap: 0", ["zero"]), ("1️⃣", "Keycap: 1", ["one"]), ("2️⃣", "Keycap: 2", ["two"]), ("3️⃣", "Keycap: 3", ["three"]),
        ("4️⃣", "Keycap: 4", ["four"]), ("5️⃣", "Keycap: 5", ["five"]), ("6️⃣", "Keycap: 6", ["six"]), ("7️⃣", "Keycap: 7", ["seven"]),
        ("8️⃣", "Keycap: 8", ["eight"]), ("9️⃣", "Keycap: 9", ["nine"]),
        (subdivisionFlag("gbeng"), "Flag: England", ["flag", "england", "uk"]),
        (subdivisionFlag("gbsct"), "Flag: Scotland", ["flag", "scotland", "uk"]),
        (subdivisionFlag("gbwls"), "Flag: Wales", ["flag", "wales", "cymru", "uk"]),
    ]

    /// A black flag with a region's tag letters: England, Scotland, Wales.
    static func subdivisionFlag(_ tag: String) -> String {
        var scalars: [Unicode.Scalar] = ["\u{1F3F4}"]
        scalars += tag.unicodeScalars.compactMap { Unicode.Scalar(0xE0000 + $0.value) }
        scalars.append("\u{E007F}")
        return String(String.UnicodeScalarView(scalars))
    }
}

/// Emoji used lately, most recent first, kept in `emoji.json` beside Islet's other files.
public struct EmojiRecents: Codable, Equatable, Sendable {
    public private(set) var emoji: [String] = []
    public static let limit = 24

    public init(_ emoji: [String] = []) {
        self.emoji = Array(emoji.prefix(Self.limit))
    }

    public mutating func use(_ e: String) {
        emoji.removeAll { $0 == e }
        emoji.insert(e, at: 0)
        if emoji.count > Self.limit { emoji.removeLast(emoji.count - Self.limit) }
    }

    public static func load(from url: URL) -> EmojiRecents {
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([String].self, from: data) else { return EmojiRecents() }
        // Only what could be an emoji: short, with an emoji or a keycap in it.
        return EmojiRecents(list.filter { e in
            (1...16).contains(e.unicodeScalars.count)
                && e.unicodeScalars.contains { $0.value == 0x20E3 || $0.value > 0x7F && $0.properties.isEmoji }
        })
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(emoji).write(to: url, options: .atomic)
    }
}
