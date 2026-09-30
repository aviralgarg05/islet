import Foundation
import AppKit
import IOKit.ps
import IsletCore
import Testing
@testable import IsletSystem

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Minimal backend for exercising the real HTTP server.
actor MemoryBackend: IsletBackend {
    var center = ActivityCenter()
    func listActivities() async -> [Activity] { center.ordered(now: Date()) }
    func applyActivity(_ spec: ActivitySpec) async throws -> Activity { try center.apply(spec, now: Date()) }
    func removeActivity(id: String) async -> Bool { center.remove(id: id) != nil }
    func removeActivities(source: String) async -> Int { center.removeAll(source: source) }
    func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async {}
    func pushMedia(_ media: NowPlaying?) async {}
    func mediaCommand(_ command: PlaybackCommand, position: Double?) async -> Bool { false }
    func setExpanded(_ expanded: Bool) async {}
    func stateSnapshot() async -> StateSnapshot {
        StateSnapshot(version: "t", presentation: "idle", activities: [], nowPlaying: nil, battery: nil)
    }
    func menuBarItems() async -> [MenuBarItemInfo] { [] }
    func keepAwake(_ change: KeepAwakeChange?) async -> KeepAwakeStatus { KeepAwakeStatus(active: false) }
}

func startServer(lan: Bool = false, limit: Int? = nil) async throws -> (LocalAPIServer, UInt16) {
    let server = LocalAPIServer(router: APIRouter(token: "tok", version: "t", backend: MemoryBackend(), allowRemoteHosts: lan))
    if let limit { server.rateLimiter = RateLimiter(limit: limit, window: 60) }
    let port: UInt16 = try await withCheckedThrowingContinuation { cont in
        server.start(port: 0, onAllInterfaces: lan) { cont.resume(with: $0) }
    }
    return (server, port)
}

func request(_ port: UInt16, _ method: String, _ path: String, token: String? = "tok", body: String? = nil) async throws -> (Int, Data) {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    r.httpMethod = method
    if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
        r.httpBody = Data(body.utf8)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, resp) = try await URLSession.shared.data(for: r)
    return ((resp as! HTTPURLResponse).statusCode, data)
}

@Suite(.serialized) struct LocalServerTests {
    @Test func servesTheAPIOverRealSockets() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        #expect(port > 0)
        #expect(try await request(port, "GET", "/v1/health", token: nil).0 == 200)
        #expect(try await request(port, "GET", "/v1/activities", token: nil).0 == 401)
        let (status, data) = try await request(port, "POST", "/v1/activities", body: #"{"id":"x","title":"Hello"}"#)
        #expect(status == 201)
        #expect(try APIJSON.decoder.decode(Activity.self, from: data).title == "Hello")
        #expect(try await request(port, "DELETE", "/v1/activities/x").0 == 204)
    }

    @Test func malformedRequestsGetAnHTTPError() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        // Raw socket: send garbage and read the reply.
        let reply = try rawExchange(port: port, payload: "HELLO\r\n\r\n")
        #expect(reply.hasPrefix("HTTP/1.1 400"))
    }

    @Test func lanModeIsRateLimited() async throws {
        let (server, port) = try await startServer(lan: true, limit: 3)
        defer { server.stop() }
        var codes: [Int] = []
        for _ in 0..<5 { codes.append(try await request(port, "GET", "/v1/health", token: nil).0) }
        #expect(codes.prefix(3).allSatisfy { $0 == 200 })
        #expect(codes.last == 429)
    }

    func rawExchange(port: UInt16, payload: String) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { throw POSIXError(.ECONNREFUSED) }
        _ = payload.withCString { send(fd, $0, strlen($0), 0) }
        var buf = [UInt8](repeating: 0, count: 4096)
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let n = recv(fd, &buf, buf.count, 0)
        return n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
    }
}

@Suite struct DiscoveryTests {
    @Test func discoveryFileIsPrivateAndOwned() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("api.json")
        try APIDiscoveryStore.write(APIDiscovery(port: 1234, token: "abc", pid: 42), to: url)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(APIDiscoveryStore.read(from: url)?.port == 1234)
        // Another instance must not delete our file.
        APIDiscoveryStore.remove(at: url, ownedBy: 7)
        #expect(FileManager.default.fileExists(atPath: url.path))
        APIDiscoveryStore.remove(at: url, ownedBy: 42)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct ParserTests {
    @Test func batteryFromIOKitDescription() {
        let d: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 76, kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true, kIOPSTimeToFullChargeKey: 48,
        ]
        let s = BatteryMonitor.parse(d)
        #expect(s == BatteryState(level: 76, isCharging: true, isPluggedIn: true, minutesRemaining: 48))
        var onBattery = d
        onBattery[kIOPSPowerSourceStateKey] = kIOPSBatteryPowerValue
        onBattery[kIOPSIsChargingKey] = false
        onBattery[kIOPSTimeToEmptyKey] = -1 // still calculating
        #expect(BatteryMonitor.parse(onBattery)?.minutesRemaining == nil)
        #expect(BatteryMonitor.parse([kIOPSTypeKey: "UPS"]) == nil)
    }

