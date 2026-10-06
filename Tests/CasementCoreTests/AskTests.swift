import Foundation
import Testing
@testable import CasementCore


/// Fake API keys are assembled so the source never holds anything shaped like a real one.
private let sk = "s" + "k-"

@Suite struct SSEParserTests {
    @Test func basicRecords() {
        var p = SSEParser()
        let events = p.feed("event: a\ndata: 1\n\ndata: plain\n\n")
        #expect(events == [SSEEvent(event: "a", data: "1"), SSEEvent(event: "message", data: "plain")])
    }

    @Test func lineEndingsAndMultilineData() {
        var p = SSEParser()
        let events = p.feed("event: x\r\ndata: one\r\ndata: two\r\n\r\ndata:three\rdata:  four\r\r")
        #expect(events == [SSEEvent(event: "x", data: "one\ntwo"), SSEEvent(data: "three\n four")])
    }

    @Test func commentsIdsRetryAndUnknownFields() {
        var p = SSEParser()
        let events = p.feed(": keep-alive\nid: 7\nretry: 3000\nfoo: bar\ndata\ndata: x\n\nevent: only-type\n\n")
        #expect(events == [SSEEvent(data: "\nx", id: "7")])
        #expect(p.retry == 3000)
        // A record with no data dispatches nothing, and its event type doesn't leak into the next.
        #expect(p.feed("data: y\n\n") == [SSEEvent(data: "y", id: "7")])
    }

    @Test func byteOrderMarkIsSkipped() {
        var p = SSEParser()
        #expect(p.feed([0xEF, 0xBB, 0xBF] + Array("data: hi\n\n".utf8)) == [SSEEvent(data: "hi")])
    }

    @Test func splitAtEveryByteGivesTheSameEvents() {
        let raw = Array(AskFixtures.anthropicStream.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        var whole = SSEParser()
        let expected = whole.feed(raw) + whole.finish()
        #expect(expected.count == 12)
        for split in stride(from: 1, to: raw.count, by: 7) {
            var p = SSEParser()
            let got = p.feed(raw[..<split]) + p.feed(raw[split...]) + p.finish()
            #expect(got == expected, "split at \(split)")
        }
        var one = SSEParser()
        var got: [SSEEvent] = []
        for b in raw { got += one.feed([b]) }
        #expect(got + one.finish() == expected)
    }

    @Test func multibyteCharacterSplitAcrossChunks() {
        let bytes = Array("data: café ✓\n\n".utf8)
        var p = SSEParser()
        let cut = bytes.firstIndex(of: 0xC3)! + 1
        #expect(p.feed(bytes[..<cut]).isEmpty)
        #expect(p.feed(bytes[cut...]) == [SSEEvent(data: "café ✓")])
    }

    @Test func finishDeliversATrailingRecord() {
        var p = SSEParser()
        #expect(p.feed("event: message_stop\ndata: {}").isEmpty)
        #expect(p.finish() == [SSEEvent(event: "message_stop", data: "{}")])
        #expect(p.finish().isEmpty)
    }
}

/// Runs a whole SSE fixture through the parser and a decoder.
func decodeSSE<D: AskStreamDecoder>(_ text: String, _ decoder: D) -> [AskEvent] {
    var parser = SSEParser()
    var d = decoder
    var out: [AskEvent] = []
    for e in parser.feed(text) + parser.finish() { out += d.decode(e) }
    return out + d.finish()
}

func decodeLines<D: AskLineDecoder>(_ text: String, _ decoder: D) -> [AskEvent] {
    var d = decoder
    var out: [AskEvent] = []
    for line in text.split(separator: "\n") { out += d.decode(line: String(line)) }
    return out + d.finish()
}

func joinedText(_ events: [AskEvent]) -> String {
    events.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
}

@Suite struct AnthropicTests {
    @Test func streamsTextAndIgnoresThinking() {
        let events = decodeSSE(AskFixtures.anthropicStream, AnthropicStreamDecoder())
        #expect(joinedText(events) == "A monad is a type that wraps values and lets you chain steps — like Optional’s flatMap.")
        #expect(events.last == .done(AskUsage(model: "claude-opus-5-5", inputTokens: 42, outputTokens: 87, stopReason: "end_turn")))
        #expect(events.filter(\.isTerminal).count == 1)
    }

