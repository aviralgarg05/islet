import Foundation
import Testing
@testable import IsletCore

/// A client posting the same activity again (coding-agent hooks fire a couple of times a second)
/// leaves it exactly as it is, so the island has nothing to draw; every real change still lands.
@Suite struct SameActivityAgainTests {
    static func working(_ subtitle: String = "Running swift build", progress: Double = -1) -> ActivitySpec {
        ActivitySpec(id: "claude-abc", source: "claude-code", title: "Claude · islet", subtitle: subtitle,
                     icon: .symbol("gearshape.2.fill"), progress: progress, state: .running, ttl: 0, sneak: false)
    }

    // MARK: Nothing new

    @Test func theSameReportAgainLeavesTheActivityAlone() throws {
        var c = ActivityCenter()
        let first = try c.apply(Self.working(), now: t0)
        for second in 1...20 {
            let again = try c.apply(Self.working(), now: t0.addingTimeInterval(Double(second)))
            #expect(again == first)
        }
        #expect(c.activities["claude-abc"] == first)
        #expect(c.activities["claude-abc"]?.updatedAt == t0)
    }

    /// `ordered(now:)` sorts by `updatedAt`, so an activity that only repeated itself must not
    /// climb over one that really changed.
    @Test func theSameReportAgainDoesNotJumpTheOrder() throws {
        var c = ActivityCenter()
        try c.apply(Self.working(), now: t0)
        try c.apply(ActivitySpec(id: "build", source: "ci", title: "Release build", state: .running, sneak: false), now: t0.addingTimeInterval(1))
        #expect(c.ordered(now: t0.addingTimeInterval(2)).map(\.id) == ["build", "claude-abc"])
        try c.apply(Self.working(), now: t0.addingTimeInterval(3))
        #expect(c.ordered(now: t0.addingTimeInterval(4)).map(\.id) == ["build", "claude-abc"])
        // A real change does bring it forward.
        try c.apply(Self.working("Running swift test"), now: t0.addingTimeInterval(5))
        #expect(c.ordered(now: t0.addingTimeInterval(6)).map(\.id) == ["claude-abc", "build"])
    }

