import Foundation
import IsletCore

public struct AskServiceError: Error, LocalizedError, Equatable {
    public var message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

/// Runs one Ask provider and streams its answer.
///
/// - API providers: an ephemeral `URLSession` (no cache, no cookies, no credential store) that
///   refuses redirects, so the key header never follows a redirect, and only talks to
///   api.anthropic.com and api.openai.com over HTTPS.
/// - CLIs: `claude` / `codex` with an argument array (no shell), an empty working folder, a
///   minimal environment, stdin closed, output capped, and TERM then KILL on cancel.
/// - On-device: Foundation Models, when Apple Intelligence is ready.
///
/// Nothing runs until a question is asked. Nothing is logged.
public final class AskService: NSObject, @unchecked Sendable {
    public struct Configuration {
        public var home: String
        /// Empty folder the CLIs run in, so no project settings, MCP config or CLAUDE.md load.
        public var workingDirectory: URL
        /// Environment the CLI environment is picked from (only non-secret variables are kept).
        public var parentEnvironment: [String: String]
        public var cliOutputLimit = AskLimits.cliOutputBytes
        public var killGrace = AskCLI.killGrace
        public var overallTimeout = AskLimits.overallTimeout
        /// Test hooks: fake transports and fake CLI binaries.
        var protocolClasses: [AnyClass] = []
        var binaryOverrides: [AskProviderKind: URL] = [:]

        public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                    workingDirectory: URL = IsletPaths.supportDirectory.appendingPathComponent("ask", isDirectory: true),
                    parentEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
            self.home = home
            self.workingDirectory = workingDirectory
            self.parentEnvironment = parentEnvironment
        }
    }

    public static let allowedHosts: Set<String> = [AnthropicAPI.host, OpenAIAPI.host]

    public let secrets: SecretStore
    let config: Configuration

    public init(secrets: SecretStore = KeychainStore(), configuration: Configuration = Configuration()) {
        self.secrets = secrets
        self.config = configuration
    }

    private let sessionLock = NSLock()
    private var madeSession: URLSession?

    /// Created on first use: an idle Islet never makes one. Locked, because a key check in
    /// Settings and a streaming answer can reach it from different threads at once.
    private var session: URLSession {
        sessionLock.withLock {
            if let s = madeSession { return s }
            let s = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
            madeSession = s
            return s
        }
    }

