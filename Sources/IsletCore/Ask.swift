import Foundation

// The Ask box: a question field in the expanded island that streams answers from the on-device
// model, Claude or ChatGPT (API keys) or the local Claude Code / Codex CLIs. This file holds the
// pure parts: providers, settings, conversation rules, answer buffering and user-facing text.
// Request builders and stream decoders are in AskProviders.swift, CLI details in AskCLI.swift.

/// Where a question goes.
public enum AskProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Apple's on-device model (Apple Intelligence). Nothing leaves the Mac.
    case onDevice
    /// Anthropic Messages API with the user's API key.
    case anthropic
    /// OpenAI Responses API with the user's API key.
    case openai
    /// The `claude` CLI with the user's existing login.
    case claudeCode
    /// The `codex` CLI with the user's existing login.
    case codex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onDevice: return "On-device"
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// Who receives the question when it leaves the Mac.
    public var recipient: String? {
        switch self {
        case .onDevice: return nil
        case .anthropic, .claudeCode: return "Anthropic"
        case .openai, .codex: return "OpenAI"
        }
    }

    public var symbol: String {
        switch self {
        case .onDevice: return "laptopcomputer"
        case .anthropic: return "sparkle"
        case .openai: return "bubble.left.and.text.bubble.right"
        case .claudeCode, .codex: return "terminal"
        }
    }

    /// The question is sent over the network (the CLIs call their vendor's servers too).
    public var leavesMac: Bool { self != .onDevice }

    public var isCLI: Bool { self == .claudeCode || self == .codex }

    /// Keychain account holding this provider's API key.
    public var keyAccount: String? {
        switch self {
        case .anthropic: return "anthropic"
        case .openai: return "openai"
        default: return nil
        }
    }

    public var defaultModel: String? {
        switch self {
        case .anthropic: return AnthropicAPI.defaultModel
        case .openai: return OpenAIAPI.defaultModel
        default: return nil
        }
    }

    /// Offered when the vendor's model list can't be fetched.
    public var suggestedModels: [String] {
        switch self {
        case .anthropic: return AnthropicAPI.knownModels
        case .openai: return OpenAIAPI.knownModels
        default: return []
        }
    }

    /// Names accepted in `islet://ask?provider=`.
    public init?(alias: String) {
        switch alias.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "ondevice", "on-device", "local", "apple", "apple-intelligence": self = .onDevice
        case "anthropic", "claude": self = .anthropic
        case "openai", "chatgpt", "gpt": self = .openai
        case "claudecode", "claude-code", "claude-cli": self = .claudeCode
        case "codex", "codex-cli": self = .codex
        default: return nil
        }
    }
}

/// How hard cloud models think before answering. Low keeps the notch snappy.
public enum AskEffort: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    public var title: String { rawValue.capitalized }
}

/// Ask preferences, stored under `"ask"` in config.json. Keys never live here: they are in the
/// Keychain. Decoding is lenient field by field, and unknown fields (such as a pasted key) are
/// dropped on the next save.
public struct AskSettings: Codable, Equatable, Sendable {
    /// Provider used when the island opens. The chip in the island can change it for a session.
    public var provider: AskProviderKind = .onDevice
    /// Model per provider, keyed by the provider's raw value. Missing entries use the default.
    public var models: [String: String] = [:]
    public var effort: AskEffort = .low
    /// Keep earlier turns (up to `AskLimits.followUpTurns`) in memory and send them with the next question.
    public var followUps = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AskSettings()
        provider = (try? c.decodeIfPresent(AskProviderKind.self, forKey: .provider)) ?? d.provider
        models = ((try? c.decodeIfPresent([String: String].self, forKey: .models)) ?? d.models)
            .filter { AskProviderKind(rawValue: $0.key) != nil && AskSettings.isPlausibleModel($0.value) }
        effort = (try? c.decodeIfPresent(AskEffort.self, forKey: .effort)) ?? d.effort
        followUps = (try? c.decodeIfPresent(Bool.self, forKey: .followUps)) ?? d.followUps
    }

    /// The model to use for a provider: the user's choice or the provider's default (nil for the
    /// on-device model, and for a CLI left on its own default).
    public func model(for kind: AskProviderKind) -> String? {
        if let m = models[kind.rawValue], !m.isEmpty { return m }
        return kind.defaultModel
    }

    public mutating func setModel(_ model: String?, for kind: AskProviderKind) {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        models[kind.rawValue] = trimmed.isEmpty || !Self.isPlausibleModel(trimmed) ? nil : trimmed
    }

    /// Model ids are short tokens like `claude-opus-5-5` or `gpt-6.1-sol`. Anything else (spaces,
    /// flags, a pasted key) is refused, so it can't end up on a command line or in config.json.
    public static func isPlausibleModel(_ s: String) -> Bool {
        guard (1...80).contains(s.count), !s.hasPrefix("-"), !s.lowercased().hasPrefix("sk-") else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-._:/[]".unicodeScalars.contains($0) }
    }
}

