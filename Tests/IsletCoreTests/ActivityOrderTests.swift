import Foundation
import Testing
@testable import IsletCore

/// `ActivityOrder` gives the island the same answer as `ordered(now:)` every time, having worked
/// it out once per change rather than once per caller.
@Suite struct ActivityOrderTests {
    @Test func theOrderIsAlwaysTheRealOne() throws {
        var c = ActivityCenter()
        var order = ActivityOrder()
        func check(_ seconds: TimeInterval) {
            let now = t0.addingTimeInterval(seconds)
            #expect(order.ordered(c, now: now) == c.ordered(now: now))
        }
        check(0)
        try c.apply(ActivitySpec(id: "a", title: "A", state: .running, sneak: false), now: t0)
        check(0)
        check(0.001)
        try c.apply(ActivitySpec(id: "b", title: "B", priority: .high, ttl: 10, sneak: false), now: t0.addingTimeInterval(1))
        check(1)
        // A staleness moment and an expiry inside the window: the order changes at each of them.
        try c.apply(ActivitySpec(id: "c", title: "C", staleAt: t0.addingTimeInterval(5), sneak: false), now: t0.addingTimeInterval(2))
        for tenth in 0...200 { check(Double(tenth) / 10) }
        // Changes of every kind, each asked about at the same moment as before.
        try c.apply(ActivitySpec(id: "a", subtitle: "working", sneak: false), now: t0.addingTimeInterval(20))
        check(20)
        try c.apply(ActivitySpec(id: "a", priority: .critical, sneak: false), now: t0.addingTimeInterval(20))
        check(20)
        _ = c.remove(id: "a")
        check(20)
        _ = c.expire(now: t0.addingTimeInterval(20))
        check(20)
        c.removeAll()
        check(20)
    }

    /// An activity posted again with nothing new leaves the order exactly where it was, which is
    /// the whole point: nothing counted as a change, so nothing was sorted again.
    @Test func anUnchangedReportLeavesTheOrderStanding() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "A", state: .running, ttl: 0, sneak: false), now: t0)
        let before = c.revision
        try c.apply(ActivitySpec(id: "a", title: "A", state: .running, ttl: 0, sneak: false), now: t0.addingTimeInterval(1))
        #expect(c.revision == before)
    }

    @Test func everyChangeCounts() throws {
        var c = ActivityCenter()
        var seen: Set<UInt64> = [c.revision]
        func moved(_ change: () throws -> Void) rethrows {
            try change()
            #expect(seen.insert(c.revision).inserted)
        }
        try moved { try c.apply(ActivitySpec(id: "a", title: "A", endsAt: t0.addingTimeInterval(60), sneak: false), now: t0) }
        try moved { try c.apply(ActivitySpec(id: "a", title: "B", sneak: false), now: t0.addingTimeInterval(1)) }
        moved { c.clearClock(id: "a") }
        moved { _ = c.remove(id: "a") }
        try moved { try c.apply(ActivitySpec(id: "b", title: "B", ttl: 1, sneak: false), now: t0) }
        moved { _ = c.expire(now: t0.addingTimeInterval(2)) }
        try moved { try c.apply(ActivitySpec(id: "c", title: "C", sneak: false), now: t0) }
        moved { _ = c.removeAll(source: "api") }
        try moved { try c.apply(ActivitySpec(id: "d", title: "D", sneak: false), now: t0) }
        moved { c.removeAll() }
    }

    @Test func theWindowIsTheNextMomentSomethingCouldChange() throws {
        var c = ActivityCenter()
        #expect(c.orderedUntilChange(now: t0).validUntil == nil)
        try c.apply(ActivitySpec(id: "a", title: "A", ttl: 30, staleAt: t0.addingTimeInterval(5), sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "b", title: "B", ttl: 10, sneak: false), now: t0)
        #expect(c.orderedUntilChange(now: t0).validUntil == t0.addingTimeInterval(5))
        // Past the staleness: the next thing to happen is B expiring.
        #expect(c.orderedUntilChange(now: t0.addingTimeInterval(5)).validUntil == t0.addingTimeInterval(10))
        #expect(c.orderedUntilChange(now: t0.addingTimeInterval(10)).validUntil == t0.addingTimeInterval(30))
        #expect(c.orderedUntilChange(now: t0.addingTimeInterval(30)).validUntil == nil)
        // And the list itself is the ordinary one.
        #expect(c.orderedUntilChange(now: t0).activities == c.ordered(now: t0))
    }

    /// `Presenter.present` takes the order the caller already has, and answers exactly as it does
    /// when it works it out itself.
    @Test func thePresenterTakesTheOrderItIsGiven() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "A", priority: .high, sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "b", title: "B", sneak: false), now: t0.addingTimeInterval(1))
        var inputs = PresenterInputs(now: t0.addingTimeInterval(2), center: c)
        let worked = Presenter.present(inputs)
        inputs.orderedActivities = c.ordered(now: t0.addingTimeInterval(2))
        #expect(Presenter.present(inputs) == worked)
        #expect(worked == .compact(.activity(c.ordered(now: t0.addingTimeInterval(2))[0], others: 1)))
    }
}
