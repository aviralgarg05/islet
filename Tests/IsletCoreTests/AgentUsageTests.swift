import Foundation
import Testing
@testable import IsletCore

private let morning = Date(timeIntervalSince1970: 1_790_760_000) // 2026-09-30 09:20 UTC

/// A recorded Claude Code status-line payload (fields as in the status line docs).
private let claudeStatus = #"""
{"hook_event_name":"Status","session_id":"abc123","transcript_path":"/tmp/t.jsonl","cwd":"/Users/me/src/islet",
 "model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
 "workspace":{"current_dir":"/Users/me/src/islet","project_dir":"/Users/me/src/islet"},
 "version":"2.3.0","output_style":{"name":"default"},
 "cost":{"total_cost_usd":1.2345,"total_duration_ms":45000,"total_lines_added":156},
 "context_window":{"total_input_tokens":15234,"context_window_size":200000,"used_percentage":42.37,"remaining_percentage":57.63},
 "rate_limits":{"five_hour":{"used_percentage":62.04,"resets_at":1790771457},"seven_day":{"used_percentage":31,"resets_at":1791200000}}}
"""#

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-usage-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite struct ClaudeStatusLineTests {
    @Test func parsesEveryField() throws {
        let u = try #require(ClaudeStatusLine.parse(Data(claudeStatus.utf8), now: morning))
        #expect(u.provider == .claude)
        #expect(u.model == "Opus 5.5")
        #expect(u.contextPercent == 42.4)
        #expect(u.costUSD == 1.23)
        #expect(u.sessionID == "abc123")
        #expect(u.project == "islet")
        #expect(u.updatedAt == morning)
        let five = try #require(u.window("five_hour"))
        #expect(five.usedPercent == 62)
        #expect(five.windowMinutes == 300)
        #expect(five.resetsAt == Date(timeIntervalSince1970: 1_790_771_457))
        #expect(five.shortLabel == "5h")
        #expect(five.longLabel == "5-hour")
        let week = try #require(u.window("seven_day"))
        #expect(week.usedPercent == 31)
        #expect(week.shortLabel == "7d")
        #expect(week.longLabel == "weekly")
    }

    @Test func toleratesMissingFields() throws {
        let bare = try #require(ClaudeStatusLine.parse(Data(#"{"session_id":"s"}"#.utf8), now: morning))
        #expect(bare.windows.isEmpty)
        #expect(bare.model == nil && bare.contextPercent == nil && bare.costUSD == nil)

        let partial = try #require(ClaudeStatusLine.parse(Data(#"{"rate_limits":{"seven_day":{"used_percentage":"12.5"}},"model":{"id":"claude-x"}}"#.utf8), now: morning))
        #expect(partial.windows.map(\.id) == ["seven_day"])
        #expect(partial.windows[0].resetsAt == nil)
        #expect(partial.model == "claude-x")

        #expect(ClaudeStatusLine.parse(Data("not json".utf8), now: morning) == nil)
        #expect(ClaudeStatusLine.parse(Data("[1,2]".utf8), now: morning) == nil)
    }

    @Test func mergeKeepsAccountWindowsForANewSession() throws {
        let old = try #require(ClaudeStatusLine.parse(Data(claudeStatus.utf8), now: morning))
        let fresh = try #require(ClaudeStatusLine.parse(Data(#"{"session_id":"new","model":{"display_name":"Sonnet 5.5"},"context_window":{"used_percentage":3}}"#.utf8), now: morning))
        let m = ClaudeStatusLine.merged(fresh, previous: old)
        #expect(m.window("five_hour")?.usedPercent == 62)
        #expect(m.window("seven_day")?.usedPercent == 31)
        #expect(m.model == "Sonnet 5.5")
        #expect(m.contextPercent == 3)
        #expect(m.project == nil)
        #expect(m.costUSD == nil)

        let sameSession = try #require(ClaudeStatusLine.parse(Data(#"{"session_id":"abc123","context_window":{"used_percentage":50}}"#.utf8), now: morning))
        let s = ClaudeStatusLine.merged(sameSession, previous: old)
        #expect(s.model == "Opus 5.5")
        #expect(s.contextPercent == 50)
    }
}

@Suite struct StatusLineBridgeTests {
    @Test func writesOnlyWhenFiguresChange() throws {
        let dir = tempDir().appendingPathComponent("usage")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let payload = Data(claudeStatus.utf8)

        let first = StatusLineBridge.record(payload, in: dir, now: morning)
        #expect(first.wrote)
        let file = AgentUsageStore.claudeFile(in: dir)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((dirAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(AgentUsageStore.read(file)?.model == "Opus 5.5")
        #expect(AgentUsageStore.read(file)?.updatedAt == morning)

        // Same figures a minute later: no write, so the app isn't woken for nothing.
        let second = StatusLineBridge.record(payload, in: dir, now: morning.addingTimeInterval(60))
        #expect(!second.wrote)
        #expect(AgentUsageStore.read(file)?.updatedAt == morning)

        let changed = claudeStatus.replacingOccurrences(of: "42.37", with: "44")
        #expect(StatusLineBridge.record(Data(changed.utf8), in: dir, now: morning.addingTimeInterval(120)).wrote)
        #expect(AgentUsageStore.read(file)?.contextPercent == 44)

        // Leftover temp files would pile up in the folder.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["claude.json"])
    }

    @Test func garbageIsIgnored() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = StatusLineBridge.record(Data("oops".utf8), in: dir, now: morning)
        #expect(r.usage == nil && !r.wrote)
        #expect(!FileManager.default.fileExists(atPath: AgentUsageStore.claudeFile(in: dir).path))
    }

    @Test func defaultLine() throws {
        let u = try #require(ClaudeStatusLine.parse(Data(claudeStatus.utf8), now: morning))
        #expect(StatusLineBridge.defaultLine(u) == "Opus 5.5 · 42% context · 5h 62%")
        #expect(StatusLineBridge.defaultLine(AgentUsage(provider: .claude, model: "Haiku 4.5")) == "Haiku 4.5")
    }
}

@Suite struct CodexRolloutTests {
    static let line = #"{"timestamp":"2026-09-30T09:20:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":23.0,"window_minutes":300,"resets_at":1790771457},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1791200000},"credits":{"has_credits":false},"plan_type":"team"}}}"#

    @Test func parsesATokenCountLine() throws {
        let u = try #require(CodexRollout.usage(fromLine: Data(Self.line.utf8)))
        #expect(u.provider == .codex)
        #expect(u.planType == "team")
        #expect(u.windows.map(\.id) == ["primary", "secondary"])
        #expect(u.windows[0].usedPercent == 23)
        #expect(u.windows[0].shortLabel == "5h")
        #expect(u.windows[1].longLabel == "weekly")
        #expect(u.windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_771_457))
        #expect(u.updatedAt == morning)
    }

    @Test func olderLinesWithRelativeResets() throws {
        let old = #"{"timestamp":"2026-09-30T09:20:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40,"window_minutes":300,"resets_in_seconds":600}}}}"#
        let u = try #require(CodexRollout.usage(fromLine: Data(old.utf8)))
        #expect(u.windows[0].resetsAt == morning.addingTimeInterval(600))
    }

    @Test func ignoresOtherLines() {
        for line in [#"{"type":"response_item","payload":{"type":"message"}}"#,
                     #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#,
                     #"{"type":"event_msg","payload":{"type":"agent_message","message":"token_count"}}"#, "{broken"] {
            #expect(CodexRollout.usage(fromLine: Data(line.utf8)) == nil)
        }
    }

    @Test func scansTheTailBackwards() throws {
        let newer = Self.line.replacingOccurrences(of: "23.0", with: "57.5")
        let noLimits = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":null}}"#
        let tail = [Self.line, newer, #"{"type":"response_item","payload":{"text":"hi"}}"#, noLimits, ""].joined(separator: "\n")
        let u = try #require(CodexRollout.latestUsage(inTail: Data(tail.utf8), startsMidLine: false))
        #expect(u.windows[0].usedPercent == 57.5)

        // A cut first line is never parsed, even when it happens to be valid JSON.
        #expect(CodexRollout.latestUsage(inTail: Data(Self.line.utf8), startsMidLine: true) == nil)
        #expect(CodexRollout.latestUsage(inTail: Data(Self.line.utf8), startsMidLine: false) != nil)
        #expect(CodexRollout.latestUsage(inTail: Data(), startsMidLine: false) == nil)
    }
}

@Suite struct UsageAlertTests {
    func usage(_ five: Double, resets: Date = morning.addingTimeInterval(3600), provider: UsageProvider = .claude) -> AgentUsage {
        AgentUsage(provider: provider, windows: [UsageWindow(id: "five_hour", usedPercent: five, windowMinutes: 300, resetsAt: resets)])
    }

    @Test func alertsOncePerThresholdAndRearmsOnReset() {
        var t = UsageAlertTracker()
        #expect(t.ingest(usage(70), now: morning).isEmpty) // baseline
        #expect(t.ingest(usage(85), now: morning).isEmpty)
        let at90 = t.ingest(usage(91.5), now: morning)
        #expect(at90.map(\.threshold) == [90])
        #expect(at90.first?.title == "Claude 5-hour limit at 91%")
        #expect(t.ingest(usage(95), now: morning).isEmpty)
        #expect(t.ingest(usage(89), now: morning).isEmpty) // no flapping around the line
        #expect(t.ingest(usage(93), now: morning).isEmpty)
        let full = t.ingest(usage(100), now: morning)
        #expect(full.map(\.threshold) == [100])
        #expect(full.first?.title == "Claude 5-hour limit reached")
        #expect(t.ingest(usage(100), now: morning).isEmpty)

        // The next window starts: alerts are armed again.
        let next = morning.addingTimeInterval(6 * 3600)
        #expect(t.ingest(usage(10, resets: next), now: morning.addingTimeInterval(3700)).isEmpty)
        #expect(t.ingest(usage(90, resets: next), now: morning.addingTimeInterval(4000)).map(\.threshold) == [90])
    }

    @Test func jumpingPastBothThresholdsAlertsOnce() {
        var t = UsageAlertTracker()
        _ = t.ingest(usage(50), now: morning)
        #expect(t.ingest(usage(100), now: morning).map(\.threshold) == [100])
    }

    @Test func firstReadingIsABaseline() {
        var t = UsageAlertTracker()
        #expect(t.ingest(usage(96), now: morning).isEmpty)
        #expect(t.ingest(usage(97), now: morning).isEmpty)
        #expect(t.ingest(usage(100), now: morning).map(\.threshold) == [100])
    }

    @Test func staleWindowsNeverAlert() {
        var t = UsageAlertTracker()
        _ = t.ingest(usage(80), now: morning)
        // Figures carried over from before the reset time are out of date.
        #expect(t.ingest(usage(95, resets: morning.addingTimeInterval(3600)), now: morning.addingTimeInterval(4000)).isEmpty)
    }

    @Test func smallResetJitterIsTheSameWindow() {
        var t = UsageAlertTracker()
        _ = t.ingest(usage(80), now: morning)
        #expect(t.ingest(usage(92), now: morning).count == 1)
        #expect(t.ingest(usage(93, resets: morning.addingTimeInterval(3660)), now: morning).isEmpty)
    }

    @Test func providersAreTrackedSeparately() {
        var t = UsageAlertTracker()
        _ = t.ingest(usage(80), now: morning)
        _ = t.ingest(usage(80, provider: .codex), now: morning)
        #expect(t.ingest(usage(90, provider: .codex), now: morning).map(\.provider) == [.codex])
    }

    @Test func alertActivity() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let resets = morning.addingTimeInterval(80 * 60) // 10:40 UTC
        let alert = UsageAlert(provider: .claude, window: UsageWindow(id: "five_hour", usedPercent: 90, windowMinutes: 300, resetsAt: resets), threshold: 90)
        let spec = alert.activity(now: morning, calendar: cal, locale: Locale(identifier: "en_GB"))
        #expect(spec.title == "Claude 5-hour limit at 90%")
        #expect(spec.subtitle == "Resets 10:40")
        #expect(spec.id == "usage-claude-five_hour")
        #expect(spec.source == "agent-usage")
        #expect(spec.state == .warning)
        #expect(spec.sneak == true)
        #expect(spec.priority == .normal)

        let week = UsageAlert(provider: .codex, window: UsageWindow(id: "secondary", usedPercent: 100, windowMinutes: 10080,
                                                                    resetsAt: morning.addingTimeInterval(2 * 86400)), threshold: 100)
        let s = week.activity(now: morning, calendar: cal, locale: Locale(identifier: "en_GB"))
        #expect(s.title == "Codex weekly limit reached")
        #expect(s.subtitle == "Resets Fri 09:20")
        #expect(s.priority == .high)
    }
}

@Suite struct UsageFormatTests {
    @Test func remaining() {
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(20), now: morning) == "1 min")
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(12 * 60), now: morning) == "12 min")
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(72 * 60), now: morning) == "1 h 12 min")
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(3 * 3600), now: morning) == "3 h")
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(76 * 3600), now: morning) == "3 d 4 h")
        #expect(UsageFormat.remaining(until: morning.addingTimeInterval(-60), now: morning) == "1 min")
        #expect(UsageFormat.percent(62.5) == "63%")
        #expect(UsageFormat.percent(-3) == "0%")
    }

    @Test func relevance() {
        let fresh = AgentUsage(provider: .claude, windows: [UsageWindow(id: "five_hour", usedPercent: 10, resetsAt: morning.addingTimeInterval(60))],
                               model: "Opus 5.5", updatedAt: morning.addingTimeInterval(-86400))
        #expect(fresh.isRelevant(at: morning))
        #expect(!fresh.isRelevant(at: morning.addingTimeInterval(120)))
        #expect(!fresh.hasRecentSession(at: morning))
        let session = AgentUsage(provider: .claude, contextPercent: 10, updatedAt: morning)
        #expect(session.hasRecentSession(at: morning.addingTimeInterval(600)))
        #expect(session.isRelevant(at: morning.addingTimeInterval(600)))
        #expect(!session.hasRecentSession(at: morning.addingTimeInterval(3600)))
        // Nothing left to show: no limits and an old session.
        #expect(!session.isRelevant(at: morning.addingTimeInterval(3600)))
        #expect(!AgentUsage(provider: .claude, updatedAt: morning).isRelevant(at: morning))
        let unknownReset = AgentUsage(provider: .codex, windows: [UsageWindow(id: "primary", usedPercent: 5)], updatedAt: morning)
        #expect(unknownReset.isRelevant(at: morning.addingTimeInterval(3600)))
        #expect(!unknownReset.isRelevant(at: morning.addingTimeInterval(13 * 3600)))
    }
}
