import AppKit
import IsletCore
import SwiftUI

extension Snapshots {
    /// The tools: lyrics beside Now Playing, the Shortcuts and Weather pages (off and on), Today
    /// with the month calendar, the stopwatch, the timer composer with it, and a shortcut offered
    /// in the Ask box. Leaves the model's settings as it found them.
    static func renderTools(model: AppModel, now: Date, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        let saved = model.settings
        model.forcedPresentation = .expanded
        size(.compact)

        // Lyrics: made-up words, timed so the demo song (1:11 in) is on the third line.
        if let np = model.nowPlaying {
            model.settings.lyricsEnabled = true
            model.tab = .home
            let lyrics = SongLyrics(lines: LRC.parse("""
            [00:58.00] Lights along the river
            [01:04.50] Turning slowly into gold
            [01:10.00] Every window holds a story
            [01:15.50] Every corner something old
            [01:21.00]
            [01:27.00] We keep walking through the evening
            [01:33.00] Till the city starts to glow
            """))
            model.tools.lyrics.showForSnapshot(lyrics, for: np)
            for preset in [SizePreset.compact, .standard, .large] {
                size(preset)
                shoot("60-lyrics-\(preset.rawValue)")
            }
            size(.compact)
            model.tools.lyrics.showForSnapshot(lyrics, for: np, hidden: true)
            shoot("60b-lyrics-hidden")
            model.tools.lyrics.showForSnapshot(SongLyrics(plain: "Lights along the river\nTurning slowly into gold\nEvery window holds a story"), for: np)
            shoot("60c-lyrics-plain")
            model.tools.lyrics.showForSnapshot(nil, for: np)
            model.settings.lyricsEnabled = false
        }

        // Shortcuts: off (Turn on), then on with one running and one just done.
        model.tab = .shortcuts
        model.settings.shortcutsEnabled = false
        shoot("61-shortcuts-off")
        model.settings.shortcutsEnabled = true
        let shortcuts = [
            ShortcutItem(id: "1", name: "Morning routine"), ShortcutItem(id: "2", name: "Log a glass of water"),
            ShortcutItem(id: "3", name: "Lights off"), ShortcutItem(id: "4", name: "Text Sam I'm late"),
            ShortcutItem(id: "5", name: "Start a focus playlist"), ShortcutItem(id: "6", name: "Resize images"),
        ]
        model.tools.shortcuts.showForSnapshot(shortcuts, runs: ["3": .running, "1": .done])
        shoot("61b-shortcuts")
        size(.standard)
        shoot("61c-shortcuts-standard")
        size(.compact)
        model.tools.shortcuts.showForSnapshot(shortcuts, query: "zzz")
        shoot("61d-shortcuts-no-match")
        model.tools.shortcuts.showForSnapshot(shortcuts)

        // The Ask box offers a shortcut whose name matches.
        model.tab = .ask
        model.ask.clearForSnapshot()
        for kind in AskProviderKind.allCases { model.ask.setStatusForSnapshot(.ready, for: kind) }
        model.ask.sessionProvider = .anthropic
        model.ask.draft = "lights"
        shoot("61e-ask-shortcut")
        model.ask.draft = ""
        model.ask.sessionProvider = nil
        model.settings.shortcutsEnabled = false

        // Weather: off, then a week in London, then where it can't reach.
        model.tab = .weather
        model.settings.weatherEnabled = false
        shoot("62-weather-off")
        model.settings.weatherEnabled = true
        model.settings.weatherPlace = WeatherPlace(name: "London", region: "England", country: "United Kingdom", latitude: 51.51, longitude: -0.13)
        let days = [(61, 16.1, 9.8, 80), (3, 17.4, 10.2, 20), (2, 18.0, 11.0, 10), (0, 19.5, 10.9, 0),
                    (80, 15.2, 9.0, 60), (95, 14.8, 8.7, 70), (1, 16.6, 8.1, 5)]
        let report = WeatherReport(
            current: .init(temperature: 14.2, feelsLike: 12.6, code: 61, isDay: true, wind: 11),
            days: days.enumerated().map { i, d in
                WeatherReport.Day(date: String(format: "2026-10-%02d", i + 1), code: d.0, high: d.1, low: d.2, rainChance: d.3)
            },
            fetchedAt: now)
        model.tools.weather.showForSnapshot(report)
        shoot("62b-weather")
        size(.standard)
        shoot("62c-weather-standard")
        size(.compact)
        model.tools.weather.showForSnapshot(nil, status: .failed)
        shoot("62d-weather-failed")
        model.tools.weather.showForSnapshot(nil)

        // Today with the month calendar: today, then a picked day, and on a wide island.
        model.tab = .today
        model.settings.monthCalendar = true
        let cal = Calendar.current
        func on(_ day: Int, _ hour: Int, _ title: String, _ colour: String) -> AgendaItem {
            let first = MonthGrid.startOfMonth(now)
            let start = cal.date(byAdding: DateComponents(day: day - 1, hour: hour), to: first) ?? now
            return AgendaItem(id: "m\(day)-\(hour)", title: title, start: start, end: start.addingTimeInterval(3600), calendarColor: colour)
        }
        let month = model.agenda + [
            on(6, 10, "Dentist", "#0A84FF"), on(9, 14, "Team lunch", "#FF9F0A"), on(14, 9, "Quarterly review", "#FF9F0A"),
            on(14, 16, "Call with Ana", "#BF5AF2"), on(21, 18, "Book club", "#34C759"), on(27, 11, "Flight to Lisbon", "#FF453A"),
        ]
        model.tools.month.showForSnapshot(month: now, selected: nil, events: month)
        shoot("63-today-month")
        model.tools.month.showForSnapshot(month: now, selected: on(14, 0, "", "").start, events: month)
        shoot("63b-today-month-picked")
        model.tools.month.showForSnapshot(month: now, selected: nil, events: month)
        size(.standard)
        shoot("63c-today-month-standard")
        size(.large)
        shoot("63d-today-month-large")
        size(.compact)
        model.settings.monthCalendar = false

        // The stopwatch: Home's main thing with nothing playing, a glance beside the music,
        // beside the notch, and in the timer composer.
        model.settings.stopwatchEnabled = true
        var watch = Stopwatch()
        watch.start(now: now.addingTimeInterval(-754))
        watch.lap(now: now.addingTimeInterval(-500))
        watch.lap(now: now.addingTimeInterval(-212))
        model.tools.stopwatch.showForSnapshot(watch)
        model.tab = .home
        model.settings.mediaEnabled = false
        shoot("64-stopwatch")
        var paused = watch
        paused.pause(now: now)
        model.tools.stopwatch.showForSnapshot(paused)
        shoot("64b-stopwatch-paused")
        model.tools.stopwatch.showForSnapshot(watch)
        model.settings.mediaEnabled = true
        shoot("64c-stopwatch-glance")
        var center = ActivityCenter()
        if let spec = watch.spec(now: now), let a = try? center.apply(spec, now: now) {
            model.forcedPresentation = .compact(.activity(a, others: 0))
            shoot("64d-compact-stopwatch")
            model.closedPlacements[1] = ClosedPlacement(wing: MenuBarLayoutEngine.iconOnlyWing, slack: 0)
            shoot("i64d-compact-stopwatch")
            model.closedPlacements[1] = nil
            model.forcedPresentation = .expanded
        }
        model.tools.stopwatch.showForSnapshot(Stopwatch())
        model.timers.isEntering = true
        shoot("64e-timer-entry-stopwatch")
        size(.standard)
        shoot("64f-timer-entry-stopwatch-standard")
        size(.compact)
        model.timers.isEntering = false

        model.settings = saved
        size(saved.sizePreset)
        model.tab = .home
    }
}
