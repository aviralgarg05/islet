import CoreGraphics
import Foundation

/// A menu bar item as seen through Accessibility (only what's needed to recognise and show it).
public struct MenuBarItemInfo: Codable, Equatable, Sendable {
    public var identifier: String?
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var description: String?
    public var value: String?
    public var help: String?
    /// Text found in the item's descendants, in reading order.
    public var texts: [String]
    /// Names of the item's custom actions ("End Live Activity", "Remove from Menu Bar").
    public var customActions: [String]
    /// Who draws the item: "agent" (MenuBarAgent), "renderer" (the Live Activity renderer) or the
    /// owning app's bundle ID for third-party status items, whose content is never read.
    public var owner: String?
    /// Global x of the item, used to keep Apple's left-to-right order.
    public var x: CGFloat
    public var width: CGFloat
    /// Collapsed into the menu bar's overflow (stacked behind the chevron, not drawn).
    public var hidden: Bool
    /// Set in diagnostics output.
    public var kind: MenuBarItemKind?

    public init(identifier: String? = nil, role: String? = nil, subrole: String? = nil, title: String? = nil,
                description: String? = nil, value: String? = nil, help: String? = nil, texts: [String] = [],
                customActions: [String] = [], owner: String? = "agent", x: CGFloat = 0, width: CGFloat = 0, hidden: Bool = false) {
        self.identifier = identifier; self.role = role; self.subrole = subrole; self.title = title
        self.description = description; self.value = value; self.help = help; self.texts = texts
        self.customActions = customActions; self.owner = owner; self.x = x; self.width = width; self.hidden = hidden
    }

