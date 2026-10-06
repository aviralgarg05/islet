import Foundation
import Testing
@testable import CasementCore

@Suite struct StopwatchTests {
    let t = Date(timeIntervalSince1970: 50_000)

    @Test func countsWhileRunningAndHoldsWhilePaused() {
        var s = Stopwatch()
        #expect(!s.isActive)
        #expect(s.elapsed(at: t) == 0)
        s.start(now: t)
        #expect(s.isRunning)
        #expect(s.elapsed(at: t.addingTimeInterval(12)) == 12)
        s.pause(now: t.addingTimeInterval(12))
        #expect(!s.isRunning && s.isActive)
        #expect(s.elapsed(at: t.addingTimeInterval(500)) == 12)
        s.start(now: t.addingTimeInterval(100))
        #expect(s.elapsed(at: t.addingTimeInterval(103)) == 15)
        // Starting again while running changes nothing.
        s.start(now: t.addingTimeInterval(200))
        #expect(s.elapsed(at: t.addingTimeInterval(203)) == 115)
    }

    @Test func togglePausesAndResumes() {
        var s = Stopwatch()
        s.toggle(now: t)
        #expect(s.isRunning)
        s.toggle(now: t.addingTimeInterval(5))
        #expect(!s.isRunning)
        #expect(s.elapsed(at: t.addingTimeInterval(60)) == 5)
    }

    @Test func lapsOnlyWhileRunning() {
        var s = Stopwatch()
        s.lap(now: t)
        #expect(s.laps.isEmpty)
        s.start(now: t)
        s.lap(now: t.addingTimeInterval(30))
        s.lap(now: t.addingTimeInterval(75))
        #expect(s.laps == [30, 75])
        #expect(s.lapDurations == [30, 45])
        s.pause(now: t.addingTimeInterval(80))
        s.lap(now: t.addingTimeInterval(90))
        #expect(s.laps.count == 2)
        s.reset()
        #expect(s == Stopwatch())
    }

    @Test func lapsAreCapped() {
        var s = Stopwatch()
        s.start(now: t)
        for i in 0..<(Stopwatch.maxLaps + 10) { s.lap(now: t.addingTimeInterval(Double(i + 1))) }
        #expect(s.laps.count == Stopwatch.maxLaps)
    }

    @Test func showsAsACountUpOrAPausedTime() throws {
        var s = Stopwatch()
        #expect(s.spec(now: t) == nil)
        s.start(now: t)
        s.pause(now: t.addingTimeInterval(20))
        s.start(now: t.addingTimeInterval(100))
        let running = try #require(s.spec(now: t.addingTimeInterval(110)))
        #expect(running.id == Stopwatch.activityID)
        #expect(running.state == .running)
        // The count-up starts 20 seconds before it resumed, so it reads 0:30 ten seconds later.
        #expect(running.startedAt == t.addingTimeInterval(80))
        #expect(running.sneak == false)
        s.lap(now: t.addingTimeInterval(110))
        #expect(s.spec(now: t.addingTimeInterval(110))?.subtitle == "Lap 2")
        s.pause(now: t.addingTimeInterval(130))
        let paused = try #require(s.spec(now: t.addingTimeInterval(400)))
        #expect(paused.startedAt == nil)
        #expect(paused.trailing == "Paused")
        #expect(paused.subtitle == "0:50")
        // A valid activity.
        var center = ActivityCenter()
        #expect(throws: Never.self) { try center.apply(paused, now: t) }
    }

    @Test func survivesARelaunch() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("casement-stopwatch-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var s = Stopwatch()
        s.start(now: t)
        s.lap(now: t.addingTimeInterval(3))
        try s.save(to: file)
        #expect(Stopwatch.load(from: file) == s)
        #expect(Stopwatch.load(from: file.appendingPathExtension("missing")) == nil)
    }

    @Test func stopwatchStartsOff() {
        #expect(CasementSettings().stopwatchEnabled == false)
    }
}
