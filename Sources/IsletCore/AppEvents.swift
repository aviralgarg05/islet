import Foundation

// iPhone-style events derived from what running apps are doing: calls, mirrored
// notifications, downloads and Focus changes. Pure logic; the system layer feeds it.

// MARK: - Calls

/// Turns "which apps are using the microphone" into call activities with a live timer.
public struct CallDetector: Sendable {
    public struct App: Equatable, Sendable {
        public var name: String
        public var isBrowser: Bool
    }

    /// Apps whose microphone use almost always means a call.
    public static let callApps: [String: String] = [
        "com.apple.FaceTime": "FaceTime",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "desktop.WhatsApp": "WhatsApp",
        "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark": "Webex",
        "com.skype.skype": "Skype",
        "ru.keepcoder.Telegram": "Telegram",
        "org.whispersystems.signal-desktop": "Signal",
        "com.apple.mobilephone": "Phone",
        "com.gotomeeting.GoToMeeting": "GoTo Meeting",
        "com.around.Around": "Around",
    ]

    /// Browsers (and their helper processes) that may be hosting a web call (Meet, Zoom web…).
    public static let browsers: [String: String] = [
        "com.google.Chrome": "Chrome", "com.apple.Safari": "Safari", "com.apple.WebKit.GPU": "Safari",
        "company.thebrowser.Browser": "Arc", "org.mozilla.firefox": "Firefox", "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave", "com.vivaldi.Vivaldi": "Vivaldi", "com.operasoftware.Opera": "Opera",
        "app.zen-browser.zen": "Zen", "com.openai.atlas": "Atlas", "ai.perplexity.comet": "Comet",
    ]

    /// Map a (possibly helper) bundle id to a known call app or browser.
    public static func classify(_ bundleID: String) -> (bundleID: String, app: App)? {
        if let name = callApps[bundleID] { return (bundleID, App(name: name, isBrowser: false)) }
        // "com.google.Chrome.helper", "com.brave.Browser.helper.renderer" → parent app.
        for (id, name) in browsers where bundleID == id || bundleID.hasPrefix(id + ".") {
            return (id, App(name: name, isBrowser: true))
        }
        for (id, name) in callApps where bundleID.hasPrefix(id + ".") {
            return (id, App(name: name, isBrowser: false))
        }
        return nil
    }

    public private(set) var active: [String: Date] = [:]

    public init() {}

    public enum Change: Equatable, Sendable {
        case started(ActivitySpec)
        case updated(ActivitySpec)
        case ended(id: String)
    }

    public static func activityID(_ bundleID: String) -> String {
        "call-" + bundleID.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    /// Feed the current set of bundle ids using the microphone and whether a camera is on.
    public mutating func update(micUsers: Set<String>, cameraOn: Bool, now: Date) -> [Change] {
        var current: [String: App] = [:]
        for b in micUsers { if let c = Self.classify(b) { current[c.bundleID] = c.app } }
        var changes: [Change] = []
        for (bundle, app) in current.sorted(by: { $0.key < $1.key }) {
            let isNew = active[bundle] == nil
            if isNew { active[bundle] = now }
            let spec = ActivitySpec(
                id: Self.activityID(bundle), source: bundle,
                title: app.isBrowser ? "Call in \(app.name)" : app.name,
                subtitle: cameraOn ? "Video call" : "Call",
                icon: .symbol(cameraOn ? "video.fill" : "phone.fill"),
                state: .running, tint: "green", priority: .high, ttl: 0,
                startedAt: active[bundle], sneak: isNew
            )
            changes.append(isNew ? .started(spec) : .updated(spec))
        }
        for bundle in active.keys.sorted() where current[bundle] == nil {
            active[bundle] = nil
            changes.append(.ended(id: Self.activityID(bundle)))
        }
        return changes
    }
}

// MARK: - Mirrored notifications

public struct MirroredNotification: Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var title: String
    public var subtitle: String?
    public var body: String?

    public init(appName: String?, bundleID: String? = nil, title: String, subtitle: String? = nil, body: String? = nil) {
        self.appName = appName; self.bundleID = bundleID; self.title = title; self.subtitle = subtitle; self.body = body
    }

    /// Stable identity for de-duplicating the same banner seen twice.
    public var fingerprint: String {
        [appName ?? "", title, subtitle ?? "", body ?? ""].joined(separator: "\u{1F}")
    }

