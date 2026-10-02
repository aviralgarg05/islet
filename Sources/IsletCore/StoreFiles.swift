import Foundation

/// What reading one of Islet's JSON files found.
public enum FileRead<Value> {
    case loaded(Value)
    /// No file, or one with nothing in it: there is nothing to lose by writing a new one.
    case missing
    /// The file is there but doesn't parse. It must not be overwritten.
    case unreadable(FileProblem)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    public var problem: FileProblem? {
        if case .unreadable(let p) = self { return p }
        return nil
    }
}

extension FileRead: Equatable where Value: Equatable {}
extension FileRead: Sendable where Value: Sendable {}

/// Why a JSON file couldn't be read: the line of the first error when the parser says, and
/// its own words (for logs; Settings shows the line only).
public struct FileProblem: Error, Equatable, Sendable {
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    /// The parser's error for `data`, with the line it happened on.
    public static func json(_ error: Error, in data: Data) -> FileProblem {
        let ns = error as NSError
        let text = [ns.userInfo[NSDebugDescriptionErrorKey] as? String, ns.localizedDescription]
            .compactMap { $0 }.joined(separator: " ")
        return FileProblem(line: line(described: text) ?? line(at: ns.userInfo["NSJSONSerializationErrorIndex"] as? Int, in: data),
                           message: ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? ns.localizedDescription)
    }

    /// Foundation's own words: "… around line 3, column 7."
    static func line(described text: String) -> Int? {
        guard let r = text.range(of: #"line \d+"#, options: .regularExpression) else { return nil }
        return Int(text[r].dropFirst("line ".count))
    }

    /// The line holding byte `index` of `data`.
    static func line(at index: Int?, in data: Data) -> Int? {
        guard let index, index >= 0 else { return nil }
        return data.prefix(index).reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    }

    /// One plain sentence for Settings.
    public func sentence(file: String) -> String {
        if let line { return "\(file) has an error on line \(line)." }
        return "\(file) has an error."
    }
}

/// Reading the JSON files Islet keeps for itself (the shelf, timers).
public enum JSONStore {
    public static func read<Value: Decodable>(_ type: Value.Type, from url: URL, decoder: JSONDecoder = JSONDecoder()) -> FileRead<Value> {
        guard let data = try? Data(contentsOf: url) else {
            if FileManager.default.fileExists(atPath: url.path) {
                return .unreadable(FileProblem(line: nil, message: "The file can't be opened."))
            }
            return .missing
        }
        do {
            return .loaded(try decoder.decode(type, from: data))
        } catch {
            return .unreadable(FileProblem.json(error, in: data))
        }
    }

    /// What a store that saves itself starts from: what was saved, or nothing. A file that
    /// doesn't parse is moved to `<name>.corrupt` first, so the next save can't destroy it;
    /// when it can't be moved, `canSave` is false and the store must leave the file alone.
    public struct Start<Value> {
        public var value: Value?
        public var canSave: Bool
        /// Where a file that didn't parse went.
        public var setAside: URL?
        public var problem: FileProblem?
    }

    public static func start<Value>(_ url: URL, read: (URL) -> FileRead<Value>) -> Start<Value> {
        switch read(url) {
        case .loaded(let v): return Start(value: v, canSave: true)
        case .missing: return Start(value: nil, canSave: true)
        case .unreadable(let p):
            let moved = BrokenFile.setAside(url)
            return Start(value: nil, canSave: moved != nil, setAside: moved, problem: p)
        }
    }
}

/// Moving or copying a file that can't be read out of the way before anything replaces it.
public enum BrokenFile {
    /// `<name>.<suffix>`, or `<name>.<suffix>-2` and on when that is taken, so an earlier copy
    /// is kept too. Past nine copies the oldest name is reused.
    public static func destination(for url: URL, suffix: String, exists: (URL) -> Bool) -> URL {
        let first = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "." + suffix)
        guard exists(first) else { return first }
        for n in 2...9 {
            let next = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".\(suffix)-\(n)")
            if !exists(next) { return next }
        }
        return first
    }

    /// Moves the file aside (nothing is lost; the store then starts empty). Returns where it went.
    @discardableResult
    public static func setAside(_ url: URL, suffix: String = "corrupt") -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let target = destination(for: url, suffix: suffix) { fm.fileExists(atPath: $0.path) }
        try? fm.removeItem(at: target)
        do {
            try fm.moveItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// Copies the file aside, leaving it where it is. Returns where the copy went.
    @discardableResult
    public static func copyAside(_ url: URL, suffix: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let target = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "." + suffix)
        try? fm.removeItem(at: target)
        return (try? fm.copyItem(at: url, to: target)) != nil ? target : nil
    }
}

