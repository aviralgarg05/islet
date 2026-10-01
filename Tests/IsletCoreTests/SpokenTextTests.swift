import Foundation
import Testing
@testable import IsletCore

@Suite struct SpokenTextTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// UTC, so "tomorrow" doesn't depend on where the tests run.
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func activity(_ edit: (inout ActivitySpec) -> Void = { _ in }) throws -> Activity {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "a", source: "script", title: "Claude · islet")
        edit(&s)
        return try c.apply(s, now: now)
    }

    @Test func durations() {
        #expect(SpokenText.duration(0) == "0 seconds")
        #expect(SpokenText.duration(1) == "1 second")
        #expect(SpokenText.duration(45.9) == "45 seconds")
        #expect(SpokenText.duration(60) == "1 minute")
        #expect(SpokenText.duration(272) == "4 minutes 32 seconds")
        #expect(SpokenText.duration(3600) == "1 hour")
        #expect(SpokenText.duration(3900 + 59) == "1 hour 5 minutes")
        #expect(SpokenText.duration(26 * 3600) == "26 hours")
        #expect(SpokenText.duration(76 * 3600 + 600) == "3 days 4 hours")
        #expect(SpokenText.duration(-5) == "0 seconds")
        #expect(SpokenText.duration(.infinity) == "0 seconds")
        #expect(SpokenText.duration(.nan) == "0 seconds")
        #expect(SpokenText.duration(1e15) == SpokenText.duration(1e9))
    }

    @Test func phrasesReadSeparatorsAndShortUnitsAsWords() {
        #expect(SpokenText.phrase("Claude · islet") == "Claude, islet")
        #expect(SpokenText.phrase("SFO → JFK") == "SFO to JFK")
        #expect(SpokenText.phrase("in 9 min") == "in 9 minutes")
        #expect(SpokenText.phrase("1 min") == "1 minute")
        #expect(SpokenText.phrase("11 min") == "11 minutes")
        #expect(SpokenText.phrase("in 1 h 5 min") == "in 1 hour 5 minutes")
        #expect(SpokenText.phrase("2 h") == "2 hours")
        #expect(SpokenText.phrase("102–98") == "102 to 98")
        // Whole words only.
        #expect(SpokenText.phrase("3 mins of minutes") == "3 mins of minutes")
        #expect(SpokenText.phrase("5 hz") == "5 hz")
        #expect(SpokenText.phrase("Hi – there") == "Hi – there")
    }

    @Test func percent() {
        #expect(SpokenText.percent(0.456) == "46%")
        #expect(SpokenText.percent(1.7) == "100%")
        #expect(SpokenText.percent(-1) == "0%")
        #expect(SpokenText.percent(.nan) == "0%")
    }

    @Test func labelSaysTheStateAndSkipsWordsThatRepeatIt() throws {
        let waiting = try activity { $0.state = .waiting; $0.trailing = "Waiting"; $0.subtitle = "Needs permission to use Bash" }
        #expect(SpokenText.label(waiting) == "Claude, islet, waiting for you")
        #expect(SpokenText.label(waiting, detail: true) == "Claude, islet, waiting for you, Needs permission to use Bash")
        #expect(SpokenText.value(waiting, now: now) == nil)

        let failed = try activity { $0.title = "CI"; $0.state = .failure; $0.trailing = "3 failed" }
        #expect(SpokenText.label(failed) == "CI, failed")
        #expect(SpokenText.value(failed, now: now) == "3 failed")

        let running = try activity { $0.title = "Release build"; $0.progress = 0.46 }
        #expect(SpokenText.label(running) == "Release build")
        #expect(SpokenText.value(running, now: now) == "46%")

        let done = try activity { $0.title = "Deploy"; $0.state = .success; $0.trailing = "Done"; $0.subtitle = "Done" }
        #expect(SpokenText.label(done, detail: true) == "Deploy, done")
        #expect(SpokenText.value(done, now: now) == nil)
    }

    @Test func countdownsAndCountUps() throws {
        let tea = try activity { $0.title = "Tea"; $0.endsAt = now.addingTimeInterval(271.2) }
        #expect(SpokenText.value(tea, now: now) == "4 minutes 32 seconds left")
        #expect(SpokenText.value(tea, now: now.addingTimeInterval(400)) == "0 seconds left")

        let call = try activity { $0.title = "FaceTime"; $0.startedAt = now.addingTimeInterval(-754) }
        #expect(SpokenText.value(call, now: now) == "12 minutes 34 seconds so far")

        // Templates that count in minutes are read in minutes.
        let ride = try activity { $0.title = "Grey Prius"; $0.phase = "enroute"; $0.endsAt = now.addingTimeInterval(250) }
        #expect(SpokenText.value(ride, now: now) == "5 minutes left")
        let arrived = try activity { $0.title = "Grey Prius"; $0.phase = "arrived" }
        #expect(SpokenText.value(arrived, now: now) == "Here")

        // A wing that says "9 min" is read in words.
        let meeting = try activity { $0.title = "Standup"; $0.trailing = "9 min" }
        #expect(SpokenText.value(meeting, now: now) == "9 minutes")
    }

    @Test func stepsProgressAndIndeterminate() throws {
        #expect(SpokenText.value(try activity { $0.steps = 5; $0.step = 3 }, now: now) == "step 3 of 5")
        #expect(SpokenText.value(try activity { $0.progress = -1 }, now: now) == "in progress")
        #expect(SpokenText.value(try activity(), now: now) == nil)
    }

    @Test func templates() throws {
        let game = try activity { s in
            s.title = "Lakers at Celtics"
            s.teams = [ActivityTeam(abbr: "LAL", name: "Lakers", score: "102"), ActivityTeam(abbr: "BOS", score: "98")]
            s.period = "Q4"
        }
        #expect(SpokenText.value(game, now: now) == "Lakers 102, BOS 98, Q4")
        var clock = game
        clock.endsAt = now.addingTimeInterval(151)
        #expect(SpokenText.value(clock, now: now) == "Lakers 102, BOS 98, Q4")
        #expect(SpokenText.time(clock, now: now) == "2 minutes 31 seconds left")

        let order = try activity { s in
            s.title = "Swiggy"
            s.stageLabels = ["Placed", "Preparing", "On the way", "Delivered"]
            s.step = 2
            s.endsAt = now.addingTimeInterval(18 * 60)
        }
        #expect(SpokenText.value(order, now: now) == "Preparing, stage 2 of 4, 18 minutes left")

        let flight = try activity { s in
            s.title = "UA 1234 to New York"
            s.flight = ActivityFlight(number: "UA 1234", from: "SFO", to: "JFK", departs: now.addingTimeInterval(42 * 60),
                                      arrives: now.addingTimeInterval(6 * 3600))
        }
        #expect(SpokenText.value(flight, now: now) == "departs in 42 minutes")
        #expect(SpokenText.value(flight, now: now.addingTimeInterval(3600)) == "lands in 5 hours")

        let charge = try activity { s in
            s.title = "Supercharging"
            s.template = "gauge"
            s.progress = 0.72
            s.endsAt = now.addingTimeInterval(32 * 60)
        }
        #expect(SpokenText.value(charge, now: now) == "72%, 32 minutes left")

        let run = try activity { $0.title = "Run"; $0.metrics = [ActivityMetric(label: "distance", value: "5.2", unit: "km")] }
        #expect(SpokenText.value(run, now: now) == "5.2 km")
    }

    @Test func ringingAndPausedTimerActivities() throws {
        var engine = TimerEngine()
        try engine.start(seconds: 240, title: "Tea", now: now.addingTimeInterval(-245))
        _ = engine.advance(now: now)
        let rang = try #require(engine.find("Tea"))
        var c = ActivityCenter()
        let ringing = try c.apply(engine.spec(for: rang), now: now)
        #expect(SpokenText.label(ringing) == "Tea, time's up")
        // "Time's up" underneath says the state again.
        #expect(SpokenText.label(ringing, detail: true) == "Tea, time's up")
        #expect(SpokenText.value(ringing, now: now) == nil)

        var paused = TimerEngine()
        try paused.start(seconds: 240, title: "Pasta", now: now)
        try paused.pause("Pasta", now: now.addingTimeInterval(60))
        let p = try c.apply(paused.spec(for: try #require(paused.find("Pasta"))), now: now)
        #expect(SpokenText.label(p) == "Pasta")
        #expect(SpokenText.value(p, now: now) == "Paused")
    }

    @Test func timersOnHome() {
        let running = TimerItem(id: "t", title: "Tea", duration: 300, endsAt: now.addingTimeInterval(271.2), createdAt: now)
        #expect(SpokenText.timer(running, now: now) == "4 minutes 32 seconds left")
        let paused = TimerItem(id: "t", duration: 300, status: .paused, remaining: 240, createdAt: now)
        #expect(SpokenText.timer(paused, now: now) == "paused, 4 minutes left")
        let ringing = TimerItem(id: "t", duration: 300, status: .ringing, endsAt: now, createdAt: now)
        #expect(SpokenText.timer(ringing, now: now) == "time's up")
    }

    @Test func stopwatch() {
        var s = Stopwatch()
        s.start(now: now)
        #expect(SpokenText.stopwatch(s, now: now.addingTimeInterval(723)) == "12 minutes 3 seconds")
        s.lap(now: now.addingTimeInterval(30))
        #expect(SpokenText.stopwatch(s, now: now.addingTimeInterval(723)) == "12 minutes 3 seconds, lap 2")
        s.pause(now: now.addingTimeInterval(240))
        #expect(SpokenText.stopwatch(s, now: now.addingTimeInterval(900)) == "4 minutes, paused")
    }

    @Test func relativeTimesAndEvents() {
        let cal = utc
        #expect(SpokenText.relative(to: now.addingTimeInterval(20), now: now, calendar: cal) == "now")
        #expect(SpokenText.relative(to: now.addingTimeInterval(9 * 60 - 30), now: now, calendar: cal) == "in 9 minutes")
        #expect(SpokenText.relative(to: now.addingTimeInterval(60), now: now, calendar: cal) == "in 1 minute")
        #expect(SpokenText.relative(to: now.addingTimeInterval(65 * 60), now: now, calendar: cal) == "in 1 hour 5 minutes")
        #expect(SpokenText.relative(to: now.addingTimeInterval(-60), now: now, calendar: cal) == "1 minute ago")
        #expect(SpokenText.relative(to: now.addingTimeInterval(-5 * 60), now: now, calendar: cal) == "5 minutes ago")
        #expect(SpokenText.relative(to: now.addingTimeInterval(-90 * 60), now: now, calendar: cal) == "1 hour ago")
        // 14:13 UTC: twelve hours on is tomorrow, three days on is three days.
        #expect(SpokenText.relative(to: now.addingTimeInterval(12 * 3600), now: now, calendar: cal) == "tomorrow")
        #expect(SpokenText.relative(to: now.addingTimeInterval(3 * 86400), now: now, calendar: cal) == "in 3 days")

        let start = now.addingTimeInterval(9 * 60)
        #expect(SpokenText.when(start: start, now: now, ongoing: false, startText: "14:22", endText: "15:00", calendar: cal)
                == "in 9 minutes, at 14:22")
        #expect(SpokenText.when(start: start, now: now, ongoing: true, startText: "14:22", endText: "15:00", calendar: cal)
                == "now, until 15:00")
    }

    @Test func usageLimits() {
        let five = UsageWindow(id: "five_hour", usedPercent: 62, windowMinutes: 300, resetsAt: now.addingTimeInterval(72 * 60 - 20))
        #expect(SpokenText.usage(five, now: now) == ("5-hour limit", "62% used, resets in 1 hour 12 minutes"))
        let week = UsageWindow(id: "seven_day", usedPercent: 40, windowMinutes: 10080, resetsAt: now.addingTimeInterval(-1))
        #expect(SpokenText.usage(week, now: now) == ("Weekly limit", "0% used, reset"))
        let open = UsageWindow(id: "five_hour", usedPercent: 12.4)
        #expect(SpokenText.usage(open, now: now) == ("5-hour limit", "12% used"))
    }

    @Test func hudMediaBatteryAndPosition() {
        #expect(SpokenText.hud(HUDEvent(kind: .volume, value: 0.62, until: now)) == ("Volume", "62%"))
        #expect(SpokenText.hud(HUDEvent(kind: .volume, value: 0.62, muted: true, until: now)).value == "muted")
        #expect(SpokenText.hud(HUDEvent(kind: .microphone, value: 1, until: now)) == ("Microphone", "on"))
        #expect(SpokenText.hud(HUDEvent(kind: .keyboardBrightness, value: 0.5, until: now)).label == "Keyboard brightness")
        let np = NowPlaying(source: .spotify, title: "Midnight City", artist: "M83", isPlaying: true, timestamp: now)
        #expect(SpokenText.media(np) == "Midnight City, M83")
        let noArtist = NowPlaying(source: .spotify, appName: "Spotify", title: "Podcast", isPlaying: true, timestamp: now)
        #expect(SpokenText.media(noArtist) == "Podcast, Spotify")
        #expect(SpokenText.battery(level: 76, charging: true, pluggedIn: true) == "76%, charging")
        #expect(SpokenText.battery(level: 100, charging: false, pluggedIn: true) == "100%, plugged in")
        #expect(SpokenText.battery(level: 12, charging: false, pluggedIn: false) == "12%")
        #expect(SpokenText.position(80, of: 225) == "1 minute 20 seconds of 3 minutes 45 seconds")
    }
}

