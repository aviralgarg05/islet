import Foundation

/// The open island's pages and where the switcher lists them: Home, Today and Shelf in the
/// capsule, the rest in its "more" menu, unless the order was changed in Settings
/// (`IslandPageLayout`). A page whose feature is off isn't listed at all, so nothing in the
/// switcher leads to a page that only says it is off. The tools start off and, once on, are
/// listed in the menu too.
public enum IslandPage: String, CaseIterable, Sendable {
    case home, today, shelf, widgets, clipboard, stats
    case mirror, teleprompter, stocks, sales
    case shortcuts, weather
    case todos, note, converter, emoji

    /// (capsule, more menu) for these settings. `current` is the page showing now: one
    /// opened some other way (a drop, a shortcut, the API) is added to the menu so it is
    /// still clear where you are.
    public static func switcher(_ s: IsletSettings, current: IslandPage?) -> (main: [IslandPage], more: [IslandPage]) {
        var split = s.islandPages.split { $0.isAvailable(s) }
        if let current, !split.main.contains(current), !split.more.contains(current) { split.more.append(current) }
        return split
    }

    /// Whether this page's feature is on, so the page can be shown. Home always can.
    public func isAvailable(_ s: IsletSettings) -> Bool {
        switch self {
        case .home: return true
        case .today: return s.calendarEnabled || s.remindersEnabled
        case .shelf: return s.shelfEnabled
        case .widgets: return s.pluginsEnabled
        case .clipboard: return s.clipboardEnabled
        case .stats: return s.systemStatsEnabled
        case .mirror: return s.mirror.enabled
        case .teleprompter: return s.teleprompter.enabled
        case .stocks: return s.stocks.enabled
        case .sales: return s.sales.enabled
        case .shortcuts: return s.shortcutsEnabled
        case .weather: return s.weatherEnabled
        case .todos: return s.todosEnabled
        case .note: return s.noteEnabled
        case .converter: return s.converterEnabled
        case .emoji: return s.emojiEnabled
        }
    }

    /// The name the switcher and Settings give it.
    public var title: String {
        switch self {
        case .home: return "Home"
        case .today: return "Today"
        case .shelf: return "Shelf"
        case .widgets: return "Widgets"
        case .clipboard: return "Clipboard"
        case .stats: return "System"
        case .mirror: return "Mirror"
        case .teleprompter: return "Teleprompter"
        case .stocks: return "Stocks"
        case .sales: return "Sales"
        case .shortcuts: return "Shortcuts"
        case .weather: return "Weather"
        case .todos: return "To-dos"
        case .note: return "Note"
        case .converter: return "Converter"
        case .emoji: return "Emoji"
        }
    }
}

/// Where each page sits in the switcher: in the capsule, under More, or left out. Settings →
/// General → Island pages changes it by dragging; a page whose feature is off keeps its place
/// for when it comes back on. Home is always in the capsule.
public struct IslandPageLayout: Codable, Equatable, Sendable {
    /// Pages in the capsule, in order.
    public private(set) var bar: [IslandPage]
    /// Pages under More, in order.
    public private(set) var more: [IslandPage]
    /// Pages left out of the switcher. They keep their place, and a drop, a link or a shortcut
    /// still opens them.
    public private(set) var hidden: Set<IslandPage>

    /// The capsule holds at most this many pages, so it stays calm; any more go under More.
    public static let maxInBar = 4

    /// How Islet comes: Home, Today and Shelf in the capsule, and the rest under More.
    public static let defaultBar: [IslandPage] = [.home, .today, .shelf]
    public static let defaultMore: [IslandPage] = [.clipboard, .widgets, .stats, .shortcuts, .weather, .todos, .note, .converter, .emoji,
                                            .mirror, .teleprompter, .stocks, .sales]
    public static let standard = IslandPageLayout(bar: defaultBar, more: defaultMore)

    public init(bar: [IslandPage] = defaultBar, more: [IslandPage] = defaultMore, hidden: Set<IslandPage> = []) {
        self.bar = bar
        self.more = more
        self.hidden = hidden
        normalise()
    }

