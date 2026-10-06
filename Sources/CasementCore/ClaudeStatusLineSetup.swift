import Foundation

/// Adds `casementctl statusline` to Claude Code's `settings.json`. An existing status line is
/// wrapped (`casementctl statusline -- '<original>'`), never replaced, and installing twice
/// changes nothing. Edits touch only the `statusLine` value, so the rest of the file keeps
/// its key order and spacing byte for byte.
public enum ClaudeStatusLineSetup {
    public enum Status: Equatable, Sendable {
        /// No Casement status line. `current` is the user's own command, if any.
        case notInstalled(current: String?)
        /// Installed; `original` is the wrapped command, if there was one.
        case installed(original: String?)
        /// A `statusLine` Casement can't wrap (not a command).
        case unsupported(String)
    }

    public enum SetupError: Error, Equatable, CustomStringConvertible {
        case invalidJSON
        case unsupported(String)
        case changedOnDisk

        public var description: String {
            switch self {
            case .invalidJSON: return "Claude Code\u{2019}s settings file couldn\u{2019}t be read, so Casement left it alone."
            case .unsupported(let why): return why
            case .changedOnDisk: return "Claude Code\u{2019}s settings changed while Casement was looking. Try again."
            }
        }
    }

    /// A planned change: the `statusLine` command before and after, and the new file.
    public struct Edit: Equatable, Sendable {
        public var before: String?
        public var after: String?
        /// File contents the edit was planned from (nil when there was no file).
        public var original: Data?
        public var settings: Data

        public var changesFile: Bool { original != settings }
    }

    // MARK: Commands

    /// `<cli> statusline`, or `<cli> statusline -- '<original>'` to wrap an existing command.
    public static func command(cli: String, wrapping original: String? = nil) -> String {
        let base = "\(shellQuote(cli)) statusline"
        guard let original, !original.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return "\(base) -- \(shellQuote(original))"
    }

    /// Whether `command` runs `casementctl statusline`, and the command it wraps.
    public static func parseInstalled(_ command: String) -> (installed: Bool, original: String?) {
        guard let words = shellWords(command) else { return (false, nil) }
        for i in words.indices.dropLast() where (words[i] as NSString).lastPathComponent == "casementctl" && words[i + 1] == "statusline" {
            let rest = Array(words.dropFirst(i + 2))
            guard rest.first == "--", rest.count > 1 else { return (true, nil) }
            let args = Array(rest.dropFirst())
            return (true, args.count == 1 ? args[0] : args.map(shellQuote).joined(separator: " "))
        }
        return (false, nil)
    }

    // MARK: Planning

    public static func status(of settings: Data?) -> Status {
        guard let doc = try? Document(settings) else { return .unsupported(SetupError.invalidJSON.description) }
        switch doc.statusLine() {
        case .absent: return .notInstalled(current: nil)
        case .unsupported(let why): return .unsupported(why)
        case .command(let cmd, _):
            let parsed = parseInstalled(cmd)
            return parsed.installed ? .installed(original: parsed.original) : .notInstalled(current: cmd)
        }
    }

    /// Plan installing the status line. Returns an edit that leaves the file unchanged when
    /// it is already installed.
    public static func install(into settings: Data?, cli: String) throws -> Edit {
        let doc = try Document(settings)
        switch doc.statusLine() {
        case .unsupported(let why):
            throw SetupError.unsupported(why)
        case .absent(let replacing):
            let after = command(cli: cli)
            let out = doc.addingStatusLine(command: after, replacing: replacing)
            return try verified(Edit(before: nil, after: after, original: settings, settings: out))
        case .command(let cmd, let range):
            let parsed = parseInstalled(cmd)
            if parsed.installed {
                return Edit(before: cmd, after: cmd, original: settings, settings: settings ?? Data())
            }
            let after = command(cli: cli, wrapping: cmd)
            let out = doc.replacing(range, with: jsonString(after))
            return try verified(Edit(before: cmd, after: after, original: settings, settings: out))
        }
    }

    /// Plan removing Casement: restore the wrapped command, or drop the status line Casement added.
    public static func remove(from settings: Data?) throws -> Edit {
        let doc = try Document(settings)
        guard case .command(let cmd, let range) = doc.statusLine(), parseInstalled(cmd).installed else {
            return Edit(before: nil, after: nil, original: settings, settings: settings ?? Data())
        }
        if let original = parseInstalled(cmd).original {
            let out = doc.replacing(range, with: jsonString(original))
            return try verified(Edit(before: cmd, after: original, original: settings, settings: out))
        }
        let out = doc.removingStatusLine()
        return try verified(Edit(before: cmd, after: nil, original: settings, settings: out))
    }