    /// Every non-empty piece of text the item exposes, de-duplicated, in a stable order.
    public var allText: [String] {
        var seen = Set<String>()
        return ([description, title, value, help].compactMap { $0 } + texts)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// MenuBarAgent's own labels, in every language it ships (MenuBarCore.loctable). Matching on
/// them is what tells a Live Activity apart from any other item it hosts.
public struct MenuBarLabels: Equatable, Sendable {
    /// "Live Activity": the pill's accessibility label.
    public var liveActivity: Set<String>
    /// "End Live Activity" (and, from macOS 27.2, "Hide Live Activity"): its menu commands.
    public var liveActivityActions: Set<String>
    /// "AV Controls": the camera and microphone module, which isn't an activity.
    public var avControls: Set<String>
    /// "Expanded" and similar words that describe state, not content.
    public var generic: Set<String>

    public init(liveActivity: Set<String>, liveActivityActions: Set<String>, avControls: Set<String>, generic: Set<String>) {
        self.liveActivity = liveActivity; self.liveActivityActions = liveActivityActions
        self.avControls = avControls; self.generic = generic
    }

    public static let english = MenuBarLabels(
        liveActivity: ["Live Activity"],
        liveActivityActions: ["End Live Activity", "Hide Live Activity"],
        avControls: ["AV Controls"],
        generic: ["Expanded"]
    )

    /// Build from the loctable's contents: locale → key → string.
    public static func from(loctable: [String: [String: String]]) -> MenuBarLabels {
        var labels = english
        for (_, table) in loctable {
            if let s = table["liveActivity.accessibilityLabel"] { labels.liveActivity.insert(s) }
            for key in ["liveActivity.endLiveActivityMenuItem", "liveActivity.hideLiveActivityMenuItem"] {
                if let s = table[key] { labels.liveActivityActions.insert(s) }
            }
            if let s = table["avModule.accessibilityLabel"] { labels.avControls.insert(s) }
            for key in ["liveActivity.expandedChevronDescription", "avModule.expandedChevronDescription"] {
                if let s = table[key] { labels.generic.insert(s) }
            }
        }
        return labels
    }
}

/// What a menu bar item is.
public enum MenuBarItemKind: String, Codable, Sendable {
    case liveActivity, systemItem, avControls, overflowButton, thirdParty, unknown
}

/// A Live Activity from the iPhone (or a Mac app) that macOS shows in the menu bar.
public struct MirroredLiveActivity: Equatable, Sendable {
    /// Stable key for this activity while it lives.
    public var key: String
    public var appName: String
    /// The compact content, as text: e.g. "12 min" or "2 – 1".
    public var detail: String?
    /// Hidden in the menu bar's overflow, so the notch is the only place it shows.
    public var hidden: Bool

    public init(key: String, appName: String, detail: String?, hidden: Bool = false) {
        self.key = key
        self.appName = appName
        self.detail = detail
        self.hidden = hidden
    }
}

public enum MenuBarLiveActivities {
    /// The start of every mirrored activity's `source`. They may come from the iPhone or from
    /// the Mac itself (Shortcuts, Clock); macOS doesn't say which. Each app has its own source
    /// (`source(for:)`), so muting one app's activity leaves the others.
    public static let source = "live-activity"

    /// The source of one app's mirrored activities: "live-activity:uber".
    public static func source(for appName: String) -> String {
        let slug = appName.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? source : source + ":" + slug
    }

    /// Whether a source belongs to the mirror (scripts can't use it).
    public static func isMirroredSource(_ s: String) -> Bool {
        s == source || s.hasPrefix(source + ":")
    }
    /// Bundle IDs of the processes that render Live Activity content for MenuBarAgent.
    public static let rendererBundleIDs: Set<String> = ["com.apple.chrono.WidgetRenderer-Activities", "com.apple.ScreenContinuity"]

    /// Classify an item. Every built-in extra has a `com.apple.menuextra.*` identifier (battery,
    /// now-playing, timer, audiovideo, …), so anything with one is a system item; a Live
    /// Activity is recognised by its label, identifier, menu commands or renderer.
    public static func classify(_ item: MenuBarItemInfo, labels: MenuBarLabels = .english) -> MenuBarItemKind {
        switch item.owner {
        case "renderer": return .liveActivity
        case "agent", nil: break
        default: return .thirdParty
        }
        let id = item.identifier?.lowercased() ?? ""
        if item.role == "AXButton", item.identifier == nil { return .overflowButton }
        if id.hasPrefix("com.apple.menuextra.") { return .systemItem }
        if id.contains("live-activity") || id.contains("liveactivit") { return .liveActivity }
        let names = [item.description, item.title].compactMap { $0 }
        if names.contains(where: labels.avControls.contains) { return .avControls }
        if names.contains(where: labels.liveActivity.contains) { return .liveActivity }
        if item.customActions.contains(where: labels.liveActivityActions.contains) { return .liveActivity }
        // A menu bar item MenuBarAgent draws without an identifier: every system item has one.
        if item.identifier == nil, item.role == "AXMenuBarItem" || item.subrole == "AXMenuExtra",
           !content(item, labels: labels).isEmpty {
            return .liveActivity
        }
        return .unknown
    }

    public static func isLiveActivity(_ item: MenuBarItemInfo, labels: MenuBarLabels = .english) -> Bool {
        classify(item, labels: labels) == .liveActivity
    }

    /// The item's text without MenuBarAgent's generic words.
    static func content(_ item: MenuBarItemInfo, labels: MenuBarLabels) -> [String] {
        item.allText.filter { !labels.liveActivity.contains($0) && !labels.generic.contains($0) && !labels.liveActivityActions.contains($0) }
    }

    /// Turn an item into the app name and compact text Islet shows.
    /// - Parameters:
    ///   - key: a stable identity for the item (the caller knows the element; the label doesn't
    ///     tell activities apart). Defaults to the identifier.
    ///   - knownApp: recognises an app name among the item's text (the Live Activity catalogue).
    public static func mirror(_ item: MenuBarItemInfo, key: String? = nil, labels: MenuBarLabels = .english,
                              knownApp: (String) -> Bool = { _ in false }) -> MirroredLiveActivity? {
        guard isLiveActivity(item, labels: labels) else { return nil }
        var text = content(item, labels: labels)
        // "Uber, 4 min" in a single description splits into app and detail.
        if text.count == 1, let comma = text[0].range(of: ", ") {
            text = [String(text[0][..<comma.lowerBound]), String(text[0][comma.upperBound...])]
        }
        let app: String
        if let i = text.firstIndex(where: knownApp) {
            app = text.remove(at: i)
        } else if text.count >= 2, !looksLikeValue(text[0]) {
            app = text.removeFirst()
        } else {
            app = "Live Activity"
        }
        let detail = text.joined(separator: " · ")
        guard let key = key ?? item.identifier else { return nil }
        return MirroredLiveActivity(key: key, appName: app, detail: detail.isEmpty ? nil : detail, hidden: item.hidden)
    }

    /// Numbers, times and scores ("4 min", "12:40", "2 – 1") are values, not app names.
    static func looksLikeValue(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return true }
        return CharacterSet.decimalDigits.contains(first) || clockSeconds(in: s) != nil
    }

    /// Every mirrored activity's id starts with this. Such ids, like `source`, belong to the
    /// mirror: the API and the URL scheme can't create, change or remove them.
    public static let idPrefix = "live-"

    public static func activityID(_ key: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return idPrefix + String(h, radix: 36)
    }

    public static func isMirrored(id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// Mirrored activities often hold addresses, names and scores, so scripts only read them
    /// when the user shares them.
    public static func isMirrored(_ activity: Activity) -> Bool {
        isMirroredSource(activity.source) || isMirrored(id: activity.id)
    }

    /// Menu bar items as diagnostics show them while mirrored activities aren't shared: the text
    /// of Live Activities, and of items that might be ones, is left out.
    public static func withoutActivityText(_ items: [MenuBarItemInfo]) -> [MenuBarItemInfo] {
        items.map { item in
            switch item.kind {
            case .systemItem?, .avControls?, .overflowButton?, .thirdParty?: return item
            case .liveActivity?, .unknown?, nil: break
            }
            var info = item
            info.title = nil; info.description = nil; info.value = nil; info.help = nil; info.texts = []
            return info
        }
    }

    /// The live activity Islet shows for a mirrored item.
    /// - Parameters:
    ///   - look: icon and tint for the app, from the Live Activity catalogue when known. The
    ///     catalogue also supplies the template, and dark brand tints are lifted to read on black.
    ///   - clock: a running countdown or count-up read from the item, animated locally.
    public static func activity(for m: MirroredLiveActivity, look: (symbol: String, tint: String)?, isNew: Bool,
                                clock: LiveActivityClock.Reading? = nil, staleAt: Date? = nil) -> ActivitySpec {
        let suggestion = look ?? SmartIcon.suggest(title: m.appName, subtitle: m.detail).map { ($0.symbol, $0.tint) }
        let tint = suggestion.flatMap { RGBA.parse($0.1) }.map { $0.readableOnBlack().hex }
        // Updates merge, so text the item no longer shows is sent as "" to clear it: otherwise an
        // old "4 min" would stay in the wing after the item moved on to longer text.
        var spec = ActivitySpec(
            id: activityID(m.key), source: source(for: m.appName), title: m.appName, subtitle: m.detail ?? "",
            icon: .symbol(suggestion?.0 ?? "dot.radiowaves.left.and.right"), trailing: shortTrailing(m.detail) ?? "",
            state: .running, tint: tint ?? suggestion?.1 ?? "white", priority: .normal, ttl: 0, sneak: isNew
        )
        spec.template = LiveActivityCatalog.look(for: m.appName)?.template.rawValue
        spec.staleAt = staleAt
        switch clock {
        case .countdown(let end)?:
            spec.endsAt = end
            spec.trailing = ""
        case .countUp(let start)?:
            spec.startedAt = start
            spec.trailing = ""
        case nil:
            break
        }
        return spec
    }

    /// The part of the detail that fits the compact wing: a trailing number, time or score.
    /// Nothing for a two-sided score ("IND 245/3 · AUS 198"): one side alone would make that
    /// team the story, so the peek and Home show the whole score instead.
    static func shortTrailing(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let parts = detail.components(separatedBy: " · ")
        if parts.filter({ $0.contains(where: \.isNumber) }).count >= 2 { return nil }
        let last = parts.last ?? detail
        return last.count <= 8 ? last : nil
    }

    /// Seconds in a clock-style value at the end of the text: "4:59", "1:02:03", "Boarding 0:42".
    public static func clockSeconds(in text: String) -> TimeInterval? {
        guard let token = text.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }).last else { return nil }
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.dropFirst().allSatisfy({ $0.count == 2 }) else { return nil }
        let n = parts.compactMap { Double($0) }
        guard n.count == parts.count, n.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return n.reduce(0) { $0 * 60 + $1 }
    }
}

