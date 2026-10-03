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

    /// Every non-empty piece of text the item exposes, in a stable order.
    ///
    /// Only the four attributes are de-duplicated, against each other: an item repeats itself
    /// across them often. `texts` is positional, one label per piece of the pill, so a repeat
    /// there is a piece of what the pill says: ["ARS", "1", "CHE", "1"] is a tied score, and
    /// dropping the second "1" left "1 · CHE", which put a team abbreviation in the wing.
    public var allText: [String] {
        var seen = Set<String>()
        let attributes = [description, title, value, help].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let labels = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return attributes + labels
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
    /// The app the catalogue recognised, or the first of several labels. Nil when the pill named
    /// no app: `detail` is then all it says, and the island titles it with that.
    public var appName: String?
    /// The compact content, as text: e.g. "12 min" or "2 – 1".
    public var detail: String?
    /// Hidden in the menu bar's overflow, so the notch is the only place it shows.
    public var hidden: Bool
    /// Words from the app's own name for its picture ("food di preparing"), which are never shown
    /// but are often the only clue to what the activity is, so the right symbol can be chosen.
    public var hint: String?

    public init(key: String, appName: String?, detail: String?, hidden: Bool = false, hint: String? = nil) {
        self.key = key
        self.appName = appName
        self.detail = detail
        self.hidden = hidden
        self.hint = hint
    }
}

public enum MenuBarLiveActivities {
    /// The start of every mirrored activity's `source`. They may come from the iPhone or from
    /// the Mac itself (Shortcuts, Clock); macOS doesn't say which. Each app has its own source
    /// (`source(for:)`), so muting one app's activity leaves the others.
    public static let source = "live-activity"

    /// macOS puts Live Activities in the menu bar from macOS 26 on; before that there is
    /// nothing to mirror, so the switch and the Accessibility it would need don't apply.
    public static let minimumOSMajor = 26

    public static func isSupported(osMajor: Int) -> Bool { osMajor >= minimumOSMajor }

    /// What follows MenuBarAgent's menu bar between measurements.
    public enum Watch: Equatable, Sendable {
        /// Nothing: the menu bar is measured when an app comes to the front, launches or quits,
        /// or the pointer reaches the island.
        case off
        /// Only items appearing, going or moving, so "Fit the menu bar" fits the wings again as
        /// soon as an item appears or widens. No item's content is read.
        case layout
        /// Live Activities are read and shown in the island; layout changes are followed too.
        case mirror
    }

    /// - Parameters:
    ///   - showActivities: "Show Live Activities" is on.
    ///   - fitsMenuBar: the closed island fits the menu bar ("Fit the menu bar").
    ///   - inFront: this login session is the one in front.
    ///   - supported: this macOS puts Live Activities in the menu bar (`isSupported`).
    ///   - trusted: Islet has Accessibility.
    public static func watch(showActivities: Bool, fitsMenuBar: Bool, inFront: Bool, supported: Bool, trusted: Bool) -> Watch {
        guard inFront, supported, trusted else { return .off }
        if showActivities { return .mirror }
        return fitsMenuBar ? .layout : .off
    }