    @Test func appleMusicNotification() {
        let np = AppleMusicProvider.parse(["Name": "Song", "Artist": "A", "Album": "B", "Player State": "Playing", "Total Time": 200_000], now: t0)
        #expect(np?.title == "Song")
        #expect(np?.duration == 200)
        #expect(np?.isPlaying == true)
        #expect(AppleMusicProvider.parse(["Player State": "Stopped"], now: t0) == nil)
    }

    @Test func spotifyNotification() {
        let np = SpotifyProvider.parse(["Name": "S", "Artist": "X", "Player State": "Paused", "Duration": 180_000, "Playback Position": 12.5], now: t0)
        #expect(np?.isPlaying == false)
        #expect(np?.elapsed == 12.5)
        #expect(np?.duration == 180)
        #expect(SpotifyProvider.oEmbedURL(trackID: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.absoluteString
            == "https://open.spotify.com/oembed?url=https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        #expect(SpotifyProvider.oEmbedURL(trackID: "spotify:episode:1") == nil)
    }

    @Test func mediaRemoteHelperLine() {
        let art = Data([1, 2, 3]).base64EncodedString()
        let (np, hash, data) = SystemNowPlayingBridge.parse([
            "type": "nowPlaying", "title": "T", "artist": "A", "duration": 100.0, "elapsed": 10.0, "rate": 1.0,
            "timestamp": 1_800_000_000.0, "playing": true, "bundleID": "com.google.Chrome", "artworkHash": 99, "artwork": art,
        ])
        #expect(np?.source == .browser)
        #expect(np?.timestamp == t0)
        #expect(hash == 99)
        #expect(data == Data([1, 2, 3]))
        #expect(SystemNowPlayingBridge.parse(["type": "nowPlaying", "empty": true]).0 == nil)
        let (spotify, _, _) = SystemNowPlayingBridge.parse(["title": "x", "bundleID": "com.spotify.client", "playing": false])
        #expect(spotify?.source == .system)
        #expect(spotify?.isPlaying == false)
    }

    @Test func fullscreenCoverage() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(FullscreenDetector.covers(window: display, display: display))
        // Fullscreen below the camera housing on a notched display.
        #expect(FullscreenDetector.covers(window: CGRect(x: 0, y: 32, width: 1512, height: 950), display: display))
        // A normal maximised window leaves the menu bar and more.
        #expect(!FullscreenDetector.covers(window: CGRect(x: 0, y: 41, width: 1512, height: 900), display: display))
        #expect(!FullscreenDetector.covers(window: CGRect(x: 100, y: 0, width: 800, height: 982), display: display))
    }
}

