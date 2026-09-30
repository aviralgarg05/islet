import AppKit
import ApplicationServices
import CoreServices
import IsletCore

/// Reads and requests the permissions listed in Settings → Permissions. Reading never prompts.
/// Automation and the Downloads folder are checked off the main thread, because macOS can take a
/// moment (or, when asking, wait for the user); completions run on the main thread.
/// Calendars and Reminders are requested through `CalendarService`, which owns the event store.
public enum PermissionProbe {
    private static let queue = DispatchQueue(label: "islet.permissions", qos: .userInitiated)
    /// Accessibility has no "not asked yet" state, so remember whether this session has asked.
    private static var askedForAccessibility = false

    public static var downloadsFolder: URL { IsletPaths.home.appendingPathComponent("Downloads") }

    /// The current status. Reading the Downloads folder would prompt the first time, so it is
    /// only read when `readDownloads` is true (the downloads module is on, or the user asked).
    public static func status(of kind: PermissionKind, readDownloads: Bool,
                              completion: @escaping (PermissionStatus) -> Void) {
        switch kind {
        case .accessibility:
            completion(AXIsProcessTrusted() ? .granted : askedForAccessibility ? .denied : .notDetermined)
        case .calendars:
            completion(status(CalendarService.eventAccess))
        case .reminders:
            completion(status(CalendarService.reminderAccess))
        case .downloadsFolder:
            guard readDownloads else { return completion(.unknown) }
            readFolder(completion)
        case .automationMusic, .automationSpotify:
            automation(kind, ask: false, completion: completion)
        }
    }

    /// Ask macOS, which shows its own prompt if it hasn't asked before, then report the status.
    /// Accessibility's prompt points to System Settings, so the answer arrives later: check
    /// again when Islet becomes active.
    public static func request(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) {
        switch kind {
        case .accessibility:
            askedForAccessibility = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            completion(AXIsProcessTrustedWithOptions([key: true] as CFDictionary) ? .granted : .denied)
        case .downloadsFolder:
            readFolder(completion)
        case .automationMusic, .automationSpotify:
            automation(kind, ask: true, completion: completion)
        case .calendars, .reminders:
            status(of: kind, readDownloads: false, completion: completion)
        }
    }

    static func status(_ access: CalendarService.Access) -> PermissionStatus {
        switch access {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        }
    }

    /// Listing the folder is what the downloads module does; the first time, macOS asks.
    private static func readFolder(_ completion: @escaping (PermissionStatus) -> Void) {
        let folder = downloadsFolder
        queue.async {
            let result: PermissionStatus
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                result = .granted
            } catch let error as NSError {
                let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
                result = error.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES)
                    ? .denied : .unknown
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Never launches the other app: macOS can only answer while it is open.
    private static func automation(_ kind: PermissionKind, ask: Bool, completion: @escaping (PermissionStatus) -> Void) {
        guard let bundleID = kind.automationTarget,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return completion(.appNotInstalled)
        }
        queue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            let result = PermissionStatus.automation(code)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .isletAutomationStatus, object: bundleID, userInfo: ["status": result])
                completion(result)
            }
        }
    }
}

public extension Notification.Name {
    /// Every Automation answer from macOS, posted on the main thread. The object is the target
    /// app's bundle ID and `userInfo["status"]` its `PermissionStatus`. The Music and Spotify
    /// providers listen, so an Allow in Settings → Permissions takes effect at once.
    static let isletAutomationStatus = Notification.Name("IsletAutomationStatus")
}