/// Works out whether a clock shown in a mirrored activity counts down or up, from two readings,
/// so Islet can animate it itself instead of re-reading the menu bar every second.
public struct LiveActivityClock: Sendable {
    public enum Reading: Equatable, Sendable {
        case countdown(endsAt: Date)
        case countUp(startedAt: Date)
    }

    private var last: [String: (seconds: TimeInterval, at: Date)] = [:]
    private var known: [String: Reading] = [:]

    public init() {}

    /// Feed the latest detail text for an activity; returns the clock once its direction is known.
    public mutating func update(key: String, detail: String?, now: Date) -> Reading? {
        guard let s = detail.flatMap(MenuBarLiveActivities.clockSeconds(in:)) else {
            last[key] = nil
            known[key] = nil
            return nil
        }
        defer { last[key] = (s, now) }
        if let previous = last[key] {
            let elapsed = now.timeIntervalSince(previous.at)
            let delta = s - previous.seconds
            if elapsed > 0.5, delta < 0, abs(-delta - elapsed) < 2.5 {
                known[key] = .countdown(endsAt: now.addingTimeInterval(s))
            } else if elapsed > 0.5, delta > 0, abs(delta - elapsed) < 2.5 {
                known[key] = .countUp(startedAt: now.addingTimeInterval(-s))
            } else if abs(delta) > 2.5 || elapsed > 0.5 && delta == 0 {
                // Jumped (a new phase, a paused timer): start over.
                known[key] = nil
            }
        }
        // Keep the known clock unless the new reading disagrees with it by more than 2 s.
        if let k = known[key] {
            switch k {
            case .countdown(let end) where abs(end.timeIntervalSince(now) - s) <= 2: return k
            case .countUp(let start) where abs(now.timeIntervalSince(start) - s) <= 2: return k
            default:
                known[key] = nil
                return nil
            }
        }
        return nil
    }