@Suite struct FileTests {
    func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("islet-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func scriptRunnerCapturesOutputExitCodesAndTimeouts() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        func script(_ name: String, _ body: String) -> URL {
            let url = dir.appendingPathComponent(name)
            try? "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        let ok = ScriptPluginRunner.run(script("ok.1m.sh", "echo \"Hi | color=red\"; echo ---; echo item"), timeout: 5)
        #expect(ok.error == nil)
        #expect(ok.stdout.contains("Hi | color=red"))
        let fail = ScriptPluginRunner.run(script("fail.sh", "echo boom >&2; exit 3"), timeout: 5)
        #expect(fail.error?.hasPrefix("exit 3") == true)
        #expect(fail.error?.contains("boom") == true)
        let started = Date()
        let slow = ScriptPluginRunner.run(script("slow.sh", "sleep 10"), timeout: 1)
        #expect(slow.error?.contains("timed out") == true)
        #expect(Date().timeIntervalSince(started) < 5)
        // Big output doesn't deadlock on a full pipe.
        let big = ScriptPluginRunner.run(script("big.sh", "yes x | head -c 300000; yes y | head -c 300000 >&2"), timeout: 5)
        #expect(big.stdout.count == 300_000)
        // Only executables are discovered.
        try "not executable".write(to: dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let names = ScriptPluginRunner.discover(in: dir).map(\.lastPathComponent)
        #expect(names.contains("ok.1m.sh"))
        #expect(!names.contains("readme.txt"))
        // A script anyone could have rewritten is skipped, and so is a folder others can write to.
        let loose = script("loose.sh", "echo hi")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: loose.path)
        #expect(!ScriptPluginRunner.discover(in: dir).map(\.lastPathComponent).contains("loose.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: dir.path)
        #expect(ScriptPluginRunner.discover(in: dir).isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
    }

    @Test func partialDownloads() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Safari: a .download bundle whose Info.plist records progress.
        let safari = dir.appendingPathComponent("big.iso.download")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        let plist: [String: Any] = ["DownloadEntryProgressBytesSoFar": 250, "DownloadEntryProgressTotalToLoad": 1000]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: safari.appendingPathComponent("Info.plist"))
        let s = DownloadsWatcher.partial(at: safari)
        #expect(s == PartialDownload(fileName: "big.iso.download", bytes: 250, totalBytes: 1000))
        // Chrome: a growing .crdownload file.
        let chrome = dir.appendingPathComponent("video.mp4.crdownload")
        try Data(repeating: 0, count: 4096).write(to: chrome)
        #expect(DownloadsWatcher.partial(at: chrome)?.bytes == 4096)
        #expect(DownloadsWatcher.partial(at: dir.appendingPathComponent("done.zip")) == nil)
    }

    @Test func shelfPersistsAcrossLaunches() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        let store = dir.appendingPathComponent("shelf.json")
        let a = ShelfService(storeURL: store)
        a.add(urls: [file])
        #expect(a.shelf.items.count == 1)
        let b = ShelfService(storeURL: store)
        #expect(b.shelf.items.first?.name == "note.txt")
        // Missing files are pruned on load.
        try FileManager.default.removeItem(at: file)
        #expect(ShelfService(storeURL: store).shelf.items.isEmpty)
    }
}

@Suite struct HostProbeTests {
    /// Smoke tests against the real machine: these read state only.
    @Test func coreAudioProcessObjectsAreReadable() {
        let apps = MicUsageMonitor.recordingApps()
        #expect(apps.allSatisfy { !$0.isEmpty })
        _ = AudioMonitor.readOutput()
    }

    @Test func helperIsLocatableFromTheBuildTree() {
        // In development the bridge finds build/helpers next to the package.
        if FileManager.default.fileExists(atPath: "build/helpers/IsletMediaRemote.dylib") {
            setenv("ISLET_HELPERS_DIR", FileManager.default.currentDirectoryPath + "/build/helpers", 1)
            #expect(SystemNowPlayingBridge.helperPaths() != nil)
            unsetenv("ISLET_HELPERS_DIR")
        }
    }
}

@Suite struct MenuBarHostTests {
    /// Runs against this Mac's real menu bar when Accessibility is available (read-only).
    @Test func systemItemsAreNeverLiveActivities() throws {
        guard MenuBarLiveActivityMonitor.isAvailable, let agent = MenuBarAgentScanner.agentPID else { return }
        let slots = MenuBarAgentScanner.slots(agent: agent, readContent: true)
        #expect(!slots.isEmpty)
        for slot in slots where slot.info.identifier?.hasPrefix("com.apple.menuextra.") == true {
            #expect(slot.kind == .systemItem, "\(slot.info)")
        }
        // Items collapsed into the overflow are stacked on the chevron and flagged.
        if let chevron = slots.first(where: { $0.kind == .overflowButton })?.frame {
            for slot in slots where slot.kind != .overflowButton && slot.frame.intersects(chevron) {
                #expect(slot.info.hidden, "\(slot.info)")
            }
        }
        // Other apps' items are recorded by frame only.
        for slot in slots where slot.kind == .thirdParty {
            #expect(slot.info.texts.isEmpty && slot.info.description == nil)
        }
        #expect(!MenuBarLiveActivityMonitor.dump().isEmpty)
    }

    @Test func inspectorMeasuresTheMenuBar() async {
        guard MenuBarInspector.isAvailable, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return }
        let notch = CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                           width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        let occupancy: MenuBarOccupancy? = await withCheckedContinuation { cont in
            MenuBarInspector.measure(notch: notch, screenFrame: screen.frame) { cont.resume(returning: $0) }
        }
        #expect(occupancy != nil)
        // The second measurement reuses the cached status-item owners.
        let again: MenuBarOccupancy? = await withCheckedContinuation { cont in
            MenuBarInspector.measure(notch: notch, screenFrame: screen.frame) { cont.resume(returning: $0) }
        }
        #expect(again?.rightObstacleMinX == occupancy?.rightObstacleMinX)
        if let r = occupancy?.rightObstacleMinX { #expect(r >= notch.maxX - 1) }
        if let l = occupancy?.leftObstacleMaxX { #expect(l <= notch.minX + 1) }
    }
}
