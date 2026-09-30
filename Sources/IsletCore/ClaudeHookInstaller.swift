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

        public var isUpToDate: Bool { changes.isEmpty }
    }

    public enum InstallError: Error, Equatable, CustomStringConvertible {
        case notJSON
        case unexpectedShape(String)

        public var description: String {
            switch self {
            case .notJSON: return "settings.json isn't valid JSON, so it was left alone."
            case .unexpectedShape(let key): return "“\(key)” in settings.json isn't in the expected shape, so it was left alone."
            }
        }
    }

    /// - Parameters:
    ///   - existing: the current file, or nil when there is none.
    ///   - executable: how hooks call `isletctl` (a name on `PATH` or a full path).
    ///   - wait: seconds the approval hooks wait for an answer in the notch.
    public static func plan(existing: Data?, executable: String = "isletctl", wait: Int) throws -> Plan {
        var root: [String: Any] = [:]
        if let existing, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let obj = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw InstallError.notJSON }
            root = obj
        }
        guard var hooks = (root["hooks"] ?? [String: Any]()) as? [String: Any] else { throw InstallError.unexpectedShape("hooks") }
        let exe = quoted(executable)
        var changes: [String] = []

        for e in entries(wait: wait) {
            guard var groups = (hooks[e.event] ?? [Any]()) as? [[String: Any]] else { throw InstallError.unexpectedShape("hooks.\(e.event)") }
            let command = exe + " " + e.arguments
            let label = e.event + (e.matcher.map { " (\($0))" } ?? "") + ": isletctl " + e.arguments
            if let (g, h) = find(e, in: groups) {
                var list = groups[g]["hooks"] as? [[String: Any]] ?? []
                let current = list[h]
                if e.waits, (current["command"] as? String).flatMap(isletWait) != wait || (current["timeout"] as? Int) != e.timeout {
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
        return Plan(merged: merged + Data("\n".utf8), changes: changes)
    }

    /// The group and hook index of Islet's hook for this entry, if the file already has it.
    static func find(_ e: Entry, in groups: [[String: Any]]) -> (Int, Int)? {
        for (g, group) in groups.enumerated() {
            let matcher = (group["matcher"] as? String).flatMap { $0.isEmpty || $0 == "*" ? nil : $0 }
            guard matcher == e.matcher else { continue }
            for (h, hook) in (group["hooks"] as? [[String: Any]] ?? []).enumerated() {
                guard let args = (hook["command"] as? String).flatMap(isletArguments), args.starts(with: ["hook", "claude"]) else { continue }
                if args.contains("--wait") == e.waits { return (g, h) }
            }
        }
        return nil
    }

    /// Arguments of an `isletctl` command line, or nil for any other command.
    static func isletArguments(_ command: String) -> [String]? {
        let s = command.trimmingCharacters(in: .whitespaces)
        var exe: String
        var rest: Substring
        if let q = s.first, q == "'" || q == "\"", let end = s.dropFirst().firstIndex(of: q) {
            exe = String(s[s.index(after: s.startIndex)..<end])
            rest = s[s.index(after: end)...]
        } else {
            let parts = s.split(separator: " ", maxSplits: 1)
            exe = parts.first.map(String.init) ?? ""
            rest = parts.count > 1 ? parts[1] : ""
        }
        guard (exe as NSString).lastPathComponent == "isletctl" else { return nil }
        return rest.split(separator: " ").map(String.init)
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