    var sessionConfiguration: URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = AskLimits.requestTimeout
        c.timeoutIntervalForResource = config.overallTimeout
        c.waitsForConnectivity = false
        if !config.protocolClasses.isEmpty { c.protocolClasses = config.protocolClasses + (c.protocolClasses ?? []) }
        return c
    }

    /// Only HTTPS to the two API hosts.
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && allowedHosts.contains(url.host ?? "") && url.port == nil
    }

    // MARK: Status

    public func status(of kind: AskProviderKind) -> AskProviderStatus {
        switch kind {
        case .onDevice: return OnDeviceAsk.status
        case .anthropic, .openai: return secrets.contains(kind.keyAccount ?? "") ? .ready : .needsKey
        case .claudeCode, .codex: return cliBinary(for: kind) != nil ? .ready : .notInstalled
        }
    }

    public func cliBinary(for kind: AskProviderKind) -> URL? {
        if let url = config.binaryOverrides[kind] { return url }
        return AskCLI.searchPaths(for: kind, home: config.home)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: Asking

    /// Stream an answer. Cancelling the consuming task (or dropping the stream) cancels the
    /// request, closes the HTTP stream and stops a CLI. After `overallTimeout` it gives up.
    public func stream(_ request: AskRequest) -> AsyncThrowingStream<AskEvent, Error> {
        AsyncThrowingStream { continuation in
            let emit: @Sendable (AskEvent) -> Void = { continuation.yield($0) }
            let work = Task {
                switch request.provider {
                case .onDevice: await OnDeviceAsk.run(request.turns, emit: emit)
                case .anthropic, .openai: await self.runHTTP(request, emit: emit)
                case .claudeCode, .codex: await self.runCLI(request, emit: emit)
                }
                continuation.finish()
            }
            let timeout = config.overallTimeout
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                work.cancel()
                let limit = timeout >= 60 ? "\(Int(timeout / 60)) minutes" : "\(Int(timeout)) s"
                continuation.yield(.error("No complete answer within \(limit), so Islet stopped waiting."))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                work.cancel()
                watchdog.cancel()
            }
        }
    }

    /// The provider's model list; with `key`, also a check that the key works.
    public func models(for kind: AskProviderKind, key: String? = nil) async throws -> [String] {
        guard let account = kind.keyAccount else { return kind.suggestedModels }
        guard let key = key ?? secrets.read(account) else { throw AskServiceError(AskProviderStatus.needsKey.message(for: kind)) }
        let http = kind == .anthropic ? AnthropicAPI.models(key: key) : OpenAIAPI.models(key: key)
        let request = try urlRequest(http, timeout: 15)
        do {
            let (data, response) = try await session.data(for: request, delegate: self)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw AskServiceError(AskErrorText.http(status: status, body: data, retryAfter: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after"), provider: kind))
            }
            return kind == .anthropic ? AnthropicAPI.modelIDs(from: data) : OpenAIAPI.modelIDs(from: data)
        } catch let e as URLError {
            throw AskServiceError(Self.describe(e, host: http.url.host))
        }
    }

    /// Check a pasted key against the provider, then store it in the Keychain.
    /// Returns the models the key can use.
    public func validateAndStore(key raw: String, for kind: AskProviderKind) async throws -> [String] {
        let key = AskKeys.normalized(raw)
        guard let account = kind.keyAccount else { throw AskServiceError("\(kind.title) doesn't use an API key.") }
        guard AskKeys.looksValid(key, for: kind) else {
            throw AskServiceError(kind == .anthropic ? "That doesn't look like an Anthropic key. It starts with sk-ant-."
                                                     : "That doesn't look like an OpenAI key. It starts with sk-.")
        }
        let models = try await models(for: kind, key: key)
        try secrets.save(key, account: account)
        return models
    }

    public func removeKey(for kind: AskProviderKind) throws {
        guard let account = kind.keyAccount else { return }
        try secrets.delete(account)
    }

    /// "•••• abcd" for a stored key, or nil.
    public func maskedKey(for kind: AskProviderKind) -> String? {
        guard let account = kind.keyAccount, let key = secrets.read(account) else { return nil }
        return AskKeys.masked(key)
    }

    /// Stop using the network session (tests).
    public func invalidate() { session.invalidateAndCancel() }

    // MARK: HTTP

    private enum Outcome {
        case finished
        case failed(status: Int, body: Data, retryAfter: String?)
    }

    private func runHTTP(_ request: AskRequest, emit: @Sendable (AskEvent) -> Void) async {
        let kind = request.provider
        guard let account = kind.keyAccount, let key = secrets.read(account) else {
            emit(.needsKey(AskProviderStatus.needsKey.message(for: kind)))
            return
        }
        let model = request.model ?? kind.defaultModel ?? ""
        var effort: AskEffort? = request.effort
        var retriedOverload = false
        while !Task.isCancelled {
            let http = kind == .anthropic
                ? AnthropicAPI.messages(turns: request.turns, model: model, effort: request.effort, key: key)
                : OpenAIAPI.responses(turns: request.turns, model: model, effort: effort, key: key)
            switch await send(http, kind: kind, emit: emit) {
            case .finished:
                return
            case .failed(let status, let body, let retryAfter):
                if kind == .openai, effort != nil, OpenAIAPI.rejectsReasoning(status: status, body: body) {
                    effort = nil
                    continue
                }
                if !retriedOverload, AskErrorText.isOverloaded(status: status, body: body) {
                    retriedOverload = true
                    try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.6...1.6) * 1_000_000_000))
                    continue
                }
                let message = AskErrorText.http(status: status, body: body, retryAfter: retryAfter, provider: kind)
                emit(AskErrorText.isKeyProblem(status: status) ? .needsKey(message) : .error(message))
                return
            }
        }
    }

    private func urlRequest(_ http: AskHTTPRequest, timeout: TimeInterval) throws -> URLRequest {
        guard Self.isAllowed(http.url) else { throw AskServiceError("Islet only sends questions to api.anthropic.com and api.openai.com.") }
        var r = URLRequest(url: http.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = http.method
        r.httpShouldHandleCookies = false
        for (name, value) in http.headers { r.setValue(value, forHTTPHeaderField: name) }
        r.httpBody = http.body
        return r
    }

    private func send(_ http: AskHTTPRequest, kind: AskProviderKind, emit: @Sendable (AskEvent) -> Void) async -> Outcome {
        do {
            let request = try urlRequest(http, timeout: AskLimits.requestTimeout)
            let (bytes, response) = try await session.bytes(for: request, delegate: self)
            let reply = response as? HTTPURLResponse
            let status = reply?.statusCode ?? 0
            guard status == 200 else {
                var body = Data()
                for try await b in bytes {
                    body.append(b)
                    if body.count >= 16_384 { break }
                }
                bytes.task.cancel()
                return .failed(status: status, body: body, retryAfter: reply?.value(forHTTPHeaderField: "retry-after"))
            }
            if kind == .anthropic {
                try await consume(bytes, decoder: AnthropicStreamDecoder(), emit: emit)
            } else {
                try await consume(bytes, decoder: OpenAIStreamDecoder(), emit: emit)
            }
        } catch let e as AskServiceError {
            emit(.error(e.message))
        } catch is CancellationError {
        } catch let e as URLError {
            if e.code != .cancelled { emit(.error(Self.describe(e, host: http.url.host))) }
        } catch {
            if !Task.isCancelled { emit(.error(error.localizedDescription)) }
        }
        return .finished
    }

    /// Bytes → SSE records → events. Raw bytes rather than `lines`, which drops the blank lines
    /// that end SSE records.
    private func consume<D: AskStreamDecoder>(_ bytes: URLSession.AsyncBytes, decoder: D, emit: @Sendable (AskEvent) -> Void) async throws {
        var decoder = decoder
        var parser = SSEParser()
        var line: [UInt8] = []
        line.reserveCapacity(2048)
        func deliver(_ records: [SSEEvent]) -> Bool {
            for record in records {
                for event in decoder.decode(record) {
                    emit(event)
                    if event.isTerminal { return true }
                }
            }
            return false
        }
        for try await byte in bytes {
            line.append(byte)
            guard byte == 0x0A || line.count >= 65_536 else { continue }
            let done = deliver(parser.feed(line))
            line.removeAll(keepingCapacity: true)
            if done {
                bytes.task.cancel()
                return
            }
        }
        if deliver(parser.feed(line) + parser.finish()) { return }
        decoder.finish().forEach(emit)
    }

    static func describe(_ e: URLError, host: String?) -> String {
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "You're offline."
        case .timedOut: return "The request timed out."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Couldn't reach \(host ?? "the server")."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "Couldn't make a secure connection to \(host ?? "the server")."
        default: return e.localizedDescription
        }
    }

    // MARK: CLIs

    private func runCLI(_ request: AskRequest, emit: @escaping @Sendable (AskEvent) -> Void) async {
        let kind = request.provider
        guard let binary = cliBinary(for: kind) else {
            emit(.error(AskProviderStatus.notInstalled.message(for: kind)))
            return
        }
        let prompt = AskPrompt.flattened(request.turns, instructions: AskPrompt.cliInstructions)
        let model = request.model.flatMap { AskSettings.isPlausibleModel($0) ? $0 : nil }
        let args = kind == .claudeCode ? AskCLI.claudeArguments(prompt: prompt, model: model) : AskCLI.codexArguments(prompt: prompt, model: model)
        try? FileManager.default.createDirectory(at: config.workingDirectory, withIntermediateDirectories: true)
        let child = CLIChild(executable: binary, arguments: args, directory: config.workingDirectory,
                             environment: AskCLI.environment(parent: config.parentEnvironment, binaryDirectory: binary.deletingLastPathComponent().path),
                             outputLimit: config.cliOutputLimit, killGrace: config.killGrace)
        if kind == .claudeCode {
            await drive(child, decoder: ClaudeCLIDecoder(), kind: kind, emit: emit)
        } else {
            await drive(child, decoder: CodexDecoder(), kind: kind, emit: emit)
        }
    }

    private func drive<D: AskLineDecoder>(_ child: CLIChild, decoder: D, kind: AskProviderKind, emit: @escaping @Sendable (AskEvent) -> Void) async {
        var decoder = decoder
        await withTaskCancellationHandler {
            do {
                try child.start()
            } catch {
                emit(.error("Couldn't start \(kind.title): \(error.localizedDescription)"))
                return
            }
            var ended = false
            // Keep draining after the answer ends, so a chatty CLI never blocks on a full pipe.
            for await line in child.lines where !ended {
                for event in decoder.decode(line: line) {
                    emit(event)
                    if event.isTerminal {
                        ended = true
                        child.stop(after: config.killGrace)
                    }
                }
            }
            let status = await child.waitForExit()
            guard !ended, !Task.isCancelled else { return }
            for event in decoder.finish() {
                emit(event)
                if event.isTerminal { return }
            }
            if child.hitOutputLimit {
                emit(.error("\(kind.title) wrote more than \(config.cliOutputLimit / 1024) KB, so Islet stopped it."))
            } else if status == 0 {
                emit(.done(AskUsage()))
            } else {
                emit(.error(AskCLI.failureText(kind: kind, status: status, stderr: child.stderrText)))
            }
        } onCancel: {
            child.stop()
        }
    }
}

