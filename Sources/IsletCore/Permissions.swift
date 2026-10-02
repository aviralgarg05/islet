import Foundation

/// A macOS privacy permission that some Islet feature can use. None is needed to run.
public enum PermissionKind: String, CaseIterable, Sendable, Identifiable {
    case accessibility, calendars, reminders, location, camera, downloadsFolder, automationMusic, automationSpotify

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .location: return "Location"
        case .camera: return "Camera"
        case .downloadsFolder: return "Downloads folder"
        case .automationMusic: return "Automation: Music"
        case .automationSpotify: return "Automation: Spotify"
        }
    }

    /// A plain line under the permission, when it needs one: what Accessibility lets Islet do
    /// (people worry it reads their typing), and from macOS 27 the name System Settings uses.
    /// - Parameter status: a refusal adds what to try when the switch is already on.
    public func note(osMajor: Int, status: PermissionStatus? = nil) -> String? {
        guard self == .accessibility else { return nil }
        var lines: [String] = []
        if osMajor >= 27 { lines.append("Called Device Control and Data Access in System Settings.") }
        lines.append("Islet doesn't read what you type. It reads where menu bar items are, whether a window is in full screen, the text of Live Activities and banners, and, only with Replace the system volume and brightness display on, those keys. With Type emoji where you're typing on, it types the emoji you pick, and nothing else.")
        if status == .denied {
            lines.append("Already on in System Settings? Remove Islet with the minus button and add it again.")
        }
        return lines.joined(separator: " ")
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
        case .location: anchor = "Privacy_LocationServices"
        case .camera: anchor = "Privacy_Camera"
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
                PermissionUse("Replace the system volume and brightness display", on: s.replaceSystemHUD),
                PermissionUse("Mirror notifications from every app", on: s.notificationMirroring),
                PermissionUse("Show Live Activities", on: s.mirrorMenuBarActivities),
                PermissionUse("Fit the closed island between menu bar icons", on: s.closedLayout == .auto),
                PermissionUse("Type emoji where you're typing", on: s.emojiEnabled && s.emojiTypes),
            ]
        case .calendars:
            return [PermissionUse("Next event, meeting reminders and Join buttons", on: s.calendarEnabled)]
        case .reminders:
            return [PermissionUse("Reminders due today", on: s.remindersEnabled)]
        case .location:
            return [PermissionUse("Weather where you are", on: s.weatherEnabled && s.weatherUsesLocation)]
        case .camera:
            return [PermissionUse("Camera mirror", on: s.mirror.enabled)]
        case .downloadsFolder:
            return [PermissionUse("Download progress", on: s.downloadsEnabled)]
        case .automationMusic:
            return [PermissionUse("Music controls, when the usual way is unavailable",
                                  on: s.mediaEnabled && !s.disabledMediaSources.contains(.appleMusic))]
        case .automationSpotify:
            return [PermissionUse("Spotify controls, when the usual way is unavailable",
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
    /// Calendars with "Add events only": Islet can add events but not see them.
    case writeOnly
    /// Screen Time or a configuration profile decides, not the user here.
    case restricted

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
        case .granted, .denied, .appNotRunning, .writeOnly, .restricted: return .openSettings
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
/// launch, then again each time the app opens or comes to the front, or the user presses one of
/// its controls, while it has given no lasting answer (not asked yet, or the app wasn't open to
/// check).
public struct AutomationGate: Equatable, Sendable {
    public enum Trigger: Sendable {
        /// Islet is about to want Apple Events for the app (its integration started, or the
        /// system bridge went away).
        case firstUse
        /// The app launched or came to the front.
        case appActivated
        /// The user pressed one of the app's controls in the island.
        case control
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
        case .appActivated, .control: guard !isSettled else { return false }
        }
        checking = true
        return true
    }

    /// Take an answer from macOS: one of these checks, or the user's in Settings → Permissions.
    /// - Returns: true when Apple Events have just become allowed.
    @discardableResult
    public mutating func record(_ status: PermissionStatus) -> Bool {
        let was = allowsEvents
        checking = false
        // "Not running" and the like say nothing about the permission, so they don't replace an
        // answer that does (the Permissions pane checks while the app may be closed).
        if Self.isAnswer(status) || !Self.isAnswer(self.status) { self.status = status }
        return allowsEvents && !was
    }

    /// Allowed or refused: only the user changes that, in System Settings.
    private var isSettled: Bool { status == .granted || status == .denied }

    private static func isAnswer(_ status: PermissionStatus?) -> Bool {
        status == .granted || status == .denied || status == .notDetermined
    }
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

/// Where Islet runs from. Opening at login is reliable only from an Applications folder: a copy
/// run from Downloads, or one macOS moved to a random read-only place (App Translocation), may
/// not open at the next login.
public enum AppLocation {
    public static func isSettled(bundlePath: String, home: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        if isTranslocated(bundlePath: path) { return false }
        let homeApps = (home as NSString).appendingPathComponent("Applications")
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApps + "/")
    }

    /// macOS opened a downloaded copy that was never moved, from a random read-only place (App
    /// Translocation). The place changes at every launch, so whatever remembers where Islet is
    /// (coding agents' hooks, Login Items) loses it.
    public static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// When Islet offers to move itself to Applications.
    public enum MoveMoment: Equatable, Sendable {
        /// Just opened.
        case launch
        /// Before connecting this coding agent (its title).
        case connecting(String)
        /// Move to Applications… in Settings.
        case asked
    }

    /// Whether Islet offers to move itself: never for a build run from the command line; at launch
    /// and before connecting a coding agent only when macOS runs a translocated copy (that is when
    /// things break); when asked in Settings, whenever it is outside Applications.
    public static func offersMove(bundlePath: String, home: String, isAppBundle: Bool, moment: MoveMoment) -> Bool {
        guard isAppBundle else { return false }
        switch moment {
        case .launch, .connecting: return isTranslocated(bundlePath: bundlePath)
        case .asked: return !isSettled(bundlePath: bundlePath, home: home)
        }
    }

    /// Where the move puts Islet: the shared Applications folder when Islet may write there,
    /// otherwise Applications in the home folder.
    public static func destination(appName: String, home: String, canWriteSharedApplications: Bool) -> String {
        let folder = canWriteSharedApplications ? "/Applications" : (home as NSString).appendingPathComponent("Applications")
        return (folder as NSString).appendingPathComponent(appName)
    }

    /// What the offer says, in plain words.
    public struct MovePrompt: Equatable, Sendable {
        public var title: String
        public var message: String
        public var confirm: String
        public var cancel: String
    }

    /// - Parameters:
    ///   - folder: the folder Islet was opened from ("Downloads"), when known.
    ///   - translocated: macOS runs a temporary copy (`isTranslocated`).
    ///   - destination: where it goes (`destination`).
    ///   - replacing: a copy of Islet is already there.
    public static func prompt(for moment: MoveMoment, folder: String?, translocated: Bool, destination: String,
                              home: String, replacing: Bool) -> MovePrompt {
        let place = (destination as NSString).deletingLastPathComponent.hasPrefix(home + "/")
            ? "Applications in your home folder" : "Applications"
        let stillThere = folder.map { "Islet is still in \($0)" } ?? "Islet hasn\u{2019}t been moved to Applications"
        var title = "Move Islet to Applications?"
        var cancel = moment == .launch ? "Not now" : "Cancel"
        // Two sentences: what goes wrong, and what Islet can do about it.
        let message: String
        if case .connecting(let agent) = moment {
            title = "Move Islet to Applications first?"
            message = "\(stillThere), so \(agent) would lose track of it the next time Islet opens."
                + " Islet can move itself to \(place) and reopen, then you can connect."
            cancel = "Cancel"
        } else if translocated {
            message = "\(stillThere), so it may not open at login and coding agents can lose track of it."
                + " Islet can move itself to \(place) and reopen."
        } else {
            message = "Islet runs from \(folder ?? "outside Applications"). From Applications it opens reliably at login, and coding agents keep finding it."
                + " Islet can move itself to \(place) and reopen."
        }
        let replaced = replacing ? " The copy of Islet already there goes to the Bin." : ""
        return MovePrompt(title: title, message: message + replaced, confirm: "Move to Applications", cancel: cancel)
    }

    /// The command that opens Islet from its new place once this copy has quit: it waits up to
    /// 20 seconds for `pid` to end, then opens `appPath` (passed as an argument, never spliced
    /// into the script).
    public static func reopenArguments(pid: Int32, appPath: String) -> [String] {
        let script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt 100 ]; do /bin/sleep 0.2; i=$((i+1)); done; /usr/bin/open \"$0\""
        return ["/bin/sh", "-c", script, appPath]
    }
}