    @Test func refusalEndsTheAnswer() {
        let events = decodeSSE(AskFixtures.anthropicRefusal, AnthropicStreamDecoder())
        #expect(events.last == .refusal("This request was declined."))
        #expect(events.filter(\.isTerminal).count == 1)
    }

    @Test func serverSideFallbackContinuesTheAnswer() {
        let events = decodeSSE(AskFixtures.anthropicFallback, AnthropicStreamDecoder())
        #expect(joinedText(events) == "Port scanners probe which ports answer.")
        guard case .done(let usage) = events.last else { Issue.record("expected done"); return }
        #expect(usage.outputTokens == 12)
    }

    @Test func streamErrorIsFriendly() {
        let events = decodeSSE(AskFixtures.anthropicOverloaded, AnthropicStreamDecoder())
        #expect(events == [.error("Anthropic is overloaded right now. Try again in a moment.")])
    }

    @Test func maxTokensIsReported() {
        let events = decodeSSE(AskFixtures.anthropicMaxTokens, AnthropicStreamDecoder())
        guard case .done(let usage) = events.last else { Issue.record("expected done"); return }
        #expect(usage.wasCut)
        #expect(usage.model == "claude-haiku-4-5")
    }

    @Test func truncatedStreamIsAnError() {
        let cut = String(AskFixtures.anthropicStream.prefix(900))
        let events = decodeSSE(cut, AnthropicStreamDecoder())
        guard case .error = events.last else { Issue.record("expected error, got \(events)"); return }
    }

    @Test func messagesRequest() throws {
        let r = AnthropicAPI.messages(turns: [.user("Hi")], model: "claude-opus-5-5", effort: .low, key: (sk + "ant-test"))
        #expect(r.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.method == "POST")
        #expect(r.headers["x-api-key"] == (sk + "ant-test"))
        #expect(r.headers["anthropic-version"] == "2023-06-01")
        #expect(r.headers["anthropic-beta"] == "server-side-fallback-2026-07-01")
        #expect(r.headers["content-type"] == "application/json")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body!) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 4096)
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: String])?["effort"] == "low")
        #expect(body["thinking"] == nil)
        #expect((body["system"] as? String)?.contains("notch") == true)
        #expect(body["messages"] as? [[String: String]] == [["role": "user", "content": "Hi"]])
    }

    @Test func followUpsAreSentAsAlternatingMessages() throws {
        let turns: [AskTurn] = [.user("What is 2+2?"), .assistant("4"), .user("And doubled?")]
        let r = AnthropicAPI.messages(turns: turns, model: "claude-sonnet-5-5", effort: .medium, key: "k")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body!) as? [String: Any])
        let roles = (body["messages"] as? [[String: String]])?.map { $0["role"] ?? "" }
        #expect(roles == ["user", "assistant", "user"])
    }

    @Test func modelsRequestAndList() {
        let r = AnthropicAPI.models(key: (sk + "ant-x"))
        #expect(r.method == "GET")
        #expect(r.url.host == "api.anthropic.com")
        #expect(r.url.path == "/v1/models")
        #expect(r.headers == ["x-api-key": (sk + "ant-x"), "anthropic-version": "2023-06-01"])
        #expect(AnthropicAPI.modelIDs(from: Data(AskFixtures.anthropicModels.utf8))
                == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-haiku-4-5-20251001"])
        #expect(AnthropicAPI.modelIDs(from: Data("nope".utf8)).isEmpty)
    }
}

@Suite struct OpenAITests {
    @Test func streamsText() {
        let events = decodeSSE(AskFixtures.openAIStream, OpenAIStreamDecoder())
        #expect(joinedText(events) == "Tokyo is 8 hours ahead of London.")
        #expect(events.last == .done(AskUsage(model: "gpt-6-astra", inputTokens: 51, outputTokens: 19)))
    }

    @Test func refusal() {
        let events = decodeSSE(AskFixtures.openAIRefusal, OpenAIStreamDecoder())
        #expect(events == [.refusal("I can't help with that.")])
    }

