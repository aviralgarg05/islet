import Foundation

/// Merges Islet's hooks into Claude Code's `settings.json`. Pure: takes the file's bytes and
/// returns the new bytes plus a list of changes to show before writing.
///
/// Idempotent. The user's own hooks and every other setting are kept. An Islet hook that is
/// already there is left alone, except that Islet's approval hooks follow the wait setting.
public enum ClaudeHookInstaller {
    public struct Entry: Equatable, Sendable {
        public var event: String
        public var matcher: String?
        /// Arguments after the `isletctl` executable.
        public var arguments: String
        /// Seconds before Claude Code gives up on the hook; nil keeps Claude's default.
        public var timeout: Int?

        public init(event: String, matcher: String? = nil, arguments: String, timeout: Int? = nil) {
            self.event = event
            self.matcher = matcher
            self.arguments = arguments
            self.timeout = timeout
        }

        var waits: Bool { arguments.contains("--wait") }
    }

    /// Status hooks for every event Islet shows, plus the two blocking approval hooks.
    public static func entries(wait: Int) -> [Entry] {
        let status = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "PreCompact", "Stop", "SessionEnd"]
        return status.map { Entry(event: $0, matcher: nil, arguments: "hook claude", timeout: nil) } + [
            Entry(event: "PermissionRequest", matcher: nil, arguments: "hook claude --wait \(wait)", timeout: wait + 30),
            Entry(event: "PreToolUse", matcher: "AskUserQuestion|ExitPlanMode", arguments: "hook claude --wait \(wait)", timeout: wait + 30),
        ]
    }

    public struct Plan: Equatable, Sendable {
        /// The whole settings file after the merge.
        public var merged: Data
        /// One line per hook added or updated ("Add PermissionRequest: isletctl hook claude --wait 300").
        public var changes: [String]
        /// The file already had at least one of Islet's hooks for this agent: it was connected,
        /// so any change brings it up to date rather than connecting it.
        public var wasConnected: Bool

        public var isUpToDate: Bool { changes.isEmpty }

        public init(merged: Data, changes: [String], wasConnected: Bool = false) {
            self.merged = merged
            self.changes = changes
            self.wasConnected = wasConnected
        }
    }

    public enum InstallError: Error, Equatable, CustomStringConvertible {
        case notJSON
        case unexpectedShape(String)

        public var description: String { description(file: "settings.json") }

        /// The same sentence about another agent's file ("hooks.json").
        public func description(file: String) -> String {
            switch self {
            case .notJSON: return "\(file) isn't valid JSON, so it was left alone."
            case .unexpectedShape(let key): return "“\(key)” in \(file) isn't in the expected shape, so it was left alone."
            }
        }
    }

    /// - Parameters:
    ///   - existing: the current file, or nil when there is none.
    ///   - executable: how hooks call `isletctl` (a name on `PATH` or a full path).
    ///   - wait: seconds the approval hooks wait for an answer in the notch.
    public static func plan(existing: Data?, executable: String = "isletctl", wait: Int) throws -> Plan {
        try merge(existing: existing, entries: entries(wait: wait), agent: "claude", executable: executable)
    }

    /// Takes Islet's hooks out of `settings.json`, and nothing else.
    public static func removal(existing: Data?) throws -> Plan {
        try removal(existing: existing, agent: "claude")
    }

    /// Merges `entries` into a file shaped like Claude Code's settings (`hooks` → event →
    /// groups of hooks), a shape Codex's `hooks.json` shares.
    /// - Parameter agent: the name in `isletctl hook <agent>`, which tells Islet's own hooks
    ///   from the user's.
    static func merge(existing: Data?, entries: [Entry], agent: String, executable: String) throws -> Plan {
        var root: [String: Any] = [:]
        if let existing, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let obj = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw InstallError.notJSON }
            root = obj
        }
        guard var hooks = (root["hooks"] ?? [String: Any]()) as? [String: Any] else { throw InstallError.unexpectedShape("hooks") }
        let exe = quoted(executable)
        var changes: [String] = []
        var found = false

        for e in entries {
            guard var groups = (hooks[e.event] ?? [Any]()) as? [[String: Any]] else { throw InstallError.unexpectedShape("hooks.\(e.event)") }
            let command = exe + " " + e.arguments
            let label = e.event + (e.matcher.map { " (\($0))" } ?? "") + ": isletctl " + e.arguments
            if let (g, h) = find(e, agent: agent, in: groups) {
                found = true
                var list = groups[g]["hooks"] as? [[String: Any]] ?? []
                if needsUpdate(list[h], to: command, entry: e, executable: executable) {
                    list[h]["command"] = command
                    if let t = e.timeout { list[h]["timeout"] = t }
                    groups[g]["hooks"] = list
                    changes.append("Update " + label)
                }
            } else {
                var hook: [String: Any] = ["type": "command", "command": command]
                if let t = e.timeout { hook["timeout"] = t }
                var group: [String: Any] = ["hooks": [hook]]
                if let m = e.matcher { group["matcher"] = m }
                groups.append(group)
                changes.append("Add " + label)
            }
            hooks[e.event] = groups
        }
        root["hooks"] = hooks
        let merged = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return Plan(merged: merged + Data("\n".utf8), changes: changes, wasConnected: found)
    }

    /// Whether Islet's existing hook needs rewriting: it calls an `isletctl` at another path
    /// (Islet.app moved, or was updated in a new place), or an approval hook's wait changed.
    /// A hook that calls `isletctl` by name, from PATH as the examples in `integrations/` do, is
    /// the user's choice and isn't moved anywhere; nor is anything compared when this build
    /// has no path of its own to offer (a development build).
    static func needsUpdate(_ hook: [String: Any], to command: String, entry e: Entry, executable: String) -> Bool {
        let current = hook["command"] as? String
        if let exe = current.flatMap(isletExecutable), exe.contains("/"), executable.contains("/"), exe != executable { return true }
        guard e.waits else { return false }
        return current.flatMap(isletWait) != isletWait(command) || (hook["timeout"] as? Int) != e.timeout
    }

    /// Takes Islet's hooks for `agent` out of a file shaped like Claude Code's settings, and
    /// nothing else: every other hook, group and setting stays. A group left with no hooks,
    /// and an event left with no groups, go too.
    static func removal(existing: Data?, agent: String) throws -> Plan {
        guard let existing, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Plan(merged: existing ?? Data(), changes: [])
        }
        guard var root = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw InstallError.notJSON }
        guard let hooks = root["hooks"] as? [String: Any] else {
            if root["hooks"] == nil { return Plan(merged: existing, changes: []) }
            throw InstallError.unexpectedShape("hooks")
        }
        var kept: [String: Any] = [:]
        var changes: [String] = []
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                kept[event] = value
                continue
            }
            var left: [[String: Any]] = []
            for var group in groups {
                guard let list = group["hooks"] as? [[String: Any]] else {
                    left.append(group)
                    continue
                }
                let others = list.filter { hook in
                    guard let args = (hook["command"] as? String).flatMap(isletArguments), args.starts(with: ["hook", agent]) else { return true }
                    changes.append("Remove " + event + ((group["matcher"] as? String).map { " (\($0))" } ?? "") + ": isletctl " + args.joined(separator: " "))
                    return false
                }
                guard others.count != list.count else {
                    left.append(group)
                    continue
                }
                if !others.isEmpty {
                    group["hooks"] = others
                    left.append(group)
                }
            }
            if !left.isEmpty { kept[event] = left }
        }
        guard !changes.isEmpty else { return Plan(merged: existing, changes: []) }
        root["hooks"] = kept
        let merged = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return Plan(merged: merged + Data("\n".utf8), changes: changes.sorted(), wasConnected: true)
    }

    /// The `isletctl` a command runs (as written, without quotes), or nil for any other command.
    static func isletExecutable(_ command: String) -> String? {
        guard let parts = split(command), (parts.exe as NSString).lastPathComponent == "isletctl" else { return nil }
        return parts.exe
    }

    /// Islet's hook commands for `agent` that call an `isletctl` that isn't there any more
    /// (Islet.app moved or was deleted). Names on `PATH` (no slash) aren't checked.
    public static func missingExecutables(in commands: [String], agent: String, exists: (String) -> Bool) -> [String] {
        commands.compactMap { command in
            guard let args = isletArguments(command), args.starts(with: ["hook", agent]),
                  let exe = isletExecutable(command), exe.contains("/"), !exists(exe) else { return nil }
            return exe
        }
    }

    /// Every hook command in a file shaped like Claude Code's or Cursor's settings.
    public static func commands(in data: Data?) -> [String] {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return [] }
        var out: [String] = []
        for case let groups as [[String: Any]] in hooks.values {
            for group in groups {
                if let c = group["command"] as? String { out.append(c) }
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    if let c = hook["command"] as? String { out.append(c) }
                }
            }
        }
        return out
    }

    /// The group and hook index of Islet's hook for this entry, if the file already has it.
    static func find(_ e: Entry, agent: String, in groups: [[String: Any]]) -> (Int, Int)? {
        for (g, group) in groups.enumerated() {
            let matcher = (group["matcher"] as? String).flatMap { $0.isEmpty || $0 == "*" ? nil : $0 }
            guard matcher == e.matcher else { continue }
            for (h, hook) in (group["hooks"] as? [[String: Any]] ?? []).enumerated() {
                guard let args = (hook["command"] as? String).flatMap(isletArguments), args.starts(with: ["hook", agent]) else { continue }
                if args.contains("--wait") == e.waits { return (g, h) }
            }
        }
        return nil
    }

    /// Arguments of an `isletctl` command line, or nil for any other command.
    static func isletArguments(_ command: String) -> [String]? {
        guard let parts = split(command), (parts.exe as NSString).lastPathComponent == "isletctl" else { return nil }
        return parts.rest.split(separator: " ").map(String.init)
    }

    /// A command line's executable (without its quotes) and the rest.
    private static func split(_ command: String) -> (exe: String, rest: Substring)? {
        let s = command.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let q = s.first, q == "'" || q == "\"", let end = s.dropFirst().firstIndex(of: q) {
            return (String(s[s.index(after: s.startIndex)..<end]), s[s.index(after: end)...])
        }
        let parts = s.split(separator: " ", maxSplits: 1)
        return (parts.first.map(String.init) ?? "", parts.count > 1 ? parts[1] : "")
    }

    static func isletWait(_ command: String) -> Int? {
        guard let args = isletArguments(command), let i = args.firstIndex(of: "--wait"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    /// Quotes a path for the shell Claude Code runs hooks with.
    static func quoted(_ path: String) -> String {
        path.contains(where: { " '\"\\$`!&;|()<>*?".contains($0) }) ? "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'" : path
    }
}
