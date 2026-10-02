import Foundation
import IsletCore

/// System-wide Now Playing (any app, including browsers) through the MediaRemote helper.
///
/// macOS 15.4+ refuses MediaRemote to non-Apple processes, so the helper library runs inside
/// `/usr/bin/perl` (an Apple platform binary) and streams JSON lines back over a pipe.
/// Transport commands are written to its stdin, and reach only the player macOS gives the
/// controls to. The helper exits when the pipe closes.
public final class SystemNowPlayingBridge {
    /// Every player macOS lists, and the one that has the controls.
    public var onUpdate: ((BridgeReport) -> Void)?
    /// Called with a human-readable reason when the bridge can't run. When it has stopped for
    /// good (given up, or it can't start), an empty report comes first: what it said last can't
    /// be trusted, and a video must not stay "playing" with controls that reach nothing.
    public var onUnavailable: ((String) -> Void)?
    /// Called when the helper says it is up, so a failure said before is over.
    public var onRunning: (() -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var startedAt = Date.distantPast
    /// Its output, cut into lines.
    private var lines = HelperLines()
    /// The artwork the helper sent, for the players in its last report.
    private var artwork = BridgeArtwork()
    private var restarts = HelperRestarts()
    private var stopped = false
    /// The next start after an exit or a failed start. Nothing is scheduled while the helper runs.
    private var pendingStart: DispatchWorkItem?

    public private(set) var isRunning = false

    public init() {}
    deinit { stop() }

    /// Locate the helper files: inside the app bundle, or next to the build products in development.
    /// Release builds only ever load the copy inside their own bundle: the helper runs with
    /// Islet's privacy permissions, so it must not come from an environment variable or a path
    /// relative to wherever the binary happens to be.
    public static func helperPaths() -> (script: URL, library: URL)? {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL, Bundle.main.bundleIdentifier != nil { dirs.append(res) }
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["ISLET_HELPERS_DIR"] { dirs.insert(URL(fileURLWithPath: env), at: 0) }
        if let res = Bundle.main.resourceURL { dirs.append(res) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        dirs.append(exe)
        // swift run: .build/<config>/Islet → <repo>/build/helpers
        dirs.append(exe.appendingPathComponent("../../../build/helpers").standardizedFileURL)
        dirs.append(exe.appendingPathComponent("../../build/helpers").standardizedFileURL)
        #endif
        for d in dirs {
            let script = d.appendingPathComponent("islet-mediaremote.pl")
            let lib = d.appendingPathComponent("IsletMediaRemote.dylib")
            if FileManager.default.fileExists(atPath: lib.path) {
                if FileManager.default.fileExists(atPath: script.path) { return (script, lib) }
                // Development layout keeps the script in Helpers/.
                let devScript = d.appendingPathComponent("../../Helpers/MediaRemoteBridge/islet-mediaremote.pl").standardizedFileURL
                if FileManager.default.fileExists(atPath: devScript.path) { return (devScript, lib) }
            }
        }
        return nil
    }

    /// Whether it gave up after the helper kept exiting (`HelperRestarts`).
    public var gaveUp: Bool { restarts.gaveUp }

    /// Start with a fresh set of tries: Now Playing switched on, the user asked, or the Mac woke
    /// after it gave up.
    public func retry() {
        restarts.reset()
        cancelPendingStart()
        start()
    }

    public func start() {
        stopped = false
        guard process == nil else { return }
        cancelPendingStart()
        guard let paths = Self.helperPaths() else {
            // Nothing would change by trying again.
            unavailable("MediaRemote helper not found; system-wide Now Playing is disabled.")
            return
        }
        // A line the last helper left unfinished would swallow this one's first, which says it is up.
        lines.reset()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.library.path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        // A write after the helper has gone must fail, not raise SIGPIPE and end Islet.
        _ = fcntl(inp.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            // End of file: without this the handler is called again at once, forever.
            guard !data.isEmpty else {
                h.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.ingest(data) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.helperExited(status: proc.terminationStatus) }
        }
        do {
            try p.run()
        } catch {
            // As if it exited at once (a busy Mac can refuse a new process for a moment).
            out.fileHandleForReading.readabilityHandler = nil
            failed("Could not start MediaRemote helper: \(error.localizedDescription)", ranFor: 0)
            return
        }
        process = p
        stdin = inp.fileHandleForWriting
        stdout = out.fileHandleForReading
        startedAt = Date()
        isRunning = true
    }

    public func stop() {
        stopped = true
        cancelPendingStart()
        stdout?.readabilityHandler = nil
        try? stdin?.close()
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        isRunning = false
        lines.reset()
    }

    private func helperExited(status: Int32) {
        stdout?.readabilityHandler = nil
        process = nil
        stdin = nil
        stdout = nil
        isRunning = false
        // What it left unfinished can't be finished now.
        lines.reset()
        guard !stopped else { return }
        failed("MediaRemote helper keeps exiting (status \(status)).", ranFor: Date().timeIntervalSince(startedAt))
    }

    /// The helper exited, or couldn't start. Restart with backoff (it crashed, or mediaremoted
    /// restarted): a helper that ran for a while earns a fresh set of retries, one that keeps
    /// dying doesn't. Given up, its players go and it is tried again much later (`HelperRestarts`).
    private func failed(_ reason: String, ranFor: TimeInterval) {
        if let delay = restarts.exited(ranFor: ranFor) {
            startLater(after: delay) { $0.start() }
            return
        }
        unavailable(reason)
        if let wait = restarts.retryAfterGivingUp {
            startLater(after: wait) {
                $0.restarts.tryAgainAfterGivingUp()
                $0.start()
            }
        }
    }

    /// Stopped for good: what it reported last goes, then the app hears why.
    private func unavailable(_ reason: String) {
        onUpdate?(BridgeReport(players: [], current: nil))
        onUnavailable?(reason)
    }

    /// One timer for the next start, replaced by any newer one and dropped by `stop`.
    private func startLater(after delay: TimeInterval, _ work: @escaping (SystemNowPlayingBridge) -> Void) {
        cancelPendingStart()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.pendingStart = nil
            work(self)
        }
        pendingStart = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPendingStart() {
        pendingStart?.cancel()
        pendingStart = nil
    }

    /// Send a transport command. Returns false when the helper isn't running.
    @discardableResult
    public func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        let line: String
        switch command {
        case .play: line = "cmd 0"
        case .pause: line = "cmd 1"
        case .togglePlayPause: line = "cmd 2"
        case .next: line = "cmd 4"
        case .previous: line = "cmd 5"
        case .toggleShuffle: line = "cmd 6"
        case .toggleRepeat: line = "cmd 7"
        // MediaRemote's own 15 s skips; the app prefers a computed seek when it knows the position.
        case .skipBackward: line = "cmd 12"
        case .skipForward: line = "cmd 13"
        case .seek:
            guard let position else { return false }
            line = "seek \(max(0, position))"
        }
        return write(line)
    }

    /// Set shuffle explicitly (more reliable than the toggle command when the state is known).
    @discardableResult
    public func setShuffle(_ on: Bool) -> Bool {
        write("shuffle \(MediaModes.mediaRemoteShuffle(on))")
    }

    /// Set the repeat mode explicitly.
    @discardableResult
    public func setRepeat(_ mode: RepeatMode) -> Bool {
        write("repeat \(MediaModes.mediaRemoteRepeat(mode))")
    }

    private func write(_ line: String) -> Bool {
        guard let stdin else { return false }
        do {
            try stdin.write(contentsOf: Data((line + "\n").utf8))
            return true
        } catch {
            return false
        }
    }

    public func refresh() {
        try? stdin?.write(contentsOf: Data("get\n".utf8))
    }

    private func ingest(_ data: Data) {
        for line in lines.append(data) { handle(line: line) }
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let report = Self.report(from: obj, artwork: &artwork) {
            onUpdate?(report)
        } else if obj["type"] as? String == "ready" {
            onRunning?()
        } else if obj["type"] as? String == "error" {
            onUnavailable?(obj["message"] as? String ?? "MediaRemote error")
        }
    }

    /// A `players` line (every player macOS lists) or a `nowPlaying` line (the current player
    /// alone, from a helper on a macOS that can't list them) as a report. Artwork the helper sent
    /// before comes from `artwork` (`BridgeArtwork`), which is left holding what this report uses.
    /// Nil for any other line. Pure, for tests.
    public static func report(from o: [String: Any], artwork: inout BridgeArtwork) -> BridgeReport? {
        let lines: [[String: Any]]
        switch o["type"] as? String {
        case "players": lines = (o["players"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        case "nowPlaying": lines = [o.merging(["current": true]) { _, new in new }]
        default: return nil
        }
        var entries: [BridgeArtwork.Entry] = []
        var current: String?
        for line in lines {
            let (parsed, hash, bytes) = parse(line)
            guard let np = parsed else { continue }
            if line["current"] as? Bool == true { current = MediaArbiter.playerID(np) }
            entries.append(BridgeArtwork.Entry(player: np, hash: hash, bytes: bytes))
        }
        return BridgeReport(players: artwork.resolve(entries), current: current)
    }

    /// Parse one player from a helper line. Pure, for tests. Returns the snapshot, the artwork
    /// hash and any new artwork bytes.
    public static func parse(_ o: [String: Any]) -> (NowPlaying?, Int?, Data?) {
        if o["empty"] as? Bool == true { return (nil, nil, nil) }
        guard let title = o["title"] as? String, !title.isEmpty else { return (nil, nil, nil) }
        let bundle = (o["bundleID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let source: MediaSourceKind = bundle.flatMap(Browsers.browser(for:)) != nil ? .browser : .system
        // The helper drops numbers JSON can't hold; a live stream has no duration at all.
        func finite(_ key: String) -> Double? { number(o[key]).flatMap { $0.isFinite ? $0 : nil } }
        let rate = finite("rate") ?? 1
        let playing = (o["playing"] as? Bool) ?? (rate > 0)
        let np = NowPlaying(
            source: source, bundleID: bundle, appName: o["appName"] as? String, title: title,
            artist: o["artist"] as? String, album: o["album"] as? String, isPlaying: playing,
            duration: finite("duration").flatMap { $0 > 0 ? $0 : nil },
            elapsed: finite("elapsed"), playbackRate: rate > 0 ? rate : 1,
            timestamp: finite("timestamp").map(Date.init(timeIntervalSince1970:)) ?? Date(),
            shuffle: MediaModes.shuffle(mediaRemote: finite("shuffleMode").flatMap { Int(exactly: $0) }),
            repeatMode: MediaModes.repeatMode(mediaRemote: finite("repeatMode").flatMap { Int(exactly: $0) }),
            // What the player says it takes, when macOS says.
            commands: (o["commands"] as? [Any]).map { list in
                PlaybackCommand.taken(mediaRemote: list.compactMap { number($0).flatMap { Int(exactly: $0) } })
            }
        )
        let art = (o["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        let hash = (o["artworkHash"] as? Int) ?? finite("artworkHash").flatMap { Int(exactly: $0) }
        return (np, hash, art)
    }

    /// A JSON number, whichever way it was read.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}
