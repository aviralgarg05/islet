import Foundation
import IsletCore
import Testing
@testable import IsletSystem

/// Collects callbacks from the watcher's queue.
private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentUsage?] = []

    func add(_ u: AgentUsage?) { lock.withLock { items.append(u) } }
    var all: [AgentUsage?] { lock.withLock { items } }
    var last: AgentUsage? { lock.withLock { items.last ?? nil } }
}

private func waitFor(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}

private func codexLine(_ used: Double) -> String {
    #"{"timestamp":"2026-09-30T09:20:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"# + "\(used)" + #","window_minutes":300,"resets_at":1790771457},"plan_type":"plus"}}}"#
}

@Suite(.serialized) struct UsageWatcherTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("islet-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func file(_ path: String, _ text: String, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    @Test func claudeFileChangesArriveWithoutPolling() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let usageFile = AgentUsageStore.claudeFile(in: root.appendingPathComponent("usage"))
        let watcher = UsageWatcher(claudeFile: usageFile, codexSessions: root.appendingPathComponent("none"))
        watcher.callbackQueue = DispatchQueue(label: "test.callbacks")
        let got = Received()
        watcher.onClaude = { got.add($0) }
        watcher.startClaude()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(got.all.isEmpty) // no file yet, nothing to report

        let first = AgentUsage(provider: .claude, windows: [UsageWindow(id: "five_hour", usedPercent: 62, windowMinutes: 300)], model: "Opus 5.5")
        try AgentUsageStore.write(AgentUsageStore.encode(first), to: usageFile)
        #expect(await waitFor { got.last?.model == "Opus 5.5" })

        var second = first
        second.windows[0].usedPercent = 91
        try AgentUsageStore.write(AgentUsageStore.encode(second), to: usageFile)
        #expect(await waitFor { got.last?.window("five_hour")?.usedPercent == 91 })

        watcher.stopClaude()
        try await Task.sleep(nanoseconds: 200_000_000)
        let count = got.all.count
        second.windows[0].usedPercent = 99
        try AgentUsageStore.write(AgentUsageStore.encode(second), to: usageFile)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(got.all.count == count)
    }

    @Test func findsTheNewestRolloutInRecentDayFolders() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        _ = try file("s/2026/08/01/rollout-old.jsonl", "{}", modified: now)            // older folder, ignored
        _ = try file("s/2026/09/29/rollout-a.jsonl", "{}", modified: now.addingTimeInterval(-60))
        let resumed = try file("s/2026/09/29/rollout-b.jsonl", "{}", modified: now.addingTimeInterval(-5))
        _ = try file("s/2026/09/30/rollout-c.jsonl", "{}", modified: now.addingTimeInterval(-30))
        _ = try file("s/2026/09/30/notes.txt", "", modified: now)
        let found = UsageWatcher.newestRollout(in: root.appendingPathComponent("s"))
        #expect(found?.lastPathComponent == resumed.lastPathComponent)
        #expect(UsageWatcher.newestRollout(in: root.appendingPathComponent("missing")) == nil)
    }

    @Test func readsOnlyTheTail() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let big = String(repeating: #"{"type":"response_item","payload":{"text":"filler"}}"# + "\n", count: 3000) + codexLine(42) + "\n"
        let url = try file("s/rollout-x.jsonl", big)
        let (tail, cut) = try #require(UsageWatcher.tail(of: url, limit: 64 * 1024))
        #expect(tail.count == 64 * 1024)
        #expect(cut)
        #expect(CodexRollout.latestUsage(inTail: tail, startsMidLine: cut)?.windows.first?.usedPercent == 42)
        let (whole, wholeCut) = try #require(UsageWatcher.tail(of: url, limit: 10 * 1024 * 1024))
        #expect(whole.count == big.utf8.count)
        #expect(!wholeCut)
    }

    @Test func codexSessionsAreWatchedWithFSEvents() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let rollout = try file("sessions/2026/09/30/rollout-t.jsonl", codexLine(10) + "\n")
        let watcher = UsageWatcher(claudeFile: root.appendingPathComponent("usage/claude.json"), codexSessions: sessions)
        watcher.codexLatency = 0.1
        watcher.callbackQueue = DispatchQueue(label: "test.callbacks")
        let got = Received()
        watcher.onCodex = { got.add($0) }
        watcher.startCodex()
        #expect(await waitFor { got.last?.windows.first?.usedPercent == 10 })
        #expect(got.last?.planType == "plus")

        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((codexLine(35) + "\n").utf8))
        try handle.close()
        #expect(await waitFor(10) { got.last?.windows.first?.usedPercent == 35 })
        watcher.stopCodex()
    }

    @Test func codexIsSkippedWhenItHasNeverRun() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = UsageWatcher(claudeFile: root.appendingPathComponent("usage/claude.json"), codexSessions: root.appendingPathComponent("nope"))
        watcher.callbackQueue = DispatchQueue(label: "test.callbacks")
        let got = Received()
        watcher.onCodex = { got.add($0) }
        watcher.startCodex()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(got.all.isEmpty)
        watcher.stopCodex()
    }
}
