import Foundation

/// One of the user's shortcuts from the Shortcuts app.
public struct ShortcutItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The shortcut's identifier when macOS gives one, otherwise its name. `shortcuts run`
    /// takes either.
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// How the last run of a shortcut went.
public enum ShortcutRunState: Equatable, Sendable {
    case running
    case done
    /// With the first line of what the Shortcuts tool said, if anything.
    case failed(String?)
}

/// Reading `shortcuts list` and finding shortcuts by name.
public enum ShortcutsCatalog {
    /// The arguments that list every shortcut with its identifier.
    public static let listArguments = ["list", "--show-identifiers"]

    /// The arguments that run one.
    public static func runArguments(_ item: ShortcutItem) -> [String] { ["run", item.id] }

    /// Reads `shortcuts list --show-identifiers`, one "Name (IDENTIFIER)" per line. A name can
    /// hold brackets itself, so only a trailing identifier-shaped bracket is taken off. Plain
    /// names (older macOS, or the list without identifiers) are kept as they are. Duplicates go.
    public static func parse(_ output: String) -> [ShortcutItem] {
        var seen: Set<String> = []
        var items: [ShortcutItem] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var item = ShortcutItem(id: line, name: line)
            if line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) {
                let inside = line[open.upperBound..<line.index(before: line.endIndex)]
                if UUID(uuidString: String(inside)) != nil {
                    let name = line[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { item = ShortcutItem(id: String(inside), name: name) }
                }
            }
            guard seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    /// Shortcuts whose name has every word of `query` (a word matches the start of a word in the
    /// name; from three letters, anywhere in it). Names that start with the query come first,
    /// then whole-word matches, then the rest; ties go to the ones run most recently, then A to Z.
    /// An empty query lists everything that way.
    public static func search(_ query: String, in items: [ShortcutItem], recent: [String] = []) -> [ShortcutItem] {
        let words = tokens(query)
        let phrase = normalized(query).trimmingCharacters(in: .whitespaces)
        let rank = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let scored = items.compactMap { item -> (item: ShortcutItem, score: Int)? in
            guard let s = score(item, words: words, phrase: phrase) else { return nil }
            return (item, s)
        }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let ra = rank[a.item.id] ?? Int.max, rb = rank[b.item.id] ?? Int.max
            if ra != rb { return ra < rb }
            return a.item.name.localizedCaseInsensitiveCompare(b.item.name) == .orderedAscending
        }.map(\.item)
    }

    /// Strong matches only, for suggesting a shortcut while someone types in the Ask box: the
    /// name starts with the text, or each word starts a word of the name. Two letters at least.
    public static func suggestions(for text: String, in items: [ShortcutItem], limit: Int = 2) -> [ShortcutItem] {
        let phrase = normalized(text).trimmingCharacters(in: .whitespaces)
        guard phrase.count >= 2 else { return [] }
        let words = tokens(text)
        return Array(items.filter { item in
            let name = tokens(item.name)
            return normalized(item.name).hasPrefix(phrase) || words.allSatisfy { w in name.contains { $0.hasPrefix(w) } }
        }.sorted { a, b in
            let pa = normalized(a.name).hasPrefix(phrase), pb = normalized(b.name).hasPrefix(phrase)
            if pa != pb { return pa }
            return a.name.count != b.name.count ? a.name.count < b.name.count : a.name < b.name
        }.prefix(limit))
    }

    /// nil when a word isn't in the name.
    static func score(_ item: ShortcutItem, words: [String], phrase: String) -> Int? {
        guard !words.isEmpty else { return 0 }
        let name = tokens(item.name)
        var total = 0
        for w in words {
            if name.contains(w) { total += 3 } else if name.contains(where: { $0.hasPrefix(w) }) { total += 2 } else if w.count >= 3, name.contains(where: { $0.contains(w) }) {
                total += 1
            } else {
                return nil
            }
        }
        if normalized(item.name).hasPrefix(phrase) { total += 10 }
        return total
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
    }

    static func tokens(_ text: String) -> [String] {
        normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The first line of what the Shortcuts tool printed when a run failed, short enough for
    /// one line in the island.
    public static func failureReason(_ stderr: String) -> String? {
        let line = stderr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var text = line else { return nil }
        if text.lowercased().hasPrefix("error: ") { text = String(text.dropFirst(7)) }
        return text.count > 90 ? String(text.prefix(89)) + "…" : text
    }
}