    @Test func incompleteAndFailed() {
        let cut = decodeSSE(AskFixtures.openAIIncomplete, OpenAIStreamDecoder())
        guard case .done(let usage) = cut.last else { Issue.record("expected done"); return }
        #expect(usage.stopReason == "max_output_tokens")
        #expect(usage.wasCut)
        #expect(decodeSSE(AskFixtures.openAIFailed, OpenAIStreamDecoder())
                == [.error("OpenAI: The server had an error processing your request.")])
    }

    @Test func responsesRequestNeverStores() throws {
        let r = OpenAIAPI.responses(turns: [.user("Hello")], model: "gpt-6-astra", effort: .low, key: (sk + "test"))
        #expect(r.url.absoluteString == "https://api.openai.com/v1/responses")
        #expect(r.headers["authorization"] == "Bearer sk-test")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body!) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["input"] as? String == "Hello")
        #expect(body["max_output_tokens"] as? Int == 2048)
        #expect((body["reasoning"] as? [String: String])?["effort"] == "low")
        #expect((body["instructions"] as? String)?.isEmpty == false)
        #expect(body["previous_response_id"] == nil)

        let multi = OpenAIAPI.responses(turns: [.user("a"), .assistant("b"), .user("c")], model: "gpt-6-luna", effort: nil, key: "k")
        let mb = try #require(try JSONSerialization.jsonObject(with: multi.body!) as? [String: Any])
        #expect((mb["input"] as? [[String: String]])?.count == 3)
        #expect(mb["reasoning"] == nil)
        #expect(mb["store"] as? Bool == false)
    }

    @Test func modelList() {
        #expect(OpenAIAPI.modelIDs(from: Data(AskFixtures.openAIModels.utf8)) == ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-luna", "o4-mini"])
        let r = OpenAIAPI.models(key: (sk + "x"))
        #expect(r.url.absoluteString == "https://api.openai.com/v1/models")
        #expect(r.headers["authorization"] == "Bearer sk-x")
    }

    @Test func reasoningRejectionIsDetected() {
        let body = Data(#"{"error":{"message":"Unsupported parameter: 'reasoning.effort' is not supported with this model.","type":"invalid_request_error","code":"unsupported_parameter"}}"#.utf8)
        #expect(OpenAIAPI.rejectsReasoning(status: 400, body: body))
        #expect(!OpenAIAPI.rejectsReasoning(status: 401, body: body))
    }
}