/// One message in a conversation.
public struct AskTurn: Equatable, Sendable, Codable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }

    public static func user(_ text: String) -> AskTurn { AskTurn(role: .user, text: text) }
    public static func assistant(_ text: String) -> AskTurn { AskTurn(role: .assistant, text: text) }
}

/// One question to answer, with any earlier turns.
public struct AskRequest: Equatable, Sendable {
    public var provider: AskProviderKind
    /// nil: the provider's default (for a CLI, its own default).
    public var model: String?
    public var effort: AskEffort
    public var turns: [AskTurn]

    public init(provider: AskProviderKind, model: String? = nil, effort: AskEffort = .low, turns: [AskTurn]) {
        self.provider = provider
        self.model = model
        self.effort = effort
        self.turns = turns
    }
}

/// Token counts and cost reported at the end of an answer.
public struct AskUsage: Equatable, Sendable {
    /// The model that actually answered (a fallback model after a refusal, for example).
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Reported by the Claude Code CLI.
    public var costUSD: Double?
    /// Why the answer ended, when the provider says (`end_turn`, `max_tokens`, …).
    public var stopReason: String?

    public init(model: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, costUSD: Double? = nil, stopReason: String? = nil) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.stopReason = stopReason
    }

    /// The answer hit the output limit.
    public var wasCut: Bool { ["max_tokens", "max_output_tokens"].contains(stopReason ?? "") }
}

/// What a provider streams back.
public enum AskEvent: Equatable, Sendable {
    /// More answer text, to append.
    case text(String)
    /// The answer is complete.
    case done(AskUsage)
    /// The model or its safety system declined. Any partial text should be discarded.
    case refusal(String?)
    /// Something failed; the message is ready to show.
    case error(String)

    public var isTerminal: Bool {
        if case .text = self { return false }
        return true
    }
}

public enum AskLimits {
    /// Answer text shown in the island.
    public static let shownBytes = 8 * 1024
    /// Answer text kept for Copy.
    public static let keptBytes = 256 * 1024
    /// Output read from a CLI before it is stopped.
    public static let cliOutputBytes = 256 * 1024
    /// Earlier turns kept for follow-ups (in memory only).
    public static let followUpTurns = 6
    /// The island redraws the answer at most this often (20 times a second).
    public static let publishInterval: TimeInterval = 0.05
    /// Longest wait between bytes from an API.
    public static let requestTimeout: TimeInterval = 30
    /// Longest a whole answer may take.
    public static let overallTimeout: TimeInterval = 120
    /// Longest question accepted.
    public static let questionCharacters = 4000
}

public enum AskPrompt {
    /// System prompt for the API providers and the on-device model.
    public static let system = "You answer inside a small panel under the MacBook notch. Answer in at most 120 words unless asked for more. Plain text, no Markdown tables."

