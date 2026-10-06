import Foundation
import Testing
@testable import CasementCore

@Suite struct TimerEngineTests {
    @Test func startsWithShortIDsAndReusesFreeOnes() throws {
        var e = TimerEngine()
        let a = try e.start(seconds: 300, title: "Tea", now: t0)
        #expect(a.id == "timer-1")
        #expect(a.status == .running)
        #expect(a.endsAt == t0.addingTimeInterval(300))
        #expect(a.duration == 300)
        #expect(try e.start(seconds: 60, now: t0).id == "timer-2")
        try e.stop("timer-1")
        #expect(try e.start(seconds: 60, now: t0).id == "timer-1")
        #expect(e.timers.count == 2)
    }

    @Test func validatesDurationsAndIDs() {
        var e = TimerEngine()
        #expect(throws: TimerError.invalidDuration(0)) { try e.start(seconds: 0, now: t0) }
        #expect(throws: TimerError.invalidDuration(-5)) { try e.start(seconds: -5, now: t0) }
        #expect(throws: TimerError.invalidDuration(86401)) { try e.start(seconds: 86401, now: t0) }
        #expect(throws: TimerError.self) { try e.start(seconds: .nan, now: t0) }
        #expect(throws: TimerError.invalidID("pomodoro")) { try e.start(seconds: 60, id: "pomodoro", now: t0) }
        #expect(throws: TimerError.invalidID("a b")) { try e.start(seconds: 60, id: "a b", now: t0) }
        // Its activity would take over a Live Activity mirrored from the menu bar.
        #expect(throws: TimerError.invalidID("live-3k9x")) { try e.start(seconds: 60, id: "live-3k9x", now: t0) }
        #expect(e.timers.isEmpty)
    }

    @Test func explicitIDReplacesAndTitlesAreTrimmed() throws {
        var e = TimerEngine()
        try e.start(seconds: 60, title: "  Eggs ", id: "eggs", now: t0)
        try e.start(seconds: 420, title: "Eggs", id: "eggs", now: t0)
        #expect(e.timers.count == 1)
        #expect(e.timers[0].duration == 420)
        #expect(e.timers[0].title == "Eggs")
        #expect(try e.start(seconds: 60, title: "   ", now: t0).title == nil)
        #expect(e.find("timer-1")?.displayTitle == "Timer")
    }

    @Test func tooManyTimers() throws {
        var e = TimerEngine()
        for _ in 0..<TimerEngine.maxTimers { try e.start(seconds: 60, now: t0) }
        #expect(throws: TimerError.tooMany) { try e.start(seconds: 60, now: t0) }
    }

    @Test func pauseKeepsTheRemainingTimeAndResumeSetsANewEnd() throws {
        var e = TimerEngine()
        try e.start(seconds: 300, title: "Tea", now: t0)
        let p = try e.pause("timer-1", now: t0.addingTimeInterval(100))
        #expect(p.status == .paused)
        #expect(p.endsAt == nil)
        #expect(p.remaining == 200)
        #expect(p.timeLeft(at: t0.addingTimeInterval(9999)) == 200)
        #expect(e.nextDeadline() == nil)
        // Pausing again changes nothing.
        #expect(try e.pause("timer-1", now: t0.addingTimeInterval(150)).remaining == 200)
        let r = try e.resume("timer-1", now: t0.addingTimeInterval(500))
        #expect(r.status == .running)
        #expect(r.endsAt == t0.addingTimeInterval(700))
        #expect(r.remaining == nil)
        // Resuming a running timer changes nothing.
        #expect(try e.resume("timer-1", now: t0.addingTimeInterval(600)).endsAt == t0.addingTimeInterval(700))
    }

    @Test func addExtendsRunningPausedAndRinging() throws {
        var e = TimerEngine()
        try e.start(seconds: 300, now: t0)
        #expect(try e.add(60, to: "timer-1", now: t0).endsAt == t0.addingTimeInterval(360))
        try e.pause("timer-1", now: t0.addingTimeInterval(60))
        #expect(try e.add(60, to: "timer-1", now: t0).remaining == 360)
        try e.resume("timer-1", now: t0)
        _ = e.advance(now: t0.addingTimeInterval(360))
        #expect(e.timers[0].status == .ringing)
        let again = try e.add(120, to: "timer-1", now: t0.addingTimeInterval(400))
        #expect(again.status == .running)
        #expect(again.endsAt == t0.addingTimeInterval(520))
        #expect(throws: TimerError.invalidDuration(0)) { try e.add(0, to: "timer-1", now: t0) }
        // Never more than 24 hours left.
        #expect(try e.add(86400, to: "timer-1", now: t0).endsAt == t0.addingTimeInterval(86400))
    }