@Suite struct IslandInkTests {
    func contrast(_ opacity: Double) -> Double { RGBA.whiteOnBlack(opacity).contrastOnBlack }

    @Test func withoutIncreaseContrastNothingChanges() {
        #expect(IslandInk.allCases.map { $0.opacity(increasedContrast: false) } == [1, 0.64, 0.42, 0.24])
        #expect(IslandWash.allCases.map { $0.opacity(increasedContrast: false) } == [0.06, 0.10, 0.16, 0.09, 0.18, 0.14, 0])
    }

    @Test func increasedContrastInkReadsAtFourAndAHalfToOneAndKeepsItsOrder() {
        let ladder = IslandInk.allCases.map { $0.opacity(increasedContrast: true) }
        for (ink, opacity) in zip(IslandInk.allCases, ladder) {
            #expect(contrast(opacity) >= 4.5, "\(ink)")
            #expect(opacity >= ink.opacity(increasedContrast: false), "\(ink)")
        }
        // Each step still quieter than the one before.
        #expect(zip(ladder, ladder.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func increasedContrastLinesAndTracksReadAtThreeToOne() {
        for wash in IslandWash.allCases {
            #expect(wash.opacity(increasedContrast: true) > wash.opacity(increasedContrast: false), "\(wash)")
        }
        for wash in [IslandWash.hairline, .track, .ringTrack, .edge] {
            #expect(contrast(wash.opacity(increasedContrast: true)) >= 3, "\(wash)")
        }
        // The edge is drawn only with Increase Contrast.
        #expect(IslandWash.edge.opacity(increasedContrast: false) == 0)
    }
}
