import CoreGraphics
import Foundation
import Testing
@testable import CasementCore

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
        func replace(_ current: CGFloat?, _ next: CGFloat) -> Bool {
            MenuBarLayoutEngine.shouldReplace(current, with: next, preferredWing: 58)
        }
        #expect(!replace(42.5, 45))
        #expect(replace(42.5, 50))
        #expect(replace(34, 26))
        #expect(!replace(26, 26))
        #expect(replace(nil, 26))
        // A status item that retitles beside full-width wings doesn't narrow them.
        #expect(!replace(58, 55.5))
    }

    @Test func aNewWingWidthInSettingsAppliesAtOnce() {
        // The Settings slider moves in 2 pt steps, under the hysteresis. With room to spare the
        // wings follow it both ways instead of staying at the old width.
        #expect(MenuBarLayoutEngine.shouldReplace(52, with: 54, preferredWing: 54))
        #expect(MenuBarLayoutEngine.shouldReplace(54, with: 52, preferredWing: 52))
        // Wings kept wider than the new setting shrink even when the bar is tight.
        #expect(MenuBarLayoutEngine.shouldReplace(54, with: 51, preferredWing: 52))
        // Still tight and under the setting: small changes are ignored as before.
        #expect(!MenuBarLayoutEngine.shouldReplace(45, with: 43, preferredWing: 54))
        #expect(!MenuBarLayoutEngine.shouldReplace(54, with: 54, preferredWing: 54))
    }

    /// A measurement kept from before a change in Settings, until the menu bar is measured
    /// again: a smaller size draws the new, narrower wing at once rather than shrinking to it.
    @Test func aKeptMeasurementNeverDrawsWiderThanTheSetting() {
        // Large (84 pt) measured, then Compact (52 pt) chosen while nothing showed.
        #expect(MenuBarLayoutEngine.usableWing(measured: 84, preference: .auto, preferredWing: 52) == 52)
        // A tight menu bar's narrow wing stays as it is.
        #expect(MenuBarLayoutEngine.usableWing(measured: 36, preference: .auto, preferredWing: 52) == 36)
        // A bigger size waits for the next measurement, starting narrow.
        #expect(MenuBarLayoutEngine.usableWing(measured: 52, preference: .auto, preferredWing: 84) == 52)
        // "Always full width" wants the whole wing: an older measurement can't be used.
        #expect(MenuBarLayoutEngine.usableWing(measured: 36, preference: .wings, preferredWing: 52) == nil)
        #expect(MenuBarLayoutEngine.usableWing(measured: 52, preference: .wings, preferredWing: 52) == 52)
    }

    @Test func smallSlackChangesAreIgnored() {
        #expect(!MenuBarLayoutEngine.differs(20, 17))
        #expect(MenuBarLayoutEngine.differs(20, 16))
        #expect(MenuBarLayoutEngine.differs(0, 38))
        // Nothing measured on a side (infinity) against a measurement is always a change.
        #expect(MenuBarLayoutEngine.differs(.infinity, 200))
        #expect(MenuBarLayoutEngine.differs(0, .infinity))
        #expect(!MenuBarLayoutEngine.differs(.infinity, .infinity))
    }

    @Test func hysteresisNeverReachesTheItemBeside() {
        // A width kept within the hysteresis still leaves part of the clearance free.
        #expect(MenuBarLayoutEngine.widthHysteresis < MenuBarLayoutEngine.clearance)
    }
}