    /// A conversation ready to send: blank turns dropped, starting with the user, roles alternating
    /// (neighbours with the same role are merged), at most `maxEarlier` turns before the last
    /// question, and each turn capped in length.
    public static func normalized(_ turns: [AskTurn], maxEarlier: Int = AskLimits.followUpTurns) -> [AskTurn] {
        var out: [AskTurn] = []
        for t in turns {
            let text = String(t.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AskLimits.keptBytes))
            guard !text.isEmpty else { continue }
            if out.isEmpty && t.role == .assistant { continue }
            if let last = out.last, last.role == t.role {
                out[out.count - 1].text += "\n\n" + text
            } else {
                out.append(AskTurn(role: t.role, text: text))
            }
        }
        // End on the user's question.
        while let last = out.last, last.role == .assistant { out.removeLast() }
        guard out.count > maxEarlier + 1 else { return out }
        var trimmed = Array(out.suffix(maxEarlier + 1))
        while let first = trimmed.first, first.role == .assistant { trimmed.removeFirst() }
        return trimmed
    }

    /// One prompt string, for providers that take no message list (the CLIs, the on-device model).
    public static func flattened(_ turns: [AskTurn], instructions: String? = nil) -> String {
        let turns = normalized(turns)
        guard let question = turns.last?.text else { return instructions ?? "" }
        var parts: [String] = []
        if let instructions, !instructions.isEmpty { parts.append(instructions) }
        let earlier = turns.dropLast()
        if !earlier.isEmpty {
            let lines = earlier.map { ($0.role == .user ? "User: " : "Assistant: ") + $0.text }
            parts.append("Earlier in this conversation:\n" + lines.joined(separator: "\n"))
            parts.append("Question: " + question)
        } else {
            parts.append(question)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Prepended for the CLIs, which have their own (coding) system prompt.
    public static let cliInstructions = "Answer briefly, in at most 120 words unless asked for more. Plain text. Do not use tools or read files."
}

/// The answer as it streams in: everything (up to `keptBytes`) for Copy, and the first
/// `shownBytes` for the island.
public struct AskAnswer: Equatable, Sendable {
    public private(set) var text = ""
    public private(set) var shown = ""
    /// More text arrived than the island shows.
    public private(set) var isTrimmed = false
    /// More text arrived than is kept.
    public private(set) var isCut = false

    public init() {}

    public var isEmpty: Bool { text.isEmpty }

    public mutating func append(_ s: String) {
        guard !s.isEmpty else { return }
        let kept = Self.prefix(s, bytes: AskLimits.keptBytes - text.utf8.count)
        if kept.utf8.count < s.utf8.count { isCut = true }
        text += kept
        let room = AskLimits.shownBytes - shown.utf8.count
        if room > 0 {
            let part = Self.prefix(kept, bytes: room)
            shown += part
            if part.utf8.count < kept.utf8.count { isTrimmed = true }
        } else if !kept.isEmpty {
            isTrimmed = true
        }
    }

    public mutating func reset() { self = AskAnswer() }

    /// The longest prefix of whole characters within a byte budget.
    static func prefix(_ s: String, bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        if s.utf8.count <= bytes { return s }
        var used = 0
        var end = s.startIndex
        for i in s.indices {
            let n = s[i].utf8.count
            if used + n > bytes { break }
            used += n
            end = s.index(after: i)
        }
        return String(s[..<end])
    }
}

/// Batches streamed text so the UI redraws at most once per `interval` rather than per token.
public struct AskCoalescer: Sendable {
    public var interval: TimeInterval
    public private(set) var pending = ""
    private var lastPublish: Date?

    public init(interval: TimeInterval = AskLimits.publishInterval) {
        self.interval = interval
    }

    /// Add text. Returns the text to show now, or nil when it should wait; then call `flush()`
    /// after `delay(now:)`.
    public mutating func add(_ s: String, now: Date) -> String? {
        pending += s
        if let last = lastPublish, now.timeIntervalSince(last) < interval { return nil }
        return flush(now: now)
    }

    /// Seconds until the pending text may be shown.
    public func delay(now: Date) -> TimeInterval {
        guard let last = lastPublish else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }

    public mutating func flush(now: Date) -> String {
        defer { pending = "" }
        lastPublish = now
        return pending
    }

    public mutating func reset() { self = AskCoalescer(interval: interval) }
}

/// Whether a provider can answer right now, and what to tell the user when it can't.
public enum AskProviderStatus: Equatable, Sendable {
    case ready
    /// No API key in the Keychain.
    case needsKey
    /// The CLI wasn't found.
    case notInstalled
    /// The on-device model can't run; the text says why.
    case unavailable(String)

    public var isReady: Bool { self == .ready }

    /// Short reason for the provider menu.
    public var shortReason: String? {
        switch self {
        case .ready: return nil
        case .needsKey: return "add a key in Settings"
        case .notInstalled: return "not installed"
        case .unavailable: return "not ready"
        }
    }

    /// What the island shows when this provider is picked.
    public func message(for kind: AskProviderKind) -> String {
        switch self {
        case .ready:
            switch kind {
            case .onDevice: return "Ask anything. The on-device model answers without anything leaving this Mac."
            case .anthropic, .openai: return "Your question goes to \(kind.recipient ?? "the provider") with your API key. Nothing is saved on this Mac."
            case .claudeCode, .codex: return "Runs \(kind.title) with your existing login, so it counts towards your plan."
            }
        case .needsKey:
            return "Add \(kind == .openai ? "an OpenAI" : "an Anthropic") API key in Settings → AI to ask \(kind.title)."
        case .notInstalled:
            let dirs = kind == .claudeCode ? "~/.local/bin, /opt/homebrew/bin, /usr/local/bin or ~/.claude/local"
                                           : "~/.local/bin, /opt/homebrew/bin or /usr/local/bin"
            return "\(kind.title) wasn't found in \(dirs)."
        case .unavailable(let reason):
            return reason + " Pick another provider from the menu."
        }
    }

    /// Text for each on-device unavailability reason.
    public static func onDeviceReason(_ reason: String) -> String {
        switch reason {
        case "deviceNotEligible": return "This Mac can't run Apple Intelligence."
        case "appleIntelligenceNotEnabled": return "Apple Intelligence is off. Turn it on in System Settings."
        case "modelNotReady": return "Apple Intelligence is still downloading."
        case "needsNewerMacOS": return "On-device answers need macOS 26 or later."
        default: return "Apple Intelligence isn't available."
        }
    }
}

/// API key handling that doesn't need the Keychain.
public enum AskKeys {
    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A quick shape check before a key is sent anywhere: the vendor prefix, a sane length and
    /// no spaces or control characters.
    public static func looksValid(_ key: String, for kind: AskProviderKind) -> Bool {
        let prefix: String
        switch kind {
        case .anthropic: prefix = "sk-ant-"
        case .openai: prefix = "sk-"
        default: return false
        }
        guard key.hasPrefix(prefix), (20...300).contains(key.count) else { return false }
        return key.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }
    }

    /// "•••• abcd": all Settings ever shows of a stored key.
    public static func masked(_ key: String) -> String {
        "•••• " + String(key.suffix(4))
    }
}