    /// Write an edit: keeps the previous file as `settings.json.bak`, follows a symlinked
    /// settings file to its target, and refuses if the file changed since the edit was planned.
    public static func apply(_ edit: Edit, to url: URL) throws {
        guard edit.changesFile else { return }
        let target = url.resolvingSymlinksInPath()
        let fm = FileManager.default
        let current = try? Data(contentsOf: target)
        guard current == edit.original else { throw SetupError.changedOnDisk }
        var permissions: NSNumber?
        if current != nil {
            permissions = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber
            let backup = target.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: target, to: backup)
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try edit.settings.write(to: target, options: .atomic)
        if let permissions { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
    }

    /// The new file must be valid JSON whose status line is exactly `edit.after`.
    private static func verified(_ edit: Edit) throws -> Edit {
        let result = try Document(edit.settings).statusLine()
        switch (result, edit.after) {
        case (.absent, nil): return edit
        case (.command(let cmd, _), let after?) where cmd == after: return edit
        default: throw SetupError.invalidJSON
        }
    }

    // MARK: Shell words

    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Split a command line the way `sh` would for plain words and quotes (no expansion).
    /// Nil when a quote is left open.
    static func shellWords(_ s: String) -> [String]? {
        var words: [String] = []
        var word = ""
        var inWord = false
        var it = s.makeIterator()
        while let c = it.next() {
            switch c {
            case " ", "\t", "\n":
                if inWord { words.append(word); word = ""; inWord = false }
            case "'":
                inWord = true
                var closed = false
                while let q = it.next() {
                    if q == "'" { closed = true; break }
                    word.append(q)
                }
                if !closed { return nil }
            case "\"":
                inWord = true
                var closed = false
                while let q = it.next() {
                    if q == "\"" { closed = true; break }
                    if q == "\\", let n = it.next() {
                        if !"\"\\$`".contains(n) { word.append(q) }
                        word.append(n)
                    } else {
                        word.append(q)
                    }
                }
                if !closed { return nil }
            case "\\":
                inWord = true
                if let n = it.next(), n != "\n" { word.append(n) }
            default:
                inWord = true
                word.append(c)
            }
        }
        if inWord { words.append(word) }
        return words
    }

    static func jsonString(_ s: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8)
    }
}

// MARK: - Minimal JSON scanner

/// Just enough JSON scanning to find byte ranges in a settings file, so an edit can replace
/// one value and leave everything else as the user wrote it.
private struct Document {
    struct Member {
        var key: String
        var keyStart: Int
        var valueStart: Int
        var valueEnd: Int
    }

    enum StatusLine {
        /// No usable `statusLine`; `replacing` is the member to overwrite (`"statusLine": null`).
        case absent(replacing: Member?)
        case command(String, range: Range<Int>)
        case unsupported(String)
    }

    let bytes: [UInt8]
    let open: Int
    let close: Int
    let members: [Member]

