import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

/// "Hide the menu bar's own": which of the menu bar's Live Activity pills Islet covers, and
/// where the black rectangle goes.
@Suite struct MenuBarCoverTests {
    // Measured on a 14" MacBook Pro running macOS 27: the pill sits at the top of the menu bar
    // row, 110.55 pt wide, on a 1512 x 982 display whose menu bar is 38 pt tall.
    static let top: CGFloat = 982
    static let menuBar: CGFloat = 38
    static let pill = CGRect(x: 895.95, y: 0, width: 110.55, height: 33)

    /// Everything lined up for a cover; each test turns one thing off.
    func input(hideOwn: Bool = true, mirroring: Bool = true, supported: Bool = true, trusted: Bool = true,
               inFront: Bool = true, islandShows: Bool = true, menuBarShows: Bool = true,
               menuBarHeight: CGFloat = menuBar, menuBarTop: CGFloat = top) -> MenuBarCovers.Input {
        MenuBarCovers.Input(hideOwn: hideOwn, mirroring: mirroring, supported: supported, trusted: trusted,
                            inFront: inFront, islandShows: islandShows, menuBarShows: menuBarShows,
                            menuBarHeight: menuBarHeight, menuBarTop: menuBarTop)
    }

    func pills(hidden: Bool = false) -> [MenuBarActivityPill] {
        [MenuBarActivityPill(key: "id:live-activity-pill", frame: Self.pill, hidden: hidden)]
    }

    // MARK: Where the rectangle goes

    @Test func theCoverLandsOnThePillNotBelowIt() {
        let covers = MenuBarCovers.covers(pills: pills(), input())
        // AX y 0 to 33 from the top of a 982 pt display: 949 to 982 in window coordinates.
        #expect(covers == [CGRect(x: 895, y: 949, width: 112, height: 33)])
        // Inside the menu bar row, and reaching the very top of the display.
        #expect(covers.first?.maxY == Self.top)
        #expect(covers.first.map { $0.minY >= Self.top - Self.menuBar } == true)
    }

    @Test func aFractionalPillIsCoveredWhole() {
        let cover = MenuBarCovers.windowFrame(pill: Self.pill, menuBarTop: Self.top, menuBarHeight: Self.menuBar)
        #expect(cover?.minX == 895)
        #expect(cover?.maxX == 1007)
        #expect(cover.map { $0.minX <= Self.pill.minX && $0.maxX >= Self.pill.maxX } == true)
    }

    /// A display without a notch has a 24 pt menu bar; a 33 pt cover would hang 9 pt below the
    /// row, where the island never goes either.
    @Test func theCoverStaysInsideTheMenuBarRow() {
        let cover = MenuBarCovers.windowFrame(pill: Self.pill, menuBarTop: 900, menuBarHeight: 24)
        #expect(cover == CGRect(x: 895, y: 876, width: 112, height: 24))
    }

    @Test func aPillBelowTheRowIsNotCovered() {
        // Nothing of it falls in the row, so there is nothing to cover.
        let below = CGRect(x: 400, y: 40, width: 100, height: 20)
        #expect(MenuBarCovers.windowFrame(pill: below, menuBarTop: Self.top, menuBarHeight: Self.menuBar) == nil)
    }

    @Test func nothingIsCoveredWithoutASizeOrAMenuBar() {
        #expect(MenuBarCovers.windowFrame(pill: .zero, menuBarTop: Self.top, menuBarHeight: Self.menuBar) == nil)
        #expect(MenuBarCovers.windowFrame(pill: Self.pill, menuBarTop: Self.top, menuBarHeight: 0) == nil)
        #expect(MenuBarCovers.windowFrame(pill: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 20),
                                          menuBarTop: Self.top, menuBarHeight: Self.menuBar) == nil)
    }

    @Test func everyVisiblePillIsCoveredLeftToRight() {
        let pills = [
            MenuBarActivityPill(key: "b", frame: CGRect(x: 895.95, y: 0, width: 110.55, height: 33)),
            MenuBarActivityPill(key: "a", frame: CGRect(x: 700, y: 0, width: 90, height: 33)),
        ]
        #expect(MenuBarCovers.covers(pills: pills, input()).map(\.minX) == [700, 895])
    }

    // MARK: When nothing is covered

    @Test func theSettingOffCoversNothing() {
        #expect(MenuBarCovers.covers(pills: pills(), input(hideOwn: false)).isEmpty)
    }

    @Test func nothingIsCoveredWithoutTheThingsTheMirrorNeeds() {
        // Covering a pill while the activity isn't mirrored would hide it altogether.
        #expect(MenuBarCovers.covers(pills: pills(), input(mirroring: false)).isEmpty)
        #expect(MenuBarCovers.covers(pills: pills(), input(supported: false)).isEmpty)
        // Without Accessibility the frames can't be refreshed, so they may already be wrong.
        #expect(MenuBarCovers.covers(pills: pills(), input(trusted: false)).isEmpty)
        // Another login session is in front: nothing is read there, and nothing is drawn.
        #expect(MenuBarCovers.covers(pills: pills(), input(inFront: false)).isEmpty)
    }

    /// A full screen app, or an app rule, hides the island on that display: the activity is not
    /// shown anywhere, so the menu bar keeps its own.
    @Test func nothingIsCoveredWhileTheIslandIsHidden() {
        #expect(MenuBarCovers.covers(pills: pills(), input(islandShows: false)).isEmpty)
    }

    /// A full screen app takes the menu bar away; a black rectangle must never be left floating
    /// over the top of it, even when an app rule keeps the island.
    @Test func nothingIsCoveredWhileTheMenuBarIsAway() {
        #expect(MenuBarCovers.covers(pills: pills(), input(menuBarShows: false)).isEmpty)
        #expect(MenuBarCovers.covers(pills: pills(), input(menuBarHeight: 0)).isEmpty)
    }

    @Test func aPillHiddenBehindTheNotchIsNotCovered() {
        // macOS doesn't draw it, so there is nothing there to cover.
        #expect(MenuBarCovers.covers(pills: pills(hidden: true), input()).isEmpty)
    }

    @Test func noActivityMeansNoCover() {
        #expect(MenuBarCovers.covers(pills: [], input()).isEmpty)
    }

    // MARK: The override

    @Test func coveringTheMenuBarMirrorsEveryActivity() {
        // "Only when the notch hides them" would leave a visible pill unmirrored, and a covered
        // pill has to be mirrored, so covering wins.
        #expect(MenuBarCovers.mirrorsOnlyHidden(onlyHidden: true, hideOwn: true) == false)
        #expect(MenuBarCovers.mirrorsOnlyHidden(onlyHidden: true, hideOwn: false) == true)
        #expect(MenuBarCovers.mirrorsOnlyHidden(onlyHidden: false, hideOwn: true) == false)
        #expect(MenuBarCovers.mirrorsOnlyHidden(onlyHidden: false, hideOwn: false) == false)
    }

    /// Showing an activity twice is the odd state, so Islet covers the menu bar's own from the
    /// start. Turning it off puts the pill back.
    @Test func theSettingStartsOn() {
        #expect(IsletSettings().hideMenuBarActivities == true)
        // It overrides "Only when the notch hides them", so a fresh Islet mirrors every activity.
        let fresh = IsletSettings()
        #expect(MenuBarCovers.mirrorsOnlyHidden(onlyHidden: fresh.mirrorOnlyHiddenActivities,
                                                hideOwn: fresh.hideMenuBarActivities) == false)
    }
}
