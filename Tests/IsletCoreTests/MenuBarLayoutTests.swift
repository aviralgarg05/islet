import CoreGraphics
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
