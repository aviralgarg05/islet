import AppKit
import Foundation
import IsletCore
import IsletSystem
import Observation

enum IslandTab: String, CaseIterable, Identifiable {
    case home, today, shelf, widgets, clipboard, stats
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .today: return "calendar"
        case .shelf: return "tray.full.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .stats: return "gauge.with.dots.needle.33percent"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .today: return "Today"
        case .shelf: return "Shelf"
        case .widgets: return "Widgets"
        case .clipboard: return "Clipboard"
        case .stats: return "System"
        }
    }
}

/// Everything the island shows. Views observe this; services and the local API write to it.
@MainActor
@Observable
final class AppModel {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0-dev"

    // State
    var settings: IsletSettings
    private(set) var center = ActivityCenter()
    private(set) var media = MediaArbiter()
    private(set) var nowPlaying: NowPlaying?
    private(set) var battery: BatteryState?
    private(set) var batteryEvent: BatteryEvent?
    private(set) var agenda: [AgendaItem] = []
    private(set) var reminders: [ReminderItem] = []
    private(set) var shelf = Shelf()
    private(set) var clipboard = ClipboardHistory()
    private(set) var stats: SystemStats?
    private(set) var plugins: [String: PluginResult] = [:]
    private(set) var micInUse = false
    private(set) var cameraInUse = false
    private(set) var outputDeviceName: String?

    /// Display the island is expanded on (nil = collapsed everywhere).
    var expandedScreen: CGDirectDisplayID?
    var tab: IslandTab = .home
    /// Displays covered by a fullscreen app, and that app.
    private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private(set) var frontBundleID: String?
    /// Bumped whenever time-driven state changes, so views re-evaluate the presentation.
    private(set) var tick = 0
    /// Bumped when a new activity arrives, driving the island's "bounce".
    private(set) var pulse = 0
    private(set) var isDraggingFile = false
    var apiStatus = "Starting…"
    var pinned = false
    /// Snapshot rendering pins the presentation instead of deriving it.
    var forcedPresentation: IslandPresentation?
    /// Measured closed-island placement per display, for the automatic layout.
    var closedPlacements: [CGDirectDisplayID: ClosedPlacement] = [:]

    // Services
    let shelfService = ShelfService()
    let battery_ = BatteryMonitor()
    let audio = AudioMonitor()
    let camera = CameraMonitor()
    let music = AppleMusicProvider()
    let spotify = SpotifyProvider()
    let systemMedia = SystemNowPlayingBridge()
    let fullscreen = FullscreenDetector()
    let calendar = CalendarService()
    let clipboardMonitor = ClipboardMonitor()
    let statsSampler = SystemStatsSampler()
    let micUsage = MicUsageMonitor()
    let notificationMirror = NotificationMirror()
    let downloads = DownloadsWatcher()
    let unlock = UnlockMonitor()
    let menuBarActivities = MenuBarLiveActivityMonitor()
    let agentUsage = AgentUsageModel()
    private var mirroredKeys: Set<String> = []
    private var mirrorClock = LiveActivityClock()
    /// Mirrored activity id → the menu bar item it came from. Clicking one presses that item;
    /// this never goes through a URL, so nothing outside Islet can trigger the press.
    private var mirroredActivityKeys: [String: String] = [:]

    /// Whether clicking the activity opens something.
    func canOpen(_ a: Activity) -> Bool { a.url != nil || mirroredActivityKeys[a.id] != nil }

    /// Open what an activity points to: a mirrored Live Activity's original item, or its link.
    func openActivity(_ a: Activity) {
        if let key = mirroredActivityKeys[a.id] {
            menuBarActivities.press(key: key)
        } else if let url = a.url {
            NSWorkspace.shared.open(url)
        }
    }
    private var calls = CallDetector()
    private var lastMicUsers: Set<String> = []
    private var lanServer: LocalAPIServer?
    /// One token for the loopback API and the LAN bridge, created once per launch
    /// (reusing the previous one so scripts that cached it keep working).
    @ObservationIgnored private lazy var apiToken = APIDiscoveryStore.loadOrCreateToken()
    var lanStatus = "Off"
    /// While the screen is locked: what happened, for the "welcome back" digest.
    private var lockedAt: Date?
    private var lockedDigest: [String: Int] = [:]
    private(set) var pluginRunner: ScriptPluginRunner?
    private var server: LocalAPIServer?
    private var deadlineTimer: Timer?
    private var batteryDetector = BatteryEventDetector()
    private var calendarTimer: Timer?
    private var alertedEvents: Set<String> = []
    private var settingsWatcher: DispatchSourceFileSystemObject?

