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

    /// Takes Islet's hooks out of `hooks.json`, and nothing else.
    public static func removal(existing: Data?) throws -> ClaudeHookInstaller.Plan {
        try ClaudeHookInstaller.removal(existing: existing, agent: "codex")
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
        var wasConnected = false
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
                wasConnected = true
                if ClaudeHookInstaller.needsUpdate(list[i], to: command, entry: e, executable: executable) {
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
        return ClaudeHookInstaller.Plan(merged: merged + Data("\n".utf8), changes: changes, wasConnected: wasConnected)
    }

    /// Takes Islet's hooks out of `hooks.json`, and nothing else. An event left with no hooks goes too.
    public static func removal(existing: Data?) throws -> ClaudeHookInstaller.Plan {
        typealias Failure = ClaudeHookInstaller.InstallError
        guard let existing, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ClaudeHookInstaller.Plan(merged: existing ?? Data(), changes: [])
        }
        guard var root = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw Failure.notJSON }
        guard let hooks = root["hooks"] as? [String: Any] else {
            if root["hooks"] == nil { return ClaudeHookInstaller.Plan(merged: existing, changes: []) }
            throw Failure.unexpectedShape("hooks")
        }
        var kept: [String: Any] = [:]
        var changes: [String] = []
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else {
                kept[event] = value
                continue
            }
            let others = list.filter { hook in
                guard let args = (hook["command"] as? String).flatMap(ClaudeHookInstaller.isletArguments),
                      args.starts(with: ["hook", "cursor"]) else { return true }
                changes.append("Remove " + event + ": isletctl " + args.joined(separator: " "))
                return false
            }
            if !others.isEmpty || list.isEmpty { kept[event] = others }
        }
        guard !changes.isEmpty else { return ClaudeHookInstaller.Plan(merged: existing, changes: []) }
        root["hooks"] = kept
        let merged = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return ClaudeHookInstaller.Plan(merged: merged + Data("\n".utf8), changes: changes.sorted(), wasConnected: true)
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

/// What connecting (or disconnecting) an agent would change, file by file.
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

    public enum Kind: Equatable, Sendable { case connect, disconnect }

    public var agent: CodingAgent
    public var files: [File]
    public var kind: Kind = .connect
    /// Islet's hooks were already there, so connecting again brings them up to date.
    public var wasConnected = false

    public init(agent: CodingAgent, files: [File], kind: Kind = .connect, wasConnected: Bool = false) {
        self.agent = agent
        self.files = files
        self.kind = kind
        self.wasConnected = wasConnected
    }

    public var changes: [String] { files.flatMap(\.changes) }
    public var isUpToDate: Bool { changes.isEmpty }
    /// Only the files that change.
    public var changedFiles: [File] { files.filter { !$0.changes.isEmpty } }

    /// Plans connecting `agent`, reading its files with `read` (nil for a missing file).
    public static func make(_ agent: CodingAgent, home: URL, executable: String, wait: Int,
                            read: (URL) throws -> Data?) throws -> AgentHookPlan {
        let urls = agent.files(home: home)
        var files: [File] = []
        let hooks: ClaudeHookInstaller.Plan
        switch agent {
        case .claudeCode:
            hooks = try ClaudeHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: hooks.merged, changes: hooks.changes))
        case .codex:
            hooks = try CodexHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: hooks.merged, changes: hooks.changes))
            let config = try read(urls[1]).map { String(decoding: $0, as: UTF8.self) }
            let edit = try CodexConfigEditor.enableHooks(in: config)
            files.append(File(url: urls[1], contents: Data(edit.text.utf8), changes: edit.changes))
        case .cursor:
            hooks = try CursorHookInstaller.plan(existing: read(urls[0]), executable: executable, wait: wait)
            files.append(File(url: urls[0], contents: hooks.merged, changes: hooks.changes))
        }
        return AgentHookPlan(agent: agent, files: files, wasConnected: hooks.wasConnected)
    }

    /// Plans disconnecting `agent`: Islet's hooks come out of its hooks file and nothing else
    /// changes. Codex's `hooks = true` stays, since other hooks may need it.
    public static func disconnect(_ agent: CodingAgent, home: URL, read: (URL) throws -> Data?) throws -> AgentHookPlan {
        let url = agent.files(home: home)[0]
        let existing = try read(url)
        let p: ClaudeHookInstaller.Plan
        switch agent {
        case .claudeCode: p = try ClaudeHookInstaller.removal(existing: existing)
        case .codex: p = try CodexHookInstaller.removal(existing: existing)
        case .cursor: p = try CursorHookInstaller.removal(existing: existing)
        }
        return AgentHookPlan(agent: agent, files: [File(url: url, contents: p.merged, changes: p.changes)], kind: .disconnect,
                             wasConnected: p.wasConnected)
    }

    /// The `isletctl` paths in `agent`'s hooks that no longer exist (Islet.app moved or was
    /// deleted), from its hooks file. A read that fails counts as no hooks.
    public static func missingExecutables(_ agent: CodingAgent, home: URL, read: (URL) throws -> Data?,
                                          exists: (String) -> Bool) -> [String] {
        let data: Data? = (try? read(agent.files(home: home)[0])) ?? nil
        let commands = ClaudeHookInstaller.commands(in: data)
        return Array(Set(ClaudeHookInstaller.missingExecutables(in: commands, agent: agent.hookName, exists: exists))).sorted()
    }
}

extension CodingAgent {
    /// The name in `isletctl hook <name>`.
    public var hookName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .cursor: return "cursor"
        }
    }
}

/// How an agent's connection stands, in Settings' words.
public enum AgentConnection: Equatable, Sendable {
    /// Islet's hooks are in place.
    case connected
    /// Connected, but out of date: Islet.app moved, the approval wait changed, or a hook is
    /// missing. Connecting again updates it.
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
            // Some of Islet's hooks are there: it was connected, and is out of date.
            if p.wasConnected { return .needsUpdate }
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
