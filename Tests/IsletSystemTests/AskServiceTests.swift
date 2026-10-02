import Foundation
import IsletCore
import Testing
@testable import IsletSystem

/// Serves scripted replies for api.anthropic.com / api.openai.com inside the test process, so
/// the real URLSession path (headers, streaming bytes, status handling) runs without a network.
/// Replies are keyed by the API key a request carries, so tests can run in parallel.
final class MockAPI: URLProtocol {
    struct Reply {
        var status = 200
        var headers = ["content-type": "text/event-stream"]
        var body: String
        var chunkSize = 37
        var chunkDelay: TimeInterval = 0
    }

    struct Seen {
        var request: URLRequest
        var body: Data
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
    }

    private static let lock = NSLock()
    private static var replies: [String: [Reply]] = [:]
    private static var seen: [String: [Seen]] = [:]
    private static var stopped: Set<String> = []
    private let queue = DispatchQueue(label: "mock-api")
    private var isStopped = false

    static func script(_ key: String, _ list: [Reply]) { lock.withLock { replies[key] = list } }
    static func requests(_ key: String) -> [Seen] { lock.withLock { seen[key] ?? [] } }
    static func wasStopped(_ key: String) -> Bool { lock.withLock { stopped.contains(key) } }

    static func key(of r: URLRequest) -> String {
        r.value(forHTTPHeaderField: "x-api-key") ?? r.value(forHTTPHeaderField: "authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = Self.key(of: request)
        let body = Self.body(of: request)
        let reply: Reply? = Self.lock.withLock {
            Self.seen[key, default: []].append(Seen(request: request, body: body))
            guard var list = Self.replies[key], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            Self.replies[key] = list
            return first
        }
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = Data(reply.body.utf8)
        queue.async { [self] in
            var offset = 0
            while offset < data.count {
                if lockedStopped { return }
                let end = min(data.count, offset + reply.chunkSize)
                client?.urlProtocol(self, didLoad: data[offset..<end])
                offset = end
                if reply.chunkDelay > 0 { Thread.sleep(forTimeInterval: reply.chunkDelay) }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var lockedStopped: Bool { Self.lock.withLock { isStopped } }

    override func stopLoading() {
        let key = Self.key(of: request)
        Self.lock.withLock {
            isStopped = true
            Self.stopped.insert(key)
        }
    }

    static func body(of r: URLRequest) -> Data {
        if let b = r.httpBody { return b }
        guard let stream = r.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-ask-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func makeService(keys: [String: String] = [:], _ configure: (inout AskService.Configuration) -> Void = { _ in }) -> AskService {
    let dir = tempDir()
    var c = AskService.Configuration(home: dir.path, workingDirectory: dir.appendingPathComponent("ask"),
                                     parentEnvironment: ["HOME": dir.path, "ANTHROPIC_API_KEY": (sk + "ant-from-parent"), "ISLET_TOKEN": "tok"])
    c.protocolClasses = [MockAPI.self]
    configure(&c)
    return AskService(secrets: MemorySecretStore(keys), configuration: c)
}

/// Close the session and remove the service's temporary home.
func cleanUp(_ service: AskService) {
    service.invalidate()
    try? FileManager.default.removeItem(atPath: service.config.home)
}

func collect(_ service: AskService, _ request: AskRequest) async -> [AskEvent] {
    var out: [AskEvent] = []
    do {
        for try await e in service.stream(request) { out.append(e) }
    } catch {
        out.append(.error("thrown: \(error)"))
    }
    return out
}

func text(_ events: [AskEvent]) -> String {
    events.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
}

let anthropicSSE = """
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":12,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Paris is the "}}

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"capital of France."}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}

event: message_stop
data: {"type":"message_stop"}


""".replacingOccurrences(of: "\n", with: "\r\n")

let openAISSE = """
event: response.created
data: {"type":"response.created","response":{"id":"r","status":"in_progress","model":"gpt-6-astra"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Hello"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":" there"}

event: response.completed
data: {"type":"response.completed","response":{"id":"r","status":"completed","model":"gpt-6-astra","usage":{"input_tokens":5,"output_tokens":2}}}


"""


/// Fake API keys are assembled so the source never holds anything shaped like a real one.
private let sk = "s" + "k-"

@Suite struct AskHTTPTests {
    @Test func anthropicStreamsThroughURLSession() async throws {
        let key = (sk + "ant-api03-test-\(UUID().uuidString)")
        MockAPI.script(key, [MockAPI.Reply(body: anthropicSSE)])
        let service = makeService(keys: ["anthropic": key])
        defer { cleanUp(service) }
        let events = await collect(service, AskRequest(provider: .anthropic, model: "claude-opus-5-5", effort: .low, turns: [.user("Capital of France?")]))
        #expect(text(events) == "Paris is the capital of France.")
        #expect(events.last == .done(AskUsage(model: "claude-opus-5-5", inputTokens: 12, outputTokens: 9, stopReason: "end_turn")))

        let seen = try #require(MockAPI.requests(key).first)
        #expect(seen.request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(seen.request.httpMethod == "POST")
        #expect(seen.request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(seen.request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(seen.request.value(forHTTPHeaderField: "cookie") == nil)
        #expect(seen.json["fallbacks"] as? String == "default")
        #expect(seen.json["thinking"] == nil)
        #expect((seen.json["output_config"] as? [String: String])?["effort"] == "low")
    }

    @Test func openAIStreamsAndNeverStores() async throws {
        let key = (sk + "test-\(UUID().uuidString)")
        MockAPI.script(key, [MockAPI.Reply(body: openAISSE, chunkSize: 5)])
        let service = makeService(keys: ["openai": key])
        defer { cleanUp(service) }
        let events = await collect(service, AskRequest(provider: .openai, turns: [.user("Hi")]))
        #expect(text(events) == "Hello there")
        #expect(events.last == .done(AskUsage(model: "gpt-6-astra", inputTokens: 5, outputTokens: 2)))
        let seen = try #require(MockAPI.requests(key).first)
        #expect(seen.request.value(forHTTPHeaderField: "authorization") == "Bearer \(key)")
        #expect(seen.json["store"] as? Bool == false)
        #expect(seen.json["model"] as? String == "gpt-6-astra")
    }

    @Test func httpErrorsAreFriendly() async {
        let key = (sk + "ant-api03-test-\(UUID().uuidString)")
        MockAPI.script(key, [
            MockAPI.Reply(status: 401, headers: ["content-type": "application/json"], body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#),
            MockAPI.Reply(status: 429, headers: ["retry-after": "7"], body: #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#),
        ])
        let service = makeService(keys: ["anthropic": key])
        defer { cleanUp(service) }
        let request = AskRequest(provider: .anthropic, turns: [.user("x")])
        #expect(await collect(service, request) == [.needsKey("Anthropic didn’t accept your key.")])
        #expect(await collect(service, request) == [.error("Too many questions at once. Try again in 7 seconds.")])
    }

    @Test func overloadIsRetriedOnce() async {
        let key = (sk + "ant-api03-test-\(UUID().uuidString)")
        let overloaded = MockAPI.Reply(status: 529, headers: [:], body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        MockAPI.script(key, [overloaded, MockAPI.Reply(body: anthropicSSE), overloaded, overloaded])
        let service = makeService(keys: ["anthropic": key])
        defer { cleanUp(service) }
        let request = AskRequest(provider: .anthropic, turns: [.user("x")])
        #expect(text(await collect(service, request)) == "Paris is the capital of France.")
        #expect(MockAPI.requests(key).count == 2)
        #expect(await collect(service, request) == [.error("Anthropic is overloaded right now. Try again in a moment.")])
        #expect(MockAPI.requests(key).count == 4)
    }

    @Test func openAIRetriesWithoutReasoningWhenTheModelHasNone() async throws {
        let key = (sk + "test-\(UUID().uuidString)")
        MockAPI.script(key, [
            MockAPI.Reply(status: 400, headers: [:], body: #"{"error":{"message":"Unsupported parameter: 'reasoning.effort' is not supported with this model.","type":"invalid_request_error","code":"unsupported_parameter"}}"#),
            MockAPI.Reply(body: openAISSE),
        ])
        let service = makeService(keys: ["openai": key])
        defer { cleanUp(service) }
        let events = await collect(service, AskRequest(provider: .openai, model: "gpt-6-luna", turns: [.user("x")]))
        #expect(text(events) == "Hello there")
        let seen = MockAPI.requests(key)
        #expect(seen.count == 2)
        #expect(seen[0].json["reasoning"] != nil)
        #expect(seen[1].json["reasoning"] == nil)
    }

    @Test func missingKeySendsNothing() async {
        let service = makeService()
        defer { cleanUp(service) }
        #expect(await collect(service, AskRequest(provider: .anthropic, turns: [.user("x")]))
                == [.needsKey("Claude needs your Anthropic key.")])
        #expect(service.status(of: .anthropic) == .needsKey)
        #expect(service.status(of: .openai) == .needsKey)
    }

    @Test func stoppingClosesTheStream() async {
        let key = (sk + "ant-api03-test-\(UUID().uuidString)")
        MockAPI.script(key, [MockAPI.Reply(body: anthropicSSE, chunkSize: 40, chunkDelay: 0.05)])
        let service = makeService(keys: ["anthropic": key])
        defer { cleanUp(service) }
        let task = Task { () -> [AskEvent] in
            var out: [AskEvent] = []
            for try await e in service.stream(AskRequest(provider: .anthropic, turns: [.user("x")])) {
                out.append(e)
                if case .text = e { break }
            }
            return out
        }
        let events = (try? await task.value) ?? []
        #expect(events.count == 1)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(MockAPI.wasStopped(key))
    }

    @Test func keysAreCheckedBeforeTheyAreStored() async throws {
        let key = (sk + "ant-api03-test-\(UUID().uuidString)")
        let models = #"{"data":[{"type":"model","id":"claude-sonnet-5-5"},{"type":"model","id":"claude-opus-5-5"}],"has_more":false}"#
        MockAPI.script(key, [MockAPI.Reply(headers: ["content-type": "application/json"], body: models)])
        let service = makeService()
        defer { cleanUp(service) }
        #expect(try await service.validateAndStore(key: "  \(key)\n", for: .anthropic) == ["claude-opus-5-5", "claude-sonnet-5-5"])
        #expect(service.secrets.read("anthropic") == key)
        #expect(service.maskedKey(for: .anthropic) == "•••• " + String(key.suffix(4)))
        let seen = try #require(MockAPI.requests(key).first)
        #expect(seen.request.url?.path == "/v1/models")
        #expect(seen.request.httpMethod == "GET")

        let bad = (sk + "ant-api03-test-\(UUID().uuidString)")
        MockAPI.script(bad, [MockAPI.Reply(status: 401, headers: [:], body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)])
        await #expect(throws: AskServiceError("Anthropic didn’t accept your key.")) {
            try await service.validateAndStore(key: bad, for: .anthropic)
        }
        #expect(service.secrets.read("anthropic") == key)

        await #expect(throws: AskServiceError.self) { try await service.validateAndStore(key: "hello", for: .openai) }
        #expect(MockAPI.requests("hello").isEmpty)
        try service.removeKey(for: .anthropic)
        #expect(service.maskedKey(for: .anthropic) == nil)
    }

    @Test func onlyTheTwoAPIHostsOverHTTPS() {
        #expect(AskService.isAllowed(URL(string: "https://api.anthropic.com/v1/messages")!))
        #expect(AskService.isAllowed(URL(string: "https://api.openai.com/v1/responses")!))
        #expect(!AskService.isAllowed(URL(string: "http://api.anthropic.com/v1/messages")!))
        #expect(!AskService.isAllowed(URL(string: "https://api.anthropic.com:8443/v1/messages")!))
        #expect(!AskService.isAllowed(URL(string: "https://evil.example/v1/messages")!))
        #expect(!AskService.isAllowed(URL(string: "https://api.anthropic.com.evil.example/")!))
    }

    @Test func sessionKeepsNothingAndRefusesRedirects() {
        let service = makeService()
        defer { cleanUp(service) }
        let c = service.sessionConfiguration
        #expect(c.urlCache == nil)
        #expect(c.httpCookieStorage == nil)
        #expect(c.urlCredentialStorage == nil)
        #expect(!c.httpShouldSetCookies)
        #expect(c.timeoutIntervalForRequest == 30)
        #expect(c.timeoutIntervalForResource == 120)
        var followed: URLRequest? = URLRequest(url: URL(string: "https://example.com")!)
        let task = URLSession.shared.dataTask(with: URL(string: "https://api.anthropic.com")!)
        service.urlSession(URLSession.shared, task: task,
                           willPerformHTTPRedirection: HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: 307, httpVersion: nil, headerFields: nil)!,
                           newRequest: URLRequest(url: URL(string: "https://evil.example")!)) { followed = $0 }
        #expect(followed == nil)
    }
}

/// Fake `claude` / `codex` executables that replay recorded output. The real CLIs never run.
@Suite struct AskCLIRunTests {
    func fakeCLI(_ name: String, script: String) throws -> (URL, URL) {
        let dir = tempDir()
        let url = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return (url, dir)
    }

    static let claudeLines = """
    {"type":"system","subtype":"init","session_id":"s","tools":[],"model":"claude-opus-5-5"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi "}}}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"there"}}}
    {"type":"result","subtype":"success","is_error":false,"result":"Hi there","total_cost_usd":0.001,"usage":{"input_tokens":3,"output_tokens":2}}
    """

    @Test func claudeRunsIsolated() async throws {
        let log = tempDir().appendingPathComponent("log.txt")
        defer { try? FileManager.default.removeItem(at: log.deletingLastPathComponent()) }
        let (exe, bin) = try fakeCLI("claude", script: """
        {
          echo "pwd=$(pwd)"
          echo "term=$TERM"
          echo "key=${ANTHROPIC_API_KEY:-none}"
          echo "token=${ISLET_TOKEN:-none}"
          if read -r line; then echo "stdin=data"; else echo "stdin=closed"; fi
          for a in "$@"; do echo "arg=[$a]"; done
        } > '\(log.path)'
        cat <<'EOF'
        \(Self.claudeLines)
        EOF
        """)
        let service = makeService { $0.binaryOverrides = [.claudeCode: exe] }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        #expect(service.status(of: .claudeCode) == .ready)
        let events = await collect(service, AskRequest(provider: .claudeCode, turns: [.user("-v means?")]))
        #expect(text(events) == "Hi there")
        guard case .done(let usage) = events.last else { Issue.record("expected done, got \(events)"); return }
        #expect(usage.costUSD == 0.001)

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        // The empty working folder (/var is a symlink to /private/var, so compare the tail).
        let folder = service.config.workingDirectory
        #expect(lines.contains { $0.hasPrefix("pwd=") && $0.hasSuffix("/\(folder.deletingLastPathComponent().lastPathComponent)/ask") })
        #expect(lines.contains("term=dumb"))
        #expect(lines.contains("key=none"))
        #expect(lines.contains("token=none"))
        #expect(lines.contains("stdin=closed"))
        #expect(lines.contains("arg=[-p]"))
        #expect(lines.contains("arg=[]"))  // --tools ""
        #expect(lines.contains(#"arg=[{"disableAllHooks": true}]"#))
        // The prompt follows -p: the short-answer instructions, then the question on its last line.
        let p = try #require(lines.firstIndex(of: "arg=[-p]"))
        #expect(lines[p + 1].hasPrefix("arg=[Answer briefly"))
        #expect(lines.contains("-v means?]"))
    }

    @Test func codexReplays() async throws {
        let (exe, bin) = try fakeCLI("codex", script: """
        cat <<'EOF'
        {"type":"thread.started","thread_id":"t"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Done."}}
        {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":2}}
        EOF
        """)
        let service = makeService { $0.binaryOverrides = [.codex: exe] }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        let events = await collect(service, AskRequest(provider: .codex, turns: [.user("x")]))
        #expect(events == [.text("Done."), .done(AskUsage(inputTokens: 10, outputTokens: 2))])
    }

    @Test func failureUsesStderr() async throws {
        let (exe, bin) = try fakeCLI("claude", script: """
        echo "error: unknown option '--no-session-persistence'" >&2
        exit 1
        """)
        let service = makeService { $0.binaryOverrides = [.claudeCode: exe] }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        let events = await collect(service, AskRequest(provider: .claudeCode, turns: [.user("x")]))
        #expect(events == [.error("Claude Code is too old for Islet. Update it and try again.")])
    }

    @Test func cancelKillsAProcessThatIgnoresTERM() async throws {
        let pidFile = tempDir().appendingPathComponent("pid")
        defer { try? FileManager.default.removeItem(at: pidFile.deletingLastPathComponent()) }
        let (exe, bin) = try fakeCLI("claude", script: """
        echo $$ > '\(pidFile.path)'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}}'
        trap '' TERM
        exec sleep 30
        """)
        let service = makeService {
            $0.binaryOverrides = [.claudeCode: exe]
            $0.killGrace = 0.3
        }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        let task = Task { () -> [AskEvent] in
            var out: [AskEvent] = []
            for try await e in service.stream(AskRequest(provider: .claudeCode, turns: [.user("x")])) {
                out.append(e)
                if case .text = e { break }
            }
            return out
        }
        #expect((try? await task.value) == [.text("partial")])
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        var gone = false
        for _ in 0..<30 where !gone {
            try await Task.sleep(nanoseconds: 100_000_000)
            gone = kill(pid, 0) != 0
        }
        #expect(gone)
    }

    @Test func outputIsCapped() async throws {
        let (exe, bin) = try fakeCLI("claude", script: """
        while :; do echo '{"type":"system","subtype":"noise","padding":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}'; done
        """)
        let service = makeService {
            $0.binaryOverrides = [.claudeCode: exe]
            $0.cliOutputLimit = 4096
            $0.killGrace = 0.3
        }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        let events = await collect(service, AskRequest(provider: .claudeCode, turns: [.user("x")]))
        #expect(events == [.error("Claude Code wrote more than 4 KB, so Islet stopped it.")])
    }

    @Test func overallTimeoutStopsWaiting() async throws {
        let (exe, bin) = try fakeCLI("codex", script: "exec sleep 30\n")
        let service = makeService {
            $0.binaryOverrides = [.codex: exe]
            $0.overallTimeout = 1
            $0.killGrace = 0.3
        }
        defer { cleanUp(service); try? FileManager.default.removeItem(at: bin) }
        let events = await collect(service, AskRequest(provider: .codex, turns: [.user("x")]))
        #expect(events == [.error("No complete answer within 1 s, so Islet stopped waiting.")])
    }

    @Test func missingCLI() async {
        let service = makeService()
        defer { cleanUp(service) }
        #expect(service.status(of: .codex) == .notInstalled)
        #expect(await collect(service, AskRequest(provider: .codex, turns: [.user("x")]))
                == [.error("Codex isn’t installed. Install it, then try again.")])
    }
}

@Suite struct AskStoreTests {
    @Test func keychainQueriesTargetOneItem() {
        let store = KeychainStore()
        #expect(store.service == "dev.islet.Islet.ai")
        let q = store.query(account: "anthropic")
        #expect(q[kSecAttrService as String] as? String == "dev.islet.Islet.ai")
        #expect(q[kSecAttrAccount as String] as? String == "anthropic")
        #expect((q[kSecClass as String] as? String) == (kSecClassGenericPassword as String))
    }

    @Test func memoryStore() throws {
        let store = MemorySecretStore()
        #expect(!store.contains("openai"))
        try store.save((sk + "1"), account: "openai")
        #expect(store.read("openai") == (sk + "1"))
        try store.delete("openai")
        #expect(store.read("openai") == nil)
    }

    /// Writes to the login keychain, so it only runs when asked: ISLET_KEYCHAIN_TESTS=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLET_KEYCHAIN_TESTS"] == "1"))
    func keychainRoundTrip() throws {
        let store = KeychainStore(service: "dev.islet.Islet.tests.\(UUID().uuidString)")
        defer { try? store.delete("anthropic") }
        #expect(store.read("anthropic") == nil)
        try store.save((sk + "ant-one"), account: "anthropic")
        try store.save((sk + "ant-two"), account: "anthropic")
        #expect(store.contains("anthropic"))
        #expect(store.read("anthropic") == (sk + "ant-two"))
        try store.delete("anthropic")
        #expect(!store.contains("anthropic"))
    }

    @Test func onDeviceReportsWhyItCantAnswer() async {
        let service = makeService()
        defer { cleanUp(service) }
        let status = service.status(of: .onDevice)
        guard !status.isReady else { return }  // Apple Intelligence is ready on this Mac: nothing to check.
        #expect(await collect(service, AskRequest(provider: .onDevice, turns: [.user("x")])) == [.error(status.message(for: .onDevice))])
    }
}
