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
