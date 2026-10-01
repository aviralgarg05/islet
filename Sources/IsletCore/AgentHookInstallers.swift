import Foundation

/// A coding agent Islet can connect to from Settings → Coding agents.
public enum CodingAgent: String, CaseIterable, Sendable, Identifiable {
    case claudeCode, codex, cursor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    /// The folder the agent creates in the home folder the first time it runs.
    public func configDirectory(home: URL) -> URL {
        switch self {
        case .claudeCode: return home.appendingPathComponent(".claude", isDirectory: true)
        case .codex: return home.appendingPathComponent(".codex", isDirectory: true)
        case .cursor: return home.appendingPathComponent(".cursor", isDirectory: true)
        }
    }

    /// The files connecting changes, in the order they are written.
    public func files(home: URL) -> [URL] {
        let dir = configDirectory(home: home)
        switch self {
        case .claudeCode: return [dir.appendingPathComponent("settings.json")]
        case .codex: return [dir.appendingPathComponent("hooks.json"), dir.appendingPathComponent("config.toml")]
        case .cursor: return [dir.appendingPathComponent("hooks.json")]
        }
    }
}

/// Codex keeps hooks in `~/.codex/hooks.json`, in the same shape as Claude Code's settings.
public enum CodexHookInstaller {
    /// Status for each turn and tool, plus the blocking approval hook.
    public static func entries(wait: Int) -> [ClaudeHookInstaller.Entry] {
        [
            .init(event: "PermissionRequest", arguments: "hook codex --wait \(wait)", timeout: wait + 30),
            .init(event: "PostToolUse", arguments: "hook codex"),
            .init(event: "UserPromptSubmit", arguments: "hook codex"),
            .init(event: "Stop", arguments: "hook codex"),
        ]
    }

    public static func plan(existing: Data?, executable: String = "isletctl", wait: Int) throws -> ClaudeHookInstaller.Plan {
        try ClaudeHookInstaller.merge(existing: existing, entries: entries(wait: wait), agent: "codex", executable: executable)
    }
}

/// Cursor keeps hooks in `~/.cursor/hooks.json`: `version`, then `hooks` → event → a flat list
/// of commands. Pure and idempotent like `ClaudeHookInstaller`; the user's hooks are kept.
public enum CursorHookInstaller {
    /// Shell commands and MCP tool calls ask in the notch; the rest reports status.
    public static func entries(wait: Int) -> [ClaudeHookInstaller.Entry] {
        [
            .init(event: "beforeShellExecution", arguments: "hook cursor --wait \(wait)", timeout: wait + 30),
            .init(event: "beforeMCPExecution", arguments: "hook cursor --wait \(wait)", timeout: wait + 30),
            .init(event: "afterShellExecution", arguments: "hook cursor"),
            .init(event: "afterMCPExecution", arguments: "hook cursor"),
            .init(event: "stop", arguments: "hook cursor"),
        ]
    }

    public static func plan(existing: Data?, executable: String = "isletctl", wait: Int) throws -> ClaudeHookInstaller.Plan {
        typealias Failure = ClaudeHookInstaller.InstallError
        var root: [String: Any] = [:]
        if let existing, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let obj = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw Failure.notJSON }
            root = obj
        }
        guard var hooks = (root["hooks"] ?? [String: Any]()) as? [String: Any] else { throw Failure.unexpectedShape("hooks") }
        let exe = ClaudeHookInstaller.quoted(executable)
        var changes: [String] = []
        if root["version"] == nil {
            root["version"] = 1
        }
        for e in entries(wait: wait) {
            guard var list = (hooks[e.event] ?? [Any]()) as? [[String: Any]] else { throw Failure.unexpectedShape("hooks.\(e.event)") }
            let command = exe + " " + e.arguments
            let label = e.event + ": isletctl " + e.arguments
            let found = list.firstIndex { hook in
                guard let args = (hook["command"] as? String).flatMap(ClaudeHookInstaller.isletArguments),
                      args.starts(with: ["hook", "cursor"]) else { return false }
                return args.contains("--wait") == e.waits
            }
            if let i = found {
                let current = list[i]
                if e.waits, (current["command"] as? String).flatMap(ClaudeHookInstaller.isletWait) != ClaudeHookInstaller.isletWait(command)
                    || (current["timeout"] as? Int) != e.timeout {
                    list[i]["command"] = command
                    if let t = e.timeout { list[i]["timeout"] = t }
                    changes.append("Update " + label)
                }
            } else {
                var hook: [String: Any] = ["command": command]
                if let t = e.timeout { hook["timeout"] = t }
                list.append(hook)
                changes.append("Add " + label)
            }
            hooks[e.event] = list
        }
        root["hooks"] = hooks
        let merged = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return ClaudeHookInstaller.Plan(merged: merged + Data("\n".utf8), changes: changes)
    }
}