    /// The source of one app's mirrored activities: "live-activity:uber".
    ///
    /// Only an app the catalogue knows, spelled as the catalogue spells it, gets a source of its
    /// own. Everything else uses the plain `source`, which the master mute ("live-activity",
    /// `IsletSettings.isMuted(source:)`) covers.
    ///
    /// An app name is never slugged straight out of a pill. What a pill says is a score, a street
    /// or a status, and it changes on the next read: "live-activity:ind-245-3" names a different
    /// thing on the next ball, so Mute would never match the same activity twice. Mute also
    /// appends the source to `mutedSources` and saves it, and what someone's iPhone is showing
    /// has no business being written to `config.json`.
    public static func source(for appName: String?) -> String {
        guard let appName, let look = LiveActivityCatalog.exact(appName) else { return source }
        let slug = look.app.lowercased().unicodeScalars
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

    /// The item's text without MenuBarAgent's generic words, and without the names apps give
    /// their own pictures (`isAssetName`), which are not written for anyone to read.
    static func content(_ item: MenuBarItemInfo, labels: MenuBarLabels) -> [String] {
        item.allText.filter {
            !labels.liveActivity.contains($0) && !labels.generic.contains($0)
                && !labels.liveActivityActions.contains($0) && !isAssetName($0)
        }
    }

    /// The words apps put in the name of a picture. None of them says what an activity is, so
    /// they are both what marks a name as an asset's and what `words(fromAssetName:)` drops
    /// before the symbol matcher reads the rest.
    static let assetWords: Set<String> = ["icon", "image", "img", "asset", "glyph", "badge", "ic", "bg", "logo", "pic"]

    /// Whether a piece of text is an app's name for one of its own pictures rather than words for
    /// a person: `food_di_preparing_icon`, `ic_delivery`, `statusIconSmall`. Several apps give an
    /// image in their Live Activity an accessibility description like that, and showing it as the
    /// activity's title is worse than showing nothing.
    ///
    /// One of `assetWords` has to be a word of the name. An underscore on its own isn't enough:
    /// `washing_machine`, `front_door`, `morning_routine`, `IND_vs_AUS`, `lofi_beats` and
    /// `voice_memo_3` are what someone named a thing, and dropping them left the activity with no
    /// title at all. In camelCase the word has to stand alone beside something else that is
    /// named, so `theBadgers`, `eBadge` and `myImagery` stay too.
    static func isAssetName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 64, !text.contains(" ") else { return false }
        let scalars = text.unicodeScalars
        guard scalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }) else { return false }
        if text.contains("_") {
            return text.lowercased().split(separator: "_").contains { assetWords.contains(String($0)) }
        }
        guard text.contains(where: \.isUppercase), text.first?.isUppercase == false else { return false }
        let words = camelCaseWords(text)
        return words.contains { assetWords.contains($0) }
            && words.contains { $0.count >= 2 && !assetWords.contains($0) }
    }

    /// `statusIconSmall` as ["status", "icon", "small"].
    static func camelCaseWords(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        for ch in text {
            if ch.isUppercase, !word.isEmpty {
                out.append(word.lowercased())
                word = ""
            }
            word.append(ch)
        }
        if !word.isEmpty { out.append(word.lowercased()) }
        return out
    }

    /// How two pieces of an activity's text are joined. A number and the unit that belongs to it
    /// arrive as separate labels ("13:01" then "min"), and a dot between them reads as two facts
    /// rather than one: "13:01 · min". Everything else keeps the dot.
    static func joined(_ pieces: [String]) -> String {
        // A number and a bare word on their own are one phrase in any language: "8", "मिनट" reads
        // "8 मिनट", which `unit`'s English list can't know. Only on their own, and only when the
        // number stands alone: ["1", "CHE", "1"] is a score, where joining would read "1 CHE".
        if pieces.count == 2, let first = pieces.first, let second = pieces.last,
           !first.contains(" "), first.last?.isNumber == true, bareWord(second) {
            return first + " " + second
        }
        return pieces.reduce(into: "") { out, piece in
            guard !out.isEmpty else { return out = piece }
            // "4", "min", "away" is one phrase: each piece carries on from a number or from the
            // unit that followed one. Anything else is a separate fact and keeps the dot.
            let previous = out.split(separator: " ").last.map(String.init) ?? ""
            let carriesOn = unit(piece) && (previous.last?.isNumber == true || unit(previous))
            out += (carriesOn ? " " : " · ") + piece
        }
    }

    /// An asset name as plain words, for the symbol matcher only: `food_di_preparing_icon`
    /// becomes "food di preparing". The words apps use for a picture are dropped, since every
    /// asset has them and none of them says what the activity is.
    static func words(fromAssetName name: String) -> String {
        var out = ""
        for ch in name {
            if ch == "_" { out += " " } else if ch.isUppercase, !out.isEmpty { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.lowercased().split(separator: " ")
            .filter { !assetWords.contains(String($0)) }
            .joined(separator: " ")
    }

    /// A bare unit that belongs to the number before it. The list is English, which is what most
    /// pills use; a unit in another language reaches the same place through `bareWord`.
    static func unit(_ text: String) -> Bool {
        ["min", "mins", "minute", "minutes", "sec", "secs", "h", "hr", "hrs", "hour", "hours",
         "km", "mi", "m", "ft", "%", "°", "left", "away", "remaining"].contains(text.lowercased())
    }

    /// A word that can only be the unit of the number before it: letters alone, short, and not an
    /// abbreviation in capitals. "min", "Minuten" and "मिनट" are units; "CHE" and "IND" are teams,
    /// and a two-letter abbreviation ("KM") is a unit again.
    static func bareWord(_ text: String) -> Bool {
        guard (1...12).contains(text.count),
              text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return false }
        let capitals = text.contains(where: \.isUppercase) && !text.contains(where: \.isLowercase)
        return !capitals || text.count <= 2
    }

    /// Turn an item into the app name and compact text Islet shows.
    /// - Parameters:
    ///   - key: the item's identity, from `key(kind:identifier:elementHash:)`. Required, and
    ///     never the identifier: every pill carries the same one.
    ///   - knownApp: the catalogue's own spelling of an app the text names exactly. A phrase that
    ///     merely holds an app's name is not that app: "Man United 2 - 1 Arsenal" is a score, and
    ///     a containment match made the whole phrase the title and gave it a flight's look.
    public static func mirror(_ item: MenuBarItemInfo, key: String, labels: MenuBarLabels = .english,
                              knownApp: (String) -> String? = { LiveActivityCatalog.exact($0)?.app }) -> MirroredLiveActivity? {
        guard isLiveActivity(item, labels: labels) else { return nil }
        var text = content(item, labels: labels)
        // "Uber, 4 min" in a single description splits into app and detail, but only when the
        // catalogue knows what stands before the comma: "Arriving at <street>, <street>" is one
        // sentence, and splitting it made half an address the title.
        if text.count == 1, let comma = text[0].range(of: ", "),
           knownApp(String(text[0][..<comma.lowerBound])) != nil {
            text = [String(text[0][..<comma.lowerBound]), String(text[0][comma.upperBound...])]
        }
        var app: String?
        for (i, piece) in text.enumerated() {
            guard let name = knownApp(piece) else { continue }
            app = name
            text.remove(at: i)
            break
        }
        if app == nil, text.count >= 2, !looksLikeValue(text[0]) { app = text.removeFirst() }
        let detail = joined(text)
        // An asset name is never shown, but "food_di_preparing_icon" is the only thing on this
        // pill that says what it is, so it still chooses the symbol.
        let hint = item.allText.first(where: isAssetName).map(words(fromAssetName:))
        return MirroredLiveActivity(key: key, appName: app, detail: detail.isEmpty ? nil : detail,
                                    hidden: item.hidden, hint: hint)
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

    /// The key a scan follows one menu bar item by, from what the scan already knows about it.
    ///
    /// A Live Activity is keyed on its element and nothing else. Every pill on this Mac carries
    /// the identifier `live-activity-pill-com.apple.chrono.WidgetRenderer-Activities`: the suffix
    /// is the bundle id of the process that draws every pill, so it names the renderer, never the
    /// activity, and two pills on screen at once share it exactly. The element is one per pill and
    /// lives as long as the pill does, while everything readable on a pill moves while it runs: a
    /// score on every ball, the minutes every minute, and even the app's own name for its picture
    /// carries the phase (`food_di_preparing_icon`). Folding any of that in would cost the
    /// identity the key is for, so none of it is folded in.
    ///
    /// Every other item has an identifier of its own (`com.apple.menuextra.battery`), which
    /// survives the item being rebuilt, so it is preferred there.
    public static func key(kind: MenuBarItemKind, identifier: String?, elementHash: UInt) -> String {
        let element = "el:" + String(elementHash, radix: 36)
        guard kind != .liveActivity, let identifier, !identifier.isEmpty else { return element }
        return "id:" + identifier
    }

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
        // The hint joins the search for a symbol, never the words on screen.
        let searched = [m.detail, m.hint].compactMap { $0 }.joined(separator: " ")
        // Most pills expose one readable label and no app name at all, which is the common case
        // rather than an edge one. The detail is then all the pill says, so it is the title and
        // nothing goes under it: the island reads "Delivered", not "Live Activity" above it. The
        // detail still feeds the wing, the clock and the symbol, which is why it stays in `m`.
        let title = m.appName ?? m.detail ?? "Live Activity"
        let suggestion = look ?? SmartIcon.suggest(title: title, subtitle: searched.isEmpty ? nil : searched)
            .map { ($0.symbol, $0.tint) }
        let tint = suggestion.flatMap { RGBA.parse($0.1) }.map { $0.readableOnBlack().hex }
        // Updates merge, so text the item no longer shows is sent as "" to clear it: otherwise an
        // old "4 min" would stay in the wing after the item moved on to longer text.
        var spec = ActivitySpec(
            id: activityID(m.key), source: source(for: m.appName), title: title,
            subtitle: m.appName == nil ? "" : m.detail ?? "",
            icon: .symbol(suggestion?.0 ?? "dot.radiowaves.left.and.right"), trailing: shortTrailing(m.detail) ?? "",
            state: .running, tint: tint ?? suggestion?.1 ?? "white", priority: .normal, ttl: 0, sneak: isNew
        )
        // Exactly as for the name: a phrase that happens to hold an app's name mustn't be given
        // that app's layout. Sent as "" when nothing matches, so an update clears a layout the
        // activity before it had, the way the text is cleared.
        spec.template = m.appName.flatMap(LiveActivityCatalog.exact)?.template.rawValue ?? ""
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
    ///
    /// The candidate has to hold a digit. `trailing` is short text like "42%" or "3/5", and a
    /// bare word is not a value in any language: "मिनट" (minutes, with no number), "Arriving",
    /// "Boarding", "On time" and "CHE" all used to end up in the wing on their own.
    static func shortTrailing(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let parts = detail.components(separatedBy: " · ")
        if parts.filter({ $0.contains(where: \.isNumber) }).count >= 2 { return nil }
        guard let last = parts.last, last.count <= 8, last.contains(where: \.isNumber) else { return nil }
        return last
    }

    /// Seconds in a clock-style value somewhere in the text: "4:59", "1:02:03", "Boarding 0:42",
    /// "13:01 min".
    ///
    /// The last clock-shaped word, not the last word. A pill shows its countdown and the unit
    /// that belongs to it as two separate labels, which `joined` puts back together as
    /// "13:01 min", so the clock is not where the text ends; reading only the end left the island
    /// with a number that sat still between reads of the menu bar and nothing animating in the
    /// wing. Last rather than first because a pill can carry a time of day and a countdown at
    /// once ("Boards 18:30 · 12:05"), and the countdown is the one that moves. Picking up a time
    /// of day on its own costs nothing: `LiveActivityClock` settles a direction only once a
    /// reading ticks along with the clock, and a departure time never does.
    public static func clockSeconds(in text: String) -> TimeInterval? {
        for word in text.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }).reversed() {
            if let seconds = clockWord(word) { return seconds }
        }
        return nil
    }

    /// Seconds in one word, when it is a clock: two or three numbers divided by colons, with
    /// every part after the first exactly two digits and under sixty.
    private static func clockWord(_ word: Substring) -> TimeInterval? {
        let parts = word.split(separator: ":", omittingEmptySubsequences: false)
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
    /// "Uber (Live Activity)" for a mirrored app, the app's name for a bundle id, the feature's
    /// name for one of Islet's own, and for anything else (a script, a hook, CI) its id as
    /// words: "Github actions (from a script)", never the raw "github-actions".
    public static func displayName(_ source: String, appName: (String) -> String?) -> String {
        if MenuBarLiveActivities.isMirroredSource(source) {
            let prefix = MenuBarLiveActivities.source + ":"
            guard source.hasPrefix(prefix) else { return "Live Activities" }
            // The app as the catalogue spells it ("DoorDash", "Domino’s"); the source keeps
            // only a lower-case slug of it.
            if let look = LiveActivityCatalog.all.first(where: { MenuBarLiveActivities.source(for: $0.app) == source }) {
                return look.app.replacingOccurrences(of: "'", with: "\u{2019}") + " (Live Activity)"
            }
            let slug = source.dropFirst(prefix.count).split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return slug.joined(separator: " ") + " (Live Activity)"
        }
        if let own = builtIn[source] { return own }
        if source.contains("."), let name = appName(source) { return name }
        let words = source.split(whereSeparator: { $0 == "-" || $0 == "_" }).joined(separator: " ")
        guard !words.isEmpty, !source.contains(".") else { return source }
        return words.prefix(1).uppercased() + words.dropFirst() + " (from a script)"
    }

    /// Whether "Mute" in the island's menus would silence anything. Appearance's previews show
    /// because they were asked for, so muting them would do nothing.
    public static func canMute(_ source: String) -> Bool { source != "preview" }

    /// The Settings page of the feature that sends `source`, where it is listed as muted with its
    /// Unmute. Nil for apps, scripts and Islet's sources without a page of their own: those are
    /// listed under Apps only.
    public static func page(for source: String) -> SettingsPage? {
        if MenuBarLiveActivities.isMirroredSource(source) { return .liveActivities }
        switch source {
        case TimerEngine.source, Stopwatch.source: return .timers
        case MeetingReminders.source, "reminders": return .calendar
        case "battery", "audio", "system": return .notifications
        case "downloads": return .downloads
        case "claude-code", "codex", "cursor", "agent-usage", "mcp": return .agents
        case "shelf": return .shelf
        case "shortcuts": return .tools
        default: return nil
        }
    }

    /// The muted sources a feature's page lists (`page(for:)`).
    public static func listed(on page: SettingsPage, _ muted: [String]) -> [String] {
        muted.filter { Self.page(for: $0) == page }
    }

    /// The muted sources Settings → Apps lists under Muted: every one except an app that has a
    /// row there, whose "Mute notifications and calls" shows it instead.
    public static func listedUnderApps(_ muted: [String], appRules: [AppRule]) -> [String] {
        let rows = Set(appRules.map(\.bundleID))
        return muted.filter { !rows.contains($0) }
    }

    /// What still shows from a muted source, said beside it in Settings.
    public static func stillShows(_ source: String) -> String? {
        source == "battery" ? "A battery about to run out still warns you." : nil
    }

    /// Islet's own sources, by the feature that sends them.
    static let builtIn: [String: String] = [
        TimerEngine.source: "Timers", Stopwatch.source: "Stopwatch", KeepAwake.source: "Keep awake",
        MeetingReminders.source: "Meeting reminders", "reminders": "Reminders", "downloads": "Downloads",
        "focus": "Focus", "system": "Islet", "agent-usage": "Usage limits", "claude-code": "Claude Code",
        "codex": "Codex", "cursor": "Cursor", "battery": "Battery", "audio": "Sound output", "shelf": "Shelf",
        "shortcuts": "Shortcuts", "preview": "Preview",
        // What arrives without a name of its own: a notification from an app with no bundle
        // id, the MCP server coding agents use, `isletctl run` and every other isletctl command.
        "notifications": "Notifications", "mcp": "Coding agents", "run": "Commands from Terminal",
        "cli": "Scripts and Terminal",
    ]
}