@Suite struct AskErrorTextTests {
    @Test func httpStatuses() {
        let empty = Data()
        #expect(AskErrorText.http(status: 401, body: empty, retryAfter: nil, provider: .anthropic)
                == "Anthropic didn’t accept your key.")
        // A new key may fix these, so the island offers the button to it.
        #expect(AskErrorText.isKeyProblem(status: 401) && AskErrorText.isKeyProblem(status: 403))
        #expect(!AskErrorText.isKeyProblem(status: 429) && !AskErrorText.isKeyProblem(status: 500))
        #expect(AskErrorText.http(status: 429, body: empty, retryAfter: "12", provider: .anthropic)
                == "Too many questions at once. Try again in 12 seconds.")
        #expect(AskErrorText.http(status: 429, body: empty, retryAfter: "1", provider: .anthropic)
                == "Too many questions at once. Try again in 1 second.")
        #expect(AskErrorText.http(status: 429, body: empty, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT", provider: .openai)
                == "Too many questions at once. Try again shortly.")
        #expect(AskErrorText.http(status: 529, body: empty, retryAfter: nil, provider: .anthropic)
                == "Anthropic is overloaded right now. Try again in a moment.")
        let quota = Data(#"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#.utf8)
        #expect(AskErrorText.http(status: 429, body: quota, retryAfter: nil, provider: .openai) == "Your OpenAI account has run out of credit.")
        let bad = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: must be positive"}}"#.utf8)
        #expect(AskErrorText.http(status: 400, body: bad, retryAfter: nil, provider: .anthropic)
                == "Anthropic rejected the request: max_tokens: must be positive")
        // Statuses go to the log; the island says what happened in words.
        #expect(AskErrorText.http(status: 503, body: empty, retryAfter: nil, provider: .openai)
                == "OpenAI is having problems right now. Try again in a moment.")
        #expect(AskErrorText.http(status: 418, body: Data(#"{"error":{"message":"I'm a teapot"}}"#.utf8), retryAfter: nil, provider: .openai)
                == "OpenAI couldn\u{2019}t answer: I'm a teapot")
        #expect(AskErrorText.http(status: 418, body: empty, retryAfter: nil, provider: .anthropic) == "Anthropic couldn\u{2019}t answer.")
        for status in [418, 500, 502, 503, 529] {
            #expect(!AskErrorText.http(status: status, body: empty, retryAfter: nil, provider: .anthropic).contains { $0.isNumber })
        }
        #expect(AskErrorText.stream(type: "rate_limit_error", message: nil, provider: .openai) == "Too many questions at once. Try again shortly.")
        #expect(AskErrorText.stream(type: "overloaded_error", message: nil, provider: .anthropic)
                == "Anthropic is overloaded right now. Try again in a moment.")
        let overloaded = Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
        #expect(AskErrorText.isOverloaded(status: 529, body: empty))
        #expect(AskErrorText.isOverloaded(status: 500, body: overloaded))
        #expect(!AskErrorText.isOverloaded(status: 500, body: empty))
    }

    /// Numbers come from the network: absurd ones must be ignored, not crash the app.
    @Test func outOfRangeNumbersAreIgnored() {
        #expect(AskErrorText.retrySeconds("1e300") == nil)
        #expect(AskErrorText.retrySeconds("9223372036854775807") == nil)
        #expect(AskErrorText.retrySeconds("-3") == nil)
        #expect(AskErrorText.retrySeconds("2.5") == 3)
        #expect(AskErrorText.http(status: 429, body: Data(), retryAfter: "1e300", provider: .anthropic) == "Too many questions at once. Try again shortly.")
        #expect(AskJSON.int(1e300) == nil)
        #expect(AskJSON.int(Double.nan) == nil)
        #expect(AskJSON.int(42.0) == 42)
        #expect(AskJSON.int(7) == 7)
        let huge = """
        event: message_start
        data: {"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1e300,"output_tokens":1}}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1e308}}

        event: message_stop
        data: {"type":"message_stop"}


        """
        let events = decodeSSE(huge, AnthropicStreamDecoder())
        #expect(events == [.done(AskUsage(model: "claude-opus-5-5", inputTokens: nil, outputTokens: 1, stopReason: "end_turn"))])
    }
}

@Suite struct AskCLITests {
    @Test func claudeArgumentsMatchTheDesign() {
        let args = AskCLI.claudeArguments(prompt: "What is HTTP/3?", model: nil)
        #expect(args == ["-p", "What is HTTP/3?", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                         "--tools", "", "--max-turns", "1", "--no-session-persistence", "--settings", #"{"disableAllHooks": true}"#])
        // `--tools` takes a list: whatever follows its "" must be another option.
        let i = args.firstIndex(of: "--tools")!
        #expect(args[i + 1] == "")
        #expect(args[i + 2].hasPrefix("--"))
        #expect(!args.contains("--bare"))
        let withModel = AskCLI.claudeArguments(prompt: "-rf means?", model: "sonnet")
        #expect(withModel[1] == " -rf means?")
        #expect(Array(withModel.suffix(2)) == ["--model", "sonnet"])
        #expect(!AskCLI.claudeArguments(prompt: "x", model: "--dangerously-skip-permissions").contains("--dangerously-skip-permissions"))
    }