    enum CodingKeys: String, CodingKey { case bar, more, hidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A page this build doesn't know is skipped, not the whole layout.
        func pages(_ key: CodingKeys) -> [IslandPage] {
            ((try? c.decodeIfPresent([String].self, forKey: key)) ?? nil)?.compactMap(IslandPage.init(rawValue:)) ?? []
        }
        self.init(bar: pages(.bar), more: pages(.more), hidden: Set(pages(.hidden)))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bar.map(\.rawValue), forKey: .bar)
        try c.encode(more.map(\.rawValue), forKey: .more)
        try c.encode(IslandPage.allCases.filter(hidden.contains).map(\.rawValue), forKey: .hidden)
    }

    /// Each page once; Home in the capsule and never left out; a page missing from the lists
    /// (one added in a later version) at the end of the list it comes in.
    mutating func normalise() {
        var seen: Set<IslandPage> = []
        bar = bar.filter { seen.insert($0).inserted }
        more = more.filter { seen.insert($0).inserted }
        if let i = more.firstIndex(of: .home) {
            more.remove(at: i)
            bar.insert(.home, at: 0)
        } else if !bar.contains(.home) {
            bar.insert(.home, at: 0)
        }
        seen.insert(.home)
        for page in Self.defaultBar + Self.defaultMore + IslandPage.allCases where seen.insert(page).inserted {
            if Self.defaultBar.contains(page) { bar.append(page) } else { more.append(page) }
        }
        hidden.remove(.home)
    }

    /// The capsule and the menu for the pages that can show (`listed`): left-out pages are
    /// skipped, and past `maxInBar` the capsule's last pages start the menu.
    public func split(_ listed: (IslandPage) -> Bool) -> (main: [IslandPage], more: [IslandPage]) {
        let shown = { (p: IslandPage) in listed(p) && !hidden.contains(p) }
        let inBar = bar.filter(shown)
        return (Array(inBar.prefix(Self.maxInBar)), Array(inBar.dropFirst(Self.maxInBar)) + more.filter(shown))
    }

    /// Whether a page is listed in the switcher (when its feature is on).
    public func isShown(_ page: IslandPage) -> Bool { !hidden.contains(page) }

    public mutating func setShown(_ page: IslandPage, _ shown: Bool) {
        guard page != .home else { return }
        if shown { hidden.remove(page) } else { hidden.insert(page) }
    }

    public enum Place: Sendable, Equatable { case bar, more }

    public func place(of page: IslandPage) -> Place { bar.contains(page) ? .bar : .more }

    /// Moves `page` to where `target` is: after it when coming from above, before it when
    /// coming from below, as a row dragged over another lands. Home stays in the capsule.
    /// - Parameter listed: the pages Settings shows; the capsule's limit counts only those.
    public mutating func move(_ page: IslandPage, onto target: IslandPage, listed: (IslandPage) -> Bool = { _ in true }) {
        guard page != target else { return }
        let order = bar + more
        guard let from = order.firstIndex(of: page), let to = order.firstIndex(of: target) else { return }
        let place = place(of: target)
        if page == .home, place == .more { return }
        remove(page)
        var list = place == .bar ? bar : more
        guard let at = list.firstIndex(of: target) else { return }
        list.insert(page, at: from < to ? at + 1 : at)
        if place == .bar { bar = list } else { more = list }
        settle(keeping: page, listed: listed)
    }

    /// Moves `page` to the start or end of a list (a drop on its heading, or "Move to More").
    public mutating func move(_ page: IslandPage, to place: Place, atStart: Bool = false, listed: (IslandPage) -> Bool = { _ in true }) {
        if page == .home, place == .more { return }
        remove(page)
        switch place {
        case .bar: if atStart { bar.insert(page, at: 0) } else { bar.append(page) }
        case .more: if atStart { more.insert(page, at: 0) } else { more.append(page) }
        }
        settle(keeping: page, listed: listed)
    }

    /// One place up or down the whole order (for the keyboard and the row's menu).
    public mutating func nudge(_ page: IslandPage, by step: Int, listed: (IslandPage) -> Bool = { _ in true }) {
        let order = (bar + more).filter { listed($0) || $0 == page }
        guard let i = order.firstIndex(of: page) else { return }
        let j = i + step
        guard order.indices.contains(j) else {
            // Past the end of the capsule's pages: down into More, or up into the capsule.
            if step > 0, place(of: page) == .bar { move(page, to: .more, atStart: true, listed: listed) }
            return
        }
        let target = order[j]
        if place(of: target) != place(of: page) {
            move(page, to: place(of: target), atStart: step > 0, listed: listed)
        } else {
            move(page, onto: target, listed: listed)
        }
    }

    private mutating func remove(_ page: IslandPage) {
        bar.removeAll { $0 == page }
        more.removeAll { $0 == page }
    }

    /// With more listed pages in the capsule than it holds, the last ones (other than the page
    /// just moved) go to the start of More.
    private mutating func settle(keeping page: IslandPage, listed: (IslandPage) -> Bool) {
        while bar.filter({ listed($0) && !hidden.contains($0) }).count > Self.maxInBar,
              let last = bar.lastIndex(where: { $0 != page && $0 != .home && listed($0) && !hidden.contains($0) }) {
            more.insert(bar.remove(at: last), at: 0)
        }
        normalise()
    }
}
