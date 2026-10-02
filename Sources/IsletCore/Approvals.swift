import Foundation

/// Coding-agent approvals answered from the notch.
///
/// A blocking hook (`isletctl hook <agent> --wait N`) posts the agent's own payload to
/// `POST /v1/hooks/{agent}?wait=N`. If it asks for a decision (a tool permission, a question,
/// a plan), the app shows a card and the request is held until the user answers. The answer
/// goes back as the exact JSON the hook must print; "no decision" prints nothing, so the
/// agent falls back to its own prompt in the terminal.
///
/// Supported hooks:
/// - Claude Code `PermissionRequest`, and `PreToolUse` for `AskUserQuestion` and `ExitPlanMode`
/// - Codex CLI `PermissionRequest` (same output shape as Claude)
/// - Cursor `beforeShellExecution` and `beforeMCPExecution`
public enum AgentProvider: String, Equatable, Sendable, CaseIterable {
    case claude, codex, cursor

    /// The `{provider}` segment of the hook endpoint.
    public init?(hookProvider name: String) {
        switch name.lowercased() {
        case "claude", "claude-code", "claudecode": self = .claude
        case "codex": self = .codex
        case "cursor": self = .cursor
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    public var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "terminal.fill"
        case .cursor: return "cursorarrow.rays"
        }
    }

    public var tint: String {
        switch self {
        case .claude: return "#D97757"
        case .codex: return "#10A37F"
        case .cursor: return "#A1A1AA"
        }
    }
}

/// A question from Claude's `AskUserQuestion` tool.
public struct AgentQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        public var detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    public var question: String
    /// Short chip text ("Auth method").
    public var header: String?
    public var options: [Option]
    public var multiSelect: Bool

    public init(question: String, header: String? = nil, options: [Option], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// Where the agent runs, from the hook's environment, so the card can bring that terminal back.
/// Keys are the environment variable names (`TERM_PROGRAM`, `TMUX_PANE`, …) plus `tty`.
public struct TerminalContext: Equatable, Sendable {
    public static let environmentKeys = [
        "TERM_PROGRAM", "__CFBundleIdentifier", "TERM_SESSION_ID", "ITERM_SESSION_ID",
        "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "WEZTERM_PANE", "ZELLIJ_PANE_ID",
    ]

    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values.filter { !$0.value.isEmpty }
    }

    /// Picks the known keys out of an environment; `tty` is the parent process's terminal.
    public static func from(environment env: [String: String], tty: String?) -> TerminalContext {
        var v: [String: String] = [:]
        for key in environmentKeys { v[key] = env[key] }
        if let tty = tty?.trimmingCharacters(in: .whitespacesAndNewlines), !tty.isEmpty, !tty.hasPrefix("?") { v["tty"] = tty }
        return TerminalContext(values: v)
    }

    public var isEmpty: Bool { values.isEmpty }

    /// Bundle identifier of the app hosting the terminal.
    public var hostBundleID: String? {
        if let id = values["__CFBundleIdentifier"], !id.isEmpty { return id }
        switch values["TERM_PROGRAM"] {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WezTerm": return "com.github.wez.wezterm"
        case "vscode": return "com.microsoft.VSCode"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "Hyper": return "co.zeit.hyper"
        case "zed": return "dev.zed.Zed"
        default: return values["KITTY_WINDOW_ID"] != nil ? "net.kovidgoyal.kitty" : nil
        }
    }

    /// tmux pane (`%3`) and the server socket from `$TMUX` (`/tmp/tmux-501/default,123,0`).
    public var tmux: (socket: String, pane: String)? {
        guard let pane = values["TMUX_PANE"], pane.range(of: #"^%[0-9]+$"#, options: .regularExpression) != nil,
              let socket = values["TMUX"]?.split(separator: ",").first.map(String.init),
              socket.hasPrefix("/"), !socket.contains("\n") else { return nil }
        return (socket, pane)
    }

    public var weztermPane: String? {
        guard let p = values["WEZTERM_PANE"], p.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return p
    }
}

/// A request for a decision, parsed from an agent's hook payload.
/// A file named on an approval card: "RiskRules.swift" in "Sources/IsletCore".
public struct ApprovalFile: Equatable, Sendable {
    public var name: String
    /// Where it is: inside the project, relative to it; elsewhere, the full folder with ~ for
    /// home. Nil for a file at the project's top.
    public var folder: String?

    public init(name: String, folder: String?) {
        self.name = name
        self.folder = folder
    }

    /// Nil for an empty path or one that ends in a slash.
    public init?(path: String, cwd: String?, home: String = NSHomeDirectory()) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasSuffix("/") else { return nil }
        let cut = trimmed.lastIndex(of: "/")
        name = cut.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed
        let parent = cut.map { $0 == trimmed.startIndex ? "/" : String(trimmed[..<$0]) }
        guard let parent else { folder = nil; return }
        let project = cwd.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }
        if let project, !project.isEmpty, parent == project {
            folder = nil
        } else if let project, !project.isEmpty, parent.hasPrefix(project == "/" ? "/" : project + "/") {
            folder = String(parent.dropFirst(project == "/" ? 1 : project.count + 1))
        } else if !home.isEmpty, parent == home || parent.hasPrefix(home + "/") {
            folder = "~" + parent.dropFirst(home.count)
        } else {
            folder = parent
        }
    }
}