    @Test func codexArguments() {
        #expect(AskCLI.codexArguments(prompt: "hello", model: nil)
                == ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "hello"])
        #expect(AskCLI.codexArguments(prompt: "--version", model: "gpt-6-luna")
                == ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--model", "gpt-6-luna", " --version"])
    }

    @Test func environmentCarriesNoSecrets() {
        let parent = ["HOME": "/Users/me", "USER": "me", "PATH": "/evil", "ANTHROPIC_API_KEY": (sk + "ant-x"), "OPENAI_API_KEY": (sk + "y"),
                      "CASEMENT_TOKEN": "t", "LANG": "en_GB.UTF-8", "TMPDIR": "/var/folders/x/", "SSH_AUTH_SOCK": "/tmp/s"]
        let env = AskCLI.environment(parent: parent, binaryDirectory: "/Users/me/.local/bin")
        #expect(Set(env.keys) == ["HOME", "USER", "TMPDIR", "LANG", "TERM", "NO_COLOR", "PATH"])
        #expect(env["TERM"] == "dumb")
        #expect(env["LANG"] == "en_GB.UTF-8")
        #expect(env["PATH"]?.hasPrefix("/Users/me/.local/bin:/opt/homebrew/bin:") == true)
        #expect(env["PATH"]?.contains("/evil") == false)
        #expect(AskCLI.environment(parent: [:], binaryDirectory: "/opt/homebrew/bin")["LANG"] == "en_US.UTF-8")
    }

    @Test func searchPaths() {
        #expect(AskCLI.searchPaths(for: .claudeCode, home: "/Users/me")
                == ["/Users/me/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/Users/me/.claude/local/claude"])
        #expect(AskCLI.searchPaths(for: .codex, home: "/h") == ["/h/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        #expect(AskCLI.searchPaths(for: .anthropic, home: "/h").isEmpty)
    }

    @Test func claudeStreamJSON() {
        let events = decodeLines(AskFixtures.claudeCLI, ClaudeCLIDecoder())
        #expect(joinedText(events) == "Use `git switch -c` to create a branch.")
        #expect(events.last == .done(AskUsage(model: "claude-opus-5-5", inputTokens: 3, outputTokens: 14, costUSD: 0.0041, stopReason: "end_turn")))
    }

    @Test func claudeWithoutPartialMessages() {
        let events = decodeLines(AskFixtures.claudeCLINoPartials, ClaudeCLIDecoder())
        #expect(joinedText(events) == "Forty-two.")
        guard case .done(let usage) = events.last else { Issue.record("expected done"); return }
        #expect(usage.costUSD == 0.002)
    }

    @Test func claudeNotLoggedIn() {
        let events = decodeLines(AskFixtures.claudeCLINotLoggedIn, ClaudeCLIDecoder())
        #expect(events.last == .error("Claude Code isn’t signed in. Run claude in Terminal and sign in."))
        #expect(events.filter(\.isTerminal).count == 1)
    }

    @Test func claudeIgnoresNoise() {
        var d = ClaudeCLIDecoder()
        #expect(d.decode(line: "").isEmpty)
        #expect(d.decode(line: "Warning: something on stdout").isEmpty)
        #expect(d.decode(line: "{\"type\":\"user\"}").isEmpty)
        #expect(d.finish().isEmpty)
    }

    @Test func codexJSONL() {
        let events = decodeLines(AskFixtures.codex, CodexDecoder())
        #expect(events == [.text("`date -u` prints the time in UTC."), .done(AskUsage(inputTokens: 2604, outputTokens: 27))])
    }

    @Test func codexRecoversAndJoinsMessages() {
        let events = decodeLines(AskFixtures.codexRetried, CodexDecoder())
        #expect(joinedText(events) == "First part.\n\nSecond part.")
        guard case .done = events.last else { Issue.record("expected done, got \(events)"); return }
    }

    @Test func codexFailure() {
        let events = decodeLines(AskFixtures.codexFailed, CodexDecoder())
        #expect(events == [.error("Codex isn’t signed in. Run codex in Terminal and sign in.")])
        var d = CodexDecoder()
        _ = d.decode(line: #"{"type":"error","message":"model overloaded"}"#)
        #expect(d.finish() == [.error("Codex: model overloaded")])
    }

    @Test func failureText() {
        #expect(AskCLI.failureText(kind: .claudeCode, status: 1, stderr: "error: unknown option '--no-session-persistence'\n")
                == "Claude Code is too old for Casement. Update it and try again.")
        #expect(AskCLI.failureText(kind: .codex, status: 2, stderr: "\n  boom  \nmore") == "Codex: boom")
        #expect(AskCLI.failureText(kind: .codex, status: 9, stderr: "") == "Codex stopped before answering. Try again.")
        #expect(AskCLI.firstLine("\n  boom  \nmore") == "boom")
        #expect(ClaudeCLIDecoder.errorText(result: nil, subtype: "error_during_execution") == "Claude Code stopped with an error. Try again.")
    }
}