/// Turns on hooks in Codex's `config.toml` (`hooks = true` under `[features]`), changing only
/// that line. Codex runs no hooks until they are on, and asks once (`/hooks`) before trusting
/// new ones. Pure: text in, text out.
public enum CodexConfigEditor {
    public struct Edit: Equatable, Sendable {
        /// The whole file after the change.
        public var text: String
        public var changes: [String]

        public var isUpToDate: Bool { changes.isEmpty }
    }

    public enum EditError: Error, Equatable, CustomStringConvertible {
        /// `features` is set in a form Islet doesn't edit (an inline table, or `hooks` isn't true or false).
        case unexpectedShape(String)

        public var description: String {
            switch self {
            case .unexpectedShape(let key):
                return "“\(key)” in config.toml isn't in a form Islet changes, so it was left alone. Set hooks = true under [features] yourself."
            }
        }
    }

    static let change = "Turn on hooks in [features]"

    public static func enableHooks(in existing: String?) throws -> Edit {
        let text = existing ?? ""
        var lines = text.components(separatedBy: "\n")
        // A file ending in a newline splits into a last empty line; keep it out of the search.
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline { lines.removeLast() }

        func finish(_ lines: [String], changed: Bool) -> Edit {
            guard changed else { return Edit(text: text, changes: []) }
            return Edit(text: lines.joined(separator: "\n") + "\n", changes: [change])
        }

        let headers = lines.indices.filter { tableName(lines[$0]) != nil }
        if let header = headers.first(where: { tableName(lines[$0]) == "features" }) {
            let end = headers.first { $0 > header } ?? lines.count
            for i in (header + 1)..<end {
                guard let value = value(of: "hooks", in: lines[i]) else { continue }
                switch value {
                case "true": return finish(lines, changed: false)
                case "false":
                    lines[i] = indentation(of: lines[i]) + "hooks = true"
                    return finish(lines, changed: true)
                default: throw EditError.unexpectedShape("features.hooks")
                }
            }
            lines.insert("hooks = true", at: header + 1)
            return finish(lines, changed: true)
        }

        // Before the first table: `features.hooks = …` or `features = { … }`.
        let top = 0..<(headers.first ?? lines.count)
        for i in top {
            if let value = value(of: "features.hooks", in: lines[i]) {
                switch value {
                case "true": return finish(lines, changed: false)
                case "false":
                    lines[i] = indentation(of: lines[i]) + "features.hooks = true"
                    return finish(lines, changed: true)
                default: throw EditError.unexpectedShape("features.hooks")
                }
            }
            if value(of: "features", in: lines[i]) != nil { throw EditError.unexpectedShape("features") }
        }

        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines += ["[features]", "hooks = true"]
        return finish(lines, changed: true)
    }

