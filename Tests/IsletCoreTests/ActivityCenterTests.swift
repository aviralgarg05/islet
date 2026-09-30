import Foundation
import Testing
@testable import IsletCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct ActivityCenterTests {
    @Test func createRequiresTitle() {
        var c = ActivityCenter()
        #expect(throws: ActivityError.missingTitle) { try c.apply(ActivitySpec(id: "a"), now: t0) }
    }

    @Test func createDefaults() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "a", title: "Hello"), now: t0)
        #expect(a.source == "api")
        #expect(a.state == .info)
        #expect(a.priority == .normal)
        #expect(a.expiresAt == nil)
        #expect(a.effectiveIcon == .symbol("info.circle.fill"))
    }

    @Test func progressImpliesRunning() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "p", title: "Upload", progress: 0.3), now: t0)
        #expect(a.state == .running)
        #expect(a.trailingText(now: t0) == "30%")
    }

    @Test func progressAcceptsPercentages() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "p", title: "x", progress: 42), now: t0)
        #expect(a.progress == 0.42)
        let b = try c.apply(ActivitySpec(id: "q", title: "x", progress: -5), now: t0)
        #expect(b.isIndeterminate)
        #expect(b.clampedProgress == nil)
        #expect(throws: ActivityError.invalidProgress(250)) { try c.apply(ActivitySpec(id: "r", title: "x", progress: 250), now: t0) }
        #expect(throws: (any Error).self) { try c.apply(ActivitySpec(id: "s", title: "x", progress: .nan), now: t0) }
    }

    @Test func rejectsBadIDsAndTints() {
        var c = ActivityCenter()
        #expect(throws: ActivityError.invalidID("has space")) { try c.apply(ActivitySpec(id: "has space", title: "x"), now: t0) }
        #expect(throws: ActivityError.invalidID("")) { try c.apply(ActivitySpec(id: "", title: "x"), now: t0) }
        #expect(throws: ActivityError.invalidTint("notacolor")) { try c.apply(ActivitySpec(id: "ok", title: "x", tint: "notacolor"), now: t0) }
        #expect(ActivityCenter.isValidID("claude-abc123:build.1_x"))
        #expect(!ActivityCenter.isValidID("é"))
    }

    @Test func updateMergesFields() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "Deploy", subtitle: "step 1", tint: "blue"), now: t0)
        let b = try c.apply(ActivitySpec(id: "a", progress: 0.5), now: t0.addingTimeInterval(1))
        #expect(b.title == "Deploy")
        #expect(b.subtitle == "step 1")
        #expect(b.tint == "blue")
        #expect(b.progress == 0.5)
        #expect(b.createdAt == t0)
        #expect(b.updatedAt == t0.addingTimeInterval(1))
        // Empty strings clear optional text.
        let d = try c.apply(ActivitySpec(id: "a", subtitle: ""), now: t0.addingTimeInterval(2))
        #expect(d.subtitle == nil)
    }

    @Test func ttlExpiry() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "x", ttl: 5), now: t0)
        try c.apply(ActivitySpec(id: "b", title: "y"), now: t0)
        #expect(c.nextDeadline(now: t0) != nil)
        #expect(c.expire(now: t0.addingTimeInterval(4)).isEmpty)
        #expect(c.expire(now: t0.addingTimeInterval(5)) == ["a"])
        #expect(c.activities.keys.sorted() == ["b"])
    }

    @Test func ttlZeroMeansSticky() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "x", ttl: 5), now: t0)
        let a = try c.apply(ActivitySpec(id: "a", ttl: 0), now: t0)
        #expect(a.expiresAt == nil)
    }

    @Test func finishedActivitiesAutoDismiss() throws {
        var c = ActivityCenter(finishedTTL: 10)
        try c.apply(ActivitySpec(id: "a", title: "Build", state: .running), now: t0)
        let done = try c.apply(ActivitySpec(id: "a", state: .success), now: t0.addingTimeInterval(3))
        #expect(done.expiresAt == t0.addingTimeInterval(13))
        // Explicitly sticky failure stays.
        let f = try c.apply(ActivitySpec(id: "f", title: "x", state: .failure, ttl: 0), now: t0)
        #expect(f.expiresAt == nil)
    }

    @Test func orderingByPriorityThenRecency() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "low", title: "l", priority: .low), now: t0)
        try c.apply(ActivitySpec(id: "n1", title: "n", priority: .normal), now: t0.addingTimeInterval(1))
        try c.apply(ActivitySpec(id: "n2", title: "n", priority: .normal), now: t0.addingTimeInterval(2))
        try c.apply(ActivitySpec(id: "hi", title: "h", priority: .high), now: t0)
        #expect(c.ordered(now: t0.addingTimeInterval(3)).map(\.id) == ["hi", "n2", "n1", "low"])
        #expect(c.primary(now: t0.addingTimeInterval(3))?.id == "hi")
    }

    @Test func sneakOnCreateAndTerminalTransition() throws {
        var c = ActivityCenter(sneakDuration: 2)
        try c.apply(ActivitySpec(id: "a", title: "x", state: .running), now: t0)
        #expect(c.currentSneak(now: t0.addingTimeInterval(1))?.id == "a")
        #expect(c.currentSneak(now: t0.addingTimeInterval(2)) == nil)
        c.expire(now: t0.addingTimeInterval(3))
        // Progress update: no sneak.
        try c.apply(ActivitySpec(id: "a", progress: 0.5), now: t0.addingTimeInterval(3))
        #expect(c.currentSneak(now: t0.addingTimeInterval(3)) == nil)
        // Finishing sneaks.
        try c.apply(ActivitySpec(id: "a", state: .success), now: t0.addingTimeInterval(4))
        #expect(c.currentSneak(now: t0.addingTimeInterval(4))?.id == "a")
        // Low priority does not sneak by default; sneak:false suppresses.
        try c.apply(ActivitySpec(id: "l", title: "x", priority: .low), now: t0.addingTimeInterval(10))
        #expect(c.currentSneak(now: t0.addingTimeInterval(10)) == nil)
        try c.apply(ActivitySpec(id: "q", title: "x", sneak: false), now: t0.addingTimeInterval(10))
        #expect(c.currentSneak(now: t0.addingTimeInterval(10)) == nil)
    }

    @Test func removingSneakingActivityClearsSneak() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "x"), now: t0)
        #expect(c.remove(id: "a") != nil)
        #expect(c.currentSneak(now: t0) == nil)
        #expect(c.remove(id: "a") == nil)
    }

    @Test func removeAllBySource() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", source: "ci", title: "x"), now: t0)
        try c.apply(ActivitySpec(id: "b", source: "ci", title: "x"), now: t0)
        try c.apply(ActivitySpec(id: "c", source: "other", title: "x"), now: t0)
        #expect(c.removeAll(source: "ci") == 2)
        #expect(c.activities.keys.sorted() == ["c"])
    }

    @Test func evictsLeastImportantWhenFull() throws {
        var c = ActivityCenter(maxActivities: 3)
        try c.apply(ActivitySpec(id: "keep-high", title: "x", priority: .high), now: t0)
        try c.apply(ActivitySpec(id: "old-low", title: "x", priority: .low), now: t0)
        try c.apply(ActivitySpec(id: "n1", title: "x"), now: t0.addingTimeInterval(1))
        try c.apply(ActivitySpec(id: "n2", title: "x"), now: t0.addingTimeInterval(2))
        #expect(c.activities.count == 3)
        #expect(c.activities["old-low"] == nil)
        #expect(c.activities["keep-high"] != nil)
    }

    @Test func hudLifecycle() {
        var c = ActivityCenter(hudDuration: 1.5)
        c.showHUD(.volume, value: 1.7, now: t0)
        #expect(c.currentHUD(now: t0)?.value == 1)
        #expect(c.currentHUD(now: t0.addingTimeInterval(1.4)) != nil)
        #expect(c.currentHUD(now: t0.addingTimeInterval(1.5)) == nil)
        #expect(c.nextDeadline(now: t0) == t0.addingTimeInterval(1.5))
        c.expire(now: t0.addingTimeInterval(2))
        #expect(c.hud == nil)
        #expect(c.nextDeadline(now: t0.addingTimeInterval(2)) == nil)
    }

    @Test func countdownNeedsClockTick() throws {
        var c = ActivityCenter()
        #expect(!c.needsClockTick(now: t0))
        let a = try c.apply(ActivitySpec(id: "t", title: "Tea", endsAt: t0.addingTimeInterval(90)), now: t0)
        #expect(c.needsClockTick(now: t0))
        #expect(a.trailingText(now: t0.addingTimeInterval(0.2)) == "1:30")
        #expect(a.trailingText(now: t0.addingTimeInterval(89.5)) == "0:01")
        #expect(a.trailingText(now: t0.addingTimeInterval(95)) == "0:00")
        #expect(!c.needsClockTick(now: t0.addingTimeInterval(95)))
    }

    @Test func countUpForCallsAndStopwatches() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "call", title: "FaceTime", startedAt: t0), now: t0)
        #expect(a.trailingText(now: t0.addingTimeInterval(75)) == "1:15")
        #expect(c.needsClockTick(now: t0))
    }
}