/// Background work that follows the user's session and permissions: reading the menu bar,
/// banners and keys through Accessibility, and following the pointer.
public enum SessionWork {
    /// Accessibility was granted or taken away: whether to start (or stop) what uses it now,
    /// rather than at the next launch. Nothing changes for a grant nobody uses.
    /// - Parameter wasTrusted: what Islet knew before, nil before the first look.
    public static func restartsOnTrustChange(wasTrusted: Bool?, isTrusted: Bool, settings: IsletSettings) -> Bool {
        guard let was = wasTrusted, was != isTrusted else { return false }
        return PermissionKind.accessibility.uses(settings).contains(where: \.isOn)
    }

    /// Whether the menu bar and banner readers, the key tap and the pointer watchers run. After
    /// fast user switching this session is in the background and none of them do; back in front,
    /// they start again as the settings say.
    public static func runs(sessionActive: Bool) -> Bool { sessionActive }
}

/// When the island's panels are made again.
public enum DisplayPolicy {
    /// After waking: the displays are looked at once they have settled, rebuilt whatever they
    /// say (the same displays can come back with other values, or panels that no longer draw),
    /// then once more in case something settled later.
    public static let wakeLooks: [(delay: TimeInterval, force: Bool)] = [(1, true), (2.5, false)]

    /// Whether the panels must be made again: forced after waking, or because the displays
    /// (which ones, in what order, at what size and with what notch) differ from the ones the
    /// panels were made for.
    public static func needsRebuild(current: [ScreenDescriptor], wanted: [ScreenDescriptor], force: Bool) -> Bool {
        force || current != wanted
    }
}