@Suite struct AskConversationTests {
    @Test func normalizedDropsBlanksMergesAndCaps() {
        let turns: [AskTurn] = [.assistant("stray"), .user("  "), .user("a"), .user("b"), .assistant("c"), .assistant(""), .user("d"), .assistant("trailing")]
        #expect(AskPrompt.normalized(turns) == [.user("a\n\nb"), .assistant("c"), .user("d")])
        var long: [AskTurn] = []
        for i in 0..<10 { long += [.user("q\(i)"), .assistant("a\(i)")] }
        long.append(.user("last"))
        let capped = AskPrompt.normalized(long)
        #expect(capped.count == 7)
        #expect(capped.first == .user("q7"))
        #expect(capped.last == .user("last"))
    }

    @Test func flattenedForCLIs() {
        #expect(AskPrompt.flattened([.user("Hi")]) == "Hi")
        #expect(AskPrompt.flattened([.user("Hi")], instructions: "Be brief.") == "Be brief.\n\nHi")
        #expect(AskPrompt.flattened([.user("2+2?"), .assistant("4"), .user("times 3?")])
                == "Earlier in this conversation:\nUser: 2+2?\nAssistant: 4\n\nQuestion: times 3?")
    }

    @Test func answerBufferCaps() {
        var a = AskAnswer()
        a.append(String(repeating: "x", count: AskLimits.shownBytes - 1))
        a.append("éé")
        #expect(a.shown.utf8.count <= AskLimits.shownBytes)
        #expect(a.isTrimmed)
        #expect(a.text.hasSuffix("éé"))
        #expect(!a.isCut)
        a.append(String(repeating: "y", count: AskLimits.keptBytes))
        #expect(a.text.utf8.count == AskLimits.keptBytes)
        #expect(a.isCut)
        a.reset()
        #expect(a.isEmpty && !a.isTrimmed)
    }

    @Test func coalescerPublishesAtMostTwentyTimesASecond() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var c = AskCoalescer()
        #expect(c.add("a", now: t0) == "a")
        #expect(c.add("b", now: t0.addingTimeInterval(0.01)) == nil)
        #expect(c.add("c", now: t0.addingTimeInterval(0.02)) == nil)
        #expect(abs(c.delay(now: t0.addingTimeInterval(0.02)) - 0.03) < 0.0001)
        #expect(c.add("d", now: t0.addingTimeInterval(0.06)) == "bcd")
        #expect(c.add("e", now: t0.addingTimeInterval(0.07)) == nil)
        #expect(c.flush(now: t0.addingTimeInterval(0.08)) == "e")
        #expect(c.pending.isEmpty)
    }
}

@Suite struct AskSettingsTests {
    @Test func defaults() {
        let s = CasementSettings()
        #expect(s.ask.provider == .onDevice)
        #expect(s.ask.effort == .low)
        #expect(!s.ask.followUps)
        #expect(s.ask.model(for: .anthropic) == "claude-opus-5-5")
        #expect(s.ask.model(for: .openai) == "gpt-6-astra")
        #expect(s.ask.model(for: .onDevice) == nil)
        #expect(s.ask.model(for: .claudeCode) == nil)
    }