    @Test func stopRestartAndSnooze() throws {
        var e = TimerEngine()
        try e.start(seconds: 240, title: "Tea", now: t0)
        _ = e.advance(now: t0.addingTimeInterval(240))
        let snoozed = try e.snooze("timer-1", now: t0.addingTimeInterval(250))
        #expect(snoozed.status == .running)
        #expect(snoozed.endsAt == t0.addingTimeInterval(550))
        #expect(snoozed.duration == 240)
        // Snoozing a running timer adds five minutes.
        #expect(try e.snooze("timer-1", now: t0).endsAt == t0.addingTimeInterval(850))
        let restarted = try e.restart("timer-1", now: t0.addingTimeInterval(1000))
        #expect(restarted.endsAt == t0.addingTimeInterval(1240))
        #expect(try e.stop("timer-1").title == "Tea")
        #expect(e.timers.isEmpty)
        #expect(throws: TimerError.notFound("timer-1")) { try e.stop("timer-1") }
        #expect(throws: TimerError.noTimers) { try e.stop() }
    }

    @Test func findsByIDNumberTitleOrDefault() throws {
        var e = TimerEngine()
        try e.start(seconds: 600, title: "Pizza", now: t0)
        try e.start(seconds: 300, title: "Tea", now: t0)
        #expect(e.find("timer-2")?.title == "Tea")
        #expect(e.find("2")?.title == "Tea")
        #expect(e.find("pizza")?.id == "timer-1")
        #expect(e.find(nil)?.id == "timer-2")
        #expect(e.find("  ")?.id == "timer-2")
        #expect(e.find("nope") == nil)
        // A ringing timer is the default target, even when it is older.
        _ = e.advance(now: t0.addingTimeInterval(300))
        #expect(e.find(nil)?.title == "Tea")
        try e.stop()
        #expect(e.find(nil)?.title == "Pizza")
        // An ambiguous title matches nothing.
        try e.start(seconds: 60, title: "Pizza", now: t0)
        #expect(e.find("Pizza") == nil)
    }

    @Test func advanceRingsOnlyAtTheEnd() throws {
        var e = TimerEngine()
        try e.start(seconds: 60, title: "Tea", now: t0)
        #expect(e.advance(now: t0.addingTimeInterval(59.9)).isEmpty)
        #expect(e.nextDeadline() == t0.addingTimeInterval(60))
        let events = e.advance(now: t0.addingTimeInterval(60.02))
        guard case .finished(let t)? = events.first else { Issue.record("expected finished"); return }
        #expect(t.status == .ringing)
        #expect(t.endsAt == t0.addingTimeInterval(60))
        #expect(e.isRinging)
        #expect(e.nextDeadline() == nil)
        // Already ringing: nothing new.
        #expect(e.advance(now: t0.addingTimeInterval(120)).isEmpty)
    }

    @Test func timersMissedByMoreThanAnHourAreDropped() throws {
        var e = TimerEngine()
        try e.start(seconds: 60, title: "Tea", now: t0)
        try e.start(seconds: 7200, title: "Bread", now: t0)
        let events = e.advance(now: t0.addingTimeInterval(60 + 3601))
        #expect(events.count == 1)
        guard case .missed(let t)? = events.first else { Issue.record("expected missed"); return }
        #expect(t.title == "Tea")
        #expect(e.timers.map(\.title) == ["Bread"])
    }

    @Test func orderIsRingingThenSoonestThenPaused() throws {
        var e = TimerEngine()
        try e.start(seconds: 900, title: "Late", now: t0)
        try e.start(seconds: 300, title: "Paused", now: t0)
        try e.pause("Paused", now: t0)
        try e.start(seconds: 600, title: "Soon", now: t0)
        try e.start(seconds: 30, title: "Rings", now: t0)
        _ = e.advance(now: t0.addingTimeInterval(30))
        #expect(e.ordered.map(\.displayTitle) == ["Rings", "Soon", "Late", "Paused"])
        #expect(e.nextDeadline() == t0.addingTimeInterval(600))
    }

