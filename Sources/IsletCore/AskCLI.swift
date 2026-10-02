import Foundation

/// Running `claude` and `codex` for the Ask box: where to find them, their arguments and a
/// minimal environment. The user's existing login is used; no key passes through Islet.
public enum AskCLI {
    public static func binaryName(for kind: AskProviderKind) -> String? {
        switch kind {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        default: return nil
        }
    }

    /// Where to look, in order. GUI apps don't inherit the shell's PATH, so these are fixed.
    public static func searchPaths(for kind: AskProviderKind, home: String) -> [String] {
        guard let name = binaryName(for: kind) else { return [] }
        var dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        if kind == .claudeCode { dirs.append("\(home)/.claude/local") }
        return dirs.map { "\($0)/\(name)" }
    }

    /// `claude -p` with no tools, one turn, no saved session and no hooks (so neither Islet's
    /// own hooks nor anyone else's fire for this run). Order matters: `--tools` takes a list, so
    /// the question comes straight after `-p`.
    public static func claudeArguments(prompt: String, model: String?) -> [String] {
        var args = [
            "-p", safePrompt(prompt),
            "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--tools", "",
            "--max-turns", "1",
            "--no-session-persistence",
            "--settings", #"{"disableAllHooks": true}"#,
        ]
        if let model, AskSettings.isPlausibleModel(model) { args += ["--model", model] }
        return args
    }

    /// `codex exec` in a read-only sandbox, without saving the session.
    public static func codexArguments(prompt: String, model: String?) -> [String] {
        var args = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only"]
        if let model, AskSettings.isPlausibleModel(model) { args += ["--model", model] }
        args.append(safePrompt(prompt))
        return args
    }

    /// A question starting with "-" would be read as an option; a leading space prevents that.
    static func safePrompt(_ prompt: String) -> String {
        prompt.hasPrefix("-") ? " " + prompt : prompt
    }

    /// Only what the CLIs need to find their login and run: no Islet API token, no API keys
    /// (an `ANTHROPIC_API_KEY` would also switch Claude Code from the user's plan to API billing).
    public static func environment(parent: [String: String], binaryDirectory: String) -> [String: String] {
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR"] {
            if let v = parent[key], !v.isEmpty { env[key] = v }
        }
        env["LANG"] = parent["LANG"].flatMap { $0.isEmpty ? nil : $0 } ?? "en_US.UTF-8"
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        var path = [binaryDirectory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        path = path.filter { !$0.isEmpty && seen.insert($0).inserted }
        env["PATH"] = path.joined(separator: ":")
        return env
    }

    /// Seconds between SIGTERM and SIGKILL when a run is cancelled.
    public static let killGrace: TimeInterval = 2

    /// A one-line reason from a CLI's stderr, for when it exits without saying why on stdout.
    /// The exit status and an option it didn't know are for the log (`AskService`), not the island.
    public static func failureText(kind: AskProviderKind, status: Int32, stderr: String) -> String {
        let line = firstLine(stderr)
        if let line, line.contains("unknown option") || line.contains("unexpected argument") {
            return "\(kind.title) is too old for Islet. Update it and try again."
        }
        if let line { return "\(kind.title): \(line.prefix(200))" }
        return "\(kind.title) stopped before answering. Try again."
    }

