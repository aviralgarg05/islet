import Foundation

/// A ready-to-send HTTP request (IsletSystem turns it into a `URLRequest`).
public struct AskHTTPRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// Turns SSE records from one API into `AskEvent`s. Stateful: create one per answer.
public protocol AskStreamDecoder {
    mutating func decode(_ event: SSEEvent) -> [AskEvent]
    /// The stream ended. Returns a terminal event if none was seen.
    mutating func finish() -> [AskEvent]
}

/// Turns stdout lines from a CLI into `AskEvent`s. Stateful: create one per answer.
public protocol AskLineDecoder {
    mutating func decode(line: String) -> [AskEvent]
    mutating func finish() -> [AskEvent]
}

// MARK: - Anthropic

/// Anthropic Messages API (raw HTTP; there is no Swift SDK).
public enum AnthropicAPI {
    public static let host = "api.anthropic.com"
    public static let version = "2023-06-01"
    /// Beta header for `"fallbacks": "default"`: a request the model declines is re-run
    /// server-side on Anthropic's recommended fallback model.
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let defaultModel = "claude-opus-5-5"
    public static let knownModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"]
    public static let maxTokens = 4096

    /// Streaming Messages request. `thinking` is left out on purpose: Opus 5.5 always thinks,
    /// and disabling it is a 400. Effort keeps that thinking short.
    public static func messages(turns: [AskTurn], model: String, effort: AskEffort, key: String,
                                system: String = AskPrompt.system) -> AskHTTPRequest {
        let messages = AskPrompt.normalized(turns).map { ["role": $0.role.rawValue, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "output_config": ["effort": effort.rawValue],
            "fallbacks": "default",
            "system": system,
            "messages": messages,
        ]
        return AskHTTPRequest(
            url: URL(string: "https://\(host)/v1/messages")!, method: "POST",
            headers: [
                "x-api-key": key,
                "anthropic-version": version,
                "anthropic-beta": fallbackBeta,
                "content-type": "application/json",
                "accept": "text/event-stream",
            ],
            body: AskJSON.encode(body)
        )
    }

    /// Model list. Also the cheapest way to check that a pasted key works.
    public static func models(key: String) -> AskHTTPRequest {
        AskHTTPRequest(url: URL(string: "https://\(host)/v1/models?limit=100")!,
                       headers: ["x-api-key": key, "anthropic-version": version])
    }

    /// Claude model ids from a `/v1/models` response: the known ones first, then the rest as listed.
    public static func modelIDs(from data: Data) -> [String] {
        guard let obj = AskJSON.object(data), let list = obj["data"] as? [[String: Any]] else { return [] }
        let ids = list.compactMap { $0["id"] as? String }.filter { $0.hasPrefix("claude-") }
        return AskModelList.ordered(ids, known: knownModels)
    }
}

/// Decodes Anthropic's Messages stream: `message_start`, `content_block_*`, `message_delta`,
/// `message_stop`, `ping`, `error`. Only `text_delta` becomes text; thinking, signature and
/// fallback blocks are ignored. After a server-side fallback the answer simply continues.
public struct AnthropicStreamDecoder: AskStreamDecoder {
    private var usage = AskUsage()
    private var finished = false

    public init() {}

    public mutating func decode(_ event: SSEEvent) -> [AskEvent] {
        guard !finished, let obj = AskJSON.object(event.data) else { return [] }
        switch obj["type"] as? String ?? event.event {
        case "message_start":
            let message = obj["message"] as? [String: Any]
            if let m = message?["model"] as? String { usage.model = m }
            if let u = message?["usage"] as? [String: Any] {
                usage.inputTokens = AskJSON.int(u["input_tokens"]) ?? usage.inputTokens
                usage.outputTokens = AskJSON.int(u["output_tokens"]) ?? usage.outputTokens
            }
        case "content_block_start":
            if let block = obj["content_block"] as? [String: Any], block["type"] as? String == "text",
               let text = block["text"] as? String, !text.isEmpty {
                return [.text(text)]
            }
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String, !text.isEmpty {
                return [.text(text)]
            }
        case "message_delta":
            let delta = obj["delta"] as? [String: Any]
            if let reason = delta?["stop_reason"] as? String { usage.stopReason = reason }
            if let u = obj["usage"] as? [String: Any] {
                usage.outputTokens = AskJSON.int(u["output_tokens"]) ?? usage.outputTokens
                usage.inputTokens = AskJSON.int(u["input_tokens"]) ?? usage.inputTokens
            }
            if usage.stopReason == "refusal" {
                finished = true
                let details = delta?["stop_details"] as? [String: Any]
                return [.refusal(details?["explanation"] as? String)]
            }
        case "message_stop":
            finished = true
            return [.done(usage)]
        case "error":
            finished = true
            let err = obj["error"] as? [String: Any]
            return [.error(AskErrorText.stream(type: err?["type"] as? String, message: err?["message"] as? String, provider: .anthropic))]
        default:
            break
        }
        return []
    }

    public mutating func finish() -> [AskEvent] {
        guard !finished else { return [] }
        finished = true
        return [.error("The answer stopped before it finished. Try again.")]
    }
}

// MARK: - OpenAI

/// OpenAI Responses API. `store` is always false: by default OpenAI keeps responses for 30 days.
public enum OpenAIAPI {
    public static let host = "api.openai.com"
    public static let defaultModel = "gpt-6-astra"
    public static let knownModels = ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-luna"]
    public static let maxOutputTokens = 2048