/// Error text for HTTP failures from the API providers.
public enum AskErrorText {
    public static func http(status: Int, body: Data, retryAfter: String?, provider: AskProviderKind) -> String {
        let vendor = provider.recipient ?? provider.title
        let apiMessage = message(in: body)
        let apiType = errorType(in: body)
        switch status {
        case 400:
            return "\(vendor) rejected the request" + (apiMessage.map { ": \($0)" } ?? ".")
        case 401:
            return "\(vendor) rejected the API key. Enter it again in Settings → AI."
        case 402:
            return "\(vendor) reports a billing problem on your account."
        case 403:
            return "This API key isn't allowed to do that" + (apiMessage.map { ": \($0)" } ?? ".")
        case 404:
            return "Model not found. Pick another one in Settings → AI."
        case 413:
            return "The question is too long."
        case 429:
            if apiType == "insufficient_quota" { return "Your OpenAI account has run out of credit." }
            if let s = retrySeconds(retryAfter) { return "Rate limited. Try again in \(s) s." }
            return "Rate limited. Try again shortly."
        case 529:
            return "\(provider.title) is overloaded right now. Try again in a moment."
        case 500...599:
            return "\(vendor) had a server error (HTTP \(status)). Try again."
        default:
            return "\(vendor) returned HTTP \(status)" + (apiMessage.map { ": \($0)" } ?? ".")
        }
    }

    /// An `error` record inside an otherwise successful stream.
    public static func stream(type: String?, message: String?, provider: AskProviderKind) -> String {
        switch type {
        case "overloaded_error": return "\(provider.title) is overloaded right now. Try again in a moment."
        case "rate_limit_error": return "Rate limited. Try again shortly."
        default:
            let m = message.map { String($0.prefix(200)) }
            return m.map { "\(provider.recipient ?? provider.title): \($0)" } ?? "The answer stopped with an error."
        }
    }

    /// Whole seconds from a `retry-after` header (seconds form only, up to a day).
    public static func retrySeconds(_ header: String?) -> Int? {
        guard let h = header?.trimmingCharacters(in: .whitespaces), let v = Double(h), v.isFinite, (0...86_400).contains(v) else { return nil }
        return Int(v.rounded(.up))
    }

    /// `error.message` from an Anthropic or OpenAI error body, trimmed for display.
    static func message(in body: Data) -> String? {
        guard let obj = AskJSON.object(body), let err = obj["error"] as? [String: Any],
              let m = err["message"] as? String, !m.isEmpty else { return nil }
        return String(m.prefix(200))
    }

    static func errorType(in body: Data) -> String? {
        guard let obj = AskJSON.object(body), let err = obj["error"] as? [String: Any] else { return nil }
        return (err["code"] as? String) ?? (err["type"] as? String)
    }

    /// Overloaded responses that arrive with another status (Anthropic uses 529).
    public static func isOverloaded(status: Int, body: Data) -> Bool {
        status == 529 || errorType(in: body) == "overloaded_error"
    }
}

/// Small JSON helpers shared by the decoders.
enum AskJSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func object(_ text: String) -> [String: Any]? {
        guard text.first == "{" || text.first == " " || text.first == "\t" else { return nil }
        return object(Data(text.utf8))
    }

    /// A whole number from JSON. Out-of-range values give nil rather than trapping.
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(exactly: d.rounded(.towardZero)) }
        return nil
    }

    static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }
}