    init(settings: IsletSettings = IsletSettings.load(from: IsletPaths.configFile)) {
        self.settings = settings
        shelf = shelfService.shelf
        clipboard = ClipboardHistory(limit: settings.clipboardLimit)
    }

    // MARK: Lifecycle

    func start() {
        Haptics.mode = settings.hapticFeedback ? settings.hapticsMode : .off
        media.disabled = Set(settings.disabledMediaSources)
        shelfService.onChange = { [weak self] s in self?.shelf = s }

        if settings.batteryEnabled {
            battery_.onChange = { [weak self] s in self?.ingestBattery(s) }
            battery_.start()
        }
        if settings.hudEnabled || settings.privacyIndicatorsEnabled {
            audio.onOutputChange = { [weak self] out in self?.volumeChanged(out) }
            audio.onMicrophoneInUse = { [weak self] inUse in self?.micInUse = inUse }
            audio.start()
            outputDeviceName = AudioMonitor.readOutput()?.deviceName
        }
        if settings.privacyIndicatorsEnabled {
            camera.onChange = { [weak self] on in
                self?.cameraInUse = on
                self?.updateCalls()
            }
            camera.start()
        }
        if settings.mediaEnabled { startMedia() }
        fullscreen.onChange = { [weak self] displays, bundle in
            self?.fullscreenDisplays = displays
            self?.frontBundleID = bundle
        }
        fullscreen.start()
        if settings.calendarEnabled && CalendarService.eventAccess == .granted
            || settings.remindersEnabled && CalendarService.reminderAccess == .granted { startCalendar() }
        if settings.clipboardEnabled { startClipboard() }
        if settings.pluginsEnabled { startPlugins() }
        if settings.apiEnabled { startAPI() }
        applyTiming()
        startEventSources()
        watchSettingsFile()
    }

    /// iPhone-style event sources that depend on settings; safe to call again after changes.
    func startEventSources() {
        if settings.callDetection {
            micUsage.onChange = { [weak self] users in
                self?.lastMicUsers = users
                self?.updateCalls()
            }
            micUsage.start()
        } else {
            micUsage.stop()
            for id in calls.active.keys.map(CallDetector.activityID) { remove(activityID: id) }
            calls = CallDetector()
        }
        if settings.notificationMirroring {
            notificationMirror.onNotification = { [weak self] n in self?.mirrored(n) }
            notificationMirror.start()
        } else {
            notificationMirror.stop()
        }
        if settings.downloadsEnabled {
            downloads.onEvent = { [weak self] e in self?.downloadEvent(e) }
            downloads.start()
        } else {
            downloads.stop()
        }
        unlock.onLock = { [weak self] in
            self?.lockedAt = Date()
            self?.lockedDigest = [:]
        }
        unlock.onUnlock = { [weak self] in self?.welcomeBack() }
        if settings.unlockSplash { unlock.start() } else { unlock.stop() }
        if settings.apiEnabled && settings.lanBridgeEnabled { startLAN() } else { stopLAN() }
        if settings.mirrorMenuBarActivities && MenuBarLiveActivityMonitor.isAvailable {
            menuBarActivities.onChange = { [weak self] list in self?.syncMenuBarActivities(list) }
            menuBarActivities.knownApp = { $0.count <= 24 && LiveActivityCatalog.look(for: $0) != nil }
            menuBarActivities.onStructureChange = { NotificationCenter.default.post(name: .isletMenuBarChanged, object: nil) }
            menuBarActivities.start()
        } else {
            menuBarActivities.stop()
            syncMenuBarActivities([])
        }
        agentUsage.apply(settings) { [weak self] spec in _ = try? self?.applyLocal(spec) }
    }