    /// The first line of a CLI's stderr with something on it.
    public static func firstLine(_ stderr: String) -> String? {
        stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

/// Decodes `claude -p --output-format stream-json --verbose --include-partial-messages`.
/// Text comes from `stream_event` lines with a `text_delta`; the closing `result` line carries
/// the cost and whether it failed. Without partial messages (older CLIs), `assistant` lines
/// carry the whole text instead.
public struct ClaudeCLIDecoder: AskLineDecoder {
    private var usage = AskUsage()
    private var sawDelta = false
    private var sawText = false
    private var finished = false

    public init() {}

    public mutating func decode(line: String) -> [AskEvent] {
        guard !finished, let obj = AskJSON.object(line) else { return [] }
        switch obj["type"] as? String {
        case "system":
            if let m = obj["model"] as? String { usage.model = m }
        case "stream_event":
            guard let ev = obj["event"] as? [String: Any] else { return [] }
            switch ev["type"] as? String {
            case "message_start":
                if let m = (ev["message"] as? [String: Any])?["model"] as? String { usage.model = m }
            case "content_block_delta":
                if let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                   let t = d["text"] as? String, !t.isEmpty {
                    sawDelta = true
                    sawText = true
                    return [.text(t)]
                }
            case "message_delta":
                if let r = (ev["delta"] as? [String: Any])?["stop_reason"] as? String { usage.stopReason = r }
            default:
                break
            }
        case "assistant":
            guard !sawDelta, let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return [] }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { return [] }
            sawText = true
            return [.text(text)]
        case "result":
            finished = true
            let result = obj["result"] as? String
            if obj["is_error"] as? Bool == true || (obj["subtype"] as? String).map({ $0 != "success" }) == true {
                return [.error(Self.errorText(result: result, subtype: obj["subtype"] as? String))]
            }
            if usage.stopReason == "refusal" { return [.refusal(nil)] }
            if let u = obj["usage"] as? [String: Any] {
                usage.inputTokens = AskJSON.int(u["input_tokens"])
                usage.outputTokens = AskJSON.int(u["output_tokens"])
            }
            usage.costUSD = obj["total_cost_usd"] as? Double
            var events: [AskEvent] = []
            if !sawText, let result, !result.isEmpty { events.append(.text(result)) }
            events.append(.done(usage))
            return events
        default:
            break
        }
        return []
    }

    public mutating func finish() -> [AskEvent] {
        guard !finished else { return [] }
        finished = true
        return []
    }

    static func errorText(result: String?, subtype: String?) -> String {
        let r = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if r.contains("/login") || r.lowercased().contains("not logged in") || r.lowercased().contains("invalid api key") {
            return "Claude Code isn’t signed in. Run claude in Terminal and sign in."
        }
        if subtype == "error_max_turns" { return "Claude Code wanted more than one step. Ask a simpler question." }
        if !r.isEmpty { return "Claude Code: \(r.prefix(200))" }
        return "Claude Code stopped with an error. Try again."
    }
}

/// Decodes `codex exec --json` JSONL: `thread.started`, `turn.started`, `item.*` (text from
/// `agent_message` items), `turn.completed` (usage), `turn.failed` and `error`. Codex also
/// reports errors it recovers from, so `error` only counts if the run ends without a turn result.
public struct CodexDecoder: AskLineDecoder {
    private var shown: [String: String] = [:]
    private var lastError: String?
    private var finished = false

    public init() {}

    public mutating func decode(line: String) -> [AskEvent] {
        guard !finished, let obj = AskJSON.object(line) else { return [] }
        switch obj["type"] as? String {
        case "item.started", "item.updated", "item.completed":
            guard let item = obj["item"] as? [String: Any], item["type"] as? String == "agent_message",
                  let text = item["text"] as? String else { return [] }
            let id = item["id"] as? String ?? "item"
            let before = shown[id] ?? ""
            guard text.count > before.count, text.hasPrefix(before) else { return [] }
            var delta = String(text.dropFirst(before.count))
            if before.isEmpty, shown.values.contains(where: { !$0.isEmpty }) { delta = "\n\n" + delta }
            shown[id] = text
            return [.text(delta)]
        case "turn.completed":
            finished = true
            let u = obj["usage"] as? [String: Any]
            return [.done(AskUsage(inputTokens: AskJSON.int(u?["input_tokens"]), outputTokens: AskJSON.int(u?["output_tokens"])))]
        case "turn.failed":
            finished = true
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? lastError
            return [.error(Self.errorText(message))]
        case "error":
            lastError = obj["message"] as? String ?? (obj["error"] as? [String: Any])?["message"] as? String
        default:
            break
        }
        return []
    }

    public mutating func finish() -> [AskEvent] {
        guard !finished else { return [] }
        finished = true
        return lastError.map { [.error(Self.errorText($0))] } ?? []
    }

    static func errorText(_ message: String?) -> String {
        guard let m = message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty else { return "Codex stopped with an error." }
        if m.lowercased().contains("login") || m.contains("401") { return "Codex isn’t signed in. Run codex in Terminal and sign in." }
        return "Codex: \(m.prefix(200))"
    }
}