    @Test func oldConfigWithoutAskStillLoads() {
        let s = CasementSettings.decodeLenient(Data(#"{"hoverToOpen": false}"#.utf8))
        #expect(s.hoverToOpen == false)
        #expect(s.ask == AskSettings())
    }

    @Test func partialAndBadAskValuesFallBackPerField() {
        let json = #"{"ask": {"provider": "anthropic", "effort": "extreme", "models": {"openai": "gpt-6-luna", "anthropic": "\#(sk)ant-oops", "bogus": "x", "codex": "--yolo"}, "apiKey": "\#(sk)ant-secret"}}"#
        let s = CasementSettings.decodeLenient(Data(json.utf8))
        #expect(s.ask.provider == .anthropic)
        #expect(s.ask.effort == .low)
        #expect(s.ask.models == ["openai": "gpt-6-luna"])
        #expect(s.ask.model(for: .anthropic) == "claude-opus-5-5")
        let saved = String(decoding: try! JSONEncoder().encode(s), as: UTF8.self)
        #expect(!saved.contains("secret"))
        #expect(!saved.contains("apiKey"))
    }

    @Test func roundTripAndSetModel() throws {
        var s = CasementSettings()
        s.ask.provider = .codex
        s.ask.followUps = true
        s.ask.setModel("gpt-6-luna", for: .codex)
        s.ask.setModel("  ", for: .anthropic)
        s.ask.setModel("two words", for: .openai)
        #expect(s.ask.models == ["codex": "gpt-6-luna"])
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(CasementSettings.self, from: data) == s)
        #expect(CasementSettings.decodeLenient(data) == s)
    }
}

@Suite struct AskMiscTests {
    @Test func urlCommand() throws {
        func parse(_ s: String) throws -> URLCommand { try URLCommand.parse(URL(string: s)!) }
        #expect(try parse("casement://ask?q=What%20is%20a%20monad&provider=claude") == .ask(query: "What is a monad", provider: .anthropic))
        #expect(try parse("casement://ask") == .ask(query: nil, provider: nil))
        #expect(try parse("casement://ask?q=%20%20&provider=chatgpt") == .ask(query: nil, provider: .openai))
        #expect(try parse("casement://ask?text=hi&provider=claude-code") == .ask(query: "hi", provider: .claudeCode))
        #expect(try parse("casement://ask?q=x&provider=on-device") == .ask(query: "x", provider: .onDevice))
        #expect(throws: URLCommand.ParseError.invalid("provider", "skynet")) { try parse("casement://ask?q=x&provider=skynet") }
        let long = String(repeating: "a", count: 5000)
        guard case .ask(let q, _) = try parse("casement://ask?q=\(long)") else { Issue.record("expected ask"); return }
        #expect(q?.count == AskLimits.questionCharacters)
    }

    @Test func providers() {
        #expect(AskProviderKind.allCases.filter(\.leavesMac) == [.anthropic, .openai, .claudeCode, .codex])
        #expect(AskProviderKind.allCases.compactMap(\.keyAccount) == ["anthropic", "openai"])
        #expect(AskProviderKind(alias: "OpenAI") == .openai)
        #expect(AskProviderKind(alias: "claude_code") == .claudeCode)
        #expect(AskProviderKind(alias: "") == nil)
        // Plain words; the button under the hint goes to the key.
        #expect(AskProviderStatus.needsKey.message(for: .openai) == "ChatGPT needs your OpenAI key.")
        #expect(AskProviderStatus.needsKey.message(for: .anthropic) == "Claude needs your Anthropic key.")
        #expect(AskProviderStatus.ready.message(for: .anthropic) == "Your question goes to Anthropic. Nothing is saved on this Mac.")
        #expect(AskProviderStatus.notInstalled.message(for: .claudeCode) == "Claude Code isn’t installed. Install it, then try again.")
        // Folder paths belong in Advanced → Diagnostics, not in the Ask box.
        #expect(!AskProviderStatus.notInstalled.message(for: .codex).contains("/"))
        #expect(AskProviderStatus.unavailable(AskProviderStatus.onDeviceReason("modelNotReady")).message(for: .onDevice)
                == "Apple Intelligence is still downloading. Choose another model from the menu.")
        // What the island shows is for everyone: no API talk, no straight apostrophes.
        for kind in AskProviderKind.allCases {
            for status in [AskProviderStatus.ready, .needsKey, .notInstalled, .unavailable(AskProviderStatus.onDeviceReason("x"))] {
                let text = status.message(for: kind)
                #expect(!text.contains("API") && !text.contains("'"), "\(text)")
            }
        }
    }

    @Test func keys() {
        #expect(AskKeys.looksValid((sk + "ant-api03-") + String(repeating: "a", count: 40), for: .anthropic))
        #expect(!AskKeys.looksValid((sk + "proj-") + String(repeating: "a", count: 40), for: .anthropic))
        #expect(AskKeys.looksValid((sk + "proj-") + String(repeating: "a", count: 40), for: .openai))
        #expect(!AskKeys.looksValid((sk + "ant-short"), for: .anthropic))
        #expect(!AskKeys.looksValid((sk + "ant-api03-has space") + String(repeating: "a", count: 20), for: .anthropic))
        #expect(!AskKeys.looksValid((sk + "") + String(repeating: "a", count: 40), for: .claudeCode))
        #expect(AskKeys.normalized("  sk-abc\n") == (sk + "abc"))
        #expect(AskKeys.masked((sk + "ant-api03-xyz1234")) == "•••• 1234")
    }
}
