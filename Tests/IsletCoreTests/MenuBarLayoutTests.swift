import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@Suite struct MenuBarLayoutTests {
    // Measured on a 14" MacBook Pro running macOS 27: notch 663.5–848.5, first status item at 877.
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    func decide(_ occupancy: MenuBarOccupancy?, preference: ClosedLayoutPreference = .auto, hasMenuBar: Bool = true) -> ClosedLayout {
        MenuBarLayoutEngine.decide(preference: preference, notch: notch, preferredWing: 58, occupancy: occupancy, hasMenuBar: hasMenuBar)
    }

    @Test func dropsOnlyWhenNotEvenAnIconFits() {
        // 877 - 848.5 - 6 = 22.5 pt of room on the right: not even an icon fits.
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 877)) == .drop)
        // 30 pt: icon-only wings, still in the top row.
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 884.5)) == .wings(left: 26, right: 26))
    }

    @Test func narrowsWingsToTheTighterSide() {
        // Right: 900 - 848.5 - 6 = 45.5; left: 663.5 - 400 - 6 is plenty. Both wings use 45.5.
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 400, rightObstacleMinX: 900)) == .wings(left: 45.5, right: 45.5))
    }

    @Test func fullWingsWhenThereIsRoom() {
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 300, rightObstacleMinX: 1100)) == .wings(left: 58, right: 58))
        #expect(decide(MenuBarOccupancy()) == .wings(left: 58, right: 58))
    }

    @Test func longAppMenusForceDrop() {
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 650, rightObstacleMinX: 1100)) == .drop)
    }

    @Test func unmeasuredMenuBarGetsNarrowWings() {
        // Stays in the top row, narrow enough to clear most apps' menus and status items.
        #expect(decide(nil) == .wings(left: 36, right: 36))
    }

    @Test func noMenuBarMeansNothingToCover() {
        #expect(decide(nil, hasMenuBar: false) == .wings(left: 58, right: 58))
    }

    @Test func explicitPreferencesWin() {
        #expect(decide(MenuBarOccupancy(rightObstacleMinX: 850), preference: .wings) == .wings(left: 58, right: 58))
        #expect(decide(MenuBarOccupancy(), preference: .drop) == .drop)
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
        // 897 - 848.5 - 6 = 42.5 pt wings instead of dropping.
        #expect(decide(o) == .wings(left: 42.5, right: 42.5))
        // Without the chevron filter the stacked frames would force the dropped layout.
        #expect(decide(MenuBarOccupancy.from(menuFrames: [], statusFrames: hidden + visible, notch: notch)) == .drop)
    }

    @Test func revealedItemsLeftOfTheNotchForceDrop() {
        // Revealing hidden items moves them to the left of the notch (x 512–644).
        let revealed = [CGRect(x: 582, y: 0, width: 38, height: 24), CGRect(x: 627, y: 0, width: 17, height: 24)]
        let o = MenuBarOccupancy.from(menuFrames: [CGRect(x: 30, y: 0, width: 442, height: 24)], statusFrames: revealed,
                                      chevron: CGRect(x: 897, y: 0, width: 17.5, height: 24), notch: notch)
        #expect(o.leftObstacleMaxX == 644)
        #expect(decide(o) == .drop)
    }

    @Test func smallWidthChangesAreIgnored() {
        let now = Date()
        #expect(MenuBarLayoutEngine.stabilise(current: .wings(left: 42.5, right: 42.5), next: .wings(left: 45, right: 45), lastSwitch: nil, now: now) == .keep)
        #expect(MenuBarLayoutEngine.stabilise(current: .wings(left: 42.5, right: 42.5), next: .wings(left: 50, right: 50), lastSwitch: nil, now: now) == .apply)
        #expect(MenuBarLayoutEngine.stabilise(current: .drop, next: .drop, lastSwitch: nil, now: now) == .keep)
        #expect(MenuBarLayoutEngine.stabilise(current: nil, next: .drop, lastSwitch: nil, now: now) == .apply)
    }

    @Test func switchingLayoutsIsRateLimited() {
        let now = Date()
        let recent = now.addingTimeInterval(-0.4)
        #expect(MenuBarLayoutEngine.stabilise(current: .drop, next: .wings(left: 42.5, right: 42.5), lastSwitch: recent, now: now) == .defer)
        #expect(MenuBarLayoutEngine.stabilise(current: .drop, next: .wings(left: 42.5, right: 42.5), lastSwitch: now.addingTimeInterval(-2), now: now) == .apply)
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
}

@Suite struct LiveActivityCatalogTests {
    @Test func looksUpByNameAndAlias() {
        #expect(LiveActivityCatalog.look(for: "Uber")?.symbol == "car.fill")
        #expect(LiveActivityCatalog.look(for: "Uber Eats")?.symbol == "takeoutbag.and.cup.and.straw.fill")
        #expect(LiveActivityCatalog.look(for: "  flighty ")?.symbol == "airplane")
        #expect(LiveActivityCatalog.look(for: "Some Unknown App") == nil)
    }

    @Test func everyTintParses() {
        for (name, look) in LiveActivityCatalog.entries { #expect(RGBA.parse(look.tint) != nil, "\(name)") }
    }

    @Test func mirroredActivitiesCantBePressedFromAURL() {
        // Pressing the original item only ever follows a click inside Islet.
        #expect(throws: (any Error).self) { try URLCommand.parse(URL(string: "islet://menubar-activity?key=id:x")!) }
    }
}
