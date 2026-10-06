import CoreServices
import Foundation
import CasementCore

/// Reads agent plan usage from local files, only when they change. Nothing polls:
/// - Claude: `casementctl statusline` writes `usage/claude.json`; a vnode source on that folder
///   and on the file reports each replacement.
/// - Codex: FSEvents on `~/.codex/sessions` (folder events, 5 s latency). On each event the
///   newest `rollout-*.jsonl` is found and only its last 64 KB are read.
/// Callbacks arrive on `callbackQueue` (main by default), and only when the figures changed.
public final class UsageWatcher {
    public var onClaude: ((AgentUsage?) -> Void)?
    public var onCodex: ((AgentUsage?) -> Void)?
    public var callbackQueue = DispatchQueue.main

    public let claudeFile: URL
    public let codexSessions: URL
    /// Bytes read from the end of a rollout file.
    public var tailLimit = 64 * 1024
    public var codexLatency: TimeInterval = 5

    /// What was asked for (the caller's thread).
    public private(set) var isWatchingClaude = false
    public private(set) var isWatchingCodex = false

    private let queue = DispatchQueue(label: "casement.usage", qos: .utility)
    // Everything below is touched only on `queue` (and in deinit, when no handler can run).
    private var claudeDir: DispatchSourceFileSystemObject?
    private var claudeFileSource: DispatchSourceFileSystemObject?
    private var stream: FSEventStreamRef?
    private var lastClaude: AgentUsage?
    private var lastCodex: AgentUsage?
    private var rollout: URL?

    public init(claudeFile: URL = AgentUsageStore.claudeFile(),
                codexSessions: URL = CasementPaths.home.appendingPathComponent(".codex/sessions")) {
        self.claudeFile = claudeFile
        self.codexSessions = codexSessions
    }

    deinit {
        claudeDir?.cancel()
        claudeFileSource?.cancel()
        if let stream { Self.release(stream) }
    }

    // MARK: Claude

    public func startClaude() {
        guard !isWatchingClaude else { return }
        isWatchingClaude = true
        queue.async { [weak self] in self?.beginClaude() }
    }

    public func stopClaude() {
        guard isWatchingClaude else { return }
        isWatchingClaude = false
        queue.async { [weak self] in self?.endClaude() }
    }

    private func beginClaude() {
        guard claudeDir == nil else { return }
        let dir = claudeFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in
            self?.watchClaudeFile()
            self?.readClaude()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        claudeDir = src
        watchClaudeFile()
        readClaude()
    }

    private func endClaude() {
        claudeDir?.cancel()
        claudeDir = nil
        claudeFileSource?.cancel()
        claudeFileSource = nil
        lastClaude = nil
    }

    /// Follows in-place writes; the folder source covers atomic replacements.
    private func watchClaudeFile() {
        claudeFileSource?.cancel()
        claudeFileSource = nil
        let fd = open(claudeFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self, weak src] in
            if let data = src?.data, !data.isDisjoint(with: [.delete, .rename]) { self?.watchClaudeFile() }
            self?.readClaude()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        claudeFileSource = src
    }

    private func readClaude() {
        guard claudeDir != nil else { return }
        let usage = AgentUsageStore.read(claudeFile)
        guard usage != lastClaude else { return }
        lastClaude = usage
        callbackQueue.async { [weak self] in self?.onClaude?(usage) }
    }

    // MARK: Codex

    /// Watches only when the sessions folder exists (Codex has been used on this Mac).
    public func startCodex() {
        guard !isWatchingCodex else { return }
        isWatchingCodex = true
        queue.async { [weak self] in self?.beginCodex() }
    }

    public func stopCodex() {
        guard isWatchingCodex else { return }
        isWatchingCodex = false
        queue.async { [weak self] in self?.endCodex() }
    }

    /// Holds the watcher weakly, so an event already queued can't reach a freed watcher.
    private final class Box {
        weak var watcher: UsageWatcher?
        init(_ watcher: UsageWatcher) { self.watcher = watcher }
    }

    private func beginCodex() {
        guard stream == nil, FileManager.default.fileExists(atPath: codexSessions.path) else { return }
        let box = Unmanaged.passRetained(Box(self))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Box>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Box>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let watcher = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().watcher else { return }
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            watcher.readCodex(changedFolders: Array(changed.prefix(count)))
        }
        let created = FSEventStreamCreate(nil, callback, &context, [codexSessions.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), codexLatency,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        box.release() // the stream keeps its own reference
        guard let created else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        readCodex(changedFolders: nil)
    }

    private func endCodex() {
        if let stream { Self.release(stream) }
        stream = nil
        rollout = nil
        lastCodex = nil
    }

    private static func release(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Pick the newest rollout among the one already known and those in the changed folders
    /// (or the most recent day folders on a full scan), then read its tail.
    private func readCodex(changedFolders: [String]?) {
        guard stream != nil else { return }
        var candidates: [URL] = rollout.map { [$0] } ?? []
        if let changedFolders {
            for folder in Set(changedFolders) { candidates += Self.rollouts(in: URL(fileURLWithPath: folder, isDirectory: true)) }
        } else if let newest = Self.newestRollout(in: codexSessions) {
            candidates.append(newest)
        }
        guard let newest = Self.newest(candidates) else { return }
        rollout = newest
        guard let (tail, cut) = Self.tail(of: newest, limit: tailLimit),
              let usage = CodexRollout.latestUsage(inTail: tail, startsMidLine: cut),
              !usage.sameFigures(as: lastCodex) else { return }
        lastCodex = usage
        callbackQueue.async { [weak self] in self?.onCodex?(usage) }
    }

    // MARK: Files

    static func rollouts(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }.map { folder.appendingPathComponent($0) }
    }

    static func newest(_ urls: [URL]) -> URL? {
        let dated = urls.compactMap { url -> (URL, Date)? in
            guard let d = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
            return (url, d)
        }
        return dated.max { $0.1 < $1.1 }?.0
    }

    /// Newest rollout under `root` (`YYYY/MM/DD/rollout-*.jsonl`, or flat in older Codex
    /// versions), looking only in the most recent `dayFolders` day folders.
    public static func newestRollout(in root: URL, dayFolders: Int = 2) -> URL? {
        func numbered(_ dir: URL) -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }.sorted(by: >).map { dir.appendingPathComponent($0) }
        }
        var days: [URL] = []
        search: for year in numbered(root) {
            for month in numbered(year) {
                for day in numbered(month) {
                    days.append(day)
                    if days.count >= dayFolders { break search }
                }
            }
        }
        return newest(days.flatMap(rollouts(in:)) + rollouts(in: root))
    }

    /// The last `limit` bytes of a file, and whether that cut the file (so the first line is partial).
    public static func tail(of url: URL, limit: Int = 64 * 1024) -> (Data, Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(limit) ? size - UInt64(limit) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        return (data, start > 0)
    }
}
