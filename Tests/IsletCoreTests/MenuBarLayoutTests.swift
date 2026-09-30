import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@Suite struct MenuBarLayoutTests {
    // Measured on a 14" MacBook Pro running macOS 27: notch 663.5–848.5, first status item at 877.
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    func wing(_ occupancy: MenuBarOccupancy?, preference: ClosedLayoutPreference = .auto, hasMenuBar: Bool = true) -> CGFloat {
        MenuBarLayoutEngine.wingWidth(preference: preference, notch: notch, preferredWing: 58, occupancy: occupancy, hasMenuBar: hasMenuBar)
    }

    @Test func iconOnlyWingsWhenAValueDoesntFit() {
        // 884.5 - 848.5 - 6 = 30 pt of room on the right: an icon, but no value.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 884.5)) == 26)
        // Exactly the minimum still shows a value.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 888.5)) == 34)
    }

    @Test func staysBesideTheNotchWhenNotEvenAnIconFits() {
        // 877 - 848.5 - 6 = 22.5 pt: the icon-only wings cover the edge of the first status item.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 877)) == 26)
        // An item touching the notch, or measured overlapping it, changes nothing.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 848.5)) == 26)
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 700, rightObstacleMinX: 800)) == 26)
    }

    @Test func narrowsWingsToTheTighterSide() {
        // Right: 900 - 848.5 - 6 = 45.5; left: 663.5 - 400 - 6 is plenty. Both wings use 45.5.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 400, rightObstacleMinX: 900)) == 45.5)
    }

    @Test func fullWingsWhenThereIsRoom() {
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 300, rightObstacleMinX: 1100)) == 58)
        #expect(wing(MenuBarOccupancy()) == 58)
    }

    @Test func longAppMenusGiveIconOnlyWings() {
        // 663.5 - 650 - 6 = 7.5 pt on the left.
        #expect(wing(MenuBarOccupancy(leftObstacleMaxX: 650, rightObstacleMinX: 1100)) == 26)
    }

    @Test func unmeasuredMenuBarGetsNarrowWings() {
        // Stays in the top row, narrow enough to clear most apps' menus and status items.
        #expect(wing(nil) == 36)
    }

    @Test func noMenuBarMeansNothingToCover() {
        #expect(wing(nil, hasMenuBar: false) == 58)
        #expect(wing(MenuBarOccupancy(rightObstacleMinX: 850), hasMenuBar: false) == 58)
    }

    @Test func alwaysFullWidthIgnoresTheMenuBar() {
        #expect(wing(MenuBarOccupancy(rightObstacleMinX: 850), preference: .wings) == 58)
        #expect(wing(nil, preference: .wings) == 58)
    }

    @Test func occupancyFromItemFrames() {
        let menus = [CGRect(x: 0, y: 0, width: 30, height: 24), CGRect(x: 30, y: 0, width: 366, height: 24)]
        let extras = [CGRect(x: 877, y: 0, width: 38, height: 24), CGRect(x: 1374, y: 0, width: 118, height: 24), CGRect(x: 902, y: 0, width: 0, height: 24)]
        let o = MenuBarOccupancy.from(menuFrames: menus, statusFrames: extras, notch: notch)
        #expect(o.leftObstacleMaxX == 396)
        #expect(o.rightObstacleMinX == 877)
    }

    @Test func collapsedItemsBehindTheChevronDontCount() {
        // Three hidden items still report frames stacked on the chevron (x 873–915); the first
        // drawn item is at 921. Only the chevron itself is in the way.
        let chevron = CGRect(x: 897, y: 0, width: 17.5, height: 24)
        let hidden = [CGRect(x: 873, y: 0, width: 24, height: 24), CGRect(x: 885, y: 0, width: 24, height: 24),
                      CGRect(x: 891, y: 0, width: 24, height: 24)]
        let visible = [CGRect(x: 921, y: 0, width: 24, height: 24), CGRect(x: 1374.5, y: 0, width: 117.5, height: 24)]
        let o = MenuBarOccupancy.from(menuFrames: [CGRect(x: 30, y: 0, width: 442, height: 24)], statusFrames: hidden + visible,
                                      chevron: chevron, notch: notch)
        #expect(o.rightObstacleMinX == 897)
        // 897 - 848.5 - 6 = 42.5 pt wings with an icon and a value.
        #expect(wing(o) == 42.5)
        // Without the chevron filter the stacked frames would leave room for an icon only.
        #expect(wing(MenuBarOccupancy.from(menuFrames: [], statusFrames: hidden + visible, notch: notch)) == 26)
    }

    @Test func chevronRightBesideTheNotchGivesIconOnlyWings() {
        // The overflow chevron a few points from the notch: the island stays in the menu bar row
        // and its icon-only wing overlaps the chevron's edge.
        let chevron = CGRect(x: 856, y: 0, width: 17.5, height: 24)
        let o = MenuBarOccupancy.from(menuFrames: [CGRect(x: 30, y: 0, width: 442, height: 24)], statusFrames: [],
                                      chevron: chevron, notch: notch)
        #expect(o.rightObstacleMinX == 856)
        #expect(wing(o) == 26)
    }

    @Test func revealedItemsLeftOfTheNotchGiveIconOnlyWings() {
        // Revealing hidden items moves them to the left of the notch (x 512–644).
        let revealed = [CGRect(x: 582, y: 0, width: 38, height: 24), CGRect(x: 627, y: 0, width: 17, height: 24)]
        let o = MenuBarOccupancy.from(menuFrames: [CGRect(x: 30, y: 0, width: 442, height: 24)], statusFrames: revealed,
                                      chevron: CGRect(x: 897, y: 0, width: 17.5, height: 24), notch: notch)
        #expect(o.leftObstacleMaxX == 644)
        #expect(wing(o) == 26)
    }

    @Test func slackIsTheRoomLeftBeyondEachWing() {
        let o = MenuBarOccupancy(leftObstacleMaxX: 400, rightObstacleMinX: 900)
        let slack = MenuBarLayoutEngine.slack(notch: notch, occupancy: o, wing: 45.5)
        // Left: 663.5 - 400 - 6 - 45.5; right: 900 - 848.5 - 6 - 45.5.
        #expect(slack.left == 212)
        #expect(slack.right == 0)
        // Icon-only wings that overlap an item leave no room, never a negative amount.
        #expect(MenuBarLayoutEngine.slack(notch: notch, occupancy: MenuBarOccupancy(rightObstacleMinX: 877), wing: 26).right == 0)
        #expect(MenuBarLayoutEngine.slack(notch: notch, occupancy: MenuBarOccupancy(), wing: 26).left == .infinity)
    }

    @Test func smallWidthChangesAreIgnored() {
        #expect(!MenuBarLayoutEngine.shouldReplace(42.5, with: 45))
        #expect(MenuBarLayoutEngine.shouldReplace(42.5, with: 50))
        #expect(MenuBarLayoutEngine.shouldReplace(34, with: 26))
        #expect(!MenuBarLayoutEngine.shouldReplace(26, with: 26))
        #expect(MenuBarLayoutEngine.shouldReplace(nil, with: 26))
    }
}

