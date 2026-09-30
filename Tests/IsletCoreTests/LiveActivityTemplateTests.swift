import Foundation
import Testing
@testable import IsletCore

@Suite struct LiveActivityAppsTests {
    /// The generated table must match the research JSON it was generated from.
    @Test func generatedTableMatchesResearchJSON() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/research/07-live-activity-apps.json")
        struct Row: Decodable {
            var app: String
            var bundleID: String
            var aliases: [String]
            var category: String
            var symbol: String
            var tint: String
            var template: String
        }
        let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        #expect(rows.count == 119)
        for row in rows {
            let look = try #require(LiveActivityCatalog.all.first { $0.app == row.app }, "\(row.app) missing")
            #expect(look.bundleID == row.bundleID)
            #expect(look.aliases == row.aliases)
            #expect(look.category == row.category)
            #expect(look.symbol == row.symbol)
            #expect(look.tint == row.tint.uppercased())
            #expect(look.template.rawValue == row.template)
        }
    }

    @Test func namesAreUniqueAndEveryEntryIsValid() {
        let names = LiveActivityCatalog.all.map { $0.app.lowercased() }
        #expect(Set(names).count == names.count)
        #expect(LiveActivityCatalog.all.count > 119)
        for look in LiveActivityCatalog.all {
            #expect(RGBA.parse(look.tint) != nil, "\(look.app)")
            #expect(RGBA.parse(look.displayTint)!.contrastOnBlack >= 3, "\(look.app)")
        }
    }

    @Test func looksUpByBundleIDNameAndAliasIgnoringCase() {
        #expect(LiveActivityCatalog.look(for: "com.zimride.instant")?.app == "Lyft")
        #expect(LiveActivityCatalog.look(for: "COM.APPLE.FACETIME")?.app == "FaceTime")
        #expect(LiveActivityCatalog.look(for: "flighty")?.template == .flight)
        #expect(LiveActivityCatalog.look(for: "Apple Music")?.app == "Music")
        #expect(LiveActivityCatalog.look(for: "delta")?.app == "Fly Delta")
        #expect(LiveActivityCatalog.look(for: "Thuisbezorgd.nl")?.app == "Just Eat")
        #expect(LiveActivityCatalog.look(for: "Domino's")?.category == "delivery")
    }

    @Test func exactNameBeatsAnotherEntrysAlias() {
        // "Stopwatch" is an alias of Clock and also an entry of its own.
        #expect(LiveActivityCatalog.look(for: "Stopwatch")?.symbol == "stopwatch.fill")
        #expect(LiveActivityCatalog.look(for: "Timer")?.app == "Clock")
    }

    @Test func longestWholeWordMatchWins() {
        #expect(LiveActivityCatalog.look(for: "Uber Eats · 12 min")?.app == "Uber Eats")
        #expect(LiveActivityCatalog.look(for: "Uber · 4 min")?.app == "Uber")
        #expect(LiveActivityCatalog.look(for: "Delta Air Lines")?.app == "Fly Delta")
        // Whole words only: "Basecamp" must not match British Airways' "BA".
        #expect(LiveActivityCatalog.look(for: "Basecamp") == nil)
        #expect(LiveActivityCatalog.look(for: "") == nil)
    }

    @Test func sourceMatchesAreExactOnly() {
        #expect(LiveActivityCatalog.entry(forSource: "com.flightyapp.flighty")?.app == "Flighty")
        #expect(LiveActivityCatalog.entry(forSource: "timer")?.app == "Clock")
        #expect(LiveActivityCatalog.entry(forSource: "github-actions") == nil)
    }
}

@Suite struct ContrastTests {
    @Test func darkTintsAreLiftedAndBrightOnesKept() throws {
        #expect(RGBA.parse("#000000")!.readableOnBlack().hex == "#FFFFFF")
        #expect(RGBA.parse("#24292F")!.readableOnBlack().hex == "#FFFFFF")
        let orange = RGBA.parse("#FF9F0A")!
        #expect(orange.readableOnBlack() == orange)
        let navy = RGBA.parse("#0033A0")!
        let lifted = navy.readableOnBlack()
        #expect(lifted.contrastOnBlack >= 3)
        #expect(lifted.contrastOnBlack < 3.3)
        // Still blue: blue stays the largest channel.
        #expect(lifted.b > lifted.r && lifted.b > lifted.g)
    }