    /// A whole stream of Claude Code hooks for the same tool: only the first writes anything.
    @Test func aStreamOfIdenticalHooksWritesOnce() throws {
        var c = ActivityCenter()
        let payload = Data(#"{"session_id":"019a","cwd":"/tmp/islet","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift build"}}"#.utf8)
        var stored: Activity?
        for tenth in 0...30 {
            let now = t0.addingTimeInterval(Double(tenth) * 0.6)
            guard case .upsert(let spec) = try AgentHooks.map(provider: "claude", payload: payload, now: now) else {
                Issue.record("expected an activity")
                return
            }
            try c.apply(spec, now: now)
            if tenth == 0 { stored = c.activities.values.first }
        }
        #expect(c.activities.count == 1)
        #expect(c.activities.values.first == stored)
        #expect(c.activities.values.first?.updatedAt == t0)
    }

    // MARK: Every real change still lands

    @Test func everyChangedFieldLandsAndStampsTheMoment() throws {
        func changed(_ spec: ActivitySpec, _ check: (Activity) -> Bool) throws {
            var c = ActivityCenter()
            try c.apply(Self.working(), now: t0)
            var next = spec
            next.id = "claude-abc"
            next.sneak = false
            let after = try c.apply(next, now: t0.addingTimeInterval(1))
            #expect(check(after))
            #expect(after.updatedAt == t0.addingTimeInterval(1))
        }
        try changed(ActivitySpec(title: "Claude · api")) { $0.title == "Claude · api" }
        try changed(ActivitySpec(subtitle: "Running swift test")) { $0.subtitle == "Running swift test" }
        try changed(ActivitySpec(subtitle: "")) { $0.subtitle == nil }
        try changed(ActivitySpec(icon: .symbol("hammer.fill"))) { $0.icon == .symbol("hammer.fill") }
        try changed(ActivitySpec(trailing: "3/7")) { $0.trailing == "3/7" }
        try changed(ActivitySpec(progress: 0.4)) { $0.progress == 0.4 }
        try changed(ActivitySpec(state: .waiting)) { $0.state == .waiting }
        try changed(ActivitySpec(tint: "#FF3B30")) { $0.tint == "#FF3B30" }
        try changed(ActivitySpec(priority: .high)) { $0.priority == .high }
        try changed(ActivitySpec(startedAt: t0)) { $0.startedAt == t0 }
        try changed(ActivitySpec(url: URL(string: "islet://open")!)) { $0.url?.scheme == "islet" }
        try changed(ActivitySpec(relevance: 90)) { $0.relevance == 90 }
        try changed(ActivitySpec(steps: 7, step: 3)) { $0.steps == 7 && $0.step == 3 }
        try changed(ActivitySpec(actions: [ActivityAction(title: "Stop")])) { $0.actions.count == 1 }
        try changed(ActivitySpec(source: "codex")) { $0.source == "codex" }
    }

    /// A countdown's end: the ETA track is stretched, which is a change of its own.
    @Test func anEndTimeLands() throws {
        var c = ActivityCenter()
        try c.apply(Self.working(), now: t0)
        let after = try c.apply(ActivitySpec(id: "claude-abc", endsAt: t0.addingTimeInterval(120), sneak: false), now: t0.addingTimeInterval(1))
        #expect(after.endsAt == t0.addingTimeInterval(120))
        #expect(after.trackSpan != nil)
        #expect(after.updatedAt == t0.addingTimeInterval(1))
    }

    // MARK: Peeks

    @Test func anUnchangedReportDoesNotPeekButAnAskedForPeekStillDoes() throws {
        var c = ActivityCenter(sneakDuration: 2)
        try c.apply(Self.working(), now: t0)
        #expect(c.currentSneak(now: t0) == nil)
        try c.apply(Self.working(), now: t0.addingTimeInterval(1))
        #expect(c.currentSneak(now: t0.addingTimeInterval(1)) == nil)
        // The same report, but the client asked for a peek.
        var asked = Self.working()
        asked.sneak = true
        try c.apply(asked, now: t0.addingTimeInterval(2))
        #expect(c.currentSneak(now: t0.addingTimeInterval(2))?.id == "claude-abc")
    }

    @Test func finishingStillPeeks() throws {
        var c = ActivityCenter(sneakDuration: 2)
        try c.apply(Self.working(), now: t0)
        try c.apply(Self.working(), now: t0.addingTimeInterval(1))
        var done = Self.working("Done. Your turn.")
        done.state = .success
        done.progress = 1
        done.sneak = nil
        try c.apply(done, now: t0.addingTimeInterval(2))
        #expect(c.currentSneak(now: t0.addingTimeInterval(2))?.state == .success)
    }

    /// A template moment (a score changing) still peeks, and the same score again does not.
    @Test func aTemplateMomentStillPeeks() throws {
        var c = ActivityCenter(sneakDuration: 2)
        func score(_ home: String, _ away: String) -> ActivitySpec {
            var s = ActivitySpec(id: "match", source: "sport", title: "Arsenal v City", state: .info, sneak: false)
            s.template = "score"
            s.teams = [ActivityTeam(abbr: "ARS", score: home), ActivityTeam(abbr: "MCI", score: away)]
            return s
        }
        try c.apply(score("0", "0"), now: t0)
        var same = score("0", "0")
        same.sneak = nil
        try c.apply(same, now: t0.addingTimeInterval(1))
        #expect(c.currentSneak(now: t0.addingTimeInterval(1)) == nil)
        var goal = score("1", "0")
        goal.sneak = nil
        try c.apply(goal, now: t0.addingTimeInterval(2))
        #expect(c.currentSneak(now: t0.addingTimeInterval(2))?.id == "match")
    }

    // MARK: Deadlines

    /// An agent re-arms its staleness on every event. The stored moment is left alone while it is
    /// within the slack, and the activity still dims when the agent stops reporting.
    @Test func reArmedStalenessIsKeptWhileItIsFarOff() throws {
        var c = ActivityCenter()
        var spec = Self.working()
        spec.staleAt = t0.addingTimeInterval(900)
        try c.apply(spec, now: t0)
        #expect(c.activities["claude-abc"]?.staleAt == t0.addingTimeInterval(900))
        // Re-armed a second later: within three per cent of 900 s, so nothing is written.
        var again = spec
        again.staleAt = t0.addingTimeInterval(901)
        try c.apply(again, now: t0.addingTimeInterval(1))
        #expect(c.activities["claude-abc"]?.staleAt == t0.addingTimeInterval(900))
        #expect(c.activities["claude-abc"]?.updatedAt == t0)
        // Half a minute later it has drifted past the slack and is written down.
        var later = spec
        later.staleAt = t0.addingTimeInterval(930)
        try c.apply(later, now: t0.addingTimeInterval(30))
        #expect(c.activities["claude-abc"]?.staleAt == t0.addingTimeInterval(930))
        // Still not a change anyone can see, so the order is untouched.
        #expect(c.activities["claude-abc"]?.updatedAt == t0)
        // The agent stops reporting: it dims within the slack of where it last asked.
        #expect(c.activities["claude-abc"]?.isStale(at: t0.addingTimeInterval(929)) == false)
        #expect(c.activities["claude-abc"]?.isStale(at: t0.addingTimeInterval(930)) == true)
    }

    @Test func astalenessBroughtForwardIsHonouredAtOnce() throws {
        var c = ActivityCenter()
        var spec = Self.working()
        spec.staleAt = t0.addingTimeInterval(900)
        try c.apply(spec, now: t0)
        var sooner = spec
        sooner.staleAt = t0.addingTimeInterval(5)
        try c.apply(sooner, now: t0.addingTimeInterval(1))
        #expect(c.activities["claude-abc"]?.staleAt == t0.addingTimeInterval(5))
    }

    /// A ttl re-sent with nothing else new still keeps the activity alive, within the slack.
    @Test func aReArmedTtlStillKeepsTheActivity() throws {
        var c = ActivityCenter()
        var spec = Self.working()
        spec.ttl = 60
        try c.apply(spec, now: t0)
        #expect(c.activities["claude-abc"]?.expiresAt == t0.addingTimeInterval(60))
        for tenth in 1...100 {
            try c.apply(spec, now: t0.addingTimeInterval(Double(tenth) * 0.6))
        }
        // Sixty seconds of reports kept it: it is still here, and still dismisses itself.
        #expect(c.expire(now: t0.addingTimeInterval(60)).isEmpty)
        #expect(c.activities["claude-abc"] != nil)
        #expect(c.expire(now: t0.addingTimeInterval(121)) == ["claude-abc"])
    }

    @Test func theDeadlineRuleItself() {
        let now = t0
        // Newly given, taken away, brought forward: always honoured.
        #expect(ActivityCenter.keptDeadline(nil, asked: t0.addingTimeInterval(10), now: now) == t0.addingTimeInterval(10))
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(10), asked: nil, now: now) == nil)
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(10), asked: t0.addingTimeInterval(4), now: now) == t0.addingTimeInterval(4))
        // Pushed out a little: kept. Pushed out past the slack: written.
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(900), asked: t0.addingTimeInterval(910), now: now)
            == t0.addingTimeInterval(900))
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(900), asked: t0.addingTimeInterval(960), now: now)
            == t0.addingTimeInterval(960))
        // A short span still moves on about once a second, never less.
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(10), asked: t0.addingTimeInterval(10.5), now: now)
            == t0.addingTimeInterval(10))
        #expect(ActivityCenter.keptDeadline(t0.addingTimeInterval(10), asked: t0.addingTimeInterval(12), now: now)
            == t0.addingTimeInterval(12))
    }
}
