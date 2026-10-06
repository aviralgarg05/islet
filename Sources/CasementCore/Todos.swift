import Foundation

// MARK: - To-dos

/// One line on the To-dos page.
public struct TodoItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var starred: Bool
    /// When it was ticked off; nil while it is still to do.
    public var doneAt: Date?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, text: String, starred: Bool = false, doneAt: Date? = nil, createdAt: Date) {
        self.id = id
        self.text = text
        self.starred = starred
        self.doneAt = doneAt
        self.createdAt = createdAt
    }

    public var isDone: Bool { doneAt != nil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        text = TodoList.oneLine((try? c.decodeIfPresent(String.self, forKey: .text)) ?? "")
        starred = (try? c.decodeIfPresent(Bool.self, forKey: .starred)) ?? false
        doneAt = try? c.decodeIfPresent(Date.self, forKey: .doneAt)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
    }
}

/// The to-do list: add a line, star it, tick it off. Kept in `todos.json` on this Mac
/// (`TodoList.load` and `save`), nowhere else.
public struct TodoList: Codable, Equatable, Sendable {
    /// Newest first, as added. `ordered` is the order the page shows.
    public private(set) var items: [TodoItem] = []

    /// Enough for a day's list, and few enough to read at a glance.
    public static let maxItems = 200
    public static let maxLength = 300

    public init(items: [TodoItem] = []) {
        self.items = items
        trim()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A line that can't be read is skipped, not the whole list.
        let raw = (try? c.decodeIfPresent([Lenient<TodoItem>].self, forKey: .items)) ?? []
        self.init(items: raw.compactMap(\.value).filter { !$0.text.isEmpty })
    }

    /// What the page shows: what is left to do, starred first, then the newest; then what is
    /// done, the most recently ticked first.
    public var ordered: [TodoItem] {
        let open = items.filter { !$0.isDone }
        let done = items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        return open.filter(\.starred) + open.filter { !$0.starred } + done
    }

    public var openCount: Int { items.filter { !$0.isDone }.count }
    public var hasDone: Bool { items.contains(where: \.isDone) }

    /// Adds a line (newlines become spaces, and it is cut at `maxLength`). Nothing is added for
    /// blank text. Returns the new item.
    @discardableResult
    public mutating func add(_ text: String, now: Date) -> TodoItem? {
        let line = Self.oneLine(text)
        guard !line.isEmpty else { return nil }
        let item = TodoItem(text: line, createdAt: now)
        items.insert(item, at: 0)
        trim(keeping: item.id)
        return item
    }

    public mutating func toggleStar(id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].starred.toggle()
    }

    /// Ticks it off, or puts it back to do.
    public mutating func toggleDone(id: String, now: Date) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].doneAt = items[i].isDone ? nil : now
    }

    public mutating func rename(id: String, to text: String) {
        let line = Self.oneLine(text)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if line.isEmpty { items.remove(at: i) } else { items[i].text = line }
    }

    public mutating func remove(id: String) { items.removeAll { $0.id == id } }

    /// "Clear done": everything ticked off goes.
    public mutating func clearDone() { items.removeAll(where: \.isDone) }

    /// Past `maxItems`, the oldest finished lines go first, then the oldest unstarred ones,
    /// then the oldest. The line just added (`keeping`) always stays: a full list of starred
    /// lines doesn't swallow it.
    mutating func trim(keeping kept: String? = nil) {
        while items.count > Self.maxItems {
            let others = { (item: TodoItem) in item.id != kept }
            if let i = items.lastIndex(where: { others($0) && $0.isDone }) ?? items.lastIndex(where: { others($0) && !$0.starred })
                ?? items.lastIndex(where: others) {
                items.remove(at: i)
            } else {
                items.removeLast()
            }
        }
    }

    /// One line, without surrounding space, at most `maxLength` characters.
    static func oneLine(_ text: String) -> String {
        let joined = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return String(joined.prefix(maxLength))
    }

    // MARK: Storage

    public static func load(from url: URL) -> FileRead<TodoList> {
        JSONStore.read(TodoList.self, from: url, decoder: decoder)
    }

    /// Saved readable only by you; an empty list removes the file.
    public func save(to url: URL) throws {
        let fm = FileManager.default
        if items.isEmpty {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(self).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

/// Decodes a value or nothing, so one bad element doesn't lose the array around it.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Quick note

/// The quick note's text, kept in `note.txt` in Casement's support folder, readable only by you.
public struct QuickNoteFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: QuickNoteFile {
        QuickNoteFile(url: CasementPaths.supportDirectory.appendingPathComponent("note.txt"))
    }

    /// Long enough for any scratch note; past it, the end is cut.
    public static let maxLength = 100_000

    /// The saved note, or "" when there is none.
    public func read() -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return Self.clipped(String(decoding: data, as: UTF8.self))
    }

    /// Saves the note; an empty one removes the file.
    public func write(_ note: String) throws {
        let text = Self.clipped(note)
        let fm = FileManager.default
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func clipped(_ text: String) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) : text
    }

    /// "12 words" under the note.
    public static func summary(_ text: String) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return words == 1 ? "1 word" : "\(words) words"
    }
}