public struct ApprovalRequest: Equatable, Sendable {
    /// The hook that asked; it decides the shape of the answer.
    public enum Hook: String, Equatable, Sendable {
        case permissionRequest = "PermissionRequest"
        case preToolUse = "PreToolUse"
        case beforeShellExecution
        case beforeMCPExecution
    }

    public enum Kind: Equatable, Sendable {
        /// Run a command, edit a file, use an MCP tool…
        case tool
        /// `AskUserQuestion`: answered by picking options.
        case questions([AgentQuestion])
        /// `ExitPlanMode`: the plan as Markdown.
        case plan(String)
    }

    public var provider: AgentProvider
    public var hook: Hook
    public var sessionID: String
    public var cwd: String?
    public var toolName: String
    public var toolInput: JSONValue
    public var kind: Kind
    /// Claude's `permission_suggestions`, echoed back for "Always (this session)".
    public var suggestions: [JSONValue]
    /// Subagent type when a subagent asks ("Explore").
    public var agentType: String?
    public var terminal: TerminalContext

    public init(provider: AgentProvider, hook: Hook, sessionID: String, cwd: String? = nil, toolName: String,
                toolInput: JSONValue = .object([:]), kind: Kind = .tool, suggestions: [JSONValue] = [],
                agentType: String? = nil, terminal: TerminalContext = TerminalContext()) {
        self.provider = provider; self.hook = hook; self.sessionID = sessionID; self.cwd = cwd
        self.toolName = toolName; self.toolInput = toolInput; self.kind = kind; self.suggestions = suggestions
        self.agentType = agentType; self.terminal = terminal
    }

    // MARK: Parsing

    /// The request in a hook payload, or nil when the event doesn't ask for a decision.
    public static func parse(provider: String, payload: Data) -> ApprovalRequest? {
        guard let p = AgentProvider(hookProvider: provider), let obj = JSONValue.parse(payload)?.objectValue else { return nil }
        return parse(provider: p, object: obj)
    }

