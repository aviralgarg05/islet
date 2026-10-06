import Foundation

/// What Home says about Claude Code before its plan usage has reached Casement. Claude Code keeps
/// no usage on disk that Casement could read; it only passes it to its status line. So until
/// Casement's status line is in place, Home offers to add it, and until the first figures arrive,
/// it says it is waiting. Nothing changes in Claude Code's settings without the user's click
/// in Settings.
public enum ClaudeUsageHint: Equatable, Sendable {
    /// Claude Code is installed and Casement's status line isn't: offer to show usage.
    case offer
    /// The status line is in place and no figures have arrived yet.
    case waiting

    /// The hint for this moment, or nil for none.
    /// - Parameters:
    ///   - enabled: Claude usage is switched on in Settings.
    ///   - dismissed: the user closed the hint with its "x".
    ///   - claudeInstalled: Claude Code's settings folder exists (`ClaudeCodeInstall`).
    ///   - statusLine: Casement's status line in Claude Code's settings, when it could be read.
    ///   - hasUsage: figures have arrived, so usage is connected.
    ///   - canInstall: this copy of Casement has `casementctl`, so the status line can be added.
    public static func decide(enabled: Bool, dismissed: Bool, claudeInstalled: Bool,
                              statusLine: ClaudeStatusLineSetup.Status?, hasUsage: Bool, canInstall: Bool) -> ClaudeUsageHint? {
        guard enabled, !dismissed, claudeInstalled, !hasUsage, let statusLine else { return nil }
        switch statusLine {
        case .installed: return .waiting
        case .notInstalled: return canInstall ? .offer : nil
        // Settings explains why Casement can't wrap this status line; Home stays quiet.
        case .unsupported: return nil
        }
    }
}

/// Signs that Claude Code is on this Mac.
public enum ClaudeCodeInstall {
    /// Claude Code creates its settings folder (`~/.claude`) the first time it runs. The folder
    /// is passed in, so tests never look at the real one.
    public static func looksInstalled(configDirectory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: configDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Where Claude Code keeps its settings, under `home`.
    public static func configDirectory(home: URL) -> URL { home.appendingPathComponent(".claude", isDirectory: true) }

    /// Claude Code's settings file in `configDirectory`.
    public static func settingsFile(in configDirectory: URL) -> URL { configDirectory.appendingPathComponent("settings.json") }
}