    /// Streaming Responses request. With `store: false` nothing can be chained by id, so
    /// follow-ups re-send the earlier turns in `input`.
    public static func responses(turns: [AskTurn], model: String, effort: AskEffort?, key: String,
                                 instructions: String = AskPrompt.system) -> AskHTTPRequest {
        let turns = AskPrompt.normalized(turns)
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "stream": true,
            "store": false,
            "max_output_tokens": maxOutputTokens,
        ]
        if turns.count == 1 {
            body["input"] = turns[0].text
        } else {
            body["input"] = turns.map { ["role": $0.role.rawValue, "content": $0.text] }
        }
        if let effort { body["reasoning"] = ["effort": effort.rawValue] }
        return AskHTTPRequest(
            url: URL(string: "https://\(host)/v1/responses")!, method: "POST",
            headers: [
                "authorization": "Bearer \(key)",
                "content-type": "application/json",
                "accept": "text/event-stream",
            ],
            body: AskJSON.encode(body)
        )
    }

    public static func models(key: String) -> AskHTTPRequest {
        AskHTTPRequest(url: URL(string: "https://\(host)/v1/models")!, headers: ["authorization": "Bearer \(key)"])
    }

    /// Chat-capable model ids from `/v1/models` (embeddings, audio, image and moderation models
    /// are left out), known ones first.
    public static func modelIDs(from data: Data) -> [String] {
        guard let obj = AskJSON.object(data), let list = obj["data"] as? [[String: Any]] else { return [] }
        let skip = ["embedding", "tts", "whisper", "audio", "realtime", "transcribe", "image", "moderation", "dall-e", "search"]
        let ids = list.compactMap { $0["id"] as? String }.filter { id in
            let isChat = id.hasPrefix("gpt-") || id.hasPrefix("chatgpt-") || id.range(of: #"^o\d"#, options: .regularExpression) != nil
            return isChat && !skip.contains { id.contains($0) }
        }
        return AskModelList.ordered(ids.sorted(by: >), known: knownModels)
    }

    /// A 400 caused by `reasoning.effort` on a model without reasoning; retried without it.
    public static func rejectsReasoning(status: Int, body: Data) -> Bool {
        status == 400 && (AskErrorText.message(in: body)?.lowercased().contains("reasoning") ?? false)
    }
}

/// Decodes the Responses stream: `response.output_text.delta` is text; `response.refusal.*`,
/// `response.completed`, `response.incomplete`, `response.failed` and `error` end it.
public struct OpenAIStreamDecoder: AskStreamDecoder {
    private var refusal = ""
    private var finished = false

    public init() {}

    public mutating func decode(_ event: SSEEvent) -> [AskEvent] {
        guard !finished, let obj = AskJSON.object(event.data) else { return [] }
        switch obj["type"] as? String ?? event.event {
        case "response.output_text.delta":
            if let d = obj["delta"] as? String, !d.isEmpty { return [.text(d)] }
        case "response.refusal.delta":
            refusal += obj["delta"] as? String ?? ""
        case "response.refusal.done":
            finished = true
            let text = (obj["refusal"] as? String) ?? refusal
            return [.refusal(text.isEmpty ? nil : String(text.prefix(300)))]
        case "response.completed":
            finished = true
            return [.done(Self.usage(obj["response"] as? [String: Any]))]
        case "response.incomplete":
            finished = true
            let response = obj["response"] as? [String: Any]
            var usage = Self.usage(response)
            let details = response?["incomplete_details"] as? [String: Any]
            usage.stopReason = details?["reason"] as? String ?? "incomplete"
            if usage.stopReason == "content_filter" { return [.refusal(nil)] }
            return [.done(usage)]
        case "response.failed":
            finished = true
            let err = (obj["response"] as? [String: Any])?["error"] as? [String: Any]
            return [.error(AskErrorText.stream(type: err?["code"] as? String, message: err?["message"] as? String, provider: .openai))]
        case "error":
            finished = true
            let nested = obj["error"] as? [String: Any]
            let message = obj["message"] as? String ?? nested?["message"] as? String
            let code = obj["code"] as? String ?? nested?["code"] as? String
            return [.error(AskErrorText.stream(type: code, message: message, provider: .openai))]
        default:
            break
        }
        return []
    }

    public mutating func finish() -> [AskEvent] {
        guard !finished else { return [] }
        finished = true
        return [.error("The answer stopped before it finished. Try again.")]
    }

    static func usage(_ response: [String: Any]?) -> AskUsage {
        let u = response?["usage"] as? [String: Any]
        return AskUsage(model: response?["model"] as? String, inputTokens: AskJSON.int(u?["input_tokens"]),
                        outputTokens: AskJSON.int(u?["output_tokens"]))
    }
}

enum AskModelList {
    /// Known models first (in their order, when present), then the others without duplicates.
    static func ordered(_ ids: [String], known: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in known where ids.contains(id) && seen.insert(id).inserted { out.append(id) }
        for id in ids where seen.insert(id).inserted { out.append(id) }
        return out
    }
}
