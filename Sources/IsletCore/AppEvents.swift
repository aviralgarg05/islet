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

    /// Map a (possibly helper) bundle id to a known call app or browser.
    public static func classify(_ bundleID: String) -> (bundleID: String, app: App)? {
        if let name = callApps[bundleID] { return (bundleID, App(name: name, isBrowser: false)) }
        // A browser (`Browsers`) may be hosting a web call (Meet, Zoom on the web). Its helper
        // processes count as it ("com.google.Chrome.helper" is Chrome), and Safari's GPU process
        // holds the microphone for Safari.
        if bundleID == "com.apple.WebKit.GPU" || bundleID.hasPrefix("com.apple.WebKit.GPU.") {
            return ("com.apple.WebKit.GPU", App(name: "Safari", isBrowser: true))
        }
        if let b = Browsers.browser(for: bundleID) { return (b.bundleID, App(name: b.name, isBrowser: true)) }
        for (id, name) in callApps where bundleID.hasPrefix(id + ".") {
            return (id, App(name: name, isBrowser: false))
        }
        return nil
    }

    /// Apps that also send voice messages, dictate or sit in a huddle: their microphone use is
    /// often not a call, so it shows quietly first (`quietFor`).
    public static let messagingApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
        "ru.keepcoder.Telegram", "org.whispersystems.signal-desktop",
    ]

    /// Seconds an app must hold the microphone before anything shows: a voice note, a dictation
    /// or a site checking the microphone doesn't raise a call.
    public static let settle: TimeInterval = 3
    /// A browser or a messaging app holding the microphone shows a quiet "Microphone in use"
    /// until the camera comes on or this many seconds pass; then it is a call.
    public static let quietFor: TimeInterval = 60

    /// What an app's pill shows.
    enum Shown: Int, Sendable, Comparable {
        case microphone, call
        static func < (a: Shown, b: Shown) -> Bool { a.rawValue < b.rawValue }
    }

    /// Apps using the microphone, and since when, whether or not anything shows yet. A call
    /// that is joined counts from here (`ongoing`).
    public private(set) var active: [String: Date] = [:]
    private var shown: [String: Shown] = [:]
    /// Apps whose pill was dismissed: nothing more until they let go of the microphone.
    public private(set) var dismissed: Set<String> = []
    /// Apps muted on the Apps page, from the last update.
    private var muted: Set<String> = []

    public init() {}

    public enum Change: Equatable, Sendable {
        case started(ActivitySpec)
        case updated(ActivitySpec)
        case ended(id: String)
    }

    public static func activityID(_ bundleID: String) -> String {
        "call-" + bundleID.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    /// Whether an app's microphone use starts quietly (`quietFor`).
    static func startsQuietly(_ bundleID: String, _ app: App) -> Bool {
        app.isBrowser || messagingApps.contains(bundleID)
    }

    /// Feed the current set of bundle ids using the microphone and whether a camera is on.
    /// - Parameter muted: apps muted on the Apps page; they show nothing.
    public mutating func update(micUsers: Set<String>, cameraOn: Bool, now: Date, muted: Set<String> = []) -> [Change] {
        self.muted = muted
        var current: [String: App] = [:]
        for b in micUsers { if let c = Self.classify(b) { current[c.bundleID] = c.app } }
        var changes: [Change] = []
        for (bundle, app) in current.sorted(by: { $0.key < $1.key }) {
            if active[bundle] == nil { active[bundle] = now }
            let since = active[bundle] ?? now
            if dismissed.contains(bundle) || muted.contains(bundle) {
                if shown.removeValue(forKey: bundle) != nil { changes.append(.ended(id: Self.activityID(bundle))) }
                continue
            }
            let held = now.timeIntervalSince(since)
            guard held >= Self.settle else { continue }
            let quiet = Self.startsQuietly(bundle, app) && !cameraOn && held < Self.quietFor
            let before = shown[bundle]
            // Once a call, it stays one when the camera goes off.
            let next = max(before ?? .microphone, quiet ? .microphone : .call)
            shown[bundle] = next
            let spec = Self.spec(bundle: bundle, app: app, shown: next, cameraOn: cameraOn, since: since,
                                 sneak: next == .call && before != .call)
            changes.append(before == nil ? .started(spec) : .updated(spec))
        }
        for bundle in active.keys.sorted() where current[bundle] == nil {
            active[bundle] = nil
            dismissed.remove(bundle)
            if shown.removeValue(forKey: bundle) != nil { changes.append(.ended(id: Self.activityID(bundle))) }
        }
        return changes
    }

    /// The pill was dismissed (or removed by a script): it stays away until the app lets go of
    /// the microphone. Returns whether `activityID` was one of the pills on show.
    @discardableResult
    public mutating func dismiss(activityID: String) -> Bool {
        guard let bundle = shown.keys.first(where: { Self.activityID($0) == activityID }) else { return false }
        shown[bundle] = nil
        dismissed.insert(bundle)
        return true
    }

    /// When an app that holds the microphone shows something, or a quiet pill becomes a call,
    /// without anything else changing: the next `update` is due then.
    public func nextDeadline(now: Date) -> Date? {
        active.compactMap { bundle, since -> Date? in
            guard !dismissed.contains(bundle), !muted.contains(bundle) else { return nil }
            switch shown[bundle] {
            case nil: return max(now, since.addingTimeInterval(Self.settle))
            case .microphone?: return max(now, since.addingTimeInterval(Self.quietFor))
            case .call?: return nil
            }
        }.min()
    }

    static func spec(bundle: String, app: App, shown: Shown, cameraOn: Bool, since: Date, sneak: Bool) -> ActivitySpec {
        switch shown {
        case .microphone:
            return ActivitySpec(
                id: activityID(bundle), source: bundle, title: app.name, subtitle: "Microphone in use",
                icon: .symbol("mic.fill"), state: .running, tint: "orange", priority: .low, ttl: 0,
                startedAt: since, sneak: false
            )
        case .call:
            var spec = ActivitySpec(
                id: activityID(bundle), source: bundle,
                title: app.isBrowser ? "Call in \(app.name)" : app.name,
                subtitle: cameraOn ? "Video call" : "Call",
                icon: .symbol(cameraOn ? "video.fill" : "phone.fill"),
                state: .running, tint: "green", priority: .high, ttl: 0,
                startedAt: since, sneak: sneak
            )
            spec.template = ActivityTemplate.liveAudio.rawValue
            return spec
        }
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

    /// Live activity shown for this notification. macOS shows its own banner at the same
    /// moment, so it peeks below the notch only with `peek` ("Peek at new notifications");
    /// otherwise it sits beside the notch for the time it is shown.
    public func activity(rule: AppRule?, peek: Bool = false) -> ActivitySpec {
        var h: UInt64 = 1469598103934665603
        for b in fingerprint.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let detail = [subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return ActivitySpec(
            id: "notif-\(String(h, radix: 36))", source: bundleID ?? "notifications",
            title: appName.map { "\($0): \(title)" } ?? title,
            subtitle: detail.isEmpty ? nil : String(detail.prefix(140)),
            icon: rule?.icon ?? bundleID.map { .app(bundleID: $0) } ?? .symbol("bell.badge.fill"),
            state: .info, tint: rule?.tint, priority: rule?.priority ?? .normal, ttl: 7, sneak: peek
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

// MARK: - Welcome back

/// The "Welcome back" summary on unlock: what arrived while the screen was locked, by source.
public enum WelcomeBack {
    /// Locked for less than this, nothing is said.
    public static let minimumAway: TimeInterval = 60

    /// The activity to show, or nil: nothing arrived (an empty "Nothing new" would only be
    /// noise), or the screen was locked for under a minute.
    public static func activity(counts: [String: Int], lockedFor: TimeInterval, name: (String) -> String) -> ActivitySpec? {
        let arrived = counts.filter { $0.value > 0 }
        guard lockedFor > minimumAway, !arrived.isEmpty else { return nil }
        // Most first; ties in name order, so the line reads the same each time.
        let summary = arrived.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3)
            .map { "\($0.value) from \(name($0.key))" }.joined(separator: " · ")
        return ActivitySpec(
            id: "welcome-back", source: "system", title: "Welcome back", subtitle: summary,
            icon: .symbol("lock.open.fill"), state: .info, tint: "white", priority: .normal, ttl: 4, sneak: true
        )
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
