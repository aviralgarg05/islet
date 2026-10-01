import Foundation

/// What macOS lets Islet do with calendars or with reminders (EventKit's authorisation status).
public enum CalendarAccess: String, Codable, Sendable, CaseIterable {
    /// macOS hasn't asked yet.
    case notDetermined
    case fullAccess
    /// "Add events only": Islet may add events but not see them. Only calendars have it.
    case writeOnly
    /// Refused, in macOS's prompt or later in System Settings.
    case denied
    /// Not the user's to change here (Screen Time or a configuration profile).
    case restricted

    /// Whether Islet can read what is there.
    public var canRead: Bool { self == .fullAccess }
}

/// Calendars and reminders for `GET /v1/state`: the access to each and how many timed events are
/// left today. Never a title.
public struct CalendarStatus: Codable, Equatable, Sendable {
    public var events: CalendarAccess
    public var reminders: CalendarAccess
    public var upcoming: Int

    public init(events: CalendarAccess, reminders: CalendarAccess, upcoming: Int) {
        self.events = events
        self.reminders = reminders
        self.upcoming = upcoming
    }
}

/// What Settings, the Today page and Settings → Permissions say about calendar or reminders
/// access, in plain words, and the one button that helps.
///
/// macOS asks only once. After a refusal, or with "Add events only", asking again returns at
/// once without a prompt, so the button opens the right page of System Settings instead.
public struct CalendarAccessAdvice: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Ask macOS, which shows its own prompt.
        case ask
        /// Open Privacy & Security in System Settings at this page.
        case openSettings(URL)
    }

    /// A few words: "Allowed", "Not allowed yet", "Turned off in System Settings", "Islet can only add events".
    public var status: String
    /// One line on what to switch, when there is something to do.
    public var detail: String?
    public var action: Action?
    /// The button's title, with `action`.
    public var button: String?

    public var isAllowed: Bool { action == nil }

    /// - Parameters:
    ///   - kind: `.calendars` or `.reminders`.
    ///   - refused: "Allow…" was pressed this session and macOS answered no. It may not have
    ///     shown its prompt at all (it remembers an earlier refusal), so asking again won't help.
    public static func advice(_ access: CalendarAccess, kind: PermissionKind, refused: Bool = false) -> CalendarAccessAdvice {
        let pane = kind == .reminders ? "Reminders" : "Calendars"
        let settings = Action.openSettings(kind.settingsURL)
        let open = "Open System Settings"
        let switchOn = "In Privacy & Security → \(pane), switch on Islet."
        switch access {
        case .fullAccess:
            return CalendarAccessAdvice(status: "Allowed")
        case .notDetermined where refused:
            return CalendarAccessAdvice(status: "macOS didn't ask", detail: switchOn, action: settings, button: open)
        case .notDetermined:
            return CalendarAccessAdvice(status: "Not allowed yet", detail: "macOS asks once, when you press Allow.", action: .ask, button: "Allow…")
        case .denied:
            return CalendarAccessAdvice(status: "Turned off in System Settings", detail: switchOn, action: settings, button: open)
        case .restricted:
            return CalendarAccessAdvice(status: "Turned off in System Settings",
                                        detail: "Screen Time or a profile on this Mac manages it.", action: settings, button: open)
        case .writeOnly:
            let noun = kind == .reminders ? "reminders" : "events"
            return CalendarAccessAdvice(status: "Islet can only add \(noun)",
                                        detail: "In Privacy & Security → \(pane), choose Full Access for Islet.", action: settings, button: open)
        }
    }
}

extension PermissionStatus {
    /// Calendar or reminders access as Settings → Permissions shows it. A refusal this session
    /// counts as refused even while macOS still says "not asked", so the row offers System Settings.
    public static func calendar(_ access: CalendarAccess, refused: Bool = false) -> PermissionStatus {
        switch access {
        case .fullAccess: return .granted
        case .notDetermined: return refused ? .denied : .notDetermined
        case .denied: return .denied
        case .writeOnly: return .writeOnly
        case .restricted: return .restricted
        }
    }
}
