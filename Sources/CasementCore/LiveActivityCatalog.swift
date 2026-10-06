import Foundation

/// Icon, colour and layout for apps known to publish Live Activities, so a mirrored activity
/// looks like its app rather than a generic pill. The table itself (`apps`) is generated from
/// docs/research/07-live-activity-apps.json by scripts/gen-live-activity-apps.py.
public enum LiveActivityCatalog {
    public struct Look: Equatable, Sendable {
        public var app: String
        /// The iOS bundle ID from the App Store (nil for Casement's own additions).
        public var bundleID: String?
        /// Other names the app goes by (App Store title, older names).
        public var aliases: [String]
        /// One of: system, rideshare, ev-parking, delivery, travel, transit, sports, fitness,
        /// health, productivity, cooking, weather, finance, ai, developer, home, media.
        public var category: String
        public var symbol: String
        /// Brand colour as published. Some are too dark for the island; see `displayTint`.
        public var tint: String
        public var template: ActivityTemplate

        /// The tint lifted until it reads on the black island (3:1 contrast).
        public var displayTint: String { RGBA.parse(tint).map { $0.readableOnBlack().hex } ?? tint }
    }

    /// Every entry, in catalogue order.
    public static var all: [Look] { apps }

    private static let byBundleID: [String: Look] = index(apps.compactMap { e in e.bundleID.map { ($0, e) } })
    private static let byName: [String: Look] = index(apps.map { ($0.app, $0) })
    private static let byAlias: [String: Look] = index(apps.flatMap { e in e.aliases.map { ($0, e) } })

    /// Lowercased keys; the first entry wins when two share a key.
    private static func index(_ pairs: [(String, Look)]) -> [String: Look] {
        var out: [String: Look] = [:]
        for (key, look) in pairs where out[key.lowercased()] == nil { out[key.lowercased()] = look }
        return out
    }

    /// Exact match on bundle ID, app name or alias, ignoring case and surrounding spaces.
    public static func exact(_ nameOrBundleID: String) -> Look? {
        let key = nameOrBundleID.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return byBundleID[key] ?? byName[key] ?? byAlias[key]
    }

    /// Look for an app name as shown in the menu bar ("Uber", "Uber Eats", "Flighty") or a bundle ID.
    /// Falls back to the longest app name or alias found as whole words in the text, so
    /// "Uber Eats · 12 min" finds Uber Eats rather than Uber.
    public static func look(for appName: String) -> Look? {
        if let hit = exact(appName) { return hit }
        let words = Self.words(appName)
        guard !words.isEmpty else { return nil }
        var best: (length: Int, look: Look)?
        for p in phrases where p.length > (best?.length ?? 0) && contains(words, p.words) {
            best = (p.length, p.look)
        }
        return best?.look
    }

    /// App names, then aliases, as word lists for the fuzzy match (names win ties).
    private static let phrases: [(words: [String], length: Int, look: Look)] =
        (apps.map { ($0.app, $0) } + apps.flatMap { e in e.aliases.map { ($0, e) } }).compactMap { key, look in
            let w = words(key)
            return w.isEmpty ? nil : (w, w.joined(separator: " ").count, look)
        }

    /// The entry for an activity's `source`: exact matches only, so a source that merely contains
    /// an app's name ("claude-code", "github-actions") never picks up that app. A generic source
    /// can still equal a name ("focus" is the Focus app), which is why `resolvedTemplate` uses the
    /// entry's template only when the activity has the data for it.
    public static func entry(forSource source: String) -> Look? { exact(source) }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'+!")).inverted)
            .filter { !$0.isEmpty }
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }
}