extension AskService: URLSessionTaskDelegate {
    /// Never follow a redirect: the key header must only ever go to the host it was meant for.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// One `claude` or `codex` run: stdout as lines, stderr kept (capped) for error messages.
final class CLIChild: @unchecked Sendable {
    let process = Process()
    let lines: AsyncStream<String>
    private let linesContinuation: AsyncStream<String>.Continuation
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let outputLimit: Int
    private let killGrace: TimeInterval
    private let lock = NSLock()
    private let exited = DispatchGroup()
    private let stderrClosed = DispatchGroup()
    private var stderrData = Data()
    private var outputBytes = 0
    private var limitHit = false
    private var cancelled = false

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String], outputLimit: Int, killGrace: TimeInterval) {
        (lines, linesContinuation) = AsyncStream.makeStream(of: String.self)
        self.outputLimit = outputLimit
        self.killGrace = killGrace
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
    }

    var hitOutputLimit: Bool { lock.withLock { limitHit } }
    var stderrText: String { lock.withLock { String(decoding: stderrData, as: UTF8.self) } }

    func start() throws {
        var pending = Data()
        stdout.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if !pending.isEmpty { emit(pending) }
                pending.removeAll()
                linesContinuation.finish()
                return
            }
            let over = lock.withLock { () -> Bool in
                outputBytes += chunk.count
                if outputBytes > outputLimit { limitHit = true }
                return limitHit
            }
            if over {
                handle.readabilityHandler = nil
                linesContinuation.finish()
                stop()
                return
            }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                emit(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        stderrClosed.enter()
        stderr.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                stderrClosed.leave()
                return
            }
            lock.withLock { if stderrData.count < 8192 { stderrData.append(chunk.prefix(8192 - stderrData.count)) } }
        }
        exited.enter()
        process.terminationHandler = { [exited] _ in exited.leave() }
        let shouldRun = lock.withLock { !cancelled }
        do {
            guard shouldRun else { throw CancellationError() }
            try process.run()
        } catch {
            process.terminationHandler = nil
            exited.leave()
            stderrClosed.leave()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            linesContinuation.finish()
            throw error
        }
        // A stop() between the check above and run() found nothing to stop, so stop it now.
        if lock.withLock({ cancelled }) { stop() }
    }

    private func emit(_ data: Data) {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        if !line.isEmpty { linesContinuation.yield(line) }
    }

    /// Wait for the process to exit, then briefly for the rest of its stderr.
    func waitForExit() async -> Int32 {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            exited.notify(queue: .global()) { c.resume() }
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [stderrClosed] in
                _ = stderrClosed.wait(timeout: .now() + 0.5)
                c.resume()
            }
        }
        return process.isRunning ? -1 : process.terminationStatus
    }

    /// Stop it if it is still running after `delay` (it should exit by itself once it has answered).
    func stop(after delay: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in stop() }
    }

    /// SIGTERM, then SIGKILL if it is still running after the grace period.
    func stop() {
        lock.withLock { cancelled = true }
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
