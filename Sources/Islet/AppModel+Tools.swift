import AppKit
import IsletCore
import IsletSystem

/// The tools under "More" and the extra AI usage on Home, tied to the island's life: the
/// camera runs only while the Mirror page shows, prices are asked for only while Stocks is
/// open, sales on their 15-minute rhythm, and AI usage when the island opens. Every deadline
/// goes through the one timer in `reschedule()`.
extension AppModel {
    /// Settings changed (or Islet started): pass each tool its part.
    func applyTools() {
        let s = settings
        let again: () -> Void = { [weak self] in self?.reschedule() }
        sales.onChange = again
        stocks.onChange = again
        teleprompter.onChange = again
        sales.apply(s.sales)
        stocks.apply(s.stocks)
        toolUsage.apply(s)
        teleprompter.apply(s.teleprompter)
        syncToolPages()
    }

    func toolsIslandOpened() {
        toolUsage.islandOpened()
        syncToolPages()
    }

    func toolsIslandClosed() { syncToolPages() }

    func toolsTabChanged(from previous: IslandTab) {
        guard previous != tab else { return }
        syncToolPages()
    }

    /// Start what the page on show needs and stop what it doesn't.
    func syncToolPages() {
        let open = expandedScreen != nil
        if open, tab == .mirror, settings.mirror.enabled { mirror.show() } else { mirror.hide() }
        stocks.setPageOpen(open && tab == .stocks && settings.stocks.enabled)
        if open, tab == .sales { sales.pageOpened() }
        if open, tab == .teleprompter {
            teleprompter.load()
        } else {
            teleprompter.pause()
        }
    }

    /// The tools' next moments, for `reschedule()`.
    func toolDeadlines(now: Date) -> [Date] {
        [sales.nextRefresh(now: now), stocks.nextRefresh(now: now), teleprompter.endsAt(now: now)].compactMap { $0 }
    }

    /// The deadline timer fired: whatever is due runs.
    func advanceTools(now: Date) {
        sales.refreshIfDue(now: now)
        stocks.refreshIfDue(now: now)
        teleprompter.advance(now: now)
    }

    /// The teleprompter asks for clear glass while it shows ("See-through while reading").
    var seeThroughPage: Bool {
        tab == .teleprompter && settings.teleprompter.enabled && settings.teleprompter.seeThrough
    }

    /// A scroll over the open island while the teleprompter shows moves the script (and stops
    /// it) instead of counting as a swipe. Returns whether it was used.
    func teleprompterScroll(deltaY: Double, precise: Bool) -> Bool {
        guard expandedScreen != nil, tab == .teleprompter, settings.teleprompter.enabled, deltaY != 0 else { return false }
        teleprompter.scroll(by: -deltaY * (precise ? 1 : 12))
        return true
    }

    /// The pace from the page's − and + buttons, saved like any other setting.
    func nudgeTeleprompterPace(by steps: Double) {
        var t = settings.teleprompter
        t.wordsPerMinute += steps * TeleprompterSettings.wordsPerMinuteStep
        settings.teleprompter = t.sanitized()
        teleprompter.apply(settings.teleprompter)
        settingsEdited()
    }
}
