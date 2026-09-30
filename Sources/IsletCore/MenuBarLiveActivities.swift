import CoreGraphics
import Foundation

/// A menu bar item as seen through Accessibility (only what's needed to recognise and show it).
public struct MenuBarItemInfo: Codable, Equatable, Sendable {
    public var identifier: String?
    public var subrole: String?
    public var title: String?
    public var description: String?
    public var value: String?
    public var help: String?
    /// Text found in the item's descendants, in reading order.
    public var texts: [String]
    /// Global x of the item, used to tell items apart and to keep their order.
    public var x: CGFloat

    public init(identifier: String? = nil, subrole: String? = nil, title: String? = nil, description: String? = nil,
                value: String? = nil, help: String? = nil, texts: [String] = [], x: CGFloat = 0) {
        self.identifier = identifier; self.subrole = subrole; self.title = title; self.description = description
        self.value = value; self.help = help; self.texts = texts; self.x = x
    }

    /// Every non-empty piece of text the item exposes, de-duplicated, in a stable order.
    public var allText: [String] {
        var seen = Set<String>()
        return ([description, title, value, help].compactMap { $0 } + texts)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// A Live Activity from the iPhone (or a Mac app) that macOS shows in the menu bar.
public struct MirroredLiveActivity: Equatable, Sendable {
    /// Stable key for this activity while it lives (identifier, or app name).
    public var key: String
    public var appName: String
    /// The compact content, as text: e.g. "12 min" or "2 – 1".
    public var detail: String?

    public init(key: String, appName: String, detail: String?) {
        self.key = key
        self.appName = appName
        self.detail = detail
    }
}

public enum MenuBarLiveActivities {
    /// Built-in menu extras that are not Live Activities. macOS 26/27 hosts these in MenuBarAgent.
    public static let systemExtras: Set<String> = [
        "battery", "wifi", "bluetooth", "screen-mirroring", "controlcenter", "clock", "focusmode", "sound",
        "display", "nowplaying", "airdrop", "keyboardbrightness", "accessibility", "hearing", "user",
        "timemachine", "vpn", "textinput", "siri", "spotlight", "stagemanager", "weather", "scriptmenu",
        "airplay", "airport", "volume", "displays", "tethering", "cellular", "ink", "eject", "ppp", "remotedesktop",
        "universalcontrol", "voicecontrol", "presenteroverlay", "mirroring", "shortcuts-status", "fastuserswitching",
    ]

    /// Identifier fragments that mark a Live Activity when present.
    static let activityHints = ["liveactivit", "live-activit", "activitykit", "chrono", ".activity."]

    /// Controls that live in the menu bar but aren't content ("Show Hidden Menu Bar Items").
    static let controlLabels: Set<String> = ["show hidden menu bar items", "hidden menu bar items"]

    public static func isSystemExtra(_ identifier: String?) -> Bool {
        guard let id = identifier?.lowercased(), id.hasPrefix("com.apple.menuextra.") else { return false }
        let name = String(id.dropFirst("com.apple.menuextra.".count))
        return systemExtras.contains(name) || systemExtras.contains(where: { name.hasPrefix($0 + ".") })
    }

    /// Whether a MenuBarAgent item is a Live Activity rather than a system extra or a control.
    public static func isLiveActivity(_ item: MenuBarItemInfo) -> Bool {
        let id = item.identifier?.lowercased() ?? ""
        if activityHints.contains(where: id.contains) { return true }
        if isSystemExtra(item.identifier) { return false }
        let text = item.allText
        if text.isEmpty { return false }
        if text.count == 1, controlLabels.contains(text[0].lowercased()) { return false }
        // Anything else MenuBarAgent hosts that has content: iPhone and system Live Activities.
        return true
    }

    /// Turn an item into the app name and compact text Islet shows.
    public static func mirror(_ item: MenuBarItemInfo) -> MirroredLiveActivity? {
        guard isLiveActivity(item) else { return nil }
        var text = item.allText
        guard !text.isEmpty else { return nil }
        // "Uber, 4 min" in a single description splits into app and detail.
        if text.count == 1, let comma = text[0].range(of: ", ") {
            text = [String(text[0][..<comma.lowerBound]), String(text[0][comma.upperBound...])]
        }
        let app = text[0]
        let detail = text.dropFirst().joined(separator: " · ")
        let key = item.identifier ?? "app:" + app.lowercased()
        return MirroredLiveActivity(key: key, appName: app, detail: detail.isEmpty ? nil : detail)
    }

    public static func activityID(_ key: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "iphone-\(String(h, radix: 36))"
    }

    /// The live activity Islet shows for a mirrored item.
    /// - Parameter look: icon and tint for the app, from the Live Activity catalogue when known.
    public static func activity(for m: MirroredLiveActivity, look: (symbol: String, tint: String)?, isNew: Bool) -> ActivitySpec {
        let suggestion = look ?? SmartIcon.suggest(title: m.appName, subtitle: m.detail).map { ($0.symbol, $0.tint) }
        return ActivitySpec(
            id: activityID(m.key), source: "iphone", title: m.appName, subtitle: m.detail,
            icon: .symbol(suggestion?.0 ?? "iphone.gen3"), trailing: shortTrailing(m.detail),
            state: .running, tint: suggestion?.1 ?? "white", priority: .normal, ttl: 0, sneak: isNew
        )
    }

    /// The part of the detail that fits the compact wing: a trailing number, time or score.
    static func shortTrailing(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let last = detail.components(separatedBy: " · ").last ?? detail
        return last.count <= 8 ? last : nil
    }
}
