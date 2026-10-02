import Foundation
import Testing
@testable import IsletCore

/// What the closed island's wings show when the full value doesn't fit: a short form, a glyph
/// or nothing, never a shrunken or cut value.
@Suite struct WingValueTests {
    private func activity(_ spec: ActivitySpec, template: String? = nil, now: Date = t0) throws -> Activity {
        var spec = spec
        spec.template = template
        var c = ActivityCenter()
        return try c.apply(spec, now: now)
    }

    @Test func shortFormsSayTheSameInFewerCharacters() throws {
        // An order's minutes, an order's stage, a flight's departure and arrival.
        var order = ActivitySpec(id: "o", title: "Swiggy", endsAt: t0.addingTimeInterval(18 * 60))
        order.stageLabels = ["Placed", "Preparing", "On the way", "Delivered"]
        #expect(try activity(order).wingShort(now: t0) == "18m")
        var later = ActivitySpec(id: "o", title: "Swiggy", step: 2)
        later.stageLabels = order.stageLabels
        #expect(try activity(later).wingShort(now: t0) == "2/4")

        var flight = ActivitySpec(id: "f", title: "UA 1234")
        flight.flight = ActivityFlight(number: "UA 1234", from: "SFO", to: "JFK", departs: t0.addingTimeInterval(42 * 60),
                                       arrives: t0.addingTimeInterval(6 * 3600))
        let f = try activity(flight)
        #expect(f.wingShort(now: t0) == "42m")
        #expect(f.wingShort(now: t0.addingTimeInterval(5 * 3600)) == "60m")
        // Minutes up to 99, never a rounded-up hour: 72 minutes is "72m", not "2h".
        #expect(f.wingShort(now: t0.addingTimeInterval(6 * 3600 - 72 * 60)) == "72m")
        #expect(f.wingShort(now: t0.addingTimeInterval(7 * 3600)) == nil)

        // A call's length, a keep-awake's hours, a gauge's time to full or its level.
        let call = try activity(ActivitySpec(id: "c", title: "ChatGPT", startedAt: t0), template: "live-audio")
        #expect(call.wingShort(now: t0.addingTimeInterval(754)) == "12m")
        let awake = try activity(ActivitySpec(id: "k", title: "Keep awake", endsAt: t0.addingTimeInterval(2 * 3600 - 6)))
        #expect(awake.templateTrailing(now: t0) == "1:59:54")
        #expect(awake.wingShort(now: t0) == "2h")
        let charging = try activity(ActivitySpec(id: "g", title: "Charging", progress: 0.72, endsAt: t0.addingTimeInterval(32 * 60)),
                                    template: "gauge")
        #expect(charging.wingShort(now: t0) == "32m")
        #expect(charging.wingShort(now: t0.addingTimeInterval(33 * 60)) == "72%")

        // An agent's steps rather than its phase; a route's stops are drawn, not shortened.
        var agent = ActivitySpec(id: "a", title: "Fix login flow", state: .running, steps: 7, step: 3)
        agent.phase = "Testing"
        #expect(try activity(agent, template: "agent").wingShort(now: t0) == "3/7")
        var route = ActivitySpec(id: "r", title: "N Judah")
        route.route = ActivityRoute(mode: "tram", line: "N", stopsLeft: 3)
        #expect(try activity(route).wingShort(now: t0) == nil)

        // What the sender gave wins.
        var short = ActivitySpec(id: "s", title: "Live", startedAt: t0)
        short.compactShort = "On"
        #expect(try activity(short).wingShort(now: t0) == "On")

        // A value sent in words shortens the same way: a mirrored ride's "4 min" is "4m".
        let ride = MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "u", appName: "Uber", detail: "Arriving · 4 min"),
                                                  look: LiveActivityCatalog.look(for: "Uber").map { ($0.symbol, $0.tint) }, isNew: false)
        #expect(try activity(ride, template: ride.template).wingShort(now: t0) == "4m")
        #expect(TemplateFormat.compactUnits("2 hours") == "2h")
        #expect(TemplateFormat.compactUnits("45 sec") == "45s")
        #expect(TemplateFormat.compactUnits("Arriving") == nil)
        #expect(TemplateFormat.compactUnits("3 stops") == nil)
    }

    @Test func aStatusWordTurnsIntoItsGlyphInANarrowWing() throws {
        let waiting = try activity(ActivitySpec(id: "w", title: "Claude · islet", trailing: "Waiting", state: .waiting))
        let wide = waiting.wingPlan(text: "Waiting", narrow: false, leading: "sparkle", now: t0)
        #expect(wide == WingPlan(full: "Waiting", short: nil, glyph: "exclamationmark.bubble.fill"))
        let narrow = waiting.wingPlan(text: "Waiting", narrow: true, leading: "sparkle", now: t0)
        #expect(narrow == WingPlan(full: nil, short: nil, glyph: "exclamationmark.bubble.fill"))
    }

    @Test func workUnderWayFallsBackToItsCountThenASpinner() throws {
        var spec = ActivitySpec(id: "a", title: "Fix login flow", state: .running, steps: 7, step: 3)
        spec.phase = "Testing"
        let a = try activity(spec, template: "agent")
        #expect(a.wingPlan(text: "Testing", narrow: true, leading: nil, now: t0)
            == WingPlan(full: nil, short: "3/7", glyph: NarrowValue.working))
        // Waiting, the glyph says more than the count: no count in between.
        let waiting = try activity(ActivitySpec(id: "a", title: "Fix login flow", state: .waiting), template: "agent")
        #expect(waiting.wingPlan(text: "Needs you", narrow: true, leading: nil, now: t0).short == nil)
    }

    @Test func theWingNeverRepeatsTheMarkBesideTheNotch() throws {
        let done = try activity(ActivitySpec(id: "d", title: "Deploy to production", icon: .symbol("checkmark.circle.fill"),
                                             trailing: "Done", progress: 1, state: .success))
        // The word is tried instead, and nothing is drawn when it doesn't fit either.
        #expect(done.wingPlan(text: "Done", narrow: true, leading: "checkmark.circle.fill", now: t0)
            == WingPlan(full: "Done", short: nil, glyph: nil))
        #expect(NarrowValue.repeats("checkmark.circle.fill", leading: "checkmark.seal"))
        #expect(!NarrowValue.repeats("checkmark.circle.fill", leading: "hammer.fill"))
        #expect(!NarrowValue.repeats(NarrowValue.working, leading: "ellipsis"))
        #expect(!NarrowValue.repeats("info.circle.fill", leading: nil))
    }

    @Test func noValueLooksTheSameAtEveryWidth() throws {
        let running = try activity(ActivitySpec(id: "r", title: "Score", state: .running), template: "score")
        #expect(running.wingPlan(text: "", narrow: true, leading: nil, now: t0) == WingPlan(full: nil, short: nil, glyph: nil))
        #expect(running.wingPlan(text: "", narrow: false, leading: nil, now: t0) == WingPlan(full: nil, short: nil, glyph: nil))
        let failed = try activity(ActivitySpec(id: "f", title: "CI", state: .failure))
        #expect(failed.wingPlan(text: "", narrow: false, leading: nil, now: t0).glyph == "xmark.circle.fill")
    }

    @Test func anUrgentNumberThatFitsNowhereGivesWayToItsStateGlyph() throws {
        let alert = try activity(ActivitySpec(id: "u", title: "Claude 5-hour limit reached", icon: .symbol("sparkle"),
                                              trailing: "100%", state: .warning))
        #expect(alert.wingPlan(text: "100%", narrow: true, leading: "sparkle", now: t0)
            == WingPlan(full: "100%", short: nil, glyph: "exclamationmark.triangle.fill"))
        // Plain information has no glyph to fall back on.
        let meeting = try activity(ActivitySpec(id: "m", title: "Standup", trailing: "9 min", state: .info))
        #expect(meeting.wingPlan(text: "9 min", narrow: true, leading: nil, now: t0).glyph == nil)
    }

    @Test func dialsStandAloneInsideARing() {
        #expect(ActivityIcon.symbol("timer").isDial)
        #expect(ActivityIcon.symbol("stopwatch.fill").isDial)
        #expect(!ActivityIcon.symbol("cup.and.saucer.fill").isDial)
        #expect(!ActivityIcon.symbol("timeline.selection").isDial)
        #expect(!ActivityIcon.emoji("⏱").isDial)
    }

    @Test func aTwoSidedScoreLeavesTheWingAlone() {
        #expect(MenuBarLiveActivities.shortTrailing("IND 245/3 · AUS 198") == nil)
        #expect(MenuBarLiveActivities.shortTrailing("Arriving · 4 min") == "4 min")
        #expect(MenuBarLiveActivities.shortTrailing("4 min") == "4 min")
    }

    @Test func valueTextReadsOnBlack() throws {
        for hex in ["#CC0000", "#005DAA"] {
            let c = try #require(RGBA.parse(hex))
            #expect(c.readableOnBlack().contrastOnBlack >= 3)
            #expect(c.readableTextOnBlack().contrastOnBlack >= RGBA.textContrast)
        }
        let white = RGBA(r: 1, g: 1, b: 1, a: 1)
        #expect(white.readableTextOnBlack() == white)
    }
}
