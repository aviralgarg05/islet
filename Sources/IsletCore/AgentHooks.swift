import Foundation

/// Maps coding-agent hook payloads to live activities, so you can see from the notch
/// when an agent is working, when it is blocked waiting for you, and when it is done.
///
/// Supported inputs:
/// - Claude Code hooks (JSON on stdin with `hook_event_name`, `session_id`, `cwd`, …)
/// - Codex hooks (the same shape) and its `notify` program payloads (`{"type": "agent-turn-complete", …}`)
/// - Cursor hooks (`hook_event_name`, `conversation_id`, `workspace_roots`, …)
/// - A generic shape any agent can send: `{"agent": "...", "event": "start|tool|waiting|done|error|end", ...}`
public enum AgentHooks {
    /// Fields of a hook payload Islet never reads, left out before it is sent: a tool's whole
    /// output (`tool_response`) can be larger than the API takes, and would only travel to be
    /// thrown away.
    public static let unreadFields: Set<String> = ["tool_response"]

    /// The payload without `unreadFields`. Anything that isn't a JSON object goes as it is.
    public static func trimmed(_ payload: Data) -> Data {
        guard var obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              !unreadFields.isDisjoint(with: obj.keys) else { return payload }
        for key in unreadFields { obj[key] = nil }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? payload
    }

    public enum Result: Equatable, Sendable {
        case upsert(ActivitySpec)
        case remove(id: String)
        case ignore
    }

    /// How long a working agent may go without an event before it's shown as out of date.
    public static let staleAfter: TimeInterval = 15 * 60

