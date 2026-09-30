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

    @Test func dropsWhenStatusItemsCrowdTheNotch() {
        // 877 - 848.5 - 6 = 22.5 pt of room on the right: too narrow for a wing.
        #expect(decide(MenuBarOccupancy(leftObstacleMaxX: 396, rightObstacleMinX: 877)) == .drop)
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

    @Test func unmeasurableMenuBarIsTreatedAsFull() {
        #expect(decide(nil) == .drop)
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
}

@Suite struct MenuBarLiveActivityTests {
    // The items MenuBarAgent exposed on this Mac (macOS 27.0.1) with no Live Activity running.
    let observed = [
        MenuBarItemInfo(identifier: "com.apple.menuextra.battery", subrole: "AXMenuExtra", description: "Battery", value: "80%, charging"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.wifi", subrole: "AXMenuExtra", description: "Wi‑Fi, connected, 2 bars"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.bluetooth", subrole: "AXMenuExtra", description: "Bluetooth"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.screen-mirroring", subrole: "AXMenuExtra", description: "Screen Mirroring"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.controlcenter", subrole: "AXMenuExtra", description: "Control Center"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.clock", subrole: "AXMenuExtra", description: "Clock", value: "Wed 30 Sep  20:57"),
        MenuBarItemInfo(description: "Show Hidden Menu Bar Items"),
        MenuBarItemInfo(subrole: "AXHostingView"),
    ]

    @Test func systemItemsAreNotLiveActivities() {
        for item in observed { #expect(!MenuBarLiveActivities.isLiveActivity(item), "\(item)") }
    }

    @Test func unknownContentfulItemsAre() {
        let uber = MenuBarItemInfo(identifier: "com.apple.menuextra.liveactivity.3F2A", description: "Uber", value: "4 min")
        #expect(MenuBarLiveActivities.isLiveActivity(uber))
        #expect(MenuBarLiveActivities.mirror(uber) == MirroredLiveActivity(key: "com.apple.menuextra.liveactivity.3F2A", appName: "Uber", detail: "4 min"))
        let noID = MenuBarItemInfo(subrole: "AXMenuExtra", description: "Flighty, Boarding 12:40")
        #expect(MenuBarLiveActivities.mirror(noID) == MirroredLiveActivity(key: "app:flighty", appName: "Flighty", detail: "Boarding 12:40"))
        let texts = MenuBarItemInfo(identifier: "x.unknown", texts: ["ESPN", "IND 245/3", "AUS 198"])
        #expect(MenuBarLiveActivities.mirror(texts)?.detail == "IND 245/3 · AUS 198")
    }

    @Test func activitySpecForMirroredItem() throws {
        let m = MirroredLiveActivity(key: "k", appName: "Uber", detail: "Arriving · 4 min")
        let spec = MenuBarLiveActivities.activity(for: m, look: ("car.fill", "#000000"), isNew: true)
        #expect(spec.icon == .symbol("car.fill"))
        #expect(spec.trailing == "4 min")
        #expect(spec.source == "iphone")
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

    @Test func menuBarActivityURL() throws {
        #expect(try URLCommand.parse(URL(string: "islet://menubar-activity?key=com.apple.x.1")!) == .openMenuBarActivity(key: "com.apple.x.1"))
        #expect(throws: URLCommand.ParseError.missing("key")) { try URLCommand.parse(URL(string: "islet://menubar-activity")!) }
    }
}