@Suite struct MenuBarLiveActivityTests {
    // MenuBarAgent's items on this Mac (macOS 27.0.1) with no Live Activity running, including
    // Now Playing collapsed into the overflow.
    let observed = [
        MenuBarItemInfo(identifier: "com.apple.menuextra.battery", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Battery", value: "80%, charging"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.wifi", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Wi\u{2011}Fi, connected, 2 bars"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.bluetooth", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Bluetooth"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.screen-mirroring", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Screen Mirroring"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.controlcenter", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Control Center"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.clock", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Clock", value: "Wed 30 Sep  20:57"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.now-playing", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Now Playing", hidden: true),
        MenuBarItemInfo(identifier: "com.apple.menuextra.timer", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "Timer", value: "4:59"),
        MenuBarItemInfo(identifier: "com.apple.menuextra.audiovideo", role: "AXMenuBarItem", subrole: "AXMenuExtra", description: "AV Controls"),
    ]

    /// The identifier every Live Activity pill on this Mac carries. The suffix is the bundle id
    /// of the process that draws every pill, so it names the renderer and never the activity:
    /// two pills on screen at the same time carry this very string.
    static let pillID = "live-activity-pill-com.apple.chrono.WidgetRenderer-Activities"

    /// A pill as macOS 27 exposes it. The menu bar item itself carries the identifier and the
    /// label "Live Activity"; inside are the app's own picture and one or two short labels, and
    /// Apple's "Expanded" chevron comes last. `texts` is what the scan collects, in that order.
    func pill(_ texts: [String], x: CGFloat = 896, width: CGFloat = 110, hidden: Bool = false) -> MenuBarItemInfo {
        MenuBarItemInfo(identifier: Self.pillID, role: "AXMenuBarItem", description: "Live Activity",
                        texts: texts + ["Expanded"], x: x, width: width, hidden: hidden)
    }

    /// The key the scan gives a pill it found at one element, as the scanner builds it.
    func key(_ element: UInt) -> String {
        MenuBarLiveActivities.key(kind: .liveActivity, identifier: Self.pillID, elementHash: element)
    }

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
        #expect(MenuBarLiveActivities.classify(pill(["12:40"])) == .liveActivity)
        let menu = MenuBarItemInfo(identifier: "x.unknown", role: "AXGroup", customActions: ["End Live Activity"])
        #expect(MenuBarLiveActivities.classify(menu) == .liveActivity)
        let rendered = MenuBarItemInfo(texts: ["IND 245/3"], owner: "renderer")
        #expect(MenuBarLiveActivities.classify(rendered) == .liveActivity)
        // No identifier is something only an activity lacks, but it needs content to count.
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem", texts: ["Flighty", "Boarding"])) == .liveActivity)
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(role: "AXMenuBarItem")) == .unknown)
    }

    /// Every pill carries one identifier, the renderer's bundle id, so the identifier can't be
    /// the key: two pills on screen at once collapsed into one island row, a click opened
    /// whichever won, a new activity never got a peek, and a dismissal swallowed the next one.
    /// The element is one per pill and lives exactly as long as the pill does.
    @Test func aPillIsKeyedOnItsElementBecauseEveryPillSharesOneIdentifier() {
        #expect(key(0x1A2B) != key(0x3C4D))
        // Stable while the pill lives, whatever its text does, and the identifier never shows.
        #expect(key(0x1A2B) == key(0x1A2B))
        #expect(!key(0x1A2B).contains(Self.pillID))
        // A pill with no identifier at all is keyed the same way.
        #expect(MenuBarLiveActivities.key(kind: .liveActivity, identifier: nil, elementHash: 0x1A2B) == key(0x1A2B))
        // Every other item has an identifier of its own, which outlives its element.
        #expect(MenuBarLiveActivities.key(kind: .systemItem, identifier: "com.apple.menuextra.battery", elementHash: 7)
            == "id:com.apple.menuextra.battery")
        #expect(MenuBarLiveActivities.key(kind: .systemItem, identifier: nil, elementHash: 7) == "el:7")
    }

    /// Two pills on screen at the same time, both carrying that one identifier, as seen on this
    /// Mac: a cricket score and a delivery. They have to reach the island as two activities.
    @Test func twoPillsAtOnceAreTwoActivities() throws {
        let pills = [pill(["IND 211/6 (20)"], x: 760), pill(["food_di_preparing_icon", "13:01", "min"], x: 882, width: 85)]
        let mirrored = try zip(pills, [key(1), key(2)]).map { item, key in
            try #require(MenuBarLiveActivities.mirror(item, key: key))
        }
        #expect(Set(mirrored.map(\.key)).count == 2)
        #expect(Set(mirrored.map { MenuBarLiveActivities.activityID($0.key) }).count == 2)
        // Both rows show, and dismissing one leaves the other where it was.
        var tracker = MirrorTracker()
        #expect(tracker.sync(mirrored, now: t0).show.count == 2)
        tracker.dismiss(key: mirrored[0].key)
        #expect(tracker.sync(mirrored, now: t0).show.map(\.key) == [mirrored[1].key])
        // Separate clocks, so one pill's time is never the other's.
        var clock = LiveActivityClock()
        #expect(clock.update(key: mirrored[0].key, detail: "4:59", now: t0) == nil)
        #expect(clock.update(key: mirrored[1].key, detail: "4:58", now: t0.addingTimeInterval(1)) == nil)
    }

    /// macOS 27 draws the pill as the menu bar item itself, with its text only in the segments'
    /// attributed descriptions. Reading the item a step too far inside left Casement with nothing:
    /// no identifier, no label and no text, so the activity never reached the island.
    @Test func theRealPillFromMacOS27IsMirrored() throws {
        let item = pill(["IND 211/6 (20)"])
        #expect(MenuBarLiveActivities.classify(item) == .liveActivity)
        let mirrored = try #require(MenuBarLiveActivities.mirror(item, key: key(1)))
        #expect(mirrored.appName == nil)
        #expect(mirrored.detail == "IND 211/6 (20)")
        // The wrapper Casement used to read instead says nothing at all.
        #expect(MenuBarLiveActivities.classify(MenuBarItemInfo(x: 896, width: 110)) == .unknown)
    }

    /// A real food-delivery pill, read off the menu bar on 3 October 2026. The app gives its
    /// picture the accessibility description `food_di_preparing_icon`, and the time arrives as two
    /// labels, "13:01" and "min". Casement used to title the activity with the asset name and write
    /// "13:01 · min" under it.
    @Test func anAppsOwnNameForItsPictureNeverReachesTheIsland() throws {
        let mirrored = try #require(MenuBarLiveActivities.mirror(pill(["food_di_preparing_icon", "13:01", "min"], width: 85), key: key(1)))
        #expect(mirrored.detail == "13:01 min")
        #expect(mirrored.appName == nil)
        #expect(mirrored.detail?.contains("_") == false)
        // Dropped from the words on screen, kept for choosing the symbol.
        #expect(mirrored.hint == "food di preparing")
    }

    /// The common pill: one readable label, no app name anywhere. The island used to read
    /// "Live Activity" with the label under it, and lost the catalogue's layout as well.
    @Test func aPillWithOneLabelIsTitledByWhatItSays() throws {
        let mirrored = try #require(MenuBarLiveActivities.mirror(pill(["Delivered"]), key: key(1)))
        #expect(mirrored.appName == nil)
        #expect(mirrored.detail == "Delivered")
        let spec = MenuBarLiveActivities.activity(for: mirrored, look: nil, isNew: true)
        #expect(spec.title == "Delivered")
        #expect(spec.subtitle == "")
        var centre = ActivityCenter()
        let activity = try centre.apply(spec, now: t0)
        #expect(activity.title == "Delivered")
        #expect(activity.subtitle == nil)
        // Nothing readable at all still says where it came from.
        let bare = try #require(MenuBarLiveActivities.mirror(pill([]), key: key(2)))
        #expect(MenuBarLiveActivities.activity(for: bare, look: nil, isNew: true).title == "Live Activity")
    }

    /// A football pill at one-all: four labels, two of them the same number. De-duplicating the
    /// labels dropped the second "1", which left "1 · CHE" and put a team in the wing.
    @Test func aTiedScoreKeepsBothNumbers() throws {
        let item = pill(["ARS", "1", "CHE", "1"])
        #expect(item.allText == ["Live Activity", "ARS", "1", "CHE", "1", "Expanded"])
        let mirrored = try #require(MenuBarLiveActivities.mirror(item, key: key(1)))
        #expect(mirrored.appName == "ARS")
        #expect(mirrored.detail == "1 · CHE · 1")
        // Two sides, so neither number is the wing's.
        #expect(MenuBarLiveActivities.activity(for: mirrored, look: nil, isNew: false).trailing == "")
    }

    /// A pill in Hindi, one of this Mac's languages: a number and the word for minutes, as two
    /// labels. They are one phrase, and the word on its own is not a value for the wing.
    @Test func aUnitInAnotherLanguageStaysWithItsNumber() throws {
        let mirrored = try #require(MenuBarLiveActivities.mirror(pill(["8", "मिनट"]), key: key(1)))
        #expect(mirrored.appName == nil)
        #expect(mirrored.detail == "8 मिनट")
        let spec = MenuBarLiveActivities.activity(for: mirrored, look: nil, isNew: false)
        #expect(spec.title == "8 मिनट")
        #expect(spec.trailing == "8 मिनट")
        #expect(MenuBarLiveActivities.joined(["45", "Minuten"]) == "45 Minuten")
        // A team abbreviation is not a unit, and neither is a number.
        #expect(MenuBarLiveActivities.joined(["1", "CHE"]) == "1 · CHE")
        #expect(MenuBarLiveActivities.joined(["Lakers", "102"]) == "Lakers · 102")
    }

    /// A Home Assistant pill: `washing_machine` is what someone named the thing, not what an app
    /// named a picture. Dropping anything underscored left the activity with no title at all.
    @Test func aSnakeCaseTitleIsNotAnAssetName() throws {
        let mirrored = try #require(MenuBarLiveActivities.mirror(pill(["washing_machine", "42%"]), key: key(1)))
        #expect(mirrored.appName == "washing_machine")
        #expect(mirrored.detail == "42%")
        #expect(mirrored.hint == nil)
        #expect(MenuBarLiveActivities.activity(for: mirrored, look: nil, isNew: false).trailing == "42%")
    }

    /// Mute is built from the source, and muting saves the source to `config.json`. A source
    /// slugged from a pill would name a different thing on the next ball, and would put what
    /// someone's iPhone is showing on disk.
    @Test func theSourceNeverCarriesWhatThePillSaid() throws {
        let score = try #require(MenuBarLiveActivities.mirror(pill(["IND 245/3", "AUS 198"]), key: key(1)))
        let source = try #require(MenuBarLiveActivities.activity(for: score, look: nil, isNew: true).source)
        #expect(source == "live-activity")
        #expect(!source.contains("245"))
        // Settings' master mute reaches it.
        var settings = CasementSettings()
        settings.mutedSources = [MenuBarLiveActivities.source]
        #expect(settings.isMuted(source: source))
        #expect(MutedSources.displayName(source) { _ in nil } == "Live Activities")
        // A catalogued app still gets its own source, spelled as the catalogue spells it.
        let uber = try #require(MenuBarLiveActivities.mirror(pill(["Uber", "4 min"]), key: key(2)))
        #expect(MenuBarLiveActivities.activity(for: uber, look: nil, isNew: true).source == "live-activity:uber")
    }

    /// An app is named only when the text names it exactly. A phrase that merely holds an app's
    /// name is a phrase: "Man United 2 - 1 Arsenal" used to become the title, with an aeroplane
    /// and a flight layout, because the catalogue matched on containment.
    @Test func onlyAnExactNameNamesTheApp() throws {
        let score = try #require(MenuBarLiveActivities.mirror(pill(["Man United 2 - 1 Arsenal"]), key: key(1)))
        #expect(score.appName == nil)
        let spec = MenuBarLiveActivities.activity(for: score, look: nil, isNew: false)
        #expect(spec.title == "Man United 2 - 1 Arsenal")
        #expect(spec.template == "")
        // The catalogue's own spelling, from whatever the pill spelled it as.
        let flight = try #require(MenuBarLiveActivities.mirror(pill(["  flighty ", "Boarding 12:40"]), key: key(2)))
        #expect(flight.appName == "Flighty")
        #expect(MenuBarLiveActivities.activity(for: flight, look: nil, isNew: false).template == "flight")
    }

    /// "Uber, 4 min" in one label is an app and a detail. "Arriving at <street>, <street>" is one
    /// sentence, and splitting on the comma made half an address the title.
    @Test func onlyAKnownAppSplitsOnTheComma() throws {
        let uber = try #require(MenuBarLiveActivities.mirror(pill(["Uber, 4 min"]), key: key(1)))
        #expect(uber.appName == "Uber")
        #expect(uber.detail == "4 min")
        let route = try #require(MenuBarLiveActivities.mirror(pill(["Arriving at Acacia Avenue, Springfield"]), key: key(2)))
        #expect(route.appName == nil)
        #expect(route.detail == "Arriving at Acacia Avenue, Springfield")
    }

    @Test func assetNamesAreToldApartFromTitles() {
        for junk in ["food_di_preparing_icon", "ic_delivery", "statusIconSmall", "bg_image_2", "liveGlyph"] {
            #expect(MenuBarLiveActivities.isAssetName(junk), "\(junk) should read as an asset name")
        }
        for real in ["Uber", "Zomato", "Design review", "2 – 1", "13:01", "min", "Flight AA100",
                     "On the way", "LAL", "Café", "F1", "90%",
                     // An underscore is not an asset word: these are what someone named a thing.
                     "washing_machine", "front_door", "morning_routine", "IND_vs_AUS", "lofi_beats", "voice_memo_3",
                     // The asset word has to stand alone beside something else that is named.
                     "theBadgers", "eBadge", "myImagery"] {
            #expect(!MenuBarLiveActivities.isAssetName(real), "\(real) should reach the island")
        }
    }

    @Test func aUnitStaysWithItsNumber() {
        #expect(MenuBarLiveActivities.joined(["13:01", "min"]) == "13:01 min")
        #expect(MenuBarLiveActivities.joined(["4", "min", "away"]) == "4 min away")
        #expect(MenuBarLiveActivities.joined(["Uber", "4 min"]) == "Uber · 4 min")
        #expect(MenuBarLiveActivities.joined(["Lakers", "102"]) == "Lakers · 102")
        #expect(MenuBarLiveActivities.joined(["min"]) == "min")
        #expect(MenuBarLiveActivities.joined([]).isEmpty)
    }

    @Test func labelsInEveryLanguage() throws {
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

    @Test func mirroredTextDropsTheGenericLabel() throws {
        let a = MenuBarItemInfo(role: "AXMenuBarItem", description: "Live Activity", texts: ["Uber", "Arriving", "4 min"])
        #expect(MenuBarLiveActivities.mirror(a, key: "el:1") == MirroredLiveActivity(key: "el:1", appName: "Uber", detail: "Arriving · 4 min"))
        // Two activities with the same generic label keep separate keys.
        let b = pill(["Flighty", "Boards 0:42"])
        #expect(MenuBarLiveActivities.mirror(b, key: key(2))?.key == key(2))
        #expect(MenuBarLiveActivities.mirror(b, key: key(3))?.key == key(3))
        // The catalogue recognises the app even when it isn't first.
        let d = pill(["4 min", "Uber"])
        #expect(MenuBarLiveActivities.mirror(d, key: key(4)) == MirroredLiveActivity(key: key(4), appName: "Uber", detail: "4 min"))
        // Values alone: the value is all there is to show.
        #expect(MenuBarLiveActivities.mirror(pill(["2 – 1"]), key: key(5))?.detail == "2 – 1")
        // Hidden in the overflow is carried through.
        #expect(MenuBarLiveActivities.mirror(pill(["Timer", "4:59"], hidden: true), key: key(6))?.hidden == true)
    }

    @Test func clockValues() {
        #expect(MenuBarLiveActivities.clockSeconds(in: "4:59") == 299)
        #expect(MenuBarLiveActivities.clockSeconds(in: "Boards 1:02:03") == 3723)
        #expect(MenuBarLiveActivities.clockSeconds(in: "4 min") == nil)
        #expect(MenuBarLiveActivities.clockSeconds(in: "2:75") == nil)
        #expect(MenuBarLiveActivities.clockSeconds(in: "IND 245/3") == nil)
        // The clock is not always the last word. A real delivery pill shows the countdown and
        // its unit as two labels, which join into one detail.
        #expect(MenuBarLiveActivities.clockSeconds(in: "13:01 min") == 781)
        #expect(MenuBarLiveActivities.clockSeconds(in: "0:42 left") == 42)
        #expect(MenuBarLiveActivities.clockSeconds(in: "8 \u{092E}\u{093F}\u{0928}\u{091F}") == nil)
        #expect(MenuBarLiveActivities.clockSeconds(in: "Arriving \u{00B7} 4 min") == nil)
        // Two clock-shaped words: the later one, which on a pill is the one that moves. A
        // departure time read on its own costs nothing, since a clock only starts animating
        // once a reading ticks with it (`clockDirectionNeverSettlesOnATimeOfDay`).
        #expect(MenuBarLiveActivities.clockSeconds(in: "Boards 18:30 \u{00B7} 12:05") == 725)
        #expect(MenuBarLiveActivities.clockSeconds(in: "Boards 18:30") == 1110)
    }

    /// A time of day sits there unchanged, so it never looks like a running clock: two equal
    /// readings a second apart lose the direction rather than settle one.
    @Test func clockDirectionNeverSettlesOnATimeOfDay() {
        var clock = LiveActivityClock()
        let t = Date(timeIntervalSince1970: 1_000_000)
        for second in 0...5 {
            #expect(clock.update(key: "f", detail: "Boards 18:30", now: t.addingTimeInterval(Double(second))) == nil,
                    "second \(second)")
        }
    }

    /// The countdown and its unit arrive as two labels, so the detail reads "13:01 min" and the
    /// clock is not the last word. Casement still has to read it: otherwise the island shows a
    /// number that sits still between menu bar reads, and nothing animates in the wing.
    @Test func aClockThatArrivesInTwoLabelsIsStillRead() throws {
        var mirror = MenuBarMirror()
        let k = key(0x5151)
        // The shape this Mac really exposes: the app's own picture, the time, the unit, Expanded.
        try mirror.read([pill(["food_di_preparing_icon", "13:01", "min"])], keys: [k], now: t0)
        let id = MenuBarLiveActivities.activityID(k)
        #expect(mirror.centre.activities[id]?.subtitle == nil)
        #expect(mirror.centre.activities[id]?.title == "13:01 min")
        // One reading can't give a direction; the next one can.
        #expect(mirror.centre.activities[id]?.endsAt == nil)
        try mirror.read([pill(["food_di_preparing_icon", "13:00", "min"])], keys: [k], now: t0.addingTimeInterval(1))
        let running = mirror.centre.activities[id]
        #expect(running?.endsAt == t0.addingTimeInterval(1 + 780))
        #expect(running?.resolvedTemplate == .timer)
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
        #expect(spec.source == "live-activity:uber")
        #expect(MenuBarLiveActivities.isMirroredSource(spec.source!))
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
            let reading = clock.update(key: m.key, detail: detail, now: now)
            let spec = MenuBarLiveActivities.activity(for: m, look: nil, isNew: false, clock: reading)
            // No reading, no clock, whatever the text still says.
            if reading == nil { c.clearClock(id: spec.id!) }
            return try c.apply(spec, now: now)
        }
        _ = try read("Closes in 4:59", at: 0)
        let running = try read("Closes in 4:58", at: 1)
        #expect(running.endsAt == t0.addingTimeInterval(299))
        #expect(running.resolvedTemplate == .timer)
        // A reading that doesn't settle the clock stops it, even though the item still shows a
        // time: the direction was lost, so the wing would be counting to a moment nobody promised.
        #expect(try read("Closes in 4:58", at: 1.9).endsAt == nil)
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

    /// One activity ends and another begins. The new pill is a new element, so it is a new key:
    /// it gets its own peek, nothing of the one before it merges into it, and a dismissal of the
    /// one before doesn't swallow it.
    @Test func anActivityEndingAndAnotherBeginning() throws {
        var mirror = MenuBarMirror()
        // A timer pill, running, dismissed from the island.
        try mirror.read([pill(["Closes in 4:59"])], keys: [key(1)], now: t0)
        try mirror.read([pill(["Closes in 4:58"])], keys: [key(1)], now: t0.addingTimeInterval(1))
        let first = try #require(mirror.centre.activities[MenuBarLiveActivities.activityID(key(1))])
        #expect(first.endsAt == t0.addingTimeInterval(299))
        #expect(mirror.centre.sneak?.id == first.id)
        mirror.tracker.dismiss(key: key(1))
        try mirror.read([pill(["Closes in 4:57"])], keys: [key(1)], now: t0.addingTimeInterval(2))
        #expect(mirror.centre.activities.isEmpty)

        // It ends, and a delivery begins at another element.
        try mirror.read([], keys: [], now: t0.addingTimeInterval(60))
        try mirror.read([pill(["Delivered"])], keys: [key(2)], now: t0.addingTimeInterval(61))
        let second = try #require(mirror.centre.activities.values.first)
        #expect(mirror.centre.activities.count == 1)
        #expect(second.id != first.id)
        #expect(second.title == "Delivered")
        // The dismissal of the one before doesn't reach it, and it gets a peek of its own.
        #expect(mirror.centre.sneak?.id == second.id)
        // Nothing of the timer merged in: no countdown is left running in the wing.
        #expect(second.endsAt == nil)
        #expect(second.trackSpan == nil)
        #expect(second.resolvedTemplate != .timer)
    }
}