    /// The name of a `[table]` header line, without spaces or a trailing comment. Array tables
    /// (`[[…]]`) count as headers too, so a search for `features` stops at them.
    static func tableName(_ line: String) -> String? {
        let s = stripComment(line).trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("["), s.hasSuffix("]") else { return nil }
        let inner = s.hasPrefix("[[") && s.hasSuffix("]]") ? s.dropFirst(2).dropLast(2) : s.dropFirst().dropLast()
        let name = inner.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ".")
        return s.hasPrefix("[[") ? "[[\(name)]]" : name
    }

    /// The value assigned to `key` on this line (comment removed), or nil if the line sets something else.
    static func value(of key: String, in line: String) -> String? {
        let s = stripComment(line)
        guard let eq = s.firstIndex(of: "=") else { return nil }
        let name = s[..<eq].split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ".")
        guard name == key else { return nil }
        return s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    }

    /// The line without a `#` comment. A `#` inside a quoted string isn't a comment.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        for (i, c) in zip(line.indices, line) {
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                return String(line[..<i])
            }
        }
        return line
    }

    static func indentation(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }
}

/// What connecting an agent would change, file by file.
public struct AgentHookPlan: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public var url: URL
        /// The file after the change.
        public var contents: Data
        /// One line per change, as shown before anything is written.
        public var changes: [String]

        public init(url: URL, contents: Data, changes: [String]) {
            self.url = url
            self.contents = contents
            self.changes = changes
        }
    }

    public var agent: CodingAgent
    public var files: [File]

    public var changes: [String] { files.flatMap(\.changes) }
    public var isUpToDate: Bool { changes.isEmpty }
    /// Only the files that change.
    public var changedFiles: [File] { files.filter { !$0.changes.isEmpty } }

    /// Plans connecting `agent`, reading its files with `read` (nil for a missing file).
    public static func make(_ agent: CodingAgent, home: URL, executable: String, wait: Int,
                            read: (URL) throws -> Data?) throws -> AgentHookPlan {
        let urls = agent.files(home: home)
        var files: [File] = []
        switch agent {
        case .claudeCode:
            let p = try ClaudeHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: p.merged, changes: p.changes))
        case .codex:
            let hooks = try CodexHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: hooks.merged, changes: hooks.changes))
            let config = try read(urls[1]).map { String(decoding: $0, as: UTF8.self) }
            let edit = try CodexConfigEditor.enableHooks(in: config)
            files.append(File(url: urls[1], contents: Data(edit.text.utf8), changes: edit.changes))
        case .cursor:
            let p = try CursorHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: p.merged, changes: p.changes))
        }
        return AgentHookPlan(agent: agent, files: files)
    }
}

/// How an agent's connection stands, in Settings' words.
public enum AgentConnection: Equatable, Sendable {
    /// Islet's hooks are in place.
    case connected
    /// Connected, but the approval wait changed since: connecting again updates it.
    case needsUpdate
    case notConnected
    /// The agent hasn't run on this Mac (no settings folder yet).
    case notFound
    /// Its files can't be read or changed; the sentence says why.
    case problem(String)

    public static func decide(_ agent: CodingAgent, installed: Bool, plan: Result<AgentHookPlan, Error>) -> AgentConnection {
        switch plan {
        case .failure(let error):
            if let e = error as? ClaudeHookInstaller.InstallError {
                return .problem(e.description(file: agent.files(home: URL(fileURLWithPath: "/"))[0].lastPathComponent))
            }
            if let e = error as? CodexConfigEditor.EditError { return .problem(e.description) }
            return .problem(error.localizedDescription)
        case .success(let p):
            if p.isUpToDate { return .connected }
            // Only the approval hooks' wait differs: everything else is there.
            if p.changes.allSatisfy({ $0.hasPrefix("Update ") }) { return .needsUpdate }
            return installed ? .notConnected : .notFound
        }
    }

    public var label: String {
        switch self {
        case .connected: return "Connected"
        case .needsUpdate: return "Needs an update"
        case .notConnected: return "Not connected"
        case .notFound: return "Not found on this Mac"
        case .problem: return "Can't connect"
        }
    }
}
