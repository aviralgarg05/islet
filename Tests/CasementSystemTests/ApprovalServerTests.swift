import Foundation
import CasementCore
import Testing
@testable import CasementSystem

/// Backend that answers approvals after a delay, or never (until cancelled).
actor ApprovingBackend: CasementBackend {
    var center = ActivityCenter()
    let delay: TimeInterval?
    let decision: ApprovalDecision
    private(set) var asked = 0
    private(set) var cancelled = 0

    init(delay: TimeInterval?, decision: ApprovalDecision = .allow) {
        self.delay = delay
        self.decision = decision
    }

    func listActivities() async -> [Activity] { center.ordered(now: Date()) }
    func applyActivity(_ spec: ActivitySpec) async throws -> Activity { try center.apply(spec, now: Date()) }
    func removeActivity(id: String) async -> Bool { center.remove(id: id) != nil }
    func removeActivities(source: String) async -> Int { center.removeAll(source: source) }
    func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async {}
    func pushMedia(_ media: NowPlaying?) async {}
    func mediaCommand(_ command: PlaybackCommand, position: Double?) async -> Bool { false }
    func setExpanded(_ expanded: Bool) async {}
    func stateSnapshot() async -> StateSnapshot {
        StateSnapshot(version: "t", presentation: "idle", activities: [], nowPlaying: nil, battery: nil)
    }
    func menuBarItems() async -> [MenuBarItemInfo] { [] }
    func keepAwake(_ change: KeepAwakeChange?) async -> KeepAwakeStatus { KeepAwakeStatus(active: false) }
    func listTimers() async -> [TimerItem] { [] }
    func timerCommand(_ command: TimerCommand) async throws -> TimerItem? { nil }

    func handleApproval(_ event: ApprovalEvent) async -> ApprovalDecision? {
        guard case .ask = event else { return nil }
        asked += 1
        try? await Task.sleep(nanoseconds: UInt64((delay ?? 3600) * 1_000_000_000))
        if Task.isCancelled {
            cancelled += 1
            return nil
        }
        return decision
    }
}

private let permission = #"""
{"session_id":"abc123","cwd":"/Users/me/code/casement","hook_event_name":"PermissionRequest","tool_name":"Bash",
 "tool_input":{"command":"swift test"},"permission_suggestions":[]}
