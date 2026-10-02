import Foundation
import Testing
@testable import IsletCore

/// The switcher's pages in the order the user dragged them: a calm capsule of at most four,
/// the rest under More, Home always there, and pages left out still a click away elsewhere.
@Suite struct IslandPageLayoutTests {
    let everything: (IslandPage) -> Bool = { _ in true }

    @Test func asItComesHomeTodayAndShelfThenTheRestUnderMore() {
        let l = IslandPageLayout.standard
        #expect(l.bar == [.home, .today, .shelf])
        #expect(Set(l.bar + l.more) == Set(IslandPage.allCases))
        #expect((l.bar + l.more).count == IslandPage.allCases.count)
        #expect(l.hidden.isEmpty)
        // With every feature on, the capsule is as it always was.
        let split = l.split(everything)
        #expect(split.main == [.home, .today, .shelf])
        #expect(split.more.first == .clipboard)
    }

    @Test func theNewToolsStartOffAndListUnderMoreOnceOn() {
        var s = IsletSettings()
        for tool in [IslandPage.todos, .note, .converter, .emoji] {
            #expect(!tool.isAvailable(s))
            #expect(!IslandPage.switcher(s, current: nil).more.contains(tool))
        }
        s.todosEnabled = true
        s.emojiEnabled = true
        let pages = IslandPage.switcher(s, current: nil)
        #expect(pages.main == [.home, .today, .shelf])
        #expect(pages.more.filter { [.todos, .note, .converter, .emoji].contains($0) } == [.todos, .emoji])
    }

    @Test func draggingOntoAPageLandsBesideIt() {
        var l = IslandPageLayout.standard
        // Up from More, before the page it was dropped on.
        l.move(.clipboard, onto: .shelf)
        #expect(l.bar == [.home, .today, .clipboard, .shelf])
        #expect(!l.more.contains(.clipboard))
        // Down within the capsule, after it.
        l.move(.today, onto: .clipboard)
        #expect(l.bar == [.home, .clipboard, .today, .shelf])
        // Down into More.
        l.move(.today, onto: .weather)
        #expect(!l.bar.contains(.today))
        #expect(l.more[l.more.firstIndex(of: .weather)! + 1] == .today)
    }

    @Test func theCapsuleHoldsFourAndTheLastOneMovesToMore() {
        var l = IslandPageLayout.standard
        l.move(.clipboard, onto: .shelf)
        l.move(.weather, onto: .today)
        #expect(l.bar == [.home, .weather, .today, .clipboard])
        #expect(l.more.first == .shelf)
        #expect(l.split(everything).main.count == IslandPageLayout.maxInBar)
    }

    @Test func onlyPagesThatShowCountTowardsTheFour() {
        var l = IslandPageLayout.standard
        let listed: (IslandPage) -> Bool = { $0 != .today }
        l.move(.clipboard, to: .bar, listed: listed)
        l.move(.weather, to: .bar, listed: listed)
        // Today is off, so Home, Shelf, Clipboard and Weather fit.
        #expect(l.bar == [.home, .today, .shelf, .clipboard, .weather])
        #expect(l.split(listed).main == [.home, .shelf, .clipboard, .weather])
        // Today coming back on pushes the last one under More rather than crowding the capsule.
        let split = l.split(everything)
        #expect(split.main == [.home, .today, .shelf, .clipboard])
        #expect(split.more.first == .weather)
    }

    @Test func homeAlwaysStaysInTheCapsule() {
        var l = IslandPageLayout.standard
        l.move(.home, to: .more)
        l.move(.home, onto: .weather)
        l.setShown(.home, false)
        #expect(l.bar.first == .home)
        #expect(l.isShown(.home))
        // It can move within the capsule.
        l.move(.home, onto: .shelf)
        #expect(l.bar == [.today, .shelf, .home])
    }

    @Test func pagesLeftOutKeepTheirPlace() {
        var l = IslandPageLayout.standard
        l.setShown(.today, false)
        #expect(!l.isShown(.today))
        #expect(l.split(everything).main == [.home, .shelf])
        #expect(l.bar == [.home, .today, .shelf])
        l.setShown(.today, true)
        #expect(l.split(everything).main == [.home, .today, .shelf])
        // The page on show is still listed, even when it is left out.
        var s = IsletSettings()
        s.islandPages.setShown(.shelf, false)
        #expect(!IslandPage.switcher(s, current: nil).main.contains(.shelf))
        #expect(IslandPage.switcher(s, current: .shelf).more.last == .shelf)
    }

    @Test func nudgingWalksThroughBothLists() {
        var l = IslandPageLayout.standard
        l.nudge(.shelf, by: -1)
        #expect(l.bar == [.home, .shelf, .today])
        l.nudge(.today, by: 1)
        #expect(l.bar == [.home, .shelf])
        #expect(l.more.first == .today)
        l.nudge(.today, by: -1)
        #expect(l.bar == [.home, .shelf, .today])
        // Past the start of the list nothing moves.
        l.nudge(.home, by: -1)
        #expect(l.bar == [.home, .shelf, .today])
        // Pages that don't show are skipped over.
        let listed: (IslandPage) -> Bool = { $0 != .clipboard }
        l.nudge(.widgets, by: -1, listed: listed)
        #expect(l.bar.last == .widgets)
    }

    @Test func savedAndReadBackAndPagesFromANewerVersionAreSkipped() throws {
        var l = IslandPageLayout.standard
        l.move(.emoji, onto: .today)
        l.setShown(.stats, false)
        let data = try JSONEncoder().encode(l)
        #expect(try JSONDecoder().decode(IslandPageLayout.self, from: data) == l)
        let json = #"{"bar": ["today", "hologram", "home", "today"], "more": ["weather"], "hidden": ["home", "stats", "warp"]}"#
        let read = try JSONDecoder().decode(IslandPageLayout.self, from: Data(json.utf8))
        // Each page once, Home never left out, the ones not mentioned at the end of where they come.
        #expect(read.bar == [.today, .home, .shelf])
        #expect(read.more.first == .weather)
        #expect(Set(read.bar + read.more) == Set(IslandPage.allCases))
        #expect(read.hidden == [.stats])
    }

    @Test func theLayoutIsASettingLikeAnyOther() throws {
        var s = IsletSettings()
        s.islandPages.move(.clipboard, onto: .today)
        s.islandPages.setShown(.shelf, false)
        let data = try JSONEncoder().encode(s)
        #expect(IsletSettings.decodeLenient(data).islandPages == s.islandPages)
        // A broken value falls back to how Islet comes, and nothing else changes.
        let broken = IsletSettings.decodeLenient(Data(#"{"islandPages": "sideways", "todosEnabled": true}"#.utf8))
        #expect(broken.islandPages == .standard)
        #expect(broken.todosEnabled)
    }

    @Test func everyPageHasATitle() {
        for page in IslandPage.allCases { #expect(!page.title.isEmpty) }
        #expect(IslandPage.todos.title == "To-dos")
    }
}