    /// Decode a raw payload for `provider` ("claude", "codex", or anything else for the generic shape).
    public static func map(provider: String, payload: Data, now: Date = Date()) throws -> Result {
        let json = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        guard let obj = json as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "hook payload must be a JSON object"))
        }
        let result: Result
        switch provider.lowercased() {
        case "claude", "claude-code", "claudecode": result = mapClaude(obj)
        case "codex": result = mapCodex(obj)
        case "cursor": result = mapCursor(obj)
        default: result = mapGeneric(obj, provider: provider)
        }
        // An agent that stops reporting (its terminal was closed mid-turn) dims after a while
        // instead of spinning forever; any later event brings it back.
        guard case .upsert(var spec) = result else { return result }
        spec.staleAt = spec.state == .running ? now.addingTimeInterval(staleAfter) : .distantFuture
        return .upsert(spec)
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
            // Only a question waits for you. Claude Code's reminder a minute after a turn ends
            // at the prompt isn't one: Stop already said "Your turn", and turning the reminder
            // into Waiting brought a finished session back to the notch with a peek.
            guard claudeNotificationNeedsYou(o) else { return .ignore }
            spec.state = .waiting
            spec.subtitle = truncate(o["message"] as? String ?? "Needs your attention", 70)
            spec.progress = 0
            spec.trailing = "Waiting"
            spec.priority = .high
            spec.sneak = true
            spec.ttl = 0
        case "Stop":
            spec.state = .success
            spec.subtitle = "Done. Your turn."
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

    /// Whether a Claude Code `Notification` asks for something: a permission prompt or an MCP
    /// server's question does; the idle reminder (`idle_prompt`) and a sign-in note
    /// (`auth_success`) don't. Older versions send no `notification_type`, so their idle
    /// reminder is known by its words. A kind Claude Code adds later counts as asking.
    static func claudeNotificationNeedsYou(_ o: [String: Any]) -> Bool {
        switch o["notification_type"] as? String {
        case "idle_prompt", "auth_success": return false
        case .some: return true
        case nil:
            let message = (o["message"] as? String ?? "").lowercased()
            return !message.contains("waiting for your input")
        }
    }

    /// Codex's hooks (`~/.codex/hooks.json`, what Connect writes) are shaped like Claude Code's
    /// and keyed by `session_id`; its older `notify` program sends `agent-turn-complete`.
    static func mapCodex(_ o: [String: Any]) -> Result {
        if let event = o["hook_event_name"] as? String { return mapCodexHook(o, event: event) }
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
            // The agent's own words can quote a key it just used; they show in the island.
            spec.subtitle = truncate(redactSecrets(msg), 70)
        } else {
            spec.subtitle = "Turn complete"
        }
        return .upsert(spec)
    }

    static func mapCodexHook(_ o: [String: Any], event: String) -> Result {
        let id = "codex-" + shortID(o["session_id"] as? String)
        let proj = project(o["cwd"] as? String)
        var spec = ActivitySpec(id: id, source: "codex", title: proj.map { "Codex · \($0)" } ?? "Codex",
                                icon: .symbol("terminal.fill"), tint: "#10A37F")
        let tool = o["tool_name"] as? String ?? "tool"
        switch event {
        case "SessionStart":
            spec.state = .info; spec.subtitle = "Session started"; spec.priority = .low; spec.sneak = false; spec.ttl = 0
        case "UserPromptSubmit":
            spec.state = .running; spec.subtitle = "Thinking…"; spec.progress = -1
            spec.priority = .normal; spec.sneak = false; spec.ttl = 0; spec.trailing = ""
        case "PreToolUse", "PostToolUse":
            // After a tool the turn goes on, so it still reads as working on that step.
            spec.state = .running; spec.subtitle = describeCodexTool(tool, input: o["tool_input"]); spec.progress = -1
            spec.priority = .normal; spec.sneak = false; spec.ttl = 0; spec.trailing = ""
        case "PermissionRequest":
            // The approval card gets attention; this only marks the wait.
            spec.state = .waiting; spec.subtitle = "Needs approval: " + describeCodexTool(tool, input: o["tool_input"])
            spec.progress = 0; spec.trailing = "Waiting"; spec.priority = .high; spec.sneak = false; spec.ttl = 0
        case "Stop":
            let last = (o["last_assistant_message"] as? String).map { truncate(redactSecrets($0), 70) }
            spec.state = .success; spec.subtitle = (last?.isEmpty == false ? last : nil) ?? "Done. Your turn."
            spec.progress = 1; spec.trailing = "Done"; spec.priority = .normal; spec.sneak = true; spec.ttl = 30
        case "SessionEnd":
            return .remove(id: id)
        default:
            return .ignore
        }
        return .upsert(spec)
    }

    /// A Codex tool call in a few words. Its shell tool takes the command as a list
    /// (`["bash", "-lc", "git status"]`), and `apply_patch` names the files in the patch.
    static func describeCodexTool(_ name: String, input: Any?) -> String {
        let object = input as? [String: Any] ?? [:]
        switch name {
        case "shell", "local_shell", "exec_command", "container.exec", "Bash":
            guard let command = commandLine(object["command"] ?? object["cmd"] ?? input) else { return "Running a command" }
            return "Running " + truncate(redactSecrets(command), 44)
        case "apply_patch":
            let patch = object["input"] as? String ?? object["patch"] as? String ?? input as? String ?? ""
            if let r = patch.range(of: #"\*\*\* (?:Add|Update|Delete) File: \S+"#, options: .regularExpression) {
                let path = String(patch[r]).components(separatedBy: "File: ").last ?? ""
                return "Editing " + URL(fileURLWithPath: path).lastPathComponent
            }
            return "Editing files"
        case "update_plan": return "Updating the plan"
        case "web_search": return "Browsing the web"
        case "view_image": return "Looking at an image"
        default: return describeTool(name, input: object)
        }
    }

    /// A command given as a string or as a list of arguments, as one line. A shell's
    /// `-c` or `-lc` wrapper is dropped, so `["bash", "-lc", "make"]` reads "make".
    static func commandLine(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        guard let args = value as? [String], !args.isEmpty else { return nil }
        let shells: Set<String> = ["bash", "sh", "zsh", "/bin/bash", "/bin/sh", "/bin/zsh"]
        if args.count >= 3, shells.contains(args[0]), args[1] == "-c" || args[1] == "-lc" { return args[2] }
        return args.joined(separator: " ")
    }

    /// Cursor's hooks (`~/.cursor/hooks.json`), keyed by `conversation_id`. A payload with no
    /// `hook_event_name` is the generic shape, as before.
    static func mapCursor(_ o: [String: Any]) -> Result {
        guard let event = o["hook_event_name"] as? String else { return mapGeneric(o, provider: "cursor") }
        let id = "cursor-" + shortID(o["conversation_id"] as? String)
        let proj = project((o["workspace_roots"] as? [String])?.first ?? o["cwd"] as? String)
        var spec = ActivitySpec(id: id, source: "cursor", title: proj.map { "Cursor · \($0)" } ?? "Cursor",
                                icon: .symbol("cursorarrow"), tint: "#C8C8C8")
        func working(_ subtitle: String) {
            spec.state = .running; spec.subtitle = subtitle; spec.progress = -1
            spec.priority = .normal; spec.sneak = false; spec.ttl = 0; spec.trailing = ""
        }
        switch event {
        case "beforeSubmitPrompt":
            working("Thinking…")
        case "beforeShellExecution", "afterShellExecution":
            working((o["command"] as? String).map { "Running " + truncate(redactSecrets($0), 44) } ?? "Running a command")
        case "beforeMCPExecution", "afterMCPExecution":
            working((o["tool_name"] as? String).map { "Using " + truncate($0, 40) } ?? "Using a tool")
        case "afterFileEdit":
            working((o["file_path"] as? String).map { "Editing " + URL(fileURLWithPath: $0).lastPathComponent } ?? "Editing a file")
        case "stop":
            switch (o["status"] as? String ?? "completed").lowercased() {
            case "error":
                spec.state = .failure; spec.subtitle = "Stopped with an error"; spec.progress = 1
                spec.trailing = "Error"; spec.priority = .high; spec.sneak = true; spec.ttl = 0
            case "aborted":
                // You stopped it yourself: nothing to point out.
                spec.state = .success; spec.subtitle = "Stopped"; spec.progress = 1
                spec.trailing = "Stopped"; spec.priority = .low; spec.sneak = false; spec.ttl = 10
            default:
                spec.state = .success; spec.subtitle = "Done. Your turn."; spec.progress = 1
                spec.trailing = "Done"; spec.priority = .normal; spec.sneak = true; spec.ttl = 30
            }
        default:
            return .ignore
        }
        return .upsert(spec)
    }

    static func mapGeneric(_ o: [String: Any], provider: String) -> Result {
        let agent = (o["agent"] as? String) ?? provider
        let session = shortID(o["session"] as? String ?? o["session_id"] as? String)
        let slug = String(agent.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
        var id = "\(slug.isEmpty ? "agent" : slug)-\(session)"
        // An agent called "live" would get a mirrored Live Activity's id, which the API refuses.
        if MenuBarLiveActivities.isMirrored(id: id) { id = "agent-" + id }
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
