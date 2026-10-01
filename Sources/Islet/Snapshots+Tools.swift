import AppKit
import IsletCore
import IsletSystem
import SwiftUI

extension Snapshots {
    static let teleprompterDemo = """
    Good morning, everyone, and thank you for joining.
    Today I want to show you three things we shipped this month, and one we didn't.
    First, the new island pages. Each one starts switched off and waits under More until you turn it on.
    Second, the teleprompter you're reading right now. It moves just under the camera, so you look into the lens.
    Third, sales and stocks at a glance, without opening a browser tab.
    """

    /// The tools under "More" from the second set (mirror, teleprompter, stocks, sales) and the AI
    /// usage lines on Home, at the compact and standard sizes. Leaves the model as it found it.
    static func renderMoreTools(model: AppModel, now: Date, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        let saved = model.settings
        model.settings.mirror.enabled = true
        model.settings.teleprompter.enabled = true
        model.settings.stocks.enabled = true
        model.settings.sales = SalesSettings(enabled: true, stores: [.stripe, .shopify, .gumroad], shopifyStore: "example")
        model.forcedPresentation = .expanded

        for preset in [SizePreset.compact, .standard] {
            size(preset)
            let suffix = preset.rawValue
            model.tab = .mirror
            model.mirror.showDemo(.running, access: .granted)
            shoot("90-mirror-\(suffix)")
            model.tab = .teleprompter
            model.teleprompter.showDemo(teleprompterDemo, at: 18)
            shoot("91-teleprompter-\(suffix)")
            model.tab = .stocks
            model.stocks.showDemo(now: now)
            shoot("92-stocks-\(suffix)")
            model.tab = .sales
            model.sales.showDemo(now: now)
            shoot("93-sales-\(suffix)")
        }
        size(.compact)

        // Asking for the camera, and none connected.
        model.tab = .mirror
        model.mirror.showDemo(.needsAccess, access: .notDetermined)
        shoot("90b-mirror-allow")
        model.mirror.showDemo(.needsAccess, access: .denied)
        shoot("90c-mirror-not-allowed")
        model.mirror.showDemo(.noCamera, access: .granted)
        shoot("90d-mirror-no-camera")
        model.mirror.showDemo(.off, access: .notDetermined)

        // See-through while reading, on the Black theme too; and with no script yet.
        model.tab = .teleprompter
        model.settings.teleprompter.seeThrough = true
        model.teleprompter.showDemo(teleprompterDemo, at: 40)
        shoot("91b-teleprompter-see-through")
        model.settings.theme = .black
        shoot("91c-teleprompter-see-through-black")
        model.settings.theme = saved.theme
        model.settings.teleprompter.seeThrough = false
        model.settings.teleprompter.textSize = 28
        shoot("91d-teleprompter-large-text")
        model.settings.teleprompter.textSize = saved.teleprompter.textSize
        model.teleprompter.showDemo("", at: 0)
        shoot("91e-teleprompter-empty")

        // A symbol Yahoo doesn't know, one with no connection and no price yet, and one whose
        // earlier price stays while the new one can't be read.
        model.tab = .stocks
        model.stocks.showDemo(now: now)
        model.stocks.showDemoProblems(["NVDA": .message("No data found"), "^GSPC": .unreachable, "MSFT": .unreachable],
                                      stale: ["MSFT"])
        size(.standard)
        shoot("92b-stocks-problems-standard")
        size(.compact)

        // Every store connected: the list scrolls rather than running off the page.
        model.tab = .sales
        model.settings.sales.stores = SalesStore.allCases
        model.sales.showDemo(now: now, stores: SalesStore.allCases)
        shoot("93c-sales-every-store-compact")

        // Sales with no store connected yet.
        model.tab = .sales
        model.settings.sales.stores = []
        shoot("93b-sales-none-connected")

        // AI usage on Home: OpenRouter, Copilot and Ollama, then beside Claude and Codex.
        model.tab = .home
        model.toolUsage.showDemo(now: now)
        model.agentUsage.clearForSnapshot()
        size(.standard)
        shoot("94-home-ai-usage-standard")
        size(.compact)
        shoot("94b-home-ai-usage-compact")
        model.agentUsage.showDemo(now: now)
        size(.large)
        shoot("94c-home-ai-usage-with-agents-large")
        size(.compact)

        model.settings = saved
        model.tab = .home
    }
}

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
                shoot("90-lyrics-\(preset.rawValue)")
            }
            size(.compact)
            model.tools.lyrics.showForSnapshot(lyrics, for: np, hidden: true)
            shoot("90b-lyrics-hidden")
            model.tools.lyrics.showForSnapshot(SongLyrics(plain: "Lights along the river\nTurning slowly into gold\nEvery window holds a story"), for: np)
            shoot("90c-lyrics-plain")
            // A stopwatch (or a timer) counting stays above the lyrics.
            model.tools.lyrics.showForSnapshot(lyrics, for: np)
            var counting = Stopwatch()
            counting.start(now: now.addingTimeInterval(-754))
            model.tools.stopwatch.showForSnapshot(counting)
            shoot("90d-lyrics-counting")
            size(.standard)
            shoot("90e-lyrics-counting-standard")
            size(.compact)
            model.tools.stopwatch.showForSnapshot(Stopwatch())
            model.tools.lyrics.showForSnapshot(nil, for: np)
            model.settings.lyricsEnabled = false
        }

        // Shortcuts: off (Turn on), then on with one running and one just done.
        model.tab = .shortcuts
        model.settings.shortcutsEnabled = false
        shoot("91-shortcuts-off")
        model.settings.shortcutsEnabled = true
        let shortcuts = [
            ShortcutItem(id: "1", name: "Morning routine"), ShortcutItem(id: "2", name: "Log a glass of water"),
            ShortcutItem(id: "3", name: "Lights off"), ShortcutItem(id: "4", name: "Text Sam I'm late"),
            ShortcutItem(id: "5", name: "Start a focus playlist"), ShortcutItem(id: "6", name: "Resize images"),
        ]
        model.tools.shortcuts.showForSnapshot(shortcuts, runs: ["3": .running, "1": .done])
        shoot("91b-shortcuts")
        size(.standard)
        shoot("91c-shortcuts-standard")
        size(.compact)
        model.tools.shortcuts.showForSnapshot(shortcuts, query: "zzz")
        shoot("91d-shortcuts-no-match")
        model.tools.shortcuts.showForSnapshot(shortcuts)

        // The Ask box offers a shortcut whose name matches.
        model.tab = .ask
        model.ask.clearForSnapshot()
        for kind in AskProviderKind.allCases { model.ask.setStatusForSnapshot(.ready, for: kind) }
        model.ask.sessionProvider = .anthropic
        model.ask.draft = "lights"
        shoot("91e-ask-shortcut")
        model.ask.draft = ""
        model.ask.sessionProvider = nil
        model.settings.shortcutsEnabled = false

        // Weather: off, then a week in London, then where it can't reach.
        model.tab = .weather
        model.settings.weatherEnabled = false
        shoot("92-weather-off")
        model.settings.weatherEnabled = true
        model.settings.weatherPlace = WeatherPlace(name: "London", region: "England", country: "United Kingdom", latitude: 51.51, longitude: -0.13)
        let days = [(61, 16.1, 9.8, 80), (3, 17.4, 10.2, 20), (2, 18.0, 11.0, 10), (0, 19.5, 10.9, 0),
                    (80, 15.2, 9.0, 60), (95, 14.8, 8.7, 70), (1, 16.6, 8.1, 5)]
        // Dates from today on, as Open-Meteo gives them for a place in the Mac's time zone.
        func dayString(_ offset: Int) -> String {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
            let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        func week(from first: Int) -> [WeatherReport.Day] {
            days.enumerated().map { i, d in
                WeatherReport.Day(date: dayString(first + i), code: d.0, high: d.1, low: d.2, rainChance: d.3)
            }
        }
        let report = WeatherReport(
            current: .init(temperature: 14.2, feelsLike: 12.6, code: 61, isDay: true, wind: 11),
            days: week(from: 0), fetchedAt: now)
        model.tools.weather.showForSnapshot(report)
        shoot("92b-weather")
        size(.standard)
        shoot("92c-weather-standard")
        size(.compact)
        // Kept from yesterday evening and not replaced: from today on, and when it is from.
        model.tools.weather.showForSnapshot(WeatherReport(current: report.current, days: week(from: -1),
                                                          fetchedAt: now.addingTimeInterval(-15 * 3600)))
        shoot("92e-weather-kept")
        model.tools.weather.showForSnapshot(nil, status: .failed)
        shoot("92d-weather-failed")
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
        shoot("93-today-month")
        model.tools.month.showForSnapshot(month: now, selected: on(14, 0, "", "").start, events: month)
        shoot("93b-today-month-picked")
        model.tools.month.showForSnapshot(month: now, selected: nil, events: month)
        size(.standard)
        shoot("93c-today-month-standard")
        size(.large)
        shoot("93d-today-month-large")
        size(.compact)
        // A month of six weeks (August 2026 starts on a Saturday) on the shortest island.
        if let august = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 15)) {
            model.tools.month.showForSnapshot(month: august, selected: nil, events: [])
            shoot("93e-today-month-six-weeks")
        }
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
        shoot("94-stopwatch")
        var paused = watch
        paused.pause(now: now)
        model.tools.stopwatch.showForSnapshot(paused)
        shoot("94b-stopwatch-paused")
        model.tools.stopwatch.showForSnapshot(watch)
        model.settings.mediaEnabled = true
        shoot("94c-stopwatch-glance")
        var center = ActivityCenter()
        if let spec = watch.spec(now: now), let a = try? center.apply(spec, now: now) {
            model.forcedPresentation = .compact(.activity(a, others: 0))
            shoot("94d-compact-stopwatch")
            model.closedPlacements[1] = ClosedPlacement(wing: MenuBarLayoutEngine.iconOnlyWing, slack: 0)
            shoot("i94d-compact-stopwatch")
            model.closedPlacements[1] = nil
            model.forcedPresentation = .expanded
        }
        model.tools.stopwatch.showForSnapshot(Stopwatch())
        model.timers.isEntering = true
        shoot("94e-timer-entry-stopwatch")
        size(.standard)
        shoot("94f-timer-entry-stopwatch-standard")
        size(.compact)
        model.timers.isEntering = false

        model.settings = saved
        size(saved.sizePreset)
        model.tab = .home
    }
}
