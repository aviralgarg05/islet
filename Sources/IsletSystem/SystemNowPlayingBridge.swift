import Foundation
import IsletCore

/// System-wide Now Playing (any app, including browsers) through the MediaRemote helper.
///
/// macOS 15.4+ refuses MediaRemote to non-Apple processes, so the helper library runs inside
/// `/usr/bin/perl` (an Apple platform binary) and streams JSON lines back over a pipe.
/// Transport commands are written to its stdin. The helper exits when the pipe closes.
public final class SystemNowPlayingBridge {
    public var onUpdate: ((NowPlaying?) -> Void)?
    /// Called with a human-readable reason when the bridge can't run.
    public var onUnavailable: ((String) -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var startedAt = Date.distantPast
    private var buffer = Data()
    private var lastArtwork: Data?
    private var lastArtworkHash: Int?
    private var restarts = 0
    private var stopped = false

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

    public func start() {
        stopped = false
        guard process == nil else { return }
        guard let paths = Self.helperPaths() else {
            onUnavailable?("MediaRemote helper not found; system-wide Now Playing is disabled.")
            return
        }
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
            onUnavailable?("Could not start MediaRemote helper: \(error.localizedDescription)")
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
        stdout?.readabilityHandler = nil
        try? stdin?.close()
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        isRunning = false
    }

    private func helperExited(status: Int32) {
        stdout?.readabilityHandler = nil
        process = nil
        stdin = nil
        stdout = nil
        isRunning = false
        guard !stopped else { return }
        // Restart with backoff if the helper crashed (e.g. mediaremoted restarted). A helper
        // that ran for a while earns a fresh set of retries; one that keeps dying doesn't.
        if Date().timeIntervalSince(startedAt) > 60 { restarts = 0 }
        restarts += 1
        guard restarts <= 5 else {
            onUnavailable?("MediaRemote helper keeps exiting (status \(status)).")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts * restarts)) { [weak self] in self?.start() }
    }

    /// Send a transport command. Returns false when the helper isn't running.
    @discardableResult
    public func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        guard let stdin else { return false }
        let line: String
        switch command {
        case .play: line = "cmd 0"
        case .pause: line = "cmd 1"
        case .togglePlayPause: line = "cmd 2"
        case .next: line = "cmd 4"
        case .previous: line = "cmd 5"
        case .seek:
            guard let position else { return false }
            line = "seek \(max(0, position))"
        }
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
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line: Data(line))
        }
        if buffer.count > 8 * 1024 * 1024 { buffer.removeAll() }
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        switch obj["type"] as? String {
        case "nowPlaying":
            let (np, artHash, art) = Self.parse(obj)
            if let art { lastArtwork = art; lastArtworkHash = artHash }
            guard var np else { onUpdate?(nil); return }
            if artHash != nil, artHash == lastArtworkHash { np.artworkData = lastArtwork }
            onUpdate?(np)
        case "error":
            onUnavailable?(obj["message"] as? String ?? "MediaRemote error")
        default:
            break
        }
    }

    /// Parse one helper line. Pure, for tests. Returns the snapshot, the artwork hash and any new artwork bytes.
    public static func parse(_ o: [String: Any]) -> (NowPlaying?, Int?, Data?) {
        if o["empty"] as? Bool == true { return (nil, nil, nil) }
        guard let title = o["title"] as? String, !title.isEmpty else { return (nil, nil, nil) }
        let bundle = o["bundleID"] as? String
        let source: MediaSourceKind = Self.browserBundles.contains(bundle ?? "") ? .browser : .system
        let rate = (o["rate"] as? Double) ?? 1
        let playing = (o["playing"] as? Bool) ?? (rate > 0)
        let np = NowPlaying(
            source: source, bundleID: bundle, appName: o["appName"] as? String, title: title,
            artist: o["artist"] as? String, album: o["album"] as? String, isPlaying: playing,
            duration: (o["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil },
            elapsed: o["elapsed"] as? Double, playbackRate: rate > 0 ? rate : 1,
            timestamp: (o["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        )
        let art = (o["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        return (np, o["artworkHash"] as? Int, art)
    }

    static let browserBundles: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "app.zen-browser.zen", "com.kagi.kagimacOS", "ai.perplexity.comet", "com.openai.atlas",
    ]
}