    init(_ data: Data?) throws {
        let data = data ?? Data()
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) {
            bytes = Array("{}\n".utf8)
        } else {
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                throw ClaudeStatusLineSetup.SetupError.invalidJSON
            }
            bytes = Array(data)
        }
        let walker = Walker(bytes: bytes)
        let start = walker.skipSpace(0)
        guard start < bytes.count, bytes[start] == UInt8(ascii: "{") else { throw ClaudeStatusLineSetup.SetupError.invalidJSON }
        let object = try walker.object(at: start)
        open = start
        close = object.close
        members = object.members
    }

    func statusLine() -> StatusLine {
        guard let m = members.last(where: { $0.key == "statusLine" }) else { return .absent(replacing: nil) }
        let first = bytes[m.valueStart]
        if first == UInt8(ascii: "n") { return .absent(replacing: m) }
        guard first == UInt8(ascii: "{"), let inner = try? Walker(bytes: bytes).object(at: m.valueStart) else {
            return .unsupported("Claude Code\u{2019}s status line is set up in a way Casement doesn\u{2019}t change, so Casement left it alone.")
        }
        if let type = inner.members.last(where: { $0.key == "type" }), string(type) != "command" {
            return .unsupported("Claude Code\u{2019}s status line isn\u{2019}t a command Casement can run beside its own, so Casement left it alone.")
        }
        guard let cmd = inner.members.last(where: { $0.key == "command" }), let text = string(cmd) else {
            return .unsupported("Claude Code\u{2019}s status line has nothing set to run, so Casement left it alone.")
        }
        return .command(text, range: cmd.valueStart..<cmd.valueEnd)
    }

    func string(_ m: Member) -> String? {
        guard bytes[m.valueStart] == UInt8(ascii: "\"") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(bytes[m.valueStart..<m.valueEnd]), options: .fragmentsAllowed)) as? String
    }

    func replacing(_ range: Range<Int>, with replacement: Data) -> Data {
        var out = bytes
        out.replaceSubrange(range, with: Array(replacement))
        return Data(out)
    }

    /// Indentation of the first member, or nil when the object is on one line.
    private var indent: String? {
        guard let first = members.first else { return "  " }
        let lead = bytes[(open + 1)..<first.keyStart]
        guard let nl = lead.lastIndex(of: 0x0A) else { return nil }
        return String(decoding: bytes[(nl + 1)..<first.keyStart], as: UTF8.self)
    }

    func addingStatusLine(command: String, replacing: Member?) -> Data {
        let cmd = String(decoding: ClaudeStatusLineSetup.jsonString(command), as: UTF8.self)
        let indent = self.indent
        let value: String
        if let indent {
            let inner = indent + (indent.isEmpty ? "  " : indent)
            value = "{\n\(inner)\"type\": \"command\",\n\(inner)\"command\": \(cmd)\n\(indent)}"
        } else {
            value = "{\"type\": \"command\", \"command\": \(cmd)}"
        }
        if let replacing {
            return self.replacing(replacing.valueStart..<replacing.valueEnd, with: Data(value.utf8))
        }
        let member = "\"statusLine\": \(value)"
        guard let last = members.last else {
            return self.replacing(open..<(close + 1), with: Data("{\n\(indent ?? "  ")\(member)\n}".utf8))
        }
        let separator = indent.map { ",\n\($0)" } ?? ", "
        return self.replacing(last.valueEnd..<last.valueEnd, with: Data((separator + member).utf8))
    }

    func removingStatusLine() -> Data {
        guard let k = members.lastIndex(where: { $0.key == "statusLine" }) else { return Data(bytes) }
        if members.count == 1 { return replacing(open..<(close + 1), with: Data("{}".utf8)) }
        if k < members.count - 1 { return replacing(members[k].keyStart..<members[k + 1].keyStart, with: Data()) }
        return replacing(members[k - 1].valueEnd..<members[k].valueEnd, with: Data())
    }

    struct Walker {
        let bytes: [UInt8]

        func skipSpace(_ i: Int) -> Int {
            var i = i
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
            return i
        }

        func expect(_ c: Character, at i: Int) throws {
            guard i < bytes.count, bytes[i] == UInt8(ascii: c.unicodeScalars.first!) else {
                throw ClaudeStatusLineSetup.SetupError.invalidJSON
            }
        }

        /// Index just past the string starting at `i`.
        func stringEnd(_ i: Int) throws -> Int {
            try expect("\"", at: i)
            var j = i + 1
            while j < bytes.count {
                if bytes[j] == UInt8(ascii: "\\") { j += 2; continue }
                if bytes[j] == UInt8(ascii: "\"") { return j + 1 }
                j += 1
            }
            throw ClaudeStatusLineSetup.SetupError.invalidJSON
        }

        /// Index just past the value starting at `i`.
        func valueEnd(_ i: Int) throws -> Int {
            guard i < bytes.count else { throw ClaudeStatusLineSetup.SetupError.invalidJSON }
            switch bytes[i] {
            case UInt8(ascii: "\""): return try stringEnd(i)
            case UInt8(ascii: "{"): return try object(at: i).close + 1
            case UInt8(ascii: "["):
                var j = skipSpace(i + 1)
                if j < bytes.count, bytes[j] == UInt8(ascii: "]") { return j + 1 }
                while true {
                    j = skipSpace(try valueEnd(j))
                    guard j < bytes.count else { throw ClaudeStatusLineSetup.SetupError.invalidJSON }
                    if bytes[j] == UInt8(ascii: "]") { return j + 1 }
                    try expect(",", at: j)
                    j = skipSpace(j + 1)
                }
            default:
                var j = i
                while j < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]")].contains(bytes[j]) { j += 1 }
                guard j > i else { throw ClaudeStatusLineSetup.SetupError.invalidJSON }
                return j
            }
        }

        func object(at i: Int) throws -> (members: [Member], close: Int) {
            try expect("{", at: i)
            var members: [Member] = []
            var j = skipSpace(i + 1)
            if j < bytes.count, bytes[j] == UInt8(ascii: "}") { return ([], j) }
            while true {
                let keyEnd = try stringEnd(j)
                let key = (try? JSONSerialization.jsonObject(with: Data(bytes[j..<keyEnd]), options: .fragmentsAllowed)) as? String ?? ""
                var k = skipSpace(keyEnd)
                try expect(":", at: k)
                k = skipSpace(k + 1)
                let end = try valueEnd(k)
                members.append(Member(key: key, keyStart: j, valueStart: k, valueEnd: end))
                j = skipSpace(end)
                guard j < bytes.count else { throw ClaudeStatusLineSetup.SetupError.invalidJSON }
                if bytes[j] == UInt8(ascii: "}") { return (members, j) }
                try expect(",", at: j)
                j = skipSpace(j + 1)
            }
        }
    }
}