@Suite struct MenuBarLiveActivityTests {
    // MenuBarAgent's items on this Mac (macOS 27.0.1) with no Live Activity running, including
    // Now Playing collapsed into the overflow.
    let observed = [
        MenuBarItemInfo(identifier: "com.apple.menuextra.battery", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Battery", value: "80%, charging"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.wifi", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Wi‑Fi, connected, 2 bars"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.bluetooth", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Bluetooth"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.screen-mirroring", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Screen Mirroring"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.controlcenter", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Control Center"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.clock", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Clock", value: "Wed 30 Sep  20:57"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.now-playing", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Now Playing", hidden: true),
        MenuBarItemInfo(identifier: "com.apple.menuextra.timer", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Timer", value: "4:59"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.audiovideo", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "AV Controls"),
    ]

    @Test func systemItemsAreNotLiveActivities() {
        for item in observed {
            #expect(MenuBarLiveActivities.classify(item) == .systemItem, "\(item)")
            #expect(MenuBarLiveActivities.mirror(item, key: "k") == nil)
        }
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXButton")) == .overflowButton)
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(owner: "com.openai.codex")) == .thirdParty)
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem", description: "AV Controls")) == .avControls)
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(subrole: "AXHostingView")) == .unknown)
    }

    @Test func recognisedByLabelIdentifierMenuOrRenderer() {
        let label = MenuBarItemInfo(role: "AXMenuBarItem", description: "Live Activity", texts: ["Uber", "4 min"])
        #expect(MenuBarLiveActivities.classify(label) == .liveActivity)
        let pill = MenuBarItemInfo(identifier: "live-activity-pill-3F2A", texts: ["12:40"])
        #expect(MenuBarLiveActivities.classify(pill) == .liveActivity)
        let menu = MenuBarItemInfo(identifier: "x.unknown", role: "AXGroup", customActions: ["End Live Activity"])
        #expect(MenuBarLiveActivities.classify(menu) == .liveActivity)
        let rendered = MenuBarItemInfo(texts: ["IND 245/3"], owner: "renderer")
        #expect(MenuBarLiveActivities.classify(rendered) == .liveActivity)
        // No identifier is something only an activity lacks, but it needs content to count.
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem", texts: ["Flighty", "Boarding"])) == .liveActivity)
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem")) == .unknown)
    }

    @Test func labelsInEveryLanguage() {
        let labels = MenuBarLabels.from(loctable: [
            "hi": ["liveActivity.accessibilityLabel": "लाइव ऐक्टिविटी", "liveActivity.endLiveActivityMenuItem": "लाइव ऐक्टिविटी समाप्त करें"],
            "de": ["avModule.accessibilityLabel": "AV-Steuerung"],
        ])
        let hindi = MenuBarItemInfo(identifier: "x.unknown", role: "AXGroup", description: "लाइव ऐक्टिविटी", texts: ["Swiggy", "12 min"])
        #expect(MenuBarLiveActivities.classify(hindi, labels: labels) == .liveActivity)
        #expect(MenuBarLiveActivities.classify(hindi) == .unknown)
        #expect(MenuBarLiveActivities.mirror(hindi, key: "k", labels: labels)?.appName == "Swiggy")
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem", description: "AV-Steuerung"), labels: labels) == .avControls)
    }

    @Test func mirroredTextDropsTheGenericLabel() {
        let a = MenuBarItemInfo(role: "AXMenuBarItem", description: "Live Activity", texts: ["Uber", "Arriving", "4 min"])
        #expect(MenuBarLiveActivities.mirror(a, key: "el:1") == MirroredLiveActivity(key: "el:1", appName: "Uber", detail: "Arriving · 4 min"))
        // Two activities with the same generic label keep separate keys.
        let b = MenuBarItemInfo(role: "AXMenuBarItem", description: "Live Activity", texts: ["Flighty", "Boards 0:42"])
        #expect(MenuBarLiveActivities.mirror(b, key: "el:2")?.key == "el:2")
        // "App, detail" in one string.
        let c = MenuBarItemInfo(role: "AXMenuBarItem", description: "Flighty, Boarding 12:40")
        #expect(MenuBarLiveActivities.mirror(c, key: "el:3") == MirroredLiveActivity(key: "el:3", appName: "Flighty", detail: "Boarding 12:40"))
        // The catalogue recognises the app even when it isn't first.
        let d = MenuBarItemInfo(identifier: "live-activity-pill-9", texts: ["4 min", "Uber"])
        #expect(MenuBarLiveActivities.mirror(d, knownApp: { $0 == "Uber" }) == MirroredLiveActivity(key: "live-activity-pill-9", appName: "Uber", detail: "4 min"))
        // Values alone: say where it came from.
        let e = MenuBarItemInfo(identifier: "live-activity-pill-10", texts: ["2 – 1"])
        #expect(MenuBarLiveActivities.mirror(e)?.appName == "Live Activity")
        // Hidden in the overflow is carried through.
        let f = MenuBarItemInfo(role: "AXMenuBarItem", description: "Live Activity", texts: ["Timer", "4:59"], hidden: true)
        #expect(MenuBarLiveActivities.mirror(f, key: "el:4")?.hidden == true)
        // Without a key or identifier there's nothing stable to follow.
        #expect(MenuBarLiveActivities.mirror(a) == nil)
    }

    @Test func clockValues() {
        #expect(MenuBarLiveActivities.clockSeconds(in: "4:59") == 299)
        #expect(MenuBarLiveActivities.clockSeconds(in: "Boards 1:02:03") == 3723)
        #expect(MenuBarLiveActivities.clockSeconds(in: "4 min") == nil)
        #expect(MenuBarLiveActivities.clockSeconds(in: "2:75") == nil)
        #expect(MenuBarLiveActivities.clockSeconds(in: "IND 245/3") == nil)
    }

    @Test func clockDirectionFromTwoReadings() {
        var clock = LiveActivityClock()
        let t = Date(timeIntervalSince1970: 1_000_000)
        #expect(clock.update(key: "a", detail: "4:59", now: t) == nil)
        #expect(clock.update(key: "a", detail: "4:58", now: t.addingTimeInterval(1)) == .countdown(endsAt: t.addingTimeInterval(1 + 298)))
        // Consistent readings keep the same end, so the island isn't redrawn every second.
        #expect(clock.update(key: "a", detail: "4:57", now: t.addingTimeInterval(2)) == .countdown(endsAt: t.addingTimeInterval(299)))
        // A jump (paused, new phase) starts over.
        #expect(clock.update(key: "a", detail: "9:00", now: t.addingTimeInterval(3)) == nil)

        #expect(clock.update(key: "b", detail: "0:10", now: t) == nil)
        #expect(clock.update(key: "b", detail: "0:11", now: t.addingTimeInterval(1)) == .countUp(startedAt: t.addingTimeInterval(-10)))
        // A time of day doesn't tick, so it stays text.
        #expect(clock.update(key: "c", detail: "Boarding 12:40", now: t) == nil)
        #expect(clock.update(key: "c", detail: "Boarding 12:40", now: t.addingTimeInterval(5)) == nil)
    }

    @Test func mirroredClockAnimatesLocally() {
        let m = MirroredLiveActivity(key: "k", appName: "Timer", detail: "4:58")
        let end = Date(timeIntervalSince1970: 2_000_000)
        let spec = MenuBarLiveActivities.activity(for: m, look: ("timer", "#FF9F0A"), isNew: false, clock: .countdown(endsAt: end))
        #expect(spec.endsAt == end)
        #expect(spec.trailing == "")
    }

    @Test func activitySpecForMirroredItem() throws {
        let m = MirroredLiveActivity(key: "k", appName: "Uber", detail: "Arriving · 4 min")
        let spec = MenuBarLiveActivities.activity(for: m, look: ("car.fill", "#000000"), isNew: true)
        #expect(spec.icon == .symbol("car.fill"))
        #expect(spec.trailing == "4 min")
        #expect(spec.source == MenuBarLiveActivities.source)
        #expect(spec.sneak == true)
        #expect(ActivityCenter.isValidID(spec.id!))
        // Without a catalogue entry, smart icons still pick something sensible.
        let smart = MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "d", appName: "DoorDash", detail: "Your order is on the way"), look: nil, isNew: false)
        #expect(smart.icon == .symbol("takeoutbag.and.cup.and.straw.fill"))
        var c = ActivityCenter()
        #expect(try c.apply(spec, now: t0).title == "Uber")
    }

    @Test func mirroredUpdateClearsTextTheItemNoLongerShows() throws {
        func spec(_ detail: String?) -> ActivitySpec {
            MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "k", appName: "Uber", detail: detail), look: nil, isNew: false)
        }
        var c = ActivityCenter()
        #expect(try c.apply(spec("Arriving · 4 min"), now: t0).trailingText(now: t0) == "4 min")
        // The last part is now too long for the wing, so the old "4 min" must not stay there.
        let longer = try c.apply(spec("Arriving · Driver is nearby"), now: t0)
        #expect(longer.trailing == nil)
        #expect(longer.trailingText(now: t0) == nil)
        #expect(longer.subtitle == "Arriving · Driver is nearby")
        // No text at all: the subtitle goes too.
        #expect(try c.apply(spec(nil), now: t0).subtitle == nil)
        // A fresh activity with no short value simply has none.
        var fresh = ActivityCenter()
        #expect(try fresh.apply(spec("Your order is on the way"), now: t0).trailing == nil)
    }

    @Test func mirroredClockStopsOnceTheItemShowsNoTime() throws {
        var clock = LiveActivityClock()
        var c = ActivityCenter()
        // Each reading of the item, handled as the app does.
        func read(_ detail: String, at s: Double) throws -> Activity {
            let now = t0.addingTimeInterval(s)
            let m = MirroredLiveActivity(key: "k", appName: "Some App", detail: detail)
            let spec = MenuBarLiveActivities.activity(for: m, look: nil, isNew: false,
                                                      clock: clock.update(key: m.key, detail: detail, now: now))
            if MenuBarLiveActivities.clockSeconds(in: detail) == nil { c.clearClock(id: spec.id!) }
            return try c.apply(spec, now: now)
        }
        _ = try read("Closes in 4:59", at: 0)
        let running = try read("Closes in 4:58", at: 1)
        #expect(running.endsAt == t0.addingTimeInterval(299))
        #expect(running.resolvedTemplate == .timer)
        // A reading that doesn't settle the clock keeps it while the item still shows a time.
        #expect(try read("Closes in 4:58", at: 1.9).endsAt == t0.addingTimeInterval(299))
        // The text moves on with no time in it: no countdown is left running in the wing.
        let later = t0.addingTimeInterval(400)
        let closed = try read("Gate closed for boarding", at: 400)
        #expect(closed.endsAt == nil)
        #expect(closed.trackSpan == nil)
        #expect(closed.resolvedTemplate != .timer)
        #expect(closed.templateTrailing(now: later) == nil)
        #expect(!c.needsClockTick(now: later))
        // A count-up stops the same way, instead of ticking every second for good.
        _ = try read("On call 0:10", at: 500)
        #expect(try read("On call 0:11", at: 501).startedAt == t0.addingTimeInterval(490))
        #expect(try read("Call ended", at: 510).startedAt == nil)
        #expect(!c.needsClockTick(now: t0.addingTimeInterval(510)))
    }

    @Test func clearClockOnlyTouchesTheClock() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "a", title: "Tea", trailing: "Hot", endsAt: t0.addingTimeInterval(60),
                                         startedAt: t0), now: t0)
        #expect(a.trackSpan == 60)
        c.clearClock(id: "a")
        let cleared = try #require(c.activities["a"])
        #expect(cleared.endsAt == nil && cleared.startedAt == nil && cleared.trackSpan == nil)
        #expect(cleared.title == "Tea" && cleared.trailing == "Hot" && cleared.updatedAt == a.updatedAt)
        // Nothing to clear, or no such activity: no change.
        c.clearClock(id: "a")
        c.clearClock(id: "missing")
        #expect(c.activities.count == 1)
    }
}

@Suite struct LiveActivityCatalogTests {
    @Test func looksUpByNameAndAlias() {
        #expect(LiveActivityCatalog.look(for: "Uber")?.symbol == "car.fill")
        #expect(LiveActivityCatalog.look(for: "Uber Eats")?.symbol == "takeoutbag.and.cup.and.straw.fill")
        #expect(LiveActivityCatalog.look(for: "  flighty ")?.symbol == "airplane")
        #expect(LiveActivityCatalog.look(for: "Some Unknown App") == nil)
    }

    @Test func everyTintParses() {
        for look in LiveActivityCatalog.all { #expect(RGBA.parse(look.tint) != nil, "\(look.app)") }
    }

    @Test func mirroredActivitiesCantBePressedFromAURL() {
        // Pressing the original item only ever follows a click inside Islet.
        #expect(throws: (any Error).self) { try URLCommand.parse(URL(string: "islet://menubar-activity?key=id:x")!) }
    }
}
