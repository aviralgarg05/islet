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
    /// How long a script that has had SIGTERM is given before SIGKILL.
    public static let killGrace: TimeInterval = 2
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
        for t in timers.values { t.cancel() }
        if paused { timers.values.forEach { $0.resume() } }
        paused = false
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
            // Cancelled before it is resumed: resuming a timer whose deadline went by while the
            // screen was locked submits its handler at once, and this widget's script has just
            // been taken away, so it would run once more and come back as a row nothing clears.
            // Cancelling a suspended source is legal; what traps is releasing the last reference
            // to one, so it is still resumed before the reference goes.
            timer.cancel()
            if paused { timer.resume() }
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
        p.environment = ScriptPlugins.environment(parent: ProcessInfo.processInfo.environment, extra: extraEnv)
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
        // Drain both pipes concurrently so a chatty script can't deadlock on a full buffer, and
        // give each read the deadline too. `readDataToEndOfFile` comes back only once every
        // writer has closed the pipe, and a script whose child inherits stdout (`foo &`, ssh, a
        // daemon) never closes it: one such widget parked two global queue threads for good,
        // once every interval, until libdispatch ran out of them.
        let group = DispatchGroup()
        var stdoutData = Data(), stderrData = Data()
        DispatchQueue.global().async(group: group) { stdoutData = Self.drain(out.fileHandleForReading, until: deadline) }
        DispatchQueue.global().async(group: group) { stderrData = Self.drain(err.fileHandleForReading, until: deadline) }
        // Stopped at the deadline whatever its pipes are doing, so `waitUntilExit` below always
        // comes back. A script that closes or redirects its own output and keeps working drains
        // in milliseconds, and waiting on it would freeze the one queue every widget runs on.
        let timer = DispatchWorkItem { Self.halt(p) }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
        // Both reads stop themselves at the deadline, so this comes back either way; the grace
        // is only for the hand-off.
        _ = group.wait(timeout: deadline + .seconds(1))
        let ranOut = DispatchTime.now() >= deadline
        p.waitUntilExit()
        timer.cancel()
        guard !ranOut else {
            // Out of time: whatever it printed is dropped, as it always was. The script itself
            // may already have gone, leaving a child holding the pipe.
            Self.halt(p)
            return ("", "timed out after \(Int(timeout)) s")
        }
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        if p.terminationStatus != 0 {
            let stderr = String(decoding: stderrData, as: UTF8.self)
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (stdout, "exit \(p.terminationStatus)" + (msg.isEmpty ? "" : ": \(msg.prefix(200))"))
        }
        return (stdout, nil)
    }

    /// Reads everything `handle` gives until every writer has closed the pipe or `deadline`
    /// passes. Unlike `readDataToEndOfFile` it gives up: a script's child can hold the pipe open
    /// long after the script itself has gone, and a blocked read parks its thread for good.
    static func drain(_ handle: FileHandle, until deadline: DispatchTime) -> Data {
        let fd = handle.fileDescriptor
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let now = DispatchTime.now()
            guard now < deadline else { return data }
            let leftMilliseconds = (deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(max(1, min(leftMilliseconds, 250))))
            if ready < 0 {
                if errno == EINTR { continue }
                return data
            }
            guard ready > 0 else { continue }
            let read = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if read > 0 {
                data.append(contentsOf: buffer[0..<read])
            } else if read == 0 {
                return data
            } else if errno != EINTR && errno != EAGAIN {
                return data
            }
        }
    }

    /// SIGTERM, then SIGKILL after a grace period if it is still there, as `CLIChild.stop()` does.
    static func halt(_ p: Process) {
        guard p.isRunning else { return }
        let pid = p.processIdentifier
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
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
