import AppKit
import Foundation
import IsletCore

/// One script widget and its latest output.
public struct PluginResult: Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var interval: TimeInterval
    public var output: ScriptPlugins.Output
    public var lastRun: Date
    public var error: String?

    public init(path: String, name: String, interval: TimeInterval, output: ScriptPlugins.Output, lastRun: Date, error: String? = nil) {
        self.path = path
        self.name = name
        self.interval = interval
        self.output = output
        self.lastRun = lastRun
        self.error = error
    }
}

/// Runs executable scripts from the plugins folder on their xbar-style schedule.
///
/// Scripts run as the user and are started by Islet, so only files the user owns in a folder the
/// user owns, writable by nobody else, are run. Schedules pause while the screen is locked or
/// the displays sleep and pick up with one run when they return.
public final class ScriptPluginRunner {
    public var onResult: ((PluginResult) -> Void)?
    public var onRemoved: ((String) -> Void)?
    public var defaultInterval: TimeInterval = 300
    public var timeout: TimeInterval = 15
    public private(set) var directory: URL

    private var timers: [String: DispatchSourceTimer] = [:]
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var paused = false
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "islet.plugins", qos: .utility)

    public init(directory: URL) {
        self.directory = directory
    }

    deinit { stop() }

    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        rescan()
        watchDirectory()
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter
        observers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.pause() },
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.resume() },
            wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() },
            wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() },
        ]
    }

    public func stop() {
        if paused { timers.values.forEach { $0.resume() } }
        paused = false
        for t in timers.values { t.cancel() }
        timers.removeAll()
        dirWatcher?.cancel()
        dirWatcher = nil
        for o in observers {
            DistributedNotificationCenter.default().removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers = []
    }

    private func pause() {
        guard !paused else { return }
        paused = true
        timers.values.forEach { $0.suspend() }
    }

    private func resume() {
        guard paused else { return }
        paused = false
        // A timer that came due while suspended fires once on resume.
        timers.values.forEach { $0.resume() }
    }

    /// Owned by the user and writable by no one else: anything else could be swapped for code
    /// that then runs with Islet's permissions.
    public static func isTrusted(_ path: String) -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        return st.st_uid == getuid() && st.st_mode & (S_IWGRP | S_IWOTH) == 0
    }

    /// Scripts in the folder that are executable, not hidden and trusted (see `isTrusted`).
    public static func discover(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard isTrusted(dir.path) else { return [] }
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return items.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile && fm.isExecutableFile(atPath: url.path) && isTrusted(url.path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func rescan() {
        let scripts = Self.discover(in: directory)
        let paths = Set(scripts.map(\.path))
        for (path, timer) in timers where !paths.contains(path) {
            timer.cancel()
            timers[path] = nil
            onRemoved?(path)
        }
        for script in scripts where timers[script.path] == nil {
            schedule(script)
            if paused { timers[script.path]?.suspend() }
        }
    }

    public func runNow(path: String) {
        let url = URL(fileURLWithPath: path)
        queue.async { [weak self] in self?.execute(url) }
    }

    private func schedule(_ script: URL) {
        let interval = ScriptPlugins.interval(fromFileName: script.lastPathComponent) ?? defaultInterval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets macOS coalesce wakeups (energy friendly).
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(min(interval * 100, 5000))))
        timer.setEventHandler { [weak self] in self?.execute(script) }
        timers[script.path] = timer
        timer.resume()
    }

    private func execute(_ script: URL) {
        let name = ScriptPlugins.displayName(fromFileName: script.lastPathComponent)
        let interval = ScriptPlugins.interval(fromFileName: script.lastPathComponent) ?? defaultInterval
        let run = Self.run(script, timeout: timeout)
        let result = PluginResult(
            path: script.path, name: name, interval: interval,
            output: run.error == nil ? ScriptPlugins.parse(run.stdout) : .empty,
            lastRun: Date(), error: run.error
        )
        DispatchQueue.main.async { [weak self] in self?.onResult?(result) }
    }

    /// Run a script with xbar-compatible environment variables and a hard timeout.
    public static func run(_ script: URL, timeout: TimeInterval, extraEnv: [String: String] = [:]) -> (stdout: String, error: String?) {
        let p = Process()
        p.executableURL = script
        p.currentDirectoryURL = script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a minimal PATH; plugins expect Homebrew tools.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["ISLET"] = "1"
        env["XBARDarkMode"] = "true"
        env["SWIFTBAR"] = "1"
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return ("", "could not start: \(error.localizedDescription)")
        }
        let deadline = DispatchTime.now() + timeout
        // Drain both pipes concurrently so a chatty script can't deadlock on a full buffer.
        let group = DispatchGroup()
        var stdoutData = Data(), stderrData = Data()
        DispatchQueue.global().async(group: group) { stdoutData = out.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: group) { stderrData = err.fileHandleForReading.readDataToEndOfFile() }
        if group.wait(timeout: deadline) == .timedOut {
            p.terminate()
            return ("", "timed out after \(Int(timeout)) s")
        }
        p.waitUntilExit()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        if p.terminationStatus != 0 {
            let stderr = String(decoding: stderrData, as: UTF8.self)
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (stdout, "exit \(p.terminationStatus)" + (msg.isEmpty ? "" : ": \(msg.prefix(200))"))
        }
        return (stdout, nil)
    }

    private func watchDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.rescan() }
        src.setCancelHandler { close(fd) }
        dirWatcher = src
        src.resume()
    }
}
