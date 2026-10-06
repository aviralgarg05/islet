import Foundation

/// Usage files shared between `casementctl statusline` (writer) and the app (reader).
public enum AgentUsageStore {
    /// `~/Library/Application Support/Casement/usage` (follows `CASEMENT_SUPPORT_DIR`).
    public static var directory: URL { CasementPaths.supportDirectory.appendingPathComponent("usage") }

    public static func claudeFile(in directory: URL = directory) -> URL {
        directory.appendingPathComponent("claude.json")
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func encode(_ usage: AgentUsage) -> Data { (try? encoder.encode(usage)) ?? Data() }

    public static func decode(_ data: Data) -> AgentUsage? { try? decoder.decode(AgentUsage.self, from: data) }

    public static func read(_ url: URL) -> AgentUsage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Replace `url` in one step with a file only the user can read (0600), creating its
    /// folder (0700) if needed.
    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temp.path]) }
        let written = data.withUnsafeBytes { buf in buf.baseAddress.map { Darwin.write(fd, $0, buf.count) } ?? 0 }
        fchmod(fd, 0o600)
        close(fd)
        guard written == data.count, rename(temp.path, url.path) == 0 else {
            unlink(temp.path)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}

/// The work behind `casementctl statusline`, kept here so it can be tested against a temporary folder.
public enum StatusLineBridge {
    /// Record a status-line payload in `directory`. The file is written only when the figures
    /// changed. Returns the merged usage (nil when the payload isn't a JSON object) and
    /// whether the file was written.
    @discardableResult
    public static func record(_ payload: Data, in directory: URL, now: Date = Date()) -> (usage: AgentUsage?, wrote: Bool) {
        guard let reading = ClaudeStatusLine.parse(payload, now: now) else { return (nil, false) }
        let file = AgentUsageStore.claudeFile(in: directory)
        let previous = AgentUsageStore.read(file)
        let merged = ClaudeStatusLine.merged(reading, previous: previous)
        if merged.sameFigures(as: previous) { return (merged, false) }
        do {
            try AgentUsageStore.write(AgentUsageStore.encode(merged), to: file)
            return (merged, true)
        } catch {
            return (merged, false)
        }
    }

    /// Printed when there is no status line to wrap: "Opus 5.5 · 42% context · 5h 62%".
    public static func defaultLine(_ u: AgentUsage) -> String {
        var parts: [String] = []
        if let m = u.model { parts.append(m) }
        if let c = u.contextPercent { parts.append("\(UsageFormat.percent(c)) context") }
        if let w = u.window("five_hour") { parts.append("\(w.shortLabel) \(UsageFormat.percent(w.usedPercent))") }
        return parts.joined(separator: " · ")
    }
}