    @Test func pomodoroCyclesThroughFocusAndBreaks() throws {
        var e = TimerEngine()
        let s = PomodoroSchedule()
        let first = try e.startPomodoro(now: t0, schedule: s)
        #expect(first.id == TimerEngine.pomodoroID)
        #expect(first.phase == .focus)
        #expect(first.displayTitle == "Focus")
        #expect(first.endsAt == t0.addingTimeInterval(25 * 60))
        // Starting again is a no-op.
        #expect(try e.startPomodoro(now: t0.addingTimeInterval(10), schedule: s) == first)

        var clock = t0
        var phases: [PomodoroPhase] = []
        for _ in 0..<9 {
            clock = e.nextDeadline()!
            let events = e.advance(now: clock, schedule: s)
            guard case .phaseChanged(_, let next)? = events.first else { Issue.record("expected a phase change"); return }
            // On time: the next phase starts exactly where the last one ended.
            #expect(next.endsAt == clock.addingTimeInterval(s.seconds(for: next.phase!)))
            phases.append(next.phase!)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus, .shortBreak])
        #expect(e.completedFocus == 5)
        #expect(e.timers.count == 1)
    }

    @Test func pomodoroStartsAfreshAfterASleepAndStops() throws {
        var e = TimerEngine()
        try e.startPomodoro(now: t0)
        let woke = t0.addingTimeInterval(25 * 60 + 600)
        _ = e.advance(now: woke)
        #expect(e.pomodoro?.phase == .shortBreak)
        #expect(e.pomodoro?.endsAt == woke.addingTimeInterval(5 * 60))
        #expect(e.stopPomodoro() != nil)
        #expect(e.pomodoro == nil)
        #expect(e.completedFocus == 0)
        #expect(e.stopPomodoro() == nil)
    }

    @Test func pomodoroMissedForHoursIsDropped() throws {
        var e = TimerEngine()
        try e.startPomodoro(now: t0)
        let events = e.advance(now: t0.addingTimeInterval(8 * 3600))
        guard case .missed? = events.first else { Issue.record("expected missed"); return }
        #expect(e.pomodoro == nil)
    }

    @Test func customScheduleAndLenientDecoding() throws {
        let s = PomodoroSchedule(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, longBreakEvery: 2)
        var e = TimerEngine()
        try e.startPomodoro(now: t0, schedule: s)
        #expect(e.pomodoro?.duration == 3000)
        #expect(s.phase(after: .focus, completedFocus: 1) == .shortBreak)
        #expect(s.phase(after: .focus, completedFocus: 2) == .longBreak)
        #expect(s.phase(after: .longBreak, completedFocus: 2) == .focus)

        let partial = try JSONDecoder().decode(PomodoroSchedule.self, from: Data(#"{"focusMinutes": 50}"#.utf8))
        #expect(partial == PomodoroSchedule(focusMinutes: 50))
        let wild = try JSONDecoder().decode(PomodoroSchedule.self, from: Data(#"{"focusMinutes": -3, "shortBreakMinutes": "x", "longBreakEvery": 0}"#.utf8))
        #expect(wild == PomodoroSchedule(focusMinutes: 1, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 1))
        #expect(PomodoroSchedule(focusMinutes: 9999).seconds(for: .focus) == 240 * 60)
    }

    @Test func settingsCarryTimerSoundAndPomodoro() {
        #expect(CasementSettings().timerSound == "Glass")
        let s = CasementSettings.decodeLenient(Data(#"{"timerSound": "none", "pomodoro": {"focusMinutes": 45, "longBreakEvery": 3}}"#.utf8))
        #expect(s.timerSound == "none")
        #expect(s.pomodoro == PomodoroSchedule(focusMinutes: 45, longBreakEvery: 3))
    }

    @Test func performMapsCommands() throws {
        var e = TimerEngine()
        let t = try e.perform(.start(seconds: 60, title: "Tea", id: nil), now: t0)
        #expect(t?.id == "timer-1")
        #expect(try e.perform(.control(.pause, id: nil, seconds: nil), now: t0)?.status == .paused)
        #expect(try e.perform(.control(.resume, id: "1", seconds: nil), now: t0)?.status == .running)
        #expect(try e.perform(.control(.add, id: nil, seconds: nil), now: t0)?.endsAt == t0.addingTimeInterval(120))
        #expect(try e.perform(.control(.snooze, id: nil, seconds: 30), now: t0)?.endsAt == t0.addingTimeInterval(150))
        #expect(try e.perform(.control(.restart, id: nil, seconds: nil), now: t0)?.endsAt == t0.addingTimeInterval(60))
        #expect(try e.perform(.control(.stop, id: nil, seconds: nil), now: t0) == nil)
        #expect(e.timers.isEmpty)
        #expect(try e.perform(.pomodoro(.toggle), now: t0)?.phase == .focus)
        #expect(try e.perform(.pomodoro(.toggle), now: t0) == nil)
        #expect(try e.perform(.pomodoro(.start), now: t0)?.id == "pomodoro")
        #expect(try e.perform(.pomodoro(.stop), now: t0) == nil)
        #expect(e.timers.isEmpty)
    }

    @Test func runningSpecIsALiveCountdown() throws {
        var e = TimerEngine()
        let t = try e.start(seconds: 300, title: "Tea", now: t0)
        let spec = e.spec(for: t)
        #expect(spec.id == "timer-1")
        #expect(spec.source == "timer")
        #expect(spec.title == "Tea")
        #expect(spec.icon == .symbol("timer"))
        #expect(spec.tint == "orange")
        #expect(spec.state == .running)
        #expect(spec.endsAt == t0.addingTimeInterval(300))
        #expect(spec.trailing == nil)
        #expect(spec.ttl == 0)
        var center = ActivityCenter()
        let a = try center.apply(spec, now: t0)
        #expect(a.trailingText(now: t0.addingTimeInterval(60)) == "4:00")
        #expect(a.expiresAt == nil)
    }

    @Test func pausedSpecHasNoCountdown() throws {
        var e = TimerEngine()
        try e.start(seconds: 300, title: "Tea", now: t0)
        let t = try e.pause("Tea", now: t0.addingTimeInterval(100))
        let spec = e.spec(for: t)
        #expect(spec.endsAt == nil)
        // The time left, still and grey, so a narrow wing keeps digits instead of an "i".
        #expect(spec.trailing == "3:20")
        #expect(spec.subtitle == "Paused")
        #expect(spec.tint == "gray")
        // The ring stays where it stopped: the share of the time still to run.
        #expect(abs((spec.progress ?? 0) - 200.0 / 300) < 0.0001)
        var center = ActivityCenter()
        let a = try center.apply(spec, now: t0)
        #expect(a.trailingText(now: t0) == "3:20")
        #expect(NarrowValue.glyph(for: "3:20", state: a.state) == nil)
        #expect(!center.needsClockTick(now: t0))
    }

    @Test func ringingSpecIsCriticalWithActions() throws {
        var e = TimerEngine()
        try e.start(seconds: 60, title: "Tea", now: t0)
        _ = e.advance(now: t0.addingTimeInterval(60))
        let spec = e.spec(for: e.timers[0])
        #expect(spec.priority == .critical)
        #expect(spec.state == .waiting)
        #expect(spec.icon == .symbol("alarm.fill"))
        // A number, not a status word, so a narrow wing doesn't trade it for the waiting bubble.
        #expect(spec.trailing == "0:00")
        #expect(NarrowValue.glyph(for: spec.trailing ?? "", state: spec.state ?? .info) == nil)
        #expect(spec.subtitle == "Time\u{2019}s up")
        #expect(spec.endsAt == nil)
        #expect(spec.actions?.map(\.title) == ["Stop", "Snooze 5 min", "Restart"])
        #expect(spec.actions?.allSatisfy { $0.dismiss == false } == true)
        // The action links go back through the URL scheme.
        let stop = try #require(spec.actions?.first?.url)
        #expect(try URLCommand.parse(stop) == .timerCommand(.control(.stop, id: "timer-1", seconds: nil)))
    }

    @Test func pomodoroSpecShowsTheRound() throws {
        var e = TimerEngine()
        let s = PomodoroSchedule()
        try e.startPomodoro(now: t0, schedule: s)
        #expect(e.spec(for: e.pomodoro!, schedule: s).subtitle == "Round 1 of 4")
        #expect(e.spec(for: e.pomodoro!, schedule: s).icon == .symbol("leaf.fill"))
        #expect(e.pomodoroRound(e.pomodoro!, schedule: s, short: true) == "1/4")
        _ = e.advance(now: e.nextDeadline()!, schedule: s)
        #expect(e.pomodoroRound(e.pomodoro!, schedule: s) == "Round 1 of 4 done")
        #expect(e.pomodoroRound(e.pomodoro!, schedule: s, short: true) == nil)
        #expect(e.spec(for: e.pomodoro!, schedule: s).icon == .symbol("cup.and.saucer.fill"))
        for _ in 0..<6 { _ = e.advance(now: e.nextDeadline()!, schedule: s) }
        #expect(e.pomodoro?.phase == .longBreak)
        #expect(e.pomodoroRound(e.pomodoro!, schedule: s) == "All 4 rounds done")
    }

    @Test func savesAndLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-timers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("timers.json")
        #expect(TimerEngine.load(from: url) == nil)
        var e = TimerEngine()
        try e.start(seconds: 300, title: "Tea", now: t0.addingTimeInterval(0.25))
        try e.start(seconds: 600, now: t0)
        try e.pause("2", now: t0.addingTimeInterval(12.5))
        try e.startPomodoro(now: t0)
        _ = e.advance(now: t0.addingTimeInterval(25 * 60))
        try e.save(to: url)
        #expect(TimerEngine.load(from: url) == e)
        try Data("not json".utf8).write(to: url)
        #expect(TimerEngine.load(from: url) == nil)
    }
}