    public mutating func forget(_ key: String) {
        last[key] = nil
        known[key] = nil
    }
}

/// What the mirror remembers between reads of the menu bar: which items were dismissed in the
/// island (they stay away until the item leaves the menu bar, even when its text changes) and
/// when each item's text last changed (one stuck for `staleAfter` dims, like any stale activity).
public struct MirrorTracker: Sendable {
    /// An item whose text hasn't changed for this long has probably stopped updating.
    public static let staleAfter: TimeInterval = 30 * 60

    private var lastChange: [String: (detail: String?, at: Date)] = [:]
    public private(set) var dismissed: Set<String> = []

    public init() {}

    /// Takes the menu bar's items: the ones to show, and the keys that have left the menu bar.
    public mutating func sync(_ items: [MirroredLiveActivity], now: Date) -> (show: [MirroredLiveActivity], gone: Set<String>) {
        let keys = Set(items.map(\.key))
        let gone = Set(lastChange.keys).union(dismissed).subtracting(keys)
        for key in gone {
            lastChange[key] = nil
            dismissed.remove(key)
        }
        for m in items where lastChange[m.key]?.detail != m.detail || lastChange[m.key] == nil {
            lastChange[m.key] = (m.detail, now)
        }
        return (items.filter { !dismissed.contains($0.key) }, gone)
    }

    /// Dismissed in the island: hidden until it leaves the menu bar.
    public mutating func dismiss(key: String) {
        dismissed.insert(key)
    }

    /// When an item dims if its text doesn't change again.
    public func staleAt(key: String) -> Date? {
        lastChange[key].map { $0.at.addingTimeInterval(Self.staleAfter) }
    }
}

/// Names for the sources a right-click muted, as Settings → Apps lists them.
public enum MutedSources {
    /// "Uber (Live Activity)" for a mirrored app, the app's name for a bundle id, or the source
    /// itself ("github-actions").
    public static func displayName(_ source: String, appName: (String) -> String?) -> String {
        if MenuBarLiveActivities.isMirroredSource(source) {
            let prefix = MenuBarLiveActivities.source + ":"
            guard source.hasPrefix(prefix) else { return "Live Activities" }
            let slug = source.dropFirst(prefix.count).split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return slug.joined(separator: " ") + " (Live Activity)"
        }
        if source.contains("."), let name = appName(source) { return name }
        return source
    }
}
