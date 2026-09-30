import Foundation
import IsletCore

/// Installs Islet's hooks into Claude Code's settings file (Settings → Integrations).
/// The merge itself is `ClaudeHookInstaller`; this reads and writes the file.
public enum ClaudeHookSetup {
    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// What installing would change, without writing anything.
    public static func plan(at url: URL = settingsURL, executable: String, wait: Int) throws -> ClaudeHookInstaller.Plan {
        try ClaudeHookInstaller.plan(existing: read(url), executable: executable, wait: wait)
    }

    /// Merges the hooks into the file and returns what changed. The previous file is kept as
    /// `settings.json.bak`. A symlinked file (dotfiles) is written through the link.
    @discardableResult
    public static func install(at url: URL = settingsURL, executable: String, wait: Int) throws -> ClaudeHookInstaller.Plan {
        let target = url.resolvingSymlinksInPath()
        let plan = try ClaudeHookInstaller.plan(existing: read(target), executable: executable, wait: wait)
        guard !plan.isUpToDate else { return plan }
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
            let backup = target.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: target, to: backup)
        }
        try plan.merged.write(to: target, options: .atomic)
        return plan
    }

    static func read(_ url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
}