"""#

@Suite(.serialized) struct ApprovalServerTests {
    func start(_ backend: ApprovingBackend, timeout: TimeInterval = 5, maxHeld: Int = 16) async throws -> (LocalAPIServer, UInt16) {
        let server = LocalAPIServer(router: APIRouter(token: "tok", version: "t", backend: backend))
        server.requestTimeout = timeout
        server.maxHeldRequests = maxHeld
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            server.start(port: 0) { cont.resume(with: $0) }
        }
        return (server, port)
    }

    /// Waits (briefly polling, test only) until `condition` holds.
    func eventually(_ seconds: TimeInterval = 3, _ condition: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await condition()
    }

    func rawRequest(_ body: String, path: String = "/v1/hooks/claude?wait=60") -> String {
        "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer tok\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }

    func connect(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    func send(_ fd: Int32, _ text: String) {
        _ = text.withCString { Darwin.send(fd, $0, strlen($0), 0) }
    }

    /// Reads until the server closes the connection (or the 5 s receive timeout).
    func readAll(_ fd: Int32) -> String {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return String(decoding: out, as: UTF8.self)
    }

    @Test func longPollOutlivesTheRequestTimeout() async throws {
        let backend = ApprovingBackend(delay: 1.0)
        let (server, port) = try await start(backend, timeout: 0.3)
        defer { server.stop() }
        let started = Date()
        let (status, data) = try await request(port, "POST", "/v1/hooks/claude?wait=10", body: permission)
        #expect(status == 200)
        #expect(String(decoding: data, as: UTF8.self) == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        #expect(Date().timeIntervalSince(started) >= 0.9)
    }

    @Test func slowSendersAreStillDropped() async throws {
        let (server, port) = try await start(ApprovingBackend(delay: 0), timeout: 0.3)
        defer { server.stop() }
        let fd = connect(port)
        defer { close(fd) }
        send(fd, "POST /v1/hooks/claude?wait=10 HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        let started = Date()
        #expect(readAll(fd).isEmpty)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func heldRequestsAreCapped() async throws {
        let backend = ApprovingBackend(delay: nil)
        let (server, port) = try await start(backend, maxHeld: 1)
        defer { server.stop() }
        let first = connect(port)
        defer { close(first) }
        send(first, rawRequest(permission))
        #expect(await eventually { await backend.asked == 1 })
        let (status, _) = try await request(port, "POST", "/v1/hooks/claude?wait=10", body: permission)
        #expect(status == 503)
        // Ordinary requests are not affected by the cap.
        #expect(try await request(port, "GET", "/v1/activities").0 == 200)
    }

    @Test func hangingUpCancelsTheWait() async throws {
        let backend = ApprovingBackend(delay: nil)
        let (server, port) = try await start(backend)
        defer { server.stop() }
        let fd = connect(port)
        send(fd, rawRequest(permission))
        #expect(await eventually { await backend.asked == 1 })
        close(fd)
        #expect(await eventually { await backend.cancelled == 1 })
        // The slot is free again.
        let fd2 = connect(port)
        defer { close(fd2) }
        send(fd2, rawRequest(permission))
        #expect(await eventually { await backend.asked == 2 })
    }
}

@Suite struct ClaudeHookSetupTests {
    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func installsIntoANewFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(".claude/settings.json")
        let preview = try ClaudeHookSetup.plan(at: url, executable: "casementctl", wait: 300)
        #expect(preview.changes.count == 10)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try ClaudeHookSetup.install(at: url, executable: "casementctl", wait: 300)
        #expect(try Data(contentsOf: url) == preview.merged)
        #expect(!FileManager.default.fileExists(atPath: url.path + ".bak"))
        #expect(try ClaudeHookSetup.plan(at: url, executable: "casementctl", wait: 300).isUpToDate)
    }

    @Test func keepsABackupAndWritesThroughSymlinks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8)
        try original.write(to: real)
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let plan = try ClaudeHookSetup.install(at: link, executable: "casementctl", wait: 120)
        #expect(!plan.isUpToDate)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try Data(contentsOf: real.appendingPathExtension("bak")) == original)
        let merged = try #require(JSONValue.parse(Data(contentsOf: real)))
        #expect(merged["model"] == "opus")
        #expect(merged["hooks"]?["Stop"]?.arrayValue?.count == 2)
        #expect(merged["hooks"]?["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"] == "casementctl hook claude --wait 120")

        // Up to date: nothing is written and the backup stays the original.
        try ClaudeHookSetup.install(at: link, executable: "casementctl", wait: 120)
        #expect(try Data(contentsOf: real.appendingPathExtension("bak")) == original)
    }

    @Test func keepsThePermissionsOfAPrivateFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let fm = FileManager.default
        #expect(fm.createFile(atPath: url.path, contents: Data(#"{"env":{"API_KEY":"x"}}"#.utf8), attributes: [.posixPermissions: 0o600]))
        let plan = try ClaudeHookSetup.install(at: url, executable: "casementctl", wait: 300)
        #expect(try Data(contentsOf: url) == plan.merged)
        #expect((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((try fm.attributesOfItem(atPath: url.path + ".bak")[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        // Nothing is left behind next to it.
        #expect(try fm.contentsOfDirectory(atPath: dir.path).sorted() == ["settings.json", "settings.json.bak"])
    }

    @Test func leavesBrokenFilesAlone() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let broken = Data("{ \"hooks\": ".utf8)
        try broken.write(to: url)
        #expect(throws: ClaudeHookInstaller.InstallError.notJSON) { try ClaudeHookSetup.install(at: url, executable: "casementctl", wait: 300) }
        #expect(try Data(contentsOf: url) == broken)
        #expect(!FileManager.default.fileExists(atPath: url.path + ".bak"))
    }
}
