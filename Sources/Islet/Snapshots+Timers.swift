import AppKit
import IsletCore
import SwiftUI

extension Snapshots {
    /// The Timer card at every size, a ringing timer, the Pomodoro, the custom field, and
    /// the closed island for a paused and a ringing timer. Leaves the model as it found it.
    static func renderTimers(model: AppModel, now: Date, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        func engine(_ build: (inout TimerEngine) throws -> Void) -> TimerEngine {
            var e = TimerEngine()
            try? build(&e)
            return e
        }
        let running = engine { e in
            try e.start(seconds: 20 * 60, title: "Take the pizza out", now: now.addingTimeInterval(-468))
            try e.start(seconds: 4 * 60, title: "Tea", now: now.addingTimeInterval(-72))
            try e.pause("Tea", now: now)
        }
        let ringing = engine { e in
            try e.start(seconds: 4 * 60, title: "Tea", now: now.addingTimeInterval(-245))
            try e.start(seconds: 20 * 60, title: "Take the pizza out", now: now.addingTimeInterval(-468))
            _ = e.advance(now: now)
        }
        let pomodoro = engine { e in
            let start = now.addingTimeInterval(-41 * 60)
            try e.startPomodoro(now: start)
            _ = e.advance(now: start.addingTimeInterval(25 * 60))
            _ = e.advance(now: start.addingTimeInterval(30 * 60))
        }

        model.forcedPresentation = .expanded
        model.tab = .home
        for preset in [SizePreset.compact, .standard, .large] {
            size(preset)
            model.timers.showForSnapshot(TimerEngine())
            shoot("30-timer-card-\(preset.rawValue)")
            model.timers.showForSnapshot(running)
            shoot("31-timers-\(preset.rawValue)")
            model.timers.showForSnapshot(ringing)
            shoot("32-timer-ringing-\(preset.rawValue)")
            model.timers.showForSnapshot(pomodoro)
            shoot("33-pomodoro-\(preset.rawValue)")
            model.timers.isEntering = true
            shoot("34-timer-entry-\(preset.rawValue)")
            model.timers.isEntering = false
        }
        size(.compact)
        model.timers.showForSnapshot(TimerEngine())

        var center = ActivityCenter()
        func activity(_ e: TimerEngine, _ id: String) -> Activity? {
            guard let t = e.find(id) else { return nil }
            return try? center.apply(e.spec(for: t), now: now)
        }
        if let paused = activity(running, "Tea") {
            model.forcedPresentation = .compact(.activity(paused, others: 1))
            shoot("35-compact-timer-paused")
        }
        if let rang = activity(ringing, "Tea") {
            model.forcedPresentation = .sneak(rang)
            shoot("36-sneak-timer-ringing")
            model.forcedPresentation = .compact(.activity(rang, others: 1))
            shoot("37-compact-timer-ringing")
        }
        if let focus = activity(pomodoro, TimerEngine.pomodoroID) {
            model.forcedPresentation = .sneak(focus)
            shoot("38-sneak-pomodoro")
        }

        model.timers.showForSnapshot(TimerEngine())
        model.forcedPresentation = .expanded
    }
}