    public static func parse(provider: AgentProvider, object o: [String: JSONValue]) -> ApprovalRequest? {
        let event = o["hook_event_name"]?.stringValue ?? ""
        let terminal = TerminalContext(values: (o["_terminal"]?.objectValue ?? [:]).compactMapValues(\.stringValue))
        switch provider {
        case .claude, .codex:
            guard let tool = o["tool_name"]?.stringValue, !tool.isEmpty else { return nil }
            let hook: Hook
            switch event {
            case "PermissionRequest": hook = .permissionRequest
            case "PreToolUse" where provider == .claude && isInteractiveTool(tool): hook = .preToolUse
            default: return nil
            }
            let input = o["tool_input"] ?? .object([:])
            var kind = Kind.tool
            if provider == .claude, isInteractiveTool(tool) {
                // Answered by picking options or approving a plan; anything else is left to the terminal.
                if tool == "AskUserQuestion", let qs = questions(in: input) {
                    kind = .questions(qs)
                } else if tool == "ExitPlanMode", let plan = input["plan"]?.stringValue, !plan.isEmpty {
                    kind = .plan(plan)
                } else {
                    return nil
                }
            }
            return ApprovalRequest(
                provider: provider, hook: hook, sessionID: o["session_id"]?.stringValue ?? "",
                cwd: o["cwd"]?.stringValue, toolName: tool, toolInput: input, kind: kind,
                suggestions: o["permission_suggestions"]?.arrayValue ?? [],
                agentType: o["agent_type"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }, terminal: terminal
            )
        case .cursor:
            let cwd = o["cwd"]?.stringValue ?? o["workspace_roots"]?.arrayValue?.first?.stringValue
            let session = o["conversation_id"]?.stringValue ?? ""
            switch event {
            case "beforeShellExecution":
                guard let command = o["command"]?.stringValue, !command.isEmpty else { return nil }
                return ApprovalRequest(provider: .cursor, hook: .beforeShellExecution, sessionID: session, cwd: cwd,
                                       toolName: "Shell", toolInput: .object(["command": .string(command)]), terminal: terminal)
            case "beforeMCPExecution":
                var input = o["tool_input"] ?? .object([:])
                // Cursor sends the tool input as a JSON string.
                if let s = input.stringValue, let parsed = JSONValue.parse(Data(s.utf8)) { input = parsed }
                return ApprovalRequest(provider: .cursor, hook: .beforeMCPExecution, sessionID: session, cwd: cwd,
                                       toolName: o["tool_name"]?.stringValue ?? "MCP tool", toolInput: input, terminal: terminal)
            default:
                return nil
            }
        }
    }

    static func isInteractiveTool(_ name: String) -> Bool { name == "AskUserQuestion" || name == "ExitPlanMode" }

    static func questions(in input: JSONValue) -> [AgentQuestion]? {
        guard let list = input["questions"]?.arrayValue, !list.isEmpty else { return nil }
        let parsed = list.compactMap { q -> AgentQuestion? in
            guard let text = q["question"]?.stringValue, !text.isEmpty else { return nil }
            let options = (q["options"]?.arrayValue ?? []).compactMap { opt -> AgentQuestion.Option? in
                if let label = opt["label"]?.stringValue, !label.isEmpty { return .init(label: label, detail: opt["description"]?.stringValue) }
                if let label = opt.stringValue, !label.isEmpty { return .init(label: label) }
                return nil
            }
            guard !options.isEmpty else { return nil }
            return AgentQuestion(question: text, header: q["header"]?.stringValue, options: options,
                                 multiSelect: q["multiSelect"]?.boolValue ?? false)
        }
        // A question the notch can't answer (free text only) goes to the terminal as a whole.
        return parsed.count == list.count ? parsed : nil
    }

    // MARK: Display

    public var project: String? { AgentHooks.project(cwd) }

    /// "Claude · islet"
    public var title: String { project.map { "\(provider.displayName) · \($0)" } ?? provider.displayName }

    /// What the agent wants to do, in a few words.
    public var action: String {
        switch kind {
        case .questions(let qs): return qs.count == 1 ? "Question" : "\(qs.count) questions"
        case .plan: return "Plan ready for review"
        case .tool: break
        }
        switch toolName {
        case "Bash", "Shell", "shell", "local_shell", "exec_command": return "Run a command"
        case "Edit", "MultiEdit": return "Edit a file"
        case "Write": return "Write a file"
        case "Read": return "Read a file"
        case "NotebookEdit": return "Edit a notebook"
        case "WebFetch": return "Fetch a web page"
        case "WebSearch": return "Search the web"
        case "Glob", "Grep": return "Search files"
        case "Task", "Agent": return "Start a subagent"
        case "apply_patch": return "Apply a patch"
        case "TodoWrite", "update_plan": return "Update the plan"
        case "Skill": return "Use a skill"
        case "BashOutput": return "Check a command"
        case "KillShell", "KillBash": return "Stop a command"
        case "LS": return "List files"
        case "ToolSearch": return "Look for tools"
        default:
            // An MCP tool by what it does, and the server it belongs to when its name means
            // something: "Use create issue in github", never "mcp__github__create_issue".
            let words = AgentHooks.toolWords(toolName)
            guard !words.isEmpty else { return "Use a tool" }
            let server = AgentHooks.mcpParts(toolName).flatMap { AgentHooks.serverWords($0.server) }
            return "Use " + words + (server.map { " in " + $0 } ?? "")
        }
    }