    /// Live activity shown for this notification.
    public func activity(rule: AppRule?) -> ActivitySpec {
        var h: UInt64 = 1469598103934665603
        for b in fingerprint.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let detail = [subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return ActivitySpec(
            id: "notif-\(String(h, radix: 36))", source: bundleID ?? "notifications",
            title: appName.map { "\($0): \(title)" } ?? title,
            subtitle: detail.isEmpty ? nil : String(detail.prefix(140)),
            icon: rule?.icon ?? bundleID.map { .app(bundleID: $0) } ?? .symbol("bell.badge.fill"),
            state: .info, tint: rule?.tint, priority: rule?.priority ?? .normal, ttl: 7, sneak: true
        )
    }
}

public enum NotificationParser {
    /// Accessibility labels that are controls, not content.
    static let noise: Set<String> = ["close", "clear", "options", "show", "reply", "mark as read", "open", "more", "dismiss", "snooze"]

    /// Build a notification from the texts found in a Notification Center banner.
    /// - Parameters:
    ///   - texts: `AXStaticText` values in reading order.
    ///   - description: the banner group's `AXDescription`, often "App, Title, Body".
    ///   - knownApps: display name → bundle id for running/installed apps, to recognise the sender.
    public static func parse(texts: [String], description: String?, knownApps: [String: String]) -> MirroredNotification? {
        var parts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !noise.contains($0.lowercased()) }
        // Drop relative timestamps ("now", "2m ago", "11:42").
        parts.removeAll { isTimestamp($0) }
        var appName: String?
        var bundleID: String?

        func matchApp(_ s: String) -> (String, String)? {
            if let b = knownApps[s] { return (s, b) }
            return knownApps.first { $0.key.caseInsensitiveCompare(s) == .orderedSame }.map { ($0.key, $0.value) }
        }

        if let first = parts.first, let m = matchApp(first) {
            appName = m.0
            bundleID = m.1
            parts.removeFirst()
        } else if let desc = description {
            // "Messages, Alice, See you soon" → app name is the first comma-separated field.
            let head = desc.components(separatedBy: ", ").first ?? ""
            if let m = matchApp(head) {
                appName = m.0
                bundleID = m.1
            }
            if parts.isEmpty {
                let fields: [String] = desc.components(separatedBy: ", ")
                parts = Array(fields.dropFirst(appName == nil ? 0 : 1))
            }
        }
        guard let title = parts.first, !title.isEmpty else { return nil }
        let rest = Array(parts.dropFirst())
        let subtitle: String? = rest.count >= 2 ? rest[0] : nil
        let body: String? = rest.count >= 2 ? rest.dropFirst().joined(separator: " ") : rest.first
        return MirroredNotification(appName: appName, bundleID: bundleID, title: title, subtitle: subtitle, body: body)
    }

    static func isTimestamp(_ s: String) -> Bool {
        let l = s.lowercased()
        if l == "now" || l == "yesterday" { return true }
        if l.hasSuffix(" ago") || l.hasSuffix("m ago") { return true }
        if l.range(of: #"^\d{1,2}:\d{2}( ?[ap]m)?$"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"^\d+ ?(m|min|h|hr|d)$"#, options: .regularExpression) != nil { return true }
        return false
    }
}

// MARK: - Downloads

/// One partially downloaded file seen in the downloads folder.
public struct PartialDownload: Equatable, Sendable {
    /// File name on disk, e.g. `ubuntu.iso.crdownload` or `ubuntu.iso.download`.
    public var fileName: String
    public var bytes: Int64
    /// Total size when the browser records it (Safari does).
    public var totalBytes: Int64?

    public init(fileName: String, bytes: Int64, totalBytes: Int64? = nil) {
        self.fileName = fileName; self.bytes = bytes; self.totalBytes = totalBytes
    }

    public static let suffixes = [".crdownload", ".download", ".part", ".opdownload", ".partial"]

    public static func isPartial(_ name: String) -> Bool { suffixes.contains { name.hasSuffix($0) } }

    /// Name of the finished file.
    public var finalName: String {
        for s in Self.suffixes where fileName.hasSuffix(s) { return String(fileName.dropLast(s.count)) }
        return fileName
    }
}

/// Tracks partial files across scans and reports progress and completion.
public struct DownloadTracker: Sendable {
    public private(set) var inFlight: [String: (started: Date, last: PartialDownload, grewAt: Date)] = [:]
    private var reportedStalled: Set<String> = []

    /// A partial that hasn't grown for this long is shown as paused and checked less often.
    public static let stallAfter: TimeInterval = 15

    public init() {}

    public enum Event: Equatable, Sendable {
        case progress(ActivitySpec)
        case finished(ActivitySpec, finalName: String)
        case vanished(id: String)
    }

    /// How often the watcher should look again: every second while something grows, every
    /// 30 s while downloads are paused, and not at all (folder events only) after 10 minutes.
    public func recheckInterval(now: Date) -> TimeInterval? {
        guard let newest = inFlight.values.map(\.grewAt).max() else { return nil }
        let quiet = now.timeIntervalSince(newest)
        if quiet < Self.stallAfter { return 1 }
        if quiet < 600 { return 30 }
        return nil
    }