    /// Show the menu bar's Live Activities (iPhone and Mac) as island activities.
    private func syncMenuBarActivities(_ all: [MirroredLiveActivity]) {
        let list = settings.mirrorOnlyHiddenActivities ? all.filter(\.hidden) : all
        let keys = Set(list.map(\.key))
        for key in mirroredKeys.subtracting(keys) {
            let id = MenuBarLiveActivities.activityID(key)
            remove(activityID: id)
            mirroredActivityKeys[id] = nil
            mirrorClock.forget(key)
        }
        let now = Date()
        for m in list {
            let look = LiveActivityCatalog.look(for: m.appName).map { ($0.symbol, $0.tint) }
            let clock = mirrorClock.update(key: m.key, detail: m.detail, now: now)
            let spec = MenuBarLiveActivities.activity(for: m, look: look, isNew: !mirroredKeys.contains(m.key), clock: clock)
            mirroredActivityKeys[MenuBarLiveActivities.activityID(m.key)] = m.key
            _ = try? applyLocal(spec)
        }
        mirroredKeys = keys
    }

    func applyTiming() {
        center.sneakDuration = settings.alertDuration
        center.hudDuration = settings.hudDuration
    }

    func stop() {
        guard server != nil else { return }
        server?.stop()
        APIDiscoveryStore.remove()
    }

    private func startMedia() {
        systemMedia.onUpdate = { [weak self] np in self?.mediaUpdate(np, source: .system) }
        systemMedia.onUnavailable = { [weak self] reason in
            // Fall back to per-player integrations with AppleScript enrichment.
            NSLog("Islet: %@", reason)
            self?.music.enrich = true
            self?.spotify.enrich = true
        }
        systemMedia.start()
        for p in [music, spotify] as [ScriptablePlayerProvider] {
            p.enrich = !systemMedia.isRunning
            p.onUpdate = { [weak self, source = p.source] np in self?.mediaUpdate(np, source: source) }
            p.start()
        }
    }

    func startCalendar() {
        calendar.includeReminders = settings.remindersEnabled
        calendar.onAgenda = { [weak self] items in
            self?.agenda = items
            self?.checkCalendarAlerts()
        }
        calendar.onReminders = { [weak self] items in
            self?.reminders = items
            self?.checkCalendarAlerts()
        }
        calendar.start()
        calendarTimer?.invalidate()
        // Re-check upcoming events once a minute (tolerant timer; calendar data itself is event-driven).
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCalendarAlerts() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        calendarTimer = t
    }

    func requestReminderAccess() {
        calendar.requestReminderAccess { [weak self] granted in
            guard let self, granted else { return }
            self.settings.remindersEnabled = true
            self.saveSettings()
            self.startCalendar()
        }
    }

    /// Events from calendars the user hasn't hidden.
    var visibleAgenda: [AgendaItem] { Agenda.visible(agenda, hiding: Set(settings.hiddenCalendars)) }

    func completeReminder(_ id: String) {
        Haptics.play(.tap)
        if calendar.complete(reminderID: id) { reminders.removeAll { $0.id == id } }
    }

    var dueReminders: [ReminderItem] { settings.remindersEnabled ? Reminders.dueSoon(reminders, now: Date()) : [] }

    func requestCalendarAccess() {
        calendar.requestAccess { [weak self] granted in
            guard let self else { return }
            if granted {
                self.settings.calendarEnabled = true
                self.saveSettings()
                self.startCalendar()
            }
        }
    }

    private func startClipboard() {
        clipboardMonitor.onCopy = { [weak self] text, types, bundle in
            self?.clipboard.add(text, types: types, sourceBundleID: bundle, now: Date())
        }
        clipboardMonitor.start()
    }

    private func startPlugins() {
        let dir = settings.pluginDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? IsletPaths.pluginsDirectory
        let runner = ScriptPluginRunner(directory: dir)
        runner.onResult = { [weak self] r in self?.pluginFinished(r) }
        runner.onRemoved = { [weak self] path in
            self?.plugins[path] = nil
            self?.remove(activityID: "plugin-" + ScriptPlugins.displayName(fromFileName: (path as NSString).lastPathComponent))
        }
        runner.start()
        pluginRunner = runner
    }