/// `AppModel.syncMenuBarActivities`, as much of it as is pure logic: the tracker, the clock and
/// the activities the island ends up with, so a test can play a menu bar through the whole path
/// rather than one function of it.
struct MenuBarMirror {
    var tracker = MirrorTracker()
    var clock = LiveActivityClock()
    var centre = ActivityCenter()
    var keys: Set<String> = []

    mutating func read(_ items: [MenuBarItemInfo], keys next: [String], now: Date) throws {
        let all = zip(items, next).compactMap { item, key in MenuBarLiveActivities.mirror(item, key: key) }
        let shown = tracker.sync(all, now: now).show
        let live = Set(shown.map(\.key))
        for key in keys.subtracting(live) {
            _ = centre.remove(id: MenuBarLiveActivities.activityID(key))
            clock.forget(key)
        }
        for m in shown {
            let reading = clock.update(key: m.key, detail: m.detail, now: now)
            let spec = MenuBarLiveActivities.activity(for: m, look: nil, isNew: !keys.contains(m.key),
                                                      clock: reading, staleAt: tracker.staleAt(key: m.key))
            if reading == nil { centre.clearClock(id: spec.id!) }
            _ = try centre.apply(spec, now: now)
        }
        keys = live
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
        // Pressing the original item only ever follows a click inside Casement.
        #expect(throws: (any Error).self) { try URLCommand.parse(URL(string: "casement://menubar-activity?key=id:x")!) }
    }
}
