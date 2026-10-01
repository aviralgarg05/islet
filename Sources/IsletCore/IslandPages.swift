import Foundation

/// The open island's pages and where the switcher lists them: Home, Today and Shelf in the
/// capsule, the rest in its "more" menu. A page whose feature is off isn't listed at all, so
/// nothing in the switcher leads to a page that only says it is off.
public enum IslandPage: String, CaseIterable, Sendable {
    case home, today, shelf, widgets, clipboard, stats

    /// (capsule, more menu) for these settings. `current` is the page showing now: one
    /// opened some other way (a drop, a shortcut, the API) is added to the menu so it is
    /// still clear where you are.
    public static func switcher(_ s: IsletSettings, current: IslandPage?) -> (main: [IslandPage], more: [IslandPage]) {
        var main: [IslandPage] = [.home]
        if s.calendarEnabled || s.remindersEnabled { main.append(.today) }
        if s.shelfEnabled { main.append(.shelf) }
        var more: [IslandPage] = []
        if s.clipboardEnabled { more.append(.clipboard) }
        if s.pluginsEnabled { more.append(.widgets) }
        if s.systemStatsEnabled { more.append(.stats) }
        if let current, !main.contains(current), !more.contains(current) { more.append(current) }
        return (main, more)
    }
}
