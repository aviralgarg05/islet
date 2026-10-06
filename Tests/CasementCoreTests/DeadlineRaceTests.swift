import Foundation
import Testing
@testable import CasementCore

/// `reschedule()` replaces the one timer. A moment that passed just before the old timer
/// fired must still come back, or the island waits for the next unrelated event.
@Suite struct DeadlineRaceTests {
    @Test func aMomentThatJustPassedIsNotLost() throws {
        var c = ActivityCenter(sneakDuration: 2)
        try c.apply(ActivitySpec(id: "a", title: "A", ttl: 5, sneak: true), now: t0)
        #expect(c.nextDeadline(now: t0) == t0.addingTimeInterval(2))
        // Something reschedules at 2.1 s, before the timer for the sneak's end at 2 s has fired.
        let late = t0.addingTimeInterval(2.1)
        #expect(c.nextDeadline(now: late) == late)
        c.expire(now: late)
        #expect(c.sneak == nil)
        #expect(c.nextDeadline(now: late) == t0.addingTimeInterval(5))
        // The same for the expiry, and the HUD.
        c.showHUD(.volume, value: 0.5, now: t0.addingTimeInterval(4))
        let later = t0.addingTimeInterval(6)
        #expect(c.nextDeadline(now: later) == later)
        c.expire(now: later)
        #expect(c.activities.isEmpty && c.hud == nil)
        #expect(c.nextDeadline(now: later) == nil)
    }

    @Test func goingStaleCountsOnceEvenWhenMissed() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "a", title: "A", staleAt: t0.addingTimeInterval(10), sneak: false), now: t0)
        c.expire(now: t0)
        #expect(c.nextDeadline(now: t0) == t0.addingTimeInterval(10))
        // Missed: still due, so the island redraws it dimmed.
        let late = t0.addingTimeInterval(11)
        #expect(c.nextDeadline(now: late) == late)
        // Dealt with: not due again, so the timer doesn't spin.
        c.expire(now: late)
        #expect(c.nextDeadline(now: late) == nil)
        #expect(c.nextDeadline(now: t0.addingTimeInterval(20)) == nil)
    }
}
