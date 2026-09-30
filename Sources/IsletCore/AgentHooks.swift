import Foundation

/// Maps coding-agent hook payloads to live activities, so you can see from the notch
/// when an agent is working, when it is blocked waiting for you, and when it is done.
///
/// Supported inputs:
/// - Claude Code hooks (JSON on stdin with `hook_event_name`, `session_id`, `cwd`, …)
/// - Codex CLI `notify` program payloads (`{"type": "agent-turn-complete", …}`)
/// - A generic shape any agent can send: `{"agent": "...", "event": "start|tool|waiting|done|error|end", ...}`
public enum AgentHooks {
    public enum Result: Equatable, Sendable {
        case upsert(ActivitySpec)
        case remove(id: String)
        case ignore
    }

    /// Decode a raw payload for `provider` ("claude", "codex", or anything else for the generic shape).
    public static func map(provider: String, payload: Data, now: Date = Date()) throws -> Result {
        let json = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        guard let obj = json as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "hook payload must be a JSON object"))
        }
        switch provider.lowercased() {
        case "claude", "claude-code", "claudecode": return mapClaude(obj)
        case "codex": return mapCodex(obj)
        default: return mapGeneric(obj, provider: provider)
        }
    }

    static func shortID(_ s: String?) -> String {
        let cleaned = (s ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var short = String(cleaned.prefix(12)).lowercased()
        while short.hasSuffix("-") { short.removeLast() }
        return short.isEmpty ? "default" : short
    }

    static func project(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func truncate(_ s: String, _ n: Int = 60) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.count > n ? String(oneLine.prefix(n - 1)) + "…" : oneLine
    }

    /// Hide values that look like credentials before a command is shown in the notch, where
    /// screen recordings and the API can see it: `API_KEY=…`, `--token …`, `Bearer …`, and
    /// well-known key prefixes.
    public static func redactSecrets(_ command: String) -> String {
        var s = command
        let patterns = [
            #"(?i)\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PASS|AUTH)[A-Z0-9_]*=)("[^"]*"|'[^']*'|\S+)"#,
            #"(?i)(--?(?:api-?key|token|password|secret|auth)[= ])("[^"]*"|'[^']*'|\S+)"#,
            #"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}"#,
            #"\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|xox[abprs]-[A-Za-z0-9-]{8,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,})"#,
        ]
        for (i, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let template: String
            switch i {
            case 0, 1: template = "$1•••"
            case 2: template = "$1 •••"
            default: template = "•••"
            }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }

    /// Describe a tool call in a few words ("Editing App.swift", "Running swift test").
    static func describeTool(_ name: String, input: [String: Any]?) -> String {
        let input = input ?? [:]
        func file(_ key: String) -> String? {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        switch name {
        case "Bash":
            if let cmd = input["command"] as? String { return "Running " + truncate(redactSecrets(cmd), 44) }
            return "Running a command"
        case "Edit", "MultiEdit", "NotebookEdit": return "Editing " + (file("file_path") ?? file("notebook_path") ?? "a file")
        case "Write": return "Writing " + (file("file_path") ?? "a file")
        case "Read": return "Reading " + (file("file_path") ?? "a file")
        case "Grep", "Glob": return "Searching" + ((input["pattern"] as? String).map { " for " + truncate($0, 30) } ?? "")
        case "WebFetch", "WebSearch": return "Browsing the web"
        case "Task", "Agent": return "Running a subagent"
        case "TodoWrite": return "Updating the plan"
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "_", omittingEmptySubsequences: true)
                return "Using " + (parts.dropFirst().first.map(String.init) ?? "a tool")
            }
            return "Using \(name)"
        }
    }

    static func mapClaude(_ o: [String: Any]) -> Result {
        let event = o["hook_event_name"] as? String ?? ""
        let sid = shortID(o["session_id"] as? String)
        let id = "claude-\(sid)"
        let proj = project(o["cwd"] as? String)
        let title = proj.map { "Claude · \($0)" } ?? "Claude Code"
        var spec = ActivitySpec(id: id, source: "claude-code", title: title, icon: .symbol("sparkle"), tint: "#D97757")

        switch event {
        case "SessionStart":
            spec.state = .info
            spec.subtitle = "Session started"
            spec.priority = .low
            spec.sneak = false
            spec.ttl = 0
        case "UserPromptSubmit":
            spec.state = .running
            spec.subtitle = "Thinking…"
            spec.progress = -1
            spec.priority = .normal
            spec.sneak = false
            spec.ttl = 0
        case "PreToolUse":
            spec.state = .running
            spec.progress = -1
            spec.subtitle = describeTool(o["tool_name"] as? String ?? "tool", input: o["tool_input"] as? [String: Any])
            spec.priority = .normal
            spec.sneak = false
            spec.ttl = 0
        case "PostToolUse":
            return .ignore
        case "PermissionRequest":
            // The approval card (or, later, the Notification event) gets attention; this only marks the wait.
            spec.state = .waiting
            spec.subtitle = "Needs approval: " + describeTool(o["tool_name"] as? String ?? "tool", input: o["tool_input"] as? [String: Any])
            spec.progress = 0
            spec.trailing = "Waiting"
            spec.priority = .high
            spec.sneak = false
            spec.ttl = 0
        case "PreCompact":
            spec.state = .running
            spec.subtitle = "Compacting context…"
            spec.sneak = false
        case "Notification":
            spec.state = .waiting
            spec.subtitle = truncate(o["message"] as? String ?? "Needs your attention", 70)
            spec.progress = 0
            spec.trailing = "Waiting"
            spec.priority = .high
            spec.sneak = true
            spec.ttl = 0
        case "Stop":
            spec.state = .success
            spec.subtitle = "Done — your turn"
            spec.progress = 1
            spec.trailing = "Done"
            spec.priority = .normal
            spec.sneak = true
            spec.ttl = 30
        case "SubagentStop":
            return .ignore
        case "SessionEnd":
            return .remove(id: id)
        default:
            return .ignore
        }
        if spec.state != .waiting && spec.state != .success { spec.trailing = "" }
        return .upsert(spec)
    }

    static func mapCodex(_ o: [String: Any]) -> Result {
        let type = o["type"] as? String ?? ""
        guard type == "agent-turn-complete" else { return .ignore }
        let turn = shortID((o["thread-id"] as? String) ?? (o["turn-id"] as? String))
        let proj = project(o["cwd"] as? String)
        var spec = ActivitySpec(
            id: "codex-\(turn)", source: "codex",
            title: proj.map { "Codex · \($0)" } ?? "Codex",
            icon: .symbol("terminal.fill"), trailing: "Done", progress: 1,
            state: .success, tint: "#10A37F", priority: .normal, ttl: 30, sneak: true
        )
        if let msg = o["last-assistant-message"] as? String, !msg.isEmpty {
            spec.subtitle = truncate(msg, 70)
        } else {
            spec.subtitle = "Turn complete"
        }
        return .upsert(spec)
    }

    static func mapGeneric(_ o: [String: Any], provider: String) -> Result {
        let agent = (o["agent"] as? String) ?? provider
        let session = shortID(o["session"] as? String ?? o["session_id"] as? String)
        let slug = String(agent.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
        let id = "\(slug.isEmpty ? "agent" : slug)-\(session)"
        let event = (o["event"] as? String ?? "").lowercased()
        let message = (o["message"] as? String).map { truncate($0, 70) }
        var spec = ActivitySpec(id: id, source: agent, title: (o["title"] as? String) ?? agent, subtitle: message, icon: .symbol("cpu"))
        switch event {
        case "start", "running", "tool", "thinking":
            spec.state = .running; spec.progress = -1; spec.sneak = false; spec.ttl = 0; spec.trailing = ""
        case "waiting", "input", "permission", "blocked":
            spec.state = .waiting; spec.priority = .high; spec.sneak = true; spec.ttl = 0; spec.trailing = "Waiting"
        case "done", "complete", "success", "stop":
            spec.state = .success; spec.progress = 1; spec.sneak = true; spec.ttl = 30; spec.trailing = "Done"
        case "error", "failed", "failure":
            spec.state = .failure; spec.priority = .high; spec.sneak = true; spec.ttl = 0; spec.trailing = "Error"
        case "end", "exit":
            return .remove(id: id)
        default:
            return .ignore
        }
        return .upsert(spec)
    }
}
