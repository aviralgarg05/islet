import Foundation
import IsletCore

/// Installs Islet's hooks into Claude Code's settings file (Settings → Coding agents).
/// The merge itself is `ClaudeHookInstaller`; this reads and writes the file.
public enum ClaudeHookSetup {
    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// What installing would change, without writing anything.
    public static func plan(at url: URL = settingsURL, executable: String, wait: Int) throws -> ClaudeHookInstaller.Plan {
        try ClaudeHookInstaller.plan(existing: AgentConfigFile.read(url), executable: executable, wait: wait)
    }

    /// Merges the hooks into the file and returns what changed. The previous file is kept as
    /// `settings.json.bak`. A symlinked file (dotfiles) is written through the link, and the
    /// file keeps its permissions (it can hold keys in `env`, so it may be private).
    @discardableResult
    public static func install(at url: URL = settingsURL, executable: String, wait: Int) throws -> ClaudeHookInstaller.Plan {
        let target = url.resolvingSymlinksInPath()
        let plan = try ClaudeHookInstaller.plan(existing: AgentConfigFile.read(target), executable: executable, wait: wait)
        guard !plan.isUpToDate else { return plan }
        try AgentConfigFile.write(plan.merged, to: target)
        return plan
    }
}

/// Connects Claude Code, Codex or Cursor: plans the change to each of the agent's files and
/// writes them after the user confirms. `home` is passed in, so tests never touch the real one.
public enum AgentHookSetup {
    public static func plan(_ agent: CodingAgent, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            executable: String, wait: Int) throws -> AgentHookPlan {
        try AgentHookPlan.make(agent, home: home, executable: executable, wait: wait) { url in
            try AgentConfigFile.read(url.resolvingSymlinksInPath())
        }
    }

    /// What disconnecting would change: Islet's hooks out, everything else as it is.
    public static func disconnectPlan(_ agent: CodingAgent, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> AgentHookPlan {
        try AgentHookPlan.disconnect(agent, home: home) { url in try AgentConfigFile.read(url.resolvingSymlinksInPath()) }
    }

    /// The `isletctl` paths an agent's hooks call that are gone (Islet.app moved or was deleted).
    /// Reads one file, only if it is there; never writes.
    public static func missingExecutables(_ agent: CodingAgent, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                          exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> [String] {
        AgentHookPlan.missingExecutables(agent, home: home, read: { url in try AgentConfigFile.read(url.resolvingSymlinksInPath()) },
                                         exists: exists)
    }

    /// Writes the files a plan changes, each with a `.bak` of what was there.
    public static func apply(_ plan: AgentHookPlan) throws {
        for file in plan.changedFiles {
            try AgentConfigFile.write(file.contents, to: file.url.resolvingSymlinksInPath())
        }
    }

    /// Where the agent stands, from its files.
    public static func connection(_ agent: CodingAgent, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  executable: String, wait: Int) -> AgentConnection {
        var isDirectory: ObjCBool = false
        let installed = FileManager.default.fileExists(atPath: agent.configDirectory(home: home).path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let plan = Result { try self.plan(agent, home: home, executable: executable, wait: wait) }
        return AgentConnection.decide(agent, installed: installed, plan: plan)
    }
}

/// Reading and writing another app's settings file without losing anything.
enum AgentConfigFile {
    static func read(_ url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    /// Writes `data` to `target` (already resolved through any symlink). An existing file is
    /// first copied to `<name>.bak` and keeps its permissions.
    static func write(_ data: Data, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var permissions: NSNumber?
        if fm.fileExists(atPath: target.path) {
            permissions = try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
            let backup = target.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: target, to: backup)
        }
        guard let permissions else {
            try data.write(to: target, options: .atomic)
            return
        }
        // An atomic write would replace the file with one made with default permissions, so
        // write a sibling that already has the old permissions, then rename it into place.
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: permissions]) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temp.path])
        }
        do {
            try data.write(to: temp)
            guard rename(temp.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