/// Any JSON value, read and written with `JSONDecoder` and `JSONEncoder` so numbers come back
/// as they were written. Used to keep the keys of `config.json` this build doesn't know.
enum RawJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([RawJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: RawJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// `config.json` kept safe. A file that doesn't parse is never overwritten: Islet keeps the
/// last good settings, and `save` refuses until the file parses again or the user replaces it
/// (`replace(with:)`, which keeps a copy as `config.json.broken`). Keys this build doesn't
/// know, written by a newer Islet or by hand, survive a save.
///
/// With `lastGood`, a copy of the file is kept each time it parses or is saved, so a file that
/// is already broken when Islet starts still gives the last good settings (`open()`).
public struct SettingsFile: Sendable {
    public let url: URL
    /// Where the copy of the last file that parsed is kept: outside the config folder, so a
    /// dotfiles repo never sees it. Nil keeps no copy.
    public let lastGood: URL?
    /// Set while the file on disk doesn't parse.
    public private(set) var problem: FileProblem?
    /// What `lastGood` holds, once known, so an unchanged file isn't copied again.
    private var lastGoodData: Data?
    /// The bytes the settings in memory were last in step with: written, found already there when
    /// saving, or read. The echo of a save, or a second event for an edit already read, can then be
    /// told from a new edit (`holdsOwnWrite`). Nil while the file is missing or doesn't parse.
    private var lastWritten: Data?

    public init(url: URL, lastGood: URL? = nil) {
        self.url = url
        self.lastGood = lastGood
    }

    /// Where the settings Islet starts with came from (`open()`).
    public enum Origin: Equatable, Sendable {
        /// config.json, or the defaults when there is no file yet (nothing to lose by writing one).
        case file
        /// config.json doesn't parse: the copy kept the last time it did.
        case lastGood
        /// config.json doesn't parse and there is no copy: the defaults, until it is fixed.
        case defaults
    }

    /// The settings to start with: the file's; or, when it doesn't parse, the last good copy's;
    /// or the defaults. The file itself is left as it is either way.
    public mutating func open() -> (settings: IsletSettings, origin: Origin) {
        switch read() {
        case .loaded(let s): return (s, .file)
        case .missing: return (IsletSettings(), .file)
        case .unreadable:
            guard let lastGood, let data = try? Data(contentsOf: lastGood),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return (IsletSettings(), .defaults) }
            lastGoodData = data
            return (IsletSettings.decodeLenient(data), .lastGood)
        }
    }

    /// Copies `data`, which parsed, to `lastGood`. Best effort: a copy that can't be written
    /// only means a broken file at the next launch starts from an older copy, or the defaults.
    private mutating func keepLastGood(_ data: Data) {
        guard let lastGood else { return }
        if lastGoodData == nil { lastGoodData = try? Data(contentsOf: lastGood) }
        guard data != lastGoodData else { return }
        do {
            try FileManager.default.createDirectory(at: lastGood.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: lastGood, options: .atomic)
            lastGoodData = data
        } catch {}
    }

    public enum SaveOutcome: Equatable, Sendable {
        case saved
        /// The file already said exactly this.
        case unchanged
        /// The file doesn't parse, so nothing was written (`problem` says why).
        case refused
    }

    /// The copy `replace(with:)` keeps of a file that didn't parse.
    public var brokenCopy: URL { url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".broken") }

    /// Reads the file. `.unreadable` also records the problem, so saving refuses; anything
    /// else clears it.
    public mutating func read() -> FileRead<IsletSettings> {
        switch Self.parse(url) {
        case .missing:
            problem = nil
            lastWritten = nil
            return .missing
        case .unreadable(let p):
            problem = p
            lastWritten = nil
            return .unreadable(p)
        case .loaded(let (data, _)):
            problem = nil
            lastWritten = data
            keepLastGood(data)
            return .loaded(IsletSettings.decodeLenient(data))
        }
    }

    /// Writes `settings`, keeping the keys on disk this build doesn't know. Old keys that
    /// were folded into newer ones (`IsletSettings.retiredKeys`) are dropped, as they always were.
    @discardableResult
    public mutating func save(_ settings: IsletSettings) throws -> SaveOutcome {
        var kept: [String: RawJSON] = [:]
        var before: Data?
        switch Self.parse(url) {
        case .unreadable(let p):
            problem = p
            lastWritten = nil
            return .refused
        case .missing:
            break
        case .loaded(let (data, object)):
            before = data
            let known = IsletSettings.knownKeys.union(IsletSettings.retiredKeys)
            kept = object.filter { !known.contains($0.key) }
        }
        problem = nil
        let data = try Self.encode(settings, keeping: kept)
        if data == before {
            lastWritten = data
            keepLastGood(data)
            return .unchanged
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastWritten = data
        keepLastGood(data)
        return .saved
    }

    /// Whether the file holds exactly the bytes the settings in memory were last in step with
    /// (written or read): the file watcher seeing its own save, or a second event for an edit
    /// already read. Settings in memory may already be newer than that (a slider still moving, a
    /// change waiting for its save), so reading it again would undo them. A file put back to
    /// those bytes after another edit, or after a typo, no longer matches and is read.
    public func holdsOwnWrite() -> Bool {
        guard let lastWritten, let data = try? Data(contentsOf: url) else { return false }
        return data == lastWritten
    }

    /// The user chose to replace a file that doesn't parse: a copy goes to `config.json.broken`
    /// and `settings` are written in its place. A file that parses is saved as usual.
    public mutating func replace(with settings: IsletSettings) throws {
        if case .unreadable = Self.parse(url) {
            guard BrokenFile.copyAside(url, suffix: "broken") != nil else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: brokenCopy.path])
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encode(settings, keeping: [:])
            try data.write(to: url, options: .atomic)
            lastWritten = data
            keepLastGood(data)
            problem = nil
            return
        }
        try save(settings)
    }

    /// The file's bytes and top-level object, or why there are none.
    static func parse(_ url: URL) -> FileRead<(Data, [String: RawJSON])> {
        guard let data = try? Data(contentsOf: url) else {
            // There but unreadable (permissions): don't write over it either.
            if FileManager.default.fileExists(atPath: url.path) {
                return .unreadable(FileProblem(line: nil, message: "The file can't be opened."))
            }
            return .missing
        }
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missing }
        do {
            guard try JSONSerialization.jsonObject(with: data) is [String: Any] else {
                return .unreadable(FileProblem(line: 1, message: "The settings must be a JSON object, in { }."))
            }
            return .loaded((data, try JSONDecoder().decode([String: RawJSON].self, from: data)))
        } catch {
            return .unreadable(FileProblem.json(error, in: data))
        }
    }

    static func encode(_ settings: IsletSettings, keeping kept: [String: RawJSON]) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard !kept.isEmpty else { return try e.encode(settings) }
        var object = try JSONDecoder().decode([String: RawJSON].self, from: JSONEncoder().encode(settings))
        object.merge(kept) { ours, _ in ours }
        return try e.encode(object)
    }
}