    private func startAPI() {
        let token = apiToken
        let router = APIRouter(token: token, version: Self.version, backend: self)
        let server = LocalAPIServer(router: router)
        self.server = server
        let preferred = UInt16(settings.apiPort)
        server.start(port: preferred) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let port):
                    self?.apiReady(port: port, token: token)
                case .failure:
                    // Port taken: fall back to an ephemeral port; clients read it from the discovery file.
                    server.start(port: 0) { r in
                        DispatchQueue.main.async {
                            if case .success(let p) = r { self?.apiReady(port: p, token: token) } else { self?.apiStatus = "Could not start API" }
                        }
                    }
                }
            }
        }
    }

    private func apiReady(port: UInt16, token: String) {
        apiStatus = "Listening on 127.0.0.1:\(port)"
        try? APIDiscoveryStore.write(APIDiscovery(port: Int(port), token: token, pid: ProcessInfo.processInfo.processIdentifier))
    }

    // MARK: Settings

    func saveSettings() {
        try? settings.save(to: IsletPaths.configFile)
    }

    /// Live-reload `config.json` when edited by hand or synced from dotfiles. Watches the
    /// folder (editors that save by atomic rename) and the file itself (in-place writes).
    private func watchSettingsFile() {
        let url = IsletPaths.configFile
        if !FileManager.default.fileExists(atPath: url.path) { saveSettings() }
        let dirFD = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let dir = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write, .rename], queue: .main)
        dir.setEventHandler { [weak self] in
            self?.reloadSettingsFromDisk()
            self?.watchConfigFileItself()
        }
        dir.setCancelHandler { close(dirFD) }
        dir.resume()
        settingsWatcher = dir
        watchConfigFileItself()
    }

    private var fileWatcher: DispatchSourceFileSystemObject?

    private func watchConfigFileItself() {
        fileWatcher?.cancel()
        let fd = open(IsletPaths.configFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            self?.reloadSettingsFromDisk()
            if let data = self?.fileWatcher?.data, !data.isDisjoint(with: [.delete, .rename]) { self?.watchConfigFileItself() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatcher = src
    }

    private func reloadSettingsFromDisk() {
        let fresh = IsletSettings.load(from: IsletPaths.configFile)
        guard fresh != settings else { return }
        settings = fresh
        media.disabled = Set(fresh.disabledMediaSources)
        clipboard.limit = fresh.clipboardLimit
        Haptics.mode = fresh.hapticFeedback ? fresh.hapticsMode : .off
        applyTiming()
        startEventSources()
        NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
    }

    // MARK: Presentation

    func presentation(for display: CGDirectDisplayID) -> IslandPresentation {
        _ = tick
        if let forcedPresentation { return forcedPresentation }
        let now = Date()
        var suppressed = false
        let frontRule = settings.rule(for: frontBundleID)
        if settings.hideInFullscreen, fullscreenDisplays.contains(display) {
            let allowed = (frontBundleID.map(settings.fullscreenAllowList.contains) ?? false) || frontRule?.showInFullscreen == true
            suppressed = !allowed
        }
        if let front = frontBundleID, settings.hideForApps.contains(front) || frontRule?.hideIsland == true { suppressed = true }
        let inputs = PresenterInputs(
            now: now,
            center: center,
            nowPlaying: settings.mediaEnabled ? nowPlaying : nil,
            batteryEvent: batteryEvent,
            isExpanded: expandedScreen == display || (isDraggingFile && expandedScreen == display),
            isSuppressed: suppressed && expandedScreen != display,
            showPausedMedia: settings.showPausedMedia
        )
        return Presenter.present(inputs)
    }

    var activities: [Activity] { center.ordered(now: Date()) }

    /// How the closed island lays out on a display: the user's choice, or the measured
    /// automatic placement (drop below the notch until the menu bar has been measured).
    func placement(for display: CGDirectDisplayID, metrics: IslandMetrics) -> ClosedPlacement {
        let preference = settings.closedLayout
        guard preference == .auto else { return .unmeasured(preference, wing: metrics.wingWidth, hasMenuBar: true) }
        return closedPlacements[display] ?? .unmeasured(.auto, wing: metrics.wingWidth, hasMenuBar: true)
    }

    var upcomingEvent: AgendaItem? { settings.calendarEnabled ? Agenda.upcoming(visibleAgenda, now: Date()) : nil }

    /// Displays that have an island, notched ones first. Set when panels are rebuilt.
    var islandDisplays: [CGDirectDisplayID] = []

    /// Where the island opens when asked from a hotkey, the menu, a URL or the API: the display
    /// under the pointer if it has one, otherwise the first (notched) one.
    func targetDisplay() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        if let under = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.displayID, islandDisplays.contains(under) {
            return under
        }
        return islandDisplays.first
    }

    func setExpanded(_ display: CGDirectDisplayID?) {
        guard expandedScreen != display else { return }
        expandedScreen = display
        DispatchQueue.main.async { NotificationCenter.default.post(name: .isletLayoutChanged, object: nil) }
        if display != nil {
            center.cancelSneak()
            Haptics.play(.open)
            if tab == .stats { statsSampler.start() }
        } else {
            statsSampler.stop()
            pinned = false
        }
    }

    func select(tab: IslandTab) {
        self.tab = tab
        if tab == .stats {
            statsSampler.onSample = { [weak self] s in self?.stats = s }
            statsSampler.start()
        } else {
            statsSampler.stop()
        }
    }

    func setDraggingFile(_ dragging: Bool) { isDraggingFile = dragging }

    func setPlugins(_ results: [PluginResult]) {
        plugins = Dictionary(uniqueKeysWithValues: results.map { ($0.path, $0) })
    }

    func setDemoBatteryEvent(_ ev: BatteryEvent) { batteryEvent = ev }

    func clearNowPlayingForSnapshot() { nowPlaying = nil }

    // MARK: Time

    /// Schedule exactly one timer for the next state change instead of polling.
    private func reschedule() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        var candidates: [Date] = []
        if let d = center.nextDeadline(now: Date()) { candidates.append(d) }
        if let b = batteryEvent { candidates.append(b.until) }
        guard let next = candidates.min() else { return }
        let t = Timer(fire: next.addingTimeInterval(0.01), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.expireNow() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        deadlineTimer = t
    }

    private func expireNow() {
        let now = Date()
        center.expire(now: now)
        if let b = batteryEvent, b.until <= now { batteryEvent = nil }
        tick &+= 1
        reschedule()
    }

    // MARK: Inputs

    private func ingestBattery(_ s: BatteryState) {
        battery = s
        if let ev = batteryDetector.ingest(s, now: Date()) {
            if ev.kind != .lowPowerOn && ev.kind != .lowPowerOff { batteryEvent = ev }
            let batterySettings = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
            switch ev.kind {
            case .critical, .low:
                _ = try? commit(ActivitySpec(
                    id: "battery-low", source: "battery", title: "Battery at \(s.level)%",
                    subtitle: s.lowPowerMode ? "Low Power Mode is on" : "Plug in soon, or turn on Low Power Mode",
                    icon: .symbol(ev.kind == .critical ? "battery.0percent" : "battery.25percent"), state: .warning,
                    tint: "red", priority: ev.kind == .critical ? .critical : .high, ttl: ev.kind == .critical ? 0 : 6,
                    url: batterySettings,
                    actions: [ActivityAction(title: "Battery Settings", url: batterySettings)], sneak: true
                ))
            case .lowPowerOn, .lowPowerOff:
                let on = ev.kind == .lowPowerOn
                _ = try? commit(ActivitySpec(
                    id: "low-power", source: "battery", title: "Low Power Mode", icon: .symbol(on ? "battery.25percent" : "battery.75percent"),
                    trailing: on ? "On" : "Off", state: .info, tint: on ? "yellow" : "gray", priority: .normal, ttl: 2.5, sneak: true
                ))
            case .pluggedIn:
                remove(activityID: "battery-low")
            default:
                break
            }
            reschedule()
        }
    }

    private func volumeChanged(_ out: AudioMonitor.Output) {
        let deviceChanged = out.deviceName != outputDeviceName
        outputDeviceName = out.deviceName
        guard settings.hudEnabled else { return }
        if deviceChanged, let name = out.deviceName {
            let bt = AudioMonitor.isBluetooth(AudioMonitor.defaultDevice(input: false))
            _ = try? commit(ActivitySpec(
                id: "audio-route", source: "audio", title: name, subtitle: bt ? "Connected" : "Audio output",
                icon: .symbol(Self.symbol(forDevice: name, bluetooth: bt)), state: .info, tint: "blue",
                priority: .normal, ttl: 3, sneak: true
            ))
        } else {
            center.showHUD(.volume, value: out.volume, muted: out.muted, label: out.deviceName, now: Date())
        }
        reschedule()
    }

    static func symbol(forDevice name: String, bluetooth: Bool) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("homepod") { return "homepod.fill" }
        if n.contains("headphone") || n.contains("buds") || bluetooth { return "headphones" }
        if n.contains("display") || n.contains("hdmi") || n.contains("tv") { return "tv" }
        return "speaker.wave.2.fill"
    }

    private func mediaUpdate(_ np: NowPlaying?, source: MediaSourceKind) {
        if let np { media.update(np) } else { media.clear(source) }
        let next = media.current(now: Date())
        if next != nowPlaying { nowPlaying = next }
    }

    private func pluginFinished(_ r: PluginResult) {
        plugins[r.path] = r
        if case .activity(var spec) = r.output {
            spec.id = spec.id ?? "plugin-\(r.name)"
            spec.source = spec.source ?? "plugin:\(r.name)"
            if spec.sneak == nil { spec.sneak = false }
            _ = try? applyLocal(spec)
        }
    }

    private func checkCalendarAlerts() {
        let now = Date()
        if settings.calendarEnabled {
            for item in visibleAgenda where Agenda.shouldAlert(item, now: now) && !alertedEvents.contains(item.id) {
                alertedEvents.insert(item.id)
                _ = try? applyLocal(Agenda.activity(for: item, now: now))
            }
        }
        if settings.remindersEnabled {
            for r in reminders where Reminders.shouldAlert(r, now: now) && !alertedEvents.contains("r:" + r.id) {
                alertedEvents.insert("r:" + r.id)
                _ = try? applyLocal(Reminders.activity(for: r))
            }
        }
        tick &+= 1
    }

    @discardableResult
    func applyLocal(_ spec: ActivitySpec) throws -> Activity? {
        if let source = spec.source, settings.mutedSources.contains(source) { return nil }
        return try commit(spec)
    }

    /// Apply a spec and react like the iPhone does when something new arrives:
    /// bounce the island and, for things that need you, tap the trackpad.
    @discardableResult
    func commit(_ spec: ActivitySpec) throws -> Activity {
        let now = Date()
        let before = center.sneak
        let a = try center.apply(spec, now: now)
        if let after = center.sneak, after.id != before?.id || after.until != before?.until {
            pulse &+= 1
            if a.state == .waiting || a.priority >= .high { Haptics.play(.alert) }
        }
        if lockedAt != nil { lockedDigest[a.source, default: 0] += 1 }
        reschedule()
        refineIcon(a)
        return a
    }

    /// Ask the on-device model for an icon when neither the sender nor the keyword rules chose one.
    private func refineIcon(_ a: Activity) {
        guard settings.smartIcons, settings.aiAssist, a.icon == nil,
              SmartIcon.suggest(title: a.title, subtitle: a.subtitle, source: a.source) == nil,
              AIAssist.shared.isAvailable else { return }
        let text = [a.title, a.subtitle].compactMap { $0 }.joined(separator: " — ")
        AIAssist.shared.suggestSymbol(for: text) { [weak self] symbol in
            guard let self, let symbol, self.center.activities[a.id]?.icon == nil else { return }
            _ = try? self.center.apply(ActivitySpec(id: a.id, icon: .symbol(symbol), sneak: false), now: Date())
            self.tick &+= 1
        }
    }

    // MARK: iPhone-style events

    private func updateCalls() {
        for change in calls.update(micUsers: lastMicUsers, cameraOn: cameraInUse, now: Date()) {
            switch change {
            case .started(let spec), .updated(let spec): _ = try? applyLocal(spec)
            case .ended(let id): remove(activityID: id)
            }
        }
    }

    private func mirrored(_ n: MirroredNotification) {
        let rule = settings.rule(for: n.bundleID)
        if rule?.muteNotifications == true { return }
        guard let a = try? applyLocal(n.activity(rule: rule)) else { return }
        if settings.aiAssist, let body = n.body, body.count > 90 {
            AIAssist.shared.summarize(body) { [weak self] summary in
                guard let summary else { return }
                _ = try? self?.center.apply(ActivitySpec(id: a.id, subtitle: summary, sneak: false), now: Date())
                self?.tick &+= 1
            }
        }
    }

    private func downloadEvent(_ e: DownloadTracker.Event) {
        switch e {
        case .progress(let spec):
            _ = try? applyLocal(spec)
        case .finished(var spec, let name):
            let file = downloads.directory.appendingPathComponent(name)
            spec.url = file
            spec.actions = [ActivityAction(title: "Open", url: file), ActivityAction(title: "Show", url: downloads.directory)]
            _ = try? applyLocal(spec)
        case .vanished(let id):
            remove(activityID: id)
        }
    }

    private func welcomeBack() {
        defer {
            lockedAt = nil
            lockedDigest = [:]
        }
        guard let since = lockedAt, Date().timeIntervalSince(since) > 60 else { return }
        let total = lockedDigest.values.reduce(0, +)
        let summary = total == 0 ? "Nothing new while you were away"
            : lockedDigest.sorted { $0.value > $1.value }.prefix(3)
                .map { "\($0.value) from \(Self.friendlySource($0.key))" }.joined(separator: " · ")
        _ = try? commit(ActivitySpec(
            id: "welcome-back", source: "system", title: "Welcome back", subtitle: summary,
            icon: .symbol("lock.open.fill"), state: .info, tint: "white", priority: .normal, ttl: 4, sneak: true
        ))
    }

    static func friendlySource(_ source: String) -> String {
        if source.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return source
    }

    /// Silence a source: remove its activities now and ignore it from now on.
    func mute(source: String) {
        if !settings.mutedSources.contains(source) { settings.mutedSources.append(source) }
        center.removeAll(source: source)
        saveSettings()
        reschedule()
    }

    private func startLAN() {
        guard lanServer == nil else { return }
        let token = apiToken
        let server = LocalAPIServer(router: APIRouter(token: token, version: Self.version, backend: self, allowRemoteHosts: true))
        server.rateLimiter = RateLimiter(limit: 30, window: 10)
        lanServer = server
        let port = UInt16(settings.lanPort)
        server.start(port: port, onAllInterfaces: true, bonjourName: Host.current().localizedName ?? "Islet") { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let p): self?.lanStatus = "Listening on \(ProcessInfo.processInfo.hostName):\(p)"
                case .failure(let e): self?.lanStatus = "Could not listen: \(e.localizedDescription)"
                }
            }
        }
    }

    private func stopLAN() {
        lanServer?.stop()
        lanServer = nil
        lanStatus = "Off"
    }

    func remove(activityID: String) {
        center.remove(id: activityID)
        reschedule()
    }

    func perform(_ action: ActivityAction, activityID: String) {
        if let url = action.url { NSWorkspace.shared.open(url) }
        if action.dismiss ?? true { remove(activityID: activityID) }
    }

    // MARK: Media control

    @discardableResult
    func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        // The bridge controls whatever macOS considers "now playing" without Automation prompts.
        if systemMedia.isRunning, systemMedia.send(command, position: position) { return true }
        guard let np = nowPlaying else { return false }
        switch np.source {
        case .spotify: return spotify.send(command, position: position)
        case .appleMusic: return music.send(command, position: position)
        case .system, .browser: return systemMedia.send(command, position: position)
        case .external: return systemMedia.send(command, position: position)
        }
    }

    func openPlayer() {
        guard let bundle = nowPlaying?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Shelf / clipboard

    func addToShelf(_ urls: [URL]) {
        Haptics.play(.drop)
        shelfService.add(urls: urls)
        _ = try? applyLocal(ActivitySpec(
            id: "shelf-add", source: "shelf", title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files",
            subtitle: "Added to shelf", icon: .symbol("tray.and.arrow.down.fill"), state: .success, tint: "blue",
            priority: .low, ttl: 2, sneak: false
        ))
    }

    func removeFromShelf(_ id: String) { shelfService.remove(id: id) }
    func clearShelf() { shelfService.removeAll() }

    func copyClip(_ entry: ClipboardEntry) {
        clipboardMonitor.copy(entry.text)
        clipboard.add(entry.text, types: [], sourceBundleID: entry.sourceBundleID, now: Date())
    }

    func togglePinClip(_ id: String) { clipboard.togglePin(id: id) }
    func removeClip(_ id: String) { clipboard.remove(id: id) }
    func clearClipboard() { clipboard.clear() }

    func runPlugin(_ path: String) { pluginRunner?.runNow(path: path) }

    // MARK: Demo content (used by --demo and snapshot rendering)

    func loadDemo(includeActivities: Bool = true) {
        let now = Date()
        nowPlaying = NowPlaying(
            source: .spotify, bundleID: "com.spotify.client", appName: "Spotify", title: "Midnight City",
            artist: "M83", album: "Hurry Up, We're Dreaming", isPlaying: true, duration: 243, elapsed: 71, timestamp: now
        )
        battery = BatteryState(level: 76, isCharging: true, isPluggedIn: true, minutesRemaining: 48)
        reminders = [
            ReminderItem(id: "r1", title: "Send the invoice", due: now.addingTimeInterval(-1800), listColor: "#FF9F0A", listTitle: "Work", priority: 1),
            ReminderItem(id: "r2", title: "Book dentist", due: now.addingTimeInterval(5400), listColor: "#0A84FF", listTitle: "Personal"),
            ReminderItem(id: "r3", title: "Water the plants", due: Calendar.current.startOfDay(for: now), isAllDay: true, listColor: "#30D158", listTitle: "Home"),
        ]
        agenda = [AgendaItem(id: "demo", title: "Design review", start: now.addingTimeInterval(22 * 60), end: now.addingTimeInterval(52 * 60),
                             calendarColor: "#FF9F0A", meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")),
                  AgendaItem(id: "demo2", title: "1:1 with Sam", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(3.5 * 3600),
                             calendarColor: "#BF5AF2"),
                  AgendaItem(id: "demo3", title: "Deadline: proposal", start: Calendar.current.startOfDay(for: now),
                             end: Calendar.current.startOfDay(for: now).addingTimeInterval(86400), isAllDay: true, calendarColor: "#FF453A")]
        if includeActivities {
        _ = try? center.apply(ActivitySpec(id: "build", source: "ci", title: "Release build", subtitle: "Compiling 142/310",
                                           icon: .symbol("hammer.fill"), progress: 0.46, state: .running, tint: "orange", sneak: false), now: now)
        _ = try? center.apply(ActivitySpec(id: "claude-demo", source: "claude-code", title: "Claude · islet", subtitle: "Running swift test",
                                           icon: .symbol("sparkle"), progress: -1, state: .running, tint: "#D97757", sneak: false), now: now)
        }
        shelfService.add(urls: [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                URL(fileURLWithPath: "/etc/hosts")])
        clipboard.add("https://example.com/islet", types: [], sourceBundleID: "com.apple.Safari", now: now)
        clipboard.add("swift test --parallel", types: [], sourceBundleID: "com.apple.Terminal", now: now)
        stats = SystemStats(cpu: 0.23, memoryUsed: 11_800_000_000, memoryTotal: 18_000_000_000)
        tick &+= 1
    }
}

extension Notification.Name {
    static let isletSettingsChanged = Notification.Name("IsletSettingsChanged")
}

// MARK: - Local API backend

extension AppModel: IsletBackend {
    nonisolated func listActivities() async -> [Activity] {
        await MainActor.run { self.sharedActivities }
    }

    /// Activities as the API reports them: mirrored Live Activities only when the user allows it.
    private var sharedActivities: [Activity] {
        settings.shareMirroredActivities ? activities : activities.filter { $0.source != MenuBarLiveActivities.source }
    }

    nonisolated func applyActivity(_ spec: ActivitySpec) async throws -> Activity {
        try await MainActor.run {
            if let source = spec.source, self.settings.mutedSources.contains(source) {
                // Validate and echo back, but show nothing: muted scripts shouldn't error out.
                var scratch = ActivityCenter()
                return try scratch.apply(spec, now: Date())
            }
            return try self.commit(spec)
        }
    }

    nonisolated func removeActivity(id: String) async -> Bool {
        await MainActor.run {
            let removed = self.center.remove(id: id) != nil
            self.reschedule()
            return removed
        }
    }

    nonisolated func removeActivities(source: String) async -> Int {
        await MainActor.run {
            let n = self.center.removeAll(source: source)
            self.reschedule()
            return n
        }
    }

    nonisolated func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async {
        await MainActor.run {
            self.center.showHUD(kind, value: value, muted: muted, label: label, now: Date())
            self.reschedule()
        }
    }

    nonisolated func pushMedia(_ media: NowPlaying?) async {
        await MainActor.run { self.mediaUpdate(media, source: .external) }
    }

    nonisolated func mediaCommand(_ command: PlaybackCommand, position: Double?) async -> Bool {
        await MainActor.run { self.send(command, position: position) }
    }

    nonisolated func setExpanded(_ expanded: Bool) async {
        await MainActor.run {
            self.pinned = expanded
            self.setExpanded(expanded ? self.targetDisplay() : nil)
        }
    }

    nonisolated func menuBarItems() async -> [MenuBarItemInfo] {
        MenuBarLiveActivityMonitor.dump()
    }

    nonisolated func stateSnapshot() async -> StateSnapshot {
        await MainActor.run {
            let display = self.expandedScreen ?? NSScreen.main?.displayID ?? 0
            return StateSnapshot(
                version: Self.version,
                presentation: String(describing: self.presentation(for: display)).components(separatedBy: "(").first ?? "",
                activities: self.sharedActivities,
                nowPlaying: self.nowPlaying.map { NowPlayingSummary($0, now: Date()) },
                battery: self.battery
            )
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