    /// The subagent that asked, in words: "general-purpose" reads "general purpose", and a
    /// plugin's "review:code-reviewer" reads "code reviewer". Nil when no subagent asked.
    public var agentLabel: String? {
        guard let type = agentType else { return nil }
        let name = type.split(separator: ":").last.map(String.init) ?? type
        let label = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    /// The command line for shell tools (Codex may send it as an argument array).
    public var command: String? {
        if let s = toolInput["command"]?.stringValue { return s }
        if let parts = toolInput["command"]?.arrayValue?.compactMap(\.stringValue), !parts.isEmpty {
            // `["bash", "-lc", "…"]`: the script is what matters.
            if parts.count == 3, ["bash", "sh", "zsh", "/bin/bash", "/bin/sh", "/bin/zsh"].contains(parts[0]),
               parts[1].hasPrefix("-"), parts[1].contains("c") { return parts[2] }
            return parts.map(Self.shellQuote).joined(separator: " ")
        }
        return nil
    }

    /// Whether `command` is something a shell will run (as opposed to a field of an MCP tool).
    public var isShell: Bool {
        guard command != nil else { return false }
        return ["Bash", "Shell", "shell", "local_shell", "exec_command"].contains(toolName) || provider == .codex
    }

    /// The full command, path, URL or input, as the card shows it. A command is never
    /// shortened. Any other tool's input reads as "name: value" lines, without JSON's braces
    /// and quotes.
    public var subject: String {
        switch kind {
        case .questions, .plan: return ""
        case .tool: break
        }
        if let s = namedSubject { return s }
        switch toolInput {
        case .object(let o): return o.isEmpty ? "No details" : Self.fieldLines(o)
        default: return Self.inline(toolInput, nested: false)
        }
    }

    /// The tool call as the agent sent it, which a later `PostToolUse` for the same call is
    /// matched on (`callKey`). It never changes with how the card reads.
    private var rawSubject: String {
        guard case .tool = kind else { return "" }
        if let s = namedSubject { return s }
        if case .object(let o) = toolInput, o.isEmpty { return toolName }
        return toolInput.prettyString
    }

    /// The command, or the one field that says what the call is about (a path, a URL, a query).
    private var namedSubject: String? {
        if let c = command { return c }
        for key in ["file_path", "notebook_path", "path", "url", "query", "pattern"] {
            if let s = toolInput[key]?.stringValue, !s.isEmpty { return s }
        }
        return toolInput["patch"]?.stringValue ?? toolInput["input"]?.stringValue
    }

    /// One line a field: its name in words, then its value ("repo: me/web"). Short fields come
    /// first, so a long body can't push the repo and title out of the box.
    static func fieldLines(_ o: [String: JSONValue]) -> String {
        let lines = o.keys.sorted().map { key in
            let name = AgentHooks.words(key)
            return (name.isEmpty ? key : name) + ": " + inline(o[key] ?? .null, nested: false)
        }
        let short = lines.filter { $0.count <= shortLine }
        return (short + lines.filter { $0.count > shortLine }).joined(separator: "\n")
    }

    /// A field line up to this long fits on one line of the card.
    static let shortLine = 60

    /// A value on one line, up to `valueLimit` characters: text as it is, a list or an object
    /// one level down, anything deeper as "…".
    static func inline(_ value: JSONValue, nested: Bool) -> String {
        let text: String
        switch value {
        case .null: text = "none"
        case .bool(let b): text = b ? "yes" : "no"
        case .number(let d): text = d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .string(let s): text = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        case .array(let a): text = nested ? "…" : a.map { inline($0, nested: true) }.joined(separator: ", ")
        case .object(let o):
            text = nested ? "…" : o.keys.sorted().map { key in
                let name = AgentHooks.words(key)
                return (name.isEmpty ? key : name) + " " + inline(o[key] ?? .null, nested: true)
            }.joined(separator: ", ")
        }
        return text.count > valueLimit ? String(text.prefix(valueLimit - 1)) + "…" : text
    }

    /// The most of one field's value a card shows.
    static let valueLimit = 200

    /// The file a file tool works on, for the card: its name first, and the folder it is in
    /// after it, relative to the project when it is inside it ("Sources/IsletCore") or with ~
    /// for the home folder otherwise. No folder for a file at the project's top. Nil for
    /// anything but a file tool. The full path stays in `subject`.
    public var file: ApprovalFile? {
        guard case .tool = kind, ["Edit", "MultiEdit", "Write", "Read", "NotebookEdit"].contains(toolName),
              let path = toolInput["file_path"]?.stringValue ?? toolInput["notebook_path"]?.stringValue else { return nil }
        return ApprovalFile(path: path, cwd: cwd)
    }

    /// Supporting text under the subject: the command's description, or the change an edit makes.
    public var detail: String? {
        func cap(_ s: String) -> String {
            let limit = 4000
            guard s.count > limit else { return s }
            return String(s.prefix(limit)) + "\n… \(s.count - limit) more characters"
        }
        func diff(_ old: String?, _ new: String?) -> String {
            let minus = (old ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { "- " + $0 }
            let plus = (new ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { "+ " + $0 }
            return (minus + plus).joined(separator: "\n")
        }
        guard case .tool = kind else { return nil }
        switch toolName {
        case "Bash": return toolInput["description"]?.stringValue
        case "Edit": return cap(diff(toolInput["old_string"]?.stringValue, toolInput["new_string"]?.stringValue))
        case "MultiEdit":
            let edits = toolInput["edits"]?.arrayValue ?? []
            return cap(edits.map { diff($0["old_string"]?.stringValue, $0["new_string"]?.stringValue) }.joined(separator: "\n\n"))
        case "Write": return toolInput["content"]?.stringValue.map(cap)
        case "NotebookEdit": return toolInput["new_source"]?.stringValue.map(cap)
        case "WebFetch": return toolInput["prompt"]?.stringValue
        default: return nil
        }
    }

    /// Why this looks dangerous, most serious first (empty when nothing matched).
    public var risks: [String] { RiskRules.reasons(for: self) }

    /// "Always (this session)" needs a suggestion from Claude to echo back.
    public var canAllowForSession: Bool {
        provider == .claude && hook == .permissionRequest && kind == .tool && !suggestions.isEmpty
    }

    /// What "Always" would allow, in words: "commands starting with “npm test”", "file edits
    /// without asking", "files in ~/other-project". Never Claude Code's own rule syntax.
    public var sessionRuleSummary: String? {
        let parts = suggestions.flatMap { s -> [String] in
            switch s["type"]?.stringValue {
            case "addRules", "replaceRules":
                return (s["rules"]?.arrayValue ?? []).compactMap { rule in
                    rule["toolName"]?.stringValue.map { Self.ruleWords(tool: $0, content: rule["ruleContent"]?.stringValue) }
                }
            case "setMode": return s["mode"]?.stringValue.map { [Self.modeWords($0)] } ?? []
            case "addDirectories":
                return (s["directories"]?.arrayValue ?? []).compactMap(\.stringValue).map { "files in " + Self.folderWords($0) }
            default: return []
            }
        }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    /// A permission rule in words. A command rule's "npm test:*" reads "commands starting with
    /// “npm test”"; a rule with nothing after the tool, the kind of thing it allows.
    static func ruleWords(tool: String, content: String?, home: String = NSHomeDirectory()) -> String {
        let content = content?.trimmingCharacters(in: .whitespaces) ?? ""
        switch tool {
        case "Bash", "Shell", "shell", "local_shell", "exec_command":
            guard !content.isEmpty, content != "*" else { return "every command" }
            for wildcard in [":*", "*"] where content.hasSuffix(wildcard) {
                let start = content.dropLast(wildcard.count).trimmingCharacters(in: .whitespaces)
                return "commands starting with \u{201C}\(start)\u{201D}"
            }
            return "\u{201C}\(content)\u{201D}"
        case "WebFetch":
            if content.hasPrefix("domain:") { return "web pages on " + content.dropFirst("domain:".count) }
            return "fetching web pages"
        case "WebSearch": return "web searches"
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "Read", "Glob", "Grep":
            let verb = ["Read": "reading files", "Glob": "searching files", "Grep": "searching files"][tool] ?? "editing files"
            guard !content.isEmpty else { return verb }
            return verb + " in " + folderWords(content, home: home)
        case "Task", "Agent": return "subagents"
        default:
            let words = AgentHooks.toolWords(tool)
            let server = AgentHooks.mcpParts(tool).flatMap { AgentHooks.serverWords($0.server) }
            if words.isEmpty { return server.map { "tools in " + $0 } ?? "this tool" }
            return words + (server.map { " in " + $0 } ?? "")
        }
    }

    /// One of Claude Code's permission modes in words.
    static func modeWords(_ mode: String) -> String {
        switch mode {
        case "acceptEdits": return "file edits without asking"
        case "bypassPermissions", "dontAsk": return "everything without asking"
        case "plan": return "plan mode"
        case "default": return "asking as usual"
        default: return AgentHooks.words(mode) + " mode"
        }
    }

    /// A folder or path pattern from a rule, with ~ for home and no trailing "/**":
    /// "//Users/me/other/**" reads "~/other".
    static func folderWords(_ path: String, home: String = NSHomeDirectory()) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("//") { p.removeFirst() }
        for tail in ["/**", "/*"] where p.hasSuffix(tail) && p.count > tail.count { p.removeLast(tail.count) }
        if home.count > 1, p == home || p.hasPrefix(home + "/") { p = "~" + p.dropFirst(home.count) }
        return p
    }

    /// Identifies the tool call, so a later `PostToolUse` for it can clear the card.
    public var callKey: String { Self.callKey(toolName: toolName, subject: rawSubject) }

    static func callKey(toolName: String, subject: String) -> String {
        isInteractiveTool(toolName) ? toolName : toolName + "\n" + subject
    }

    /// How the agent's status activity should look once the card is answered (Claude only).
    public func statusUpdate(after decision: ApprovalDecision) -> ActivitySpec? {
        guard provider == .claude, decision != .terminal else { return nil }
        var spec = ActivitySpec(id: "claude-\(AgentHooks.shortID(sessionID))", trailing: "", progress: -1, state: .running,
                                priority: .normal, ttl: 0, sneak: false)
        let allowed = decision == .allow || decision == .allowForSession
        spec.subtitle = allowed && kind == .tool
            ? AgentHooks.describeTool(toolName, input: toolInput.foundationObject as? [String: Any], cwd: cwd) : "Thinking…"
        return spec
    }

    /// The id of the agent's status activity for this session (`AgentHooks`).
    public var statusActivityID: String {
        "\(provider.rawValue)-" + AgentHooks.shortID(sessionID)
    }

    /// Why the question went back to the terminal without an answer here.
    public enum BackToTerminal: Equatable, Sendable {
        /// The card waited `approvalWait` and nobody answered it.
        case expired
        /// "Answer in the terminal", but the terminal couldn't be brought forward.
        case jumpFailed
    }

    /// The agent's status once its question has gone back to the terminal unanswered, so a
    /// card that went away doesn't leave the agent waiting unseen. It changes the agent's own
    /// activity only, which the hooks keep up to date; with none showing, nothing is added.
    public func statusUpdate(backToTerminal reason: BackToTerminal) -> ActivitySpec {
        let subtitle: String
        switch reason {
        case .expired: subtitle = "Answer in the terminal"
        case .jumpFailed: subtitle = "Couldn’t bring the terminal forward. Answer there."
        }
        return ActivitySpec(id: statusActivityID, subtitle: subtitle, trailing: "Waiting", state: .waiting,
                            priority: .normal, ttl: 0, sneak: false)
    }

    static func shellQuote(_ s: String) -> String {
        guard s.isEmpty || s.contains(where: { " \t\n'\"\\$`;&|<>()*?[]{}!#~".contains($0) }) else { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// A later hook event that makes pending cards moot: the user answered in the terminal, the
/// tool ran, the turn ended or a new prompt arrived.
public struct ApprovalSettlement: Equatable, Sendable {
    public var provider: AgentProvider
    public var sessionID: String
    /// Only the card for this tool call (`ApprovalRequest.callKey`); nil clears the whole session.
    public var callKey: String?

    public init(provider: AgentProvider, sessionID: String, callKey: String? = nil) {
        self.provider = provider
        self.sessionID = sessionID
        self.callKey = callKey
    }

    public static func parse(provider: String, payload: Data) -> ApprovalSettlement? {
        guard let p = AgentProvider(hookProvider: provider), let o = JSONValue.parse(payload)?.objectValue else { return nil }
        let event = o["hook_event_name"]?.stringValue ?? ""
        switch p {
        case .claude, .codex:
            guard let session = o["session_id"]?.stringValue, !session.isEmpty else { return nil }
            switch event {
            case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
                guard let tool = o["tool_name"]?.stringValue else { return ApprovalSettlement(provider: p, sessionID: session) }
                let probe = ApprovalRequest(provider: p, hook: .permissionRequest, sessionID: session, toolName: tool,
                                            toolInput: o["tool_input"] ?? .object([:]))
                return ApprovalSettlement(provider: p, sessionID: session, callKey: probe.callKey)
            case "Stop", "UserPromptSubmit", "SessionEnd":
                return ApprovalSettlement(provider: p, sessionID: session)
            default:
                return nil
            }
        case .cursor:
            guard let session = o["conversation_id"]?.stringValue, !session.isEmpty else { return nil }
            switch event {
            case "afterShellExecution", "afterMCPExecution":
                // Same shape as the "before" event, so the same parser gives the call's key.
                var before = o
                before["hook_event_name"] = .string(event == "afterShellExecution" ? "beforeShellExecution" : "beforeMCPExecution")
                let call = ApprovalRequest.parse(provider: .cursor, object: before)?.callKey
                return call.map { ApprovalSettlement(provider: p, sessionID: session, callKey: $0) }
            case "stop", "beforeSubmitPrompt", "sessionEnd":
                return ApprovalSettlement(provider: p, sessionID: session)
            default:
                return nil
            }
        }
    }

    public func matches(_ r: ApprovalRequest) -> Bool {
        r.provider == provider && r.sessionID == sessionID && (callKey == nil || callKey == r.callKey)
    }
}

/// The user's answer to a card.
public enum ApprovalDecision: Equatable, Sendable {
    /// Allow this once (plans: approve).
    case allow
    /// Allow, and add Claude's suggested rules for the rest of the session.
    case allowForSession
    /// Deny, with a message for the agent (plans: keep planning).
    case deny(String)
    /// Answers keyed by question text; several picks are joined with ", ".
    case answer([String: String])
    /// Leave it to the agent's own prompt.
    case terminal

    public static let deniedMessage = "The user denied this from the notch."
    public static let keepPlanningMessage = "The user wants to keep planning. Revise the plan before asking again."
}

/// The single backend call behind approvals (see `IsletBackend.handleApproval`).
public enum ApprovalEvent: Equatable, Sendable {
    /// Show a card and wait for the answer. The caller cancels the task when the wait runs out
    /// or the hook goes away.
    case ask(ApprovalRequest)
    /// Remove cards made moot by a later event.
    case settle(ApprovalSettlement)
}

/// What the hook prints for a decision, per agent. Nil means print nothing: the agent then
/// asks in the terminal as if no hook had run.
public enum ApprovalOutput {
    public static func encode(_ decision: ApprovalDecision, for r: ApprovalRequest) -> Data? {
        json(decision, for: r)?.data()
    }

    static func json(_ decision: ApprovalDecision, for r: ApprovalRequest) -> JSONValue? {
        switch r.hook {
        case .beforeShellExecution, .beforeMCPExecution:
            switch decision {
            case .allow, .allowForSession, .answer: return .object(["permission": "allow"])
            case .deny(let message):
                return .object(["permission": "deny", "user_message": .string(message), "agent_message": .string(message)])
            case .terminal: return .object(["permission": "ask"])
            }

        case .permissionRequest:
            var d: [String: JSONValue]
            switch decision {
            case .terminal: return nil
            case .allow: d = ["behavior": "allow"]
            case .allowForSession:
                d = ["behavior": "allow"]
                if r.canAllowForSession {
                    d["updatedPermissions"] = .array(r.suggestions.map { s in
                        guard case .object(var o) = s else { return s }
                        o["destination"] = "session"
                        return .object(o)
                    })
                }
            case .deny(let message): d = ["behavior": "deny", "message": .string(message)]
            case .answer(let answers):
                d = ["behavior": "allow", "updatedInput": inputWithAnswers(r.toolInput, answers)]
            }
            return .object(["hookSpecificOutput": .object(["hookEventName": "PermissionRequest", "decision": .object(d)])])

        case .preToolUse:
            var out: [String: JSONValue] = ["hookEventName": "PreToolUse"]
            switch decision {
            case .terminal: return nil
            case .allow, .allowForSession: out["permissionDecision"] = "allow"
            case .deny(let message):
                out["permissionDecision"] = "deny"
                out["permissionDecisionReason"] = .string(message)
            case .answer(let answers):
                out["permissionDecision"] = "allow"
                out["updatedInput"] = inputWithAnswers(r.toolInput, answers)
            }
            return .object(["hookSpecificOutput": .object(out)])
        }
    }

    /// The tool input echoed back with `answers` added (`AskUserQuestion` needs both).
    static func inputWithAnswers(_ input: JSONValue, _ answers: [String: String]) -> JSONValue {
        var o = input.objectValue ?? [:]
        o["answers"] = .object(answers.mapValues { .string($0) })
        return .object(o)
    }
}

/// Pending cards, oldest first. Pure bookkeeping; the app keeps the waiting callers.
public struct ApprovalQueue: Sendable {
    public static let capacity = 16

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        public var request: ApprovalRequest
        public var received: Date
    }

    public private(set) var entries: [Entry] = []
    /// Questions and plans the user sent to the terminal from their `PreToolUse` card, so the
    /// `PermissionRequest` that follows for the same call doesn't show a second card.
    private var handedOff: [String] = []

    public init() {}

    public var current: Entry? { entries.first }
    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Adds a card. False when the queue is full or the user already sent this call to the terminal.
    public mutating func enqueue(_ request: ApprovalRequest, id: String, now: Date) -> Bool {
        if request.hook == .permissionRequest, let i = handedOff.firstIndex(of: Self.handOffKey(request)) {
            handedOff.remove(at: i)
            return false
        }
        guard entries.count < Self.capacity else { return false }
        entries.append(Entry(id: id, request: request, received: now))
        return true
    }

    @discardableResult
    public mutating func remove(id: String) -> Entry? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: i)
    }

    /// Removes a card the user chose to answer in the terminal.
    @discardableResult
    public mutating func handOff(id: String) -> Entry? {
        guard let e = remove(id: id) else { return nil }
        if e.request.hook == .preToolUse {
            handedOff.append(Self.handOffKey(e.request))
            if handedOff.count > Self.capacity { handedOff.removeFirst() }
        }
        return e
    }

    /// Removes the cards a later event made moot and returns their ids.
    public mutating func settle(_ s: ApprovalSettlement) -> [String] {
        let gone = entries.filter { s.matches($0.request) }.map(\.id)
        entries.removeAll { s.matches($0.request) }
        let prefix = Self.sessionPrefix(s.provider, s.sessionID)
        handedOff.removeAll { entry in s.callKey.map { entry == prefix + $0 } ?? entry.hasPrefix(prefix) }
        return gone
    }

    static func sessionPrefix(_ p: AgentProvider, _ session: String) -> String { "\(p.rawValue)\n\(session)\n" }

    static func handOffKey(_ r: ApprovalRequest) -> String { sessionPrefix(r.provider, r.sessionID) + r.callKey }
}

/// A JSON value that keeps agent payload fragments intact (tool input, permission
/// suggestions), so they can be shown and echoed back exactly.
public indirect enum JSONValue: Equatable, Sendable, ExpressibleByStringLiteral {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(stringLiteral value: String) { self = .string(value) }

    /// From a `JSONSerialization` result.
    public init(foundation any: Any?) {
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSONValue(foundation: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(foundation: $0) })
        default: self = .null
        }
    }

    public static func parse(_ data: Data) -> JSONValue? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return JSONValue(foundation: any)
    }

    public var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d.rounded() == d && abs(d) < 1e15 ? Int(d) as Any : d as Any
        case .string(let s): return s
        case .array(let a): return a.map(\.foundationObject)
        case .object(let o): return o.mapValues(\.foundationObject)
        }
    }

    /// Compact JSON with sorted keys.
    public func data(pretty: Bool = false) -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted) }
        return (try? JSONSerialization.data(withJSONObject: foundationObject, options: options)) ?? Data("null".utf8)
    }

    public var prettyString: String { String(decoding: data(pretty: true), as: UTF8.self) }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
}
