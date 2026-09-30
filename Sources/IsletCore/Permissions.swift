import Foundation

/// A macOS privacy permission that some Islet feature can use. None is needed to run.
public enum PermissionKind: String, CaseIterable, Sendable, Identifiable {
    case accessibility, calendars, reminders, downloadsFolder, automationMusic, automationSpotify

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .downloadsFolder: return "Downloads folder"
        case .automationMusic: return "Automation: Music"
        case .automationSpotify: return "Automation: Spotify"
        }
    }

    /// The app Islet sends Apple Events to, for the Automation permissions.
    public var automationTarget: String? {
        switch self {
        case .automationMusic: return "com.apple.Music"
        case .automationSpotify: return "com.spotify.client"
        default: return nil
        }
    }

    /// The Privacy & Security pane in System Settings that lists this permission.
    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .calendars: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .downloadsFolder: anchor = "Privacy_FilesAndFolders"
        case .automationMusic, .automationSpotify: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// The features that use this permission, and whether each is switched on.
    public func uses(_ s: IsletSettings) -> [PermissionUse] {
        switch self {
        case .accessibility:
            return [
                PermissionUse("Replace the system volume and brightness HUD", on: s.replaceSystemHUD),
                PermissionUse("Mirror notifications from every app", on: s.notificationMirroring),
                PermissionUse("Show Live Activities from the menu bar", on: s.mirrorMenuBarActivities),
                PermissionUse("Fit the closed island between menu bar icons", on: s.closedLayout == .auto),
            ]
        case .calendars:
            return [PermissionUse("Next event, meeting alerts and Join buttons", on: s.calendarEnabled)]
        case .reminders:
            return [PermissionUse("Reminders due today", on: s.remindersEnabled)]
        case .downloadsFolder:
            return [PermissionUse("Download progress", on: s.downloadsEnabled)]
        case .automationMusic:
            return [PermissionUse("Music controls when the system-wide bridge is unavailable",
                                  on: s.mediaEnabled && !s.disabledMediaSources.contains(.appleMusic))]
        case .automationSpotify:
            return [PermissionUse("Spotify controls when the system-wide bridge is unavailable",
                                  on: s.mediaEnabled && !s.disabledMediaSources.contains(.spotify))]
        }
    }
}

/// A feature that needs a permission.
public struct PermissionUse: Equatable, Sendable {
    public var feature: String
    public var isOn: Bool

    public init(_ feature: String, on: Bool) {
        self.feature = feature
        self.isOn = on
    }
}

/// What macOS says about a permission right now.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    /// macOS hasn't asked yet.
    case notDetermined
    /// Automation can only be checked while the other app is open.
    case appNotRunning
    case appNotInstalled
    /// macOS can't tell without asking (the Downloads folder before a feature has used it).
    case unknown

    /// Status from the `OSStatus` of `AEDeterminePermissionToAutomateTarget`.
    public static func automation(_ status: Int32) -> PermissionStatus {
        switch status {
        case 0: return .granted                 // noErr
        case -1743: return .denied              // errAEEventNotPermitted
        case -1744: return .notDetermined       // errAEEventWouldRequireUserConsent
        case -600: return .appNotRunning        // procNotFound
        default: return .unknown
        }
    }

    /// What the row's button does: ask macOS (it shows its own prompt) or open System Settings.
    /// macOS only prompts once, so after a refusal the switch is in System Settings.
    public var action: PermissionAction {
        switch self {
        case .notDetermined, .unknown: return .request
        case .granted, .denied, .appNotRunning: return .openSettings
        case .appNotInstalled: return .none
        }
    }
}

public enum PermissionAction: Equatable, Sendable {
    case request, openSettings, none
}

/// Whether Islet may send Apple Events to one app, and when to ask macOS about it again.
/// Asking never prompts, so nothing is sent until macOS reports Automation as granted: allowed
/// earlier, or by the user pressing Allow in Settings → Permissions. macOS is asked once per
/// launch, then again each time the app becomes active while it has given no lasting answer
/// (not asked yet, or the app wasn't open to check).
public struct AutomationGate: Equatable, Sendable {
    public enum Trigger: Sendable {
        /// Islet is about to want Apple Events for the app (its integration started, or the
        /// system bridge went away).
        case firstUse
        /// The app came to the front.
        case appActivated
    }

    /// The last answer from macOS; nil until one arrives.
    public private(set) var status: PermissionStatus?
    private var checking = false

    public init() {}

    /// Whether Apple Events may be sent now.
    public var allowsEvents: Bool { status == .granted }

    /// Whether to ask macOS now. A true result counts as the check starting; `record` ends it.
    public mutating func shouldCheck(_ trigger: Trigger) -> Bool {
        guard !checking else { return false }
        switch trigger {
        case .firstUse: guard status == nil else { return false }
        case .appActivated: guard !isSettled else { return false }
        }
        checking = true
        return true
    }

    /// Take an answer from macOS: one of these checks, or the user's in Settings → Permissions.
    /// - Returns: true when Apple Events have just become allowed.
    @discardableResult
    public mutating func record(_ status: PermissionStatus) -> Bool {
        let was = allowsEvents
        self.status = status
        checking = false
        return allowsEvents && !was
    }

    /// Allowed or refused: only the user changes that, in System Settings.
    private var isSettled: Bool { status == .granted || status == .denied }
}

/// When a feature that is switched on may ask macOS for its permission.
public enum PermissionPrompt {
    /// Only as the user switches the feature on. Finding it already on (at launch, or on some other
    /// settings change) never asks: a permission taken away since then shows as missing in
    /// Settings, and the feature does without it until it is granted again.
    /// - Parameters:
    ///   - wasOn: the setting before this change; nil at launch.
    ///   - isOn: the setting now.
    public static func shouldAsk(wasOn: Bool?, isOn: Bool) -> Bool {
        guard let wasOn else { return false }
        return isOn && !wasOn
    }
}