    public static func activityID(_ finalName: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in finalName.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "download-\(String(h, radix: 36))"
    }

    /// - Parameters:
    ///   - partials: partial files currently present.
    ///   - existing: names of all files currently in the folder (to confirm completion).
    public mutating func scan(partials: [PartialDownload], existing: Set<String>, now: Date) -> [Event] {
        var events: [Event] = []
        let byName = Dictionary(partials.map { ($0.fileName, $0) }, uniquingKeysWith: { a, _ in a })
        for p in partials.sorted(by: { $0.fileName < $1.fileName }) {
            let previous = inFlight[p.fileName]
            let isNew = previous == nil
            let grew = isNew || previous?.last.bytes != p.bytes || previous?.last.totalBytes != p.totalBytes
            let grewAt = grew ? now : previous!.grewAt
            inFlight[p.fileName] = (previous?.started ?? now, p, grewAt)
            let stalled = now.timeIntervalSince(grewAt) >= Self.stallAfter
            // Report only changes: an unchanged file would otherwise redraw the island every second.
            if grew {
                reportedStalled.remove(p.fileName)
            } else if !stalled || reportedStalled.contains(p.fileName) {
                continue
            } else {
                reportedStalled.insert(p.fileName)
            }
            var progress: Double = -1
            var trailing = Format.bytes(p.bytes)
            if let total = p.totalBytes, total > 0 {
                progress = min(1, Double(p.bytes) / Double(total))
                trailing = "\(Int((progress * 100).rounded()))%"
            }
            var spec = ActivitySpec(
                id: Self.activityID(p.finalName), source: "downloads", title: p.finalName,
                subtitle: p.totalBytes.map { "\(Format.bytes(p.bytes)) of \(Format.bytes($0))" } ?? "Downloading…",
                icon: .symbol("arrow.down.circle.fill"), trailing: trailing, progress: progress,
                state: .running, tint: "blue", priority: .normal, ttl: 0, sneak: isNew
            )
            if stalled {
                spec.subtitle = "Paused · " + Format.bytes(p.bytes)
                spec.staleAt = now
            }
            events.append(.progress(spec))
        }
        for (name, entry) in inFlight.sorted(by: { $0.key < $1.key }) where byName[name] == nil {
            inFlight[name] = nil
            reportedStalled.remove(name)
            let final = entry.last.finalName
            let id = Self.activityID(final)
            if existing.contains(final) {
                events.append(.finished(ActivitySpec(
                    id: id, source: "downloads", title: final, subtitle: "Downloaded",
                    icon: .symbol("checkmark.circle.fill"), trailing: "Done", progress: 1, state: .success,
                    tint: "green", priority: .normal, ttl: 8, sneak: true
                ), finalName: final))
            } else {
                events.append(.vanished(id: id)) // cancelled
            }
        }
        return events
    }
}

// MARK: - Focus

public enum FocusPill {
    /// iPhone-style Focus pill ("Work · On").
    public static func activity(name: String, on: Bool) -> ActivitySpec {
        let lower = name.lowercased()
        let symbol: String
        switch lower {
        case let s where s.contains("sleep"): symbol = "bed.double.fill"
        case let s where s.contains("work"): symbol = "briefcase.fill"
        case let s where s.contains("personal"): symbol = "person.fill"
        case let s where s.contains("driv"): symbol = "car.fill"
        case let s where s.contains("fitness") || s.contains("workout"): symbol = "figure.run"
        case let s where s.contains("read"): symbol = "book.fill"
        case let s where s.contains("game"): symbol = "gamecontroller.fill"
        case let s where s.contains("mindful"): symbol = "brain.head.profile"
        default: symbol = "moon.fill"
        }
        return ActivitySpec(
            id: "focus", source: "focus", title: name.isEmpty ? "Focus" : name,
            icon: .symbol(on ? symbol : "moon"), trailing: on ? "On" : "Off",
            state: .info, tint: on ? "indigo" : "gray", priority: .normal, ttl: 3, sneak: true
        )
    }
}

// MARK: - AI output

public enum AISanitizer {
    /// Extract a plausible SF Symbol name from a model reply ("sf: car.fill", "`car.fill`", "car.fill.").
    public static func symbolName(from reply: String) -> String? {
        var s = reply.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["sf symbol:", "symbol:", "sf:", "icon:"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'. \n"))
        if let first = s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," }).first { s = String(first) }
        guard !s.isEmpty, s.count <= 60,
              s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." }),
              s.first?.isLetter == true else { return nil }
        return s
    }

    /// Keep a one-line summary short and plain.
    public static func summary(from reply: String, maxLength: Int = 90) -> String? {
        let line = reply.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !line.isEmpty else { return nil }
        return line.count > maxLength ? String(line.prefix(maxLength - 1)) + "…" : line
    }
}