    @Test func hexRoundTrips() {
        #expect(RGBA.parse("#0A84FF")!.hex == "#0A84FF")
        #expect(RGBA.parse("red")!.hex == "#FF453A")
    }
}

@Suite struct TemplateModelTests {
    @Test func specDecodesEveryNewFieldAndOldPayloadsStillWork() throws {
        let json = """
        {"id":"g","title":"Lakers at Celtics","template":"score","compactShort":"3–1","trackerIcon":"sf:car.fill",
         "phase":"Arrived","stageLabels":["Placed","Ready"],"stageSymbols":["cart.fill","sf:checkmark"],
         "teams":[{"abbr":"LAL","name":"Lakers","score":102,"tint":"#552583"},{"abbr":"BOS","score":"98"}],
         "period":"Q4","flight":{"number":"UA 123","from":"SFO","to":"JFK","departs":1800000000,"gate":"B22"},
         "route":{"mode":"bus","line":"N","lineTint":"#0A84FF","stopsLeft":3},
         "metrics":[{"label":"distance","value":5.2,"unit":"km"},{"value":"5:31","unit":"/km"}]}
        """
        let s = try APIJSON.decoder.decode(ActivitySpec.self, from: Data(json.utf8))
        #expect(s.template == "score")
        #expect(s.trackerIcon == .symbol("car.fill"))
        #expect(s.stageSymbols == [.symbol("cart.fill"), .symbol("checkmark")])
        #expect(s.teams?[0].score == "102")
        #expect(s.teams?[1].badge == "BOS")
        #expect(s.flight?.departs == t0)
        #expect(s.route?.stopsLeft == 3)
        #expect(s.metrics?[0].text == "5.2 km")
        let old = try APIJSON.decoder.decode(ActivitySpec.self, from: Data(#"{"title":"Old","progress":0.5}"#.utf8))
        #expect(old.template == nil && old.teams == nil)
        // Activities stored before templates existed decode too.
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "x", title: "Old"), now: t0)
        var dict = try JSONSerialization.jsonObject(with: APIJSON.encoder.encode(a)) as! [String: Any]
        dict["template"] = nil
        let back = try APIJSON.decoder.decode(Activity.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(back.template == nil)
        #expect(back.title == "Old")
    }

    @Test func createStoresFieldsAndNormalisesNames() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "ride", title: "Grey Prius")
        s.template = "Live_Audio"
        s.phase = "En-route"
        let a = try c.apply(s, now: t0)
        #expect(a.template == .liveAudio)
        #expect(a.phase == "enroute")
        s.phase = "Waiting for the driver"
        #expect(try c.apply(s, now: t0).phase == "Waiting for the driver")
    }

    @Test func updateKeepsOmittedFieldsAndMergesObjects() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "f", title: "UA 123")
        s.flight = ActivityFlight(number: "UA 123", from: "SFO", to: "JFK", gate: "B22")
        s.teams = [ActivityTeam(abbr: "LAL", score: "0", tint: "purple"), ActivityTeam(abbr: "BOS", score: "0")]
        s.metrics = [ActivityMetric(label: "km", value: "1.0")]
        s.stageLabels = ["A", "B", "C"]
        s.period = "Q1"
        try c.apply(s, now: t0)

        var u = ActivitySpec(id: "f")
        u.flight = ActivityFlight(gate: "C4")
        u.teams = [ActivityTeam(score: "3"), ActivityTeam(score: "1")]
        let a = try c.apply(u, now: t0)
        #expect(a.flight == ActivityFlight(number: "UA 123", from: "SFO", to: "JFK", gate: "C4"))
        #expect(a.teams?.map(\.badge) == ["LAL", "BOS"])
        #expect(a.teams?.map(\.score) == ["3", "1"])
        #expect(a.teams?[0].tint == "purple")
        #expect(a.metrics?.first?.value == "1.0")
        #expect(a.stageLabels == ["A", "B", "C"])
        #expect(a.period == "Q1")

        // Empty strings and arrays clear.
        var clear = ActivitySpec(id: "f")
        clear.period = ""
        clear.stageLabels = []
        clear.teams = []
        let cleared = try c.apply(clear, now: t0)
        #expect(cleared.period == nil && cleared.stageLabels == nil && cleared.teams == nil)
        #expect(cleared.flight?.gate == "C4")
    }

    @Test func validationIsStrict() {
        var c = ActivityCenter()
        func reject(_ edit: (inout ActivitySpec) -> Void) {
            var s = ActivitySpec(id: "v", title: "V")
            edit(&s)
            #expect(throws: ActivityFieldError.self) { try c.apply(s, now: t0) }
        }
        reject { $0.template = "carousel" }
        reject { $0.compactShort = "123456" }
        reject { $0.teams = [ActivityTeam(abbr: "A")] }
        reject { $0.teams = [ActivityTeam(abbr: "TOOLONG"), ActivityTeam(abbr: "B")] }
        reject { $0.teams = [ActivityTeam(abbr: "A", tint: "nope"), ActivityTeam(abbr: "B")] }
        reject { $0.stageLabels = Array(repeating: "x", count: 9) }
        reject { $0.stageLabels = ["ok", ""] }
        reject { $0.metrics = Array(repeating: ActivityMetric(value: "1"), count: 4) }
        reject { $0.metrics = [ActivityMetric(value: "12345678901")] }
        reject { $0.flight = ActivityFlight(from: "LONDON") }
        reject { $0.flight = ActivityFlight(departs: t0, arrives: t0.addingTimeInterval(-60)) }
        reject { $0.route = ActivityRoute(lineTint: "#12") }
        reject { $0.route = ActivityRoute(stopsLeft: -1) }
        reject { $0.period = String(repeating: "x", count: 13) }
        // Nothing was half-applied.
        #expect(c.activities.isEmpty)
        #expect(ActivityFieldError("teams", "must have exactly 2 entries, got 1").description == "'teams' must have exactly 2 entries, got 1")
    }

    @Test func inferenceOrder() throws {
        func template(_ edit: (inout ActivitySpec) -> Void) throws -> ActivityTemplate {
            var c = ActivityCenter()
            var s = ActivitySpec(id: "i", source: "script", title: "Thing")
            edit(&s)
            return try c.apply(s, now: t0).resolvedTemplate
        }
        #expect(try template { _ in } == .progress)
        #expect(try template { $0.teams = [ActivityTeam(abbr: "A"), ActivityTeam(abbr: "B")]; $0.flight = ActivityFlight(number: "X") } == .score)
        #expect(try template { $0.flight = ActivityFlight(number: "X"); $0.route = ActivityRoute(line: "N") } == .flight)
        #expect(try template { $0.route = ActivityRoute(line: "N"); $0.stageLabels = ["a"] } == .route)
        #expect(try template { $0.stageLabels = ["a", "b"]; $0.trackerIcon = .symbol("car.fill") } == .stages)
        #expect(try template { $0.trackerIcon = .symbol("car.fill"); $0.metrics = [ActivityMetric(value: "1")] } == .eta)
        #expect(try template { $0.phase = "arrived" } == .eta)
        #expect(try template { $0.phase = "Planning" } == .progress)
        #expect(try template { $0.metrics = [ActivityMetric(value: "1")]; $0.endsAt = t0 } == .workout)
        #expect(try template { $0.endsAt = t0.addingTimeInterval(60) } == .timer)
        #expect(try template { $0.startedAt = t0 } == .timer)
        #expect(try template { $0.endsAt = t0.addingTimeInterval(60); $0.progress = 0.5 } == .progress)
        // Explicit beats everything.
        #expect(try template { $0.template = "gauge"; $0.teams = [ActivityTeam(abbr: "A"), ActivityTeam(abbr: "B")] } == .gauge)
    }

    @Test func catalogueTemplateForSourceNeedsItsData() throws {
        var c = ActivityCenter()
        // Tesla's catalogue template is gauge: used once there is a level.
        let charging = try c.apply(ActivitySpec(id: "t", source: "com.teslamotors.TeslaApp", title: "Charging", progress: 0.6), now: t0)
        #expect(charging.resolvedTemplate == .gauge)
        // Islet's Focus pill uses the source "focus", which is also a timer app's name: no end time, no timer.
        let focus = try c.apply(ActivitySpec(id: "f", source: "focus", title: "Work"), now: t0)
        #expect(focus.resolvedTemplate == .progress)
        let timer = try c.apply(ActivitySpec(id: "tm", source: "timer", title: "Tea", endsAt: t0.addingTimeInterval(60)), now: t0)
        #expect(timer.resolvedTemplate == .timer)
        // Media never comes from the catalogue alone.
        let spotify = try c.apply(ActivitySpec(id: "s", source: "Spotify", title: "Saved to library"), now: t0)
        #expect(spotify.resolvedTemplate == .progress)
    }

    @Test func etaTrackNeverMovesBackwards() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "ride", title: "Grey Prius", endsAt: t0.addingTimeInterval(600))
        s.template = "eta"
        try c.apply(s, now: t0)
        let half = t0.addingTimeInterval(300)
        #expect(c.activities["ride"]!.trackProgress(now: half) == 0.5)
        // The ETA slips by 5 minutes: the tracker holds where it is.
        var slip = ActivitySpec(id: "ride", endsAt: t0.addingTimeInterval(900))
        try c.apply(slip, now: half)
        let held = c.activities["ride"]!
        #expect(abs(held.trackProgress(now: half)! - 0.5) < 1e-9)
        #expect(abs(held.trackProgress(now: t0.addingTimeInterval(900))! - 1) < 1e-9)
        // The ETA improves: the tracker jumps forward on the original span.
        slip.endsAt = t0.addingTimeInterval(600)
        try c.apply(slip, now: half)
        #expect(c.activities["ride"]!.trackProgress(now: half)! > 0.5)
        // Explicit progress wins.
        try c.apply(ActivitySpec(id: "ride", progress: 0.2), now: half)
        #expect(c.activities["ride"]!.trackProgress(now: half) == 0.2)
    }

    @Test func etaText() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "e", title: "Uber", endsAt: t0.addingTimeInterval(4 * 60 + 10))
        s.template = "eta"
        let a = try c.apply(s, now: t0)
        #expect(a.templateTrailing(now: t0) == "5 min")
        #expect(a.minimalText(now: t0) == "5m")
        #expect(a.templateTrailing(now: t0.addingTimeInterval(400)) == "Now")
        var here = ActivitySpec(id: "e")
        here.phase = "arrived"
        let arrived = try c.apply(here, now: t0)
        #expect(arrived.templateTrailing(now: t0) == "Here")
        #expect(arrived.minimalText(now: t0) == nil)
    }

    @Test func stagesText() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "o", title: "Domino's", steps: 4, step: 2)
        s.stageLabels = ["Placed", "Making", "Delivering", "Delivered"]
        s.stageSymbols = [.symbol("list.bullet"), .symbol("flame.fill")]
        let a = try c.apply(s, now: t0)
        #expect(a.resolvedTemplate == .stages)
        #expect(a.currentStageLabel == "Making")
        #expect(a.currentStageSymbol == .symbol("flame.fill"))
        #expect(a.templateTrailing(now: t0) == "2/4")
        let later = try c.apply(ActivitySpec(id: "o", endsAt: t0.addingTimeInterval(720), step: 3), now: t0)
        #expect(later.currentStageSymbol == nil)
        #expect(later.templateTrailing(now: t0) == "12 min")
    }

    @Test func flightTextFollowsThePhase() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "fl", title: "UA 123")
        s.flight = ActivityFlight(number: "UA 123", from: "SFO", to: "JFK", departs: t0.addingTimeInterval(42 * 60),
                                  arrives: t0.addingTimeInterval(6 * 3600), carousel: "5")
        let a = try c.apply(s, now: t0)
        #expect(a.flightPhase(now: t0) == "predeparture")
        #expect(a.templateTrailing(now: t0) == "0:42")
        #expect(a.flightPhase(now: t0.addingTimeInterval(3600)) == "airborne")
        #expect(a.templateTrailing(now: t0.addingTimeInterval(3600)) == "5:00")
        #expect(a.flight!.progress(now: t0.addingTimeInterval(42 * 60)) == 0)
        #expect(a.templateTrailing(now: t0.addingTimeInterval(7 * 3600)) == "Belt 5")
        var boarding = ActivitySpec(id: "fl")
        boarding.phase = "Boarding"
        #expect(try c.apply(boarding, now: t0).flightPhase(now: t0.addingTimeInterval(7 * 3600)) == "boarding")
        #expect(ActivityFlight(status: "Delayed 25 min").statusKind == .delayed)
        #expect(ActivityFlight(status: "Cancelled").statusKind == .cancelled)
        #expect(ActivityFlight(status: "On time").statusKind == .normal)
    }

    @Test func routeScoreWorkoutGaugeAndAgentText() throws {
        var c = ActivityCenter()
        var route = ActivitySpec(id: "r", title: "N Judah", endsAt: t0.addingTimeInterval(180))
        route.route = ActivityRoute(mode: "tram", line: "N", stopsLeft: 1)
        let r = try c.apply(route, now: t0)
        #expect(r.templateTrailing(now: t0) == "1 stop")
        #expect(r.minimalText(now: t0) == "1")
        #expect(ActivityRoute(mode: "bus").symbol == "bus.fill")
        #expect(ActivityRoute(mode: "car", instruction: "Turn left onto Market St").symbol == "arrow.turn.up.left")

        var game = ActivitySpec(id: "g", title: "Game")
        game.teams = [ActivityTeam(abbr: "LAL", score: "3"), ActivityTeam(abbr: "BOS", score: "1")]
        let g = try c.apply(game, now: t0)
        #expect(g.templateTrailing(now: t0) == "3–1")
        #expect(g.minimalText(now: t0) == "3–1")
        var big = ActivitySpec(id: "g")
        big.teams = [ActivityTeam(score: "102"), ActivityTeam(score: "98")]
        #expect(try c.apply(big, now: t0).minimalText(now: t0) == nil)

        var run = ActivitySpec(id: "w", title: "Run", startedAt: t0)
        run.metrics = [ActivityMetric(label: "distance", value: "5.2", unit: "km")]
        let w = try c.apply(run, now: t0)
        #expect(w.templateTrailing(now: t0.addingTimeInterval(754)) == "12:34")
        #expect(w.minimalText(now: t0.addingTimeInterval(754)) == "12m")
        let rest = try c.apply(ActivitySpec(id: "w", endsAt: t0.addingTimeInterval(800)), now: t0)
        #expect(rest.templateTrailing(now: t0.addingTimeInterval(754)) == "0:46")

        var charge = ActivitySpec(id: "c", title: "Charging", progress: 0.72, endsAt: t0.addingTimeInterval(32 * 60))
        charge.template = "gauge"
        let gauge = try c.apply(charge, now: t0)
        #expect(gauge.templateTrailing(now: t0) == "32 min")
        #expect(gauge.minimalText(now: t0) == "72")

        var agent = ActivitySpec(id: "a", title: "Fix login", state: .running)
        agent.template = "agent"
        agent.phase = "Testing"
        #expect(try c.apply(agent, now: t0).templateTrailing(now: t0) == "Testing")
        #expect(try c.apply(ActivitySpec(id: "a", state: .waiting), now: t0).templateTrailing(now: t0) == "Needs you")

        var voice = ActivitySpec(id: "v", title: "ChatGPT")
        voice.template = "live-audio"
        #expect(try c.apply(voice, now: t0).templateTrailing(now: t0) == nil)
        var short = ActivitySpec(id: "v")
        short.compactShort = "Live"
        #expect(try c.apply(short, now: t0).minimalText(now: t0) == "Live")
    }

    @Test func timerFractionAndFormats() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "t", title: "Tea", endsAt: t0.addingTimeInterval(300)), now: t0)
        #expect(a.timerFractionLeft(now: t0.addingTimeInterval(60)) == 0.8)
        #expect(a.minimalText(now: t0.addingTimeInterval(60)) == "4m")
        #expect(a.minimalText(now: t0.addingTimeInterval(275)) == "25s")
        #expect(TemplateFormat.minutes(until: t0.addingTimeInterval(150 * 60), now: t0) == "3 h")
        #expect(TemplateFormat.hoursMinutes(until: t0.addingTimeInterval(13 * 3600 + 300), now: t0) == "13:05")
        #expect(TemplateFormat.hoursMinutes(until: t0.addingTimeInterval(5 * 86400), now: t0) == "5 d")
        #expect(TemplateFormat.shortDuration(since: t0, now: t0.addingTimeInterval(7300)) == "2h")
    }

    @Test func timerRingStartsFullForEachCountdown() throws {
        var c = ActivityCenter()
        // A timer restarted after it ran out: the new countdown starts with a full ring.
        try c.apply(ActivitySpec(id: "p", title: "Pomodoro", endsAt: t0.addingTimeInterval(1500)), now: t0)
        let brk = t0.addingTimeInterval(1500)
        let restarted = try c.apply(ActivitySpec(id: "p", endsAt: brk.addingTimeInterval(300)), now: brk)
        #expect(restarted.timerFractionLeft(now: brk) == 1)
        #expect(restarted.timerFractionLeft(now: brk.addingTimeInterval(150)) == 0.5)
        // An explicit start wins for a timer.
        let started = try c.apply(ActivitySpec(id: "s", title: "Eggs", endsAt: t0.addingTimeInterval(240),
                                               startedAt: t0.addingTimeInterval(-60)), now: t0)
        #expect(started.timerFractionLeft(now: t0) == 0.8)
        // A workout's rest countdown is measured from when it was set, not from the session start.
        var run = ActivitySpec(id: "w", title: "Legs", startedAt: t0.addingTimeInterval(-1500))
        run.metrics = [ActivityMetric(value: "3", unit: "sets")]
        try c.apply(run, now: t0)
        let rest = try c.apply(ActivitySpec(id: "w", endsAt: t0.addingTimeInterval(90)), now: t0)
        #expect(rest.resolvedTemplate == .workout)
        #expect(rest.timerFractionLeft(now: t0) == 1)
    }

    @Test func scoreGameClockTicks() throws {
        var c = ActivityCenter()
        var game = ActivitySpec(id: "g", title: "Game", endsAt: t0.addingTimeInterval(151))
        game.teams = [ActivityTeam(abbr: "A", score: "1"), ActivityTeam(abbr: "B", score: "0")]
        #expect(try c.apply(game, now: t0).templateRefresh(now: t0)?.interval == 1)
    }

    @Test func absurdDatesDoNotTrap() {
        let far = Date(timeIntervalSince1970: 1e297)
        let past = Date(timeIntervalSince1970: -1e297)
        #expect(TemplateFormat.minutes(until: far, now: t0).hasSuffix(" h"))
        #expect(TemplateFormat.hoursMinutes(until: far, now: t0).hasSuffix(" d"))
        #expect(TemplateFormat.shortDuration(until: far, now: t0).hasSuffix("h"))
        #expect(TemplateFormat.shortDuration(since: past, now: t0).hasSuffix("h"))
        #expect(Format.countdown(until: far, now: t0).hasSuffix(":40"))
        #expect(Format.clock(-1e297) == "0:00")
    }

    @Test func emptyStringsClearFieldsInsideObjects() throws {
        var c = ActivityCenter()
        var s = ActivitySpec(id: "f", title: "UA 1")
        s.flight = ActivityFlight(number: "", gate: "B22", status: "On time")
        s.route = ActivityRoute(line: "N", instruction: "Get off at Church")
        s.teams = [ActivityTeam(abbr: "A", tint: ""), ActivityTeam(abbr: "B")]
        let a = try c.apply(s, now: t0)
        #expect(a.flight?.number == nil)
        #expect(a.teams?[0].tint == nil)
        var u = ActivitySpec(id: "f")
        u.flight = ActivityFlight(gate: "", status: "")
        u.route = ActivityRoute(instruction: "")
        let b = try c.apply(u, now: t0)
        #expect(b.flight?.gate == nil && b.flight?.status == nil)
        #expect(b.route?.instruction == nil && b.route?.line == "N")
    }

    @Test func refreshTicksOnlyWhenTheTextCanChange() throws {
        var c = ActivityCenter()
        var eta = ActivitySpec(id: "e", title: "Ride", endsAt: t0.addingTimeInterval(250))
        eta.template = "eta"
        let e = try c.apply(eta, now: t0)
        // Minute counts tick once a minute, on the moments "5 min" becomes "4 min".
        let r = try #require(e.templateRefresh(now: t0))
        #expect(r.interval == 60)
        #expect(r.anchor == t0.addingTimeInterval(250 - 300))
        var here = ActivitySpec(id: "e")
        here.phase = "arrived"
        #expect(try c.apply(here, now: t0).templateRefresh(now: t0) == nil)

        let timer = try c.apply(ActivitySpec(id: "t", title: "Tea", endsAt: t0.addingTimeInterval(90.5)), now: t0)
        #expect(timer.templateRefresh(now: t0)?.interval == 1)
        #expect(timer.templateRefresh(now: t0)?.anchor == t0.addingTimeInterval(-0.5))
        #expect(timer.templateRefresh(now: t0.addingTimeInterval(100)) == nil)

        var game = ActivitySpec(id: "g", title: "Game")
        game.teams = [ActivityTeam(abbr: "A", score: "1"), ActivityTeam(abbr: "B", score: "0")]
        #expect(try c.apply(game, now: t0).templateRefresh(now: t0) == nil)

        let call = try c.apply(ActivitySpec(id: "c", title: "Call", startedAt: t0.addingTimeInterval(-30)), now: t0)
        #expect(call.templateRefresh(now: t0)?.anchor == t0.addingTimeInterval(-30))
    }

    /// Every example in docs/API.md's Templates section is valid and draws with its template.
    @Test func documentedExamplesAreValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/API.md")
        let doc = try String(contentsOf: url, encoding: .utf8)
        let start = try #require(doc.range(of: "### Templates"))
        let end = try #require(doc.range(of: "## HTTP API", range: start.upperBound..<doc.endIndex))
        let blocks = doc[start.upperBound..<end.lowerBound].components(separatedBy: "```json\n").dropFirst()
            .map { $0.components(separatedBy: "\n```")[0] }
        #expect(blocks.count == ActivityTemplate.allCases.count)
        var seen: Set<ActivityTemplate> = []
        for json in blocks {
            var c = ActivityCenter()
            let spec = try APIJSON.decoder.decode(ActivitySpec.self, from: Data(json.utf8))
            let a = try c.apply(spec, now: t0)
            #expect(a.resolvedTemplate.rawValue == spec.template, "\(json)")
            seen.insert(a.resolvedTemplate)
        }
        #expect(seen.count == ActivityTemplate.allCases.count)
    }

    @Test func templateMomentsSneakAndTicksStayQuiet() throws {
        var c = ActivityCenter()
        func sneaks(_ spec: ActivitySpec) throws -> Bool {
            c.cancelSneak()
            try c.apply(spec, now: t0)
            return c.currentSneak(now: t0) != nil
        }
        var ride = ActivitySpec(id: "r", title: "Ride", endsAt: t0.addingTimeInterval(300), sneak: false)
        ride.template = "eta"
        ride.phase = "enroute"
        try c.apply(ride, now: t0)
        #expect(try !sneaks(ActivitySpec(id: "r", endsAt: t0.addingTimeInterval(240))))
        var arrived = ActivitySpec(id: "r")
        arrived.phase = "arrived"
        #expect(try sneaks(arrived))
        #expect(try !sneaks(arrived))
        arrived.phase = "delivered"
        arrived.sneak = false
        #expect(try !sneaks(arrived))

        var order = ActivitySpec(id: "o", title: "Order", steps: 4, step: 1, sneak: false)
        order.stageLabels = ["A", "B", "C", "D"]
        try c.apply(order, now: t0)
        #expect(try sneaks(ActivitySpec(id: "o", step: 2)))
        #expect(try !sneaks(ActivitySpec(id: "o", subtitle: "Still cooking")))

        var game = ActivitySpec(id: "g", title: "Game", sneak: false)
        game.teams = [ActivityTeam(abbr: "A", score: "0"), ActivityTeam(abbr: "B", score: "0")]
        try c.apply(game, now: t0)
        var goal = ActivitySpec(id: "g")
        goal.teams = [ActivityTeam(score: "1"), ActivityTeam(score: "0")]
        #expect(try sneaks(goal))
        var clock = ActivitySpec(id: "g")
        clock.period = "Q2"
        #expect(try !sneaks(clock))

        var flight = ActivitySpec(id: "f", title: "UA 1", sneak: false)
        flight.flight = ActivityFlight(gate: "B22", status: "On time")
        try c.apply(flight, now: t0)
        var gate = ActivitySpec(id: "f")
        gate.flight = ActivityFlight(gate: "C4")
        #expect(try sneaks(gate))
        var delayed = ActivitySpec(id: "f")
        delayed.flight = ActivityFlight(status: "Delayed 20 min")
        #expect(try sneaks(delayed))
        delayed.flight = ActivityFlight(status: "Delayed 25 min")
        #expect(try !sneaks(delayed))

        var trip = ActivitySpec(id: "t", title: "N", sneak: false)
        trip.route = ActivityRoute(line: "N", stopsLeft: 4)
        try c.apply(trip, now: t0)
        trip.sneak = nil
        trip.route = ActivityRoute(stopsLeft: 3)
        #expect(try !sneaks(trip))
        trip.route = ActivityRoute(stopsLeft: 2)
        #expect(try sneaks(trip))
        trip.route = ActivityRoute(stopsLeft: 0)
        #expect(try sneaks(trip))
    }

    @Test func detectedCallsUseLiveAudio() {
        var d = CallDetector()
        guard case .started(let s) = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: t0).first else {
            Issue.record("expected a call")
            return
        }
        #expect(s.template == "live-audio")
    }
}

@Suite struct MirroredTemplateTests {
    @Test func mirroredActivityTakesTemplateAndReadableTint() throws {
        let m = MirroredLiveActivity(key: "k", appName: "Uber", detail: "Arriving · 4 min")
        let look = LiveActivityCatalog.look(for: m.appName).map { ($0.symbol, $0.tint) }
        let spec = MenuBarLiveActivities.activity(for: m, look: look, isNew: true)
        #expect(spec.template == "eta")
        #expect(spec.tint == "#FFFFFF")
        let lyft = MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "l", appName: "Lyft", detail: "3 min"),
                                                  look: LiveActivityCatalog.look(for: "Lyft").map { ($0.symbol, $0.tint) }, isNew: false)
        #expect(lyft.tint == "#FF00BF")
        let unknown = MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "u", appName: "Some App", detail: nil), look: nil, isNew: false)
        #expect(unknown.template == nil)
        var c = ActivityCenter()
        #expect(try c.apply(spec, now: t0).resolvedTemplate == .eta)
    }
}
