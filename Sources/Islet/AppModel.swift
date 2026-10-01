import AppKit
import Foundation
import IsletCore
import IsletSystem
import Observation

enum IslandTab: String, CaseIterable, Identifiable {
    case home, today, shelf, widgets, clipboard, stats
    case ask
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .today: return "calendar"
        case .shelf: return "tray.full.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .stats: return "gauge.with.dots.needle.33percent"
        case .ask: return "sparkles"
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
        case .ask: return "Ask"
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
    /// When a new song shows for a moment below the notch.
    private(set) var songPeek = SongPeek()
    /// When the music was paused, so the closed island keeps it for `pausedMusicTimeout`.
    private(set) var pausedMusic = PausedMusic()
    /// Play or pause just clicked, shown before the player confirms it.
    private var playbackIntent: PlaybackIntent?

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
    let controls = IslandControls()
    @ObservationIgnored lazy var timers = TimerController(model: self)
    /// Coding-agent approval cards (ApprovalController.swift).
    @ObservationIgnored lazy var approvals = ApprovalController(model: self)
    let ask: AskController
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
    /// The iPhone bridge, with its own token (LANBridge.swift).
    let lan = LANBridge()
    /// The loopback API's token, created once per launch
    /// (reusing the previous one so scripts that cached it keep working).
    @ObservationIgnored private lazy var apiToken = APIDiscoveryStore.loadOrCreateToken()
    /// While the screen is locked: what happened, for the "welcome back" digest.
    private var lockedAt: Date?
    private var lockedDigest: [String: Int] = [:]
    private(set) var pluginRunner: ScriptPluginRunner?
    private var server: LocalAPIServer?
    private var deadlineTimer: Timer?
    private var batteryDetector = BatteryEventDetector()
    private var calendarTimer: Timer?
    private var dayObserver: NSObjectProtocol?
    /// What `applyModules()` has started.
    private var modules = RunningModules()
    /// Calendar and reminder alerts already shown, by occurrence, with when they were for.
    private var alertedEvents: [String: Date] = [:]
    /// Activities already sent to the on-device model for an icon.
    private var iconAttempts: Set<String> = []
    private var settingsWatcher: DispatchSourceFileSystemObject?

    /// `ask` is replaceable so Settings snapshots keep API keys in memory instead of the Keychain.
    init(settings: IsletSettings = IsletSettings.load(from: IsletPaths.configFile), ask: AskController? = nil) {
        self.settings = settings
        self.ask = ask ?? AskController()
        shelf = shelfService.shelf
        clipboard = ClipboardHistory(limit: settings.clipboardLimit)
    }

    // MARK: Lifecycle

    func start() {
        Haptics.mode = settings.hapticsMode
        media.disabled = Set(settings.disabledMediaSources)
        shelfService.onChange = { [weak self] s in self?.shelf = s }

        fullscreen.onChange = { [weak self] displays, bundle in
            self?.fullscreenDisplays = displays
            self?.frontBundleID = bundle
        }
        fullscreen.start()
        applyTiming()
        timers.start()
        startEventSources()
        watchSettingsFile()
    }

    /// Everything that depends on settings; safe to call again after changes.
    func startEventSources() {
        applyModules()
        if settings.callDetection {
            micUsage.onChange = { [weak self] users in
                self?.lastMicUsers = users
                self?.updateCalls()
            }
            micUsage.start()
        } else {
            micUsage.stop()
            lastMicUsers = []
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
            let id = MenuBarLiveActivities.activityID(m.key)
            mirroredActivityKeys[id] = m.key
            // A spec can't clear a date: once the item shows no time at all, stop the clock Islet
            // animated, or the wing would keep counting.
            if m.detail.flatMap(MenuBarLiveActivities.clockSeconds(in:)) == nil { center.clearClock(id: id) }
            _ = try? applyLocal(spec)
        }
        mirroredKeys = keys
    }

    func applyTiming() {
        center.sneakDuration = settings.alertDuration
        center.hudDuration = settings.hudDuration
        // "Hide paused music after" may have moved the moment paused music goes.
        reschedule()
    }

    func stop() {
        releaseKeepAwake()
        ask.stop()  // Quitting stops a running claude/codex rather than leaving it behind.
        guard server != nil else { return }
        server?.stop()
        APIDiscoveryStore.remove()
    }

    private func startMedia() {
        systemMedia.onUpdate = { [weak self] np in self?.mediaUpdate(np, source: .system) }
        systemMedia.onUnavailable = { [weak self] reason in
            // Fall back to per-player enrichment. It uses AppleScript only where Automation is
            // already allowed, so this never brings up the prompt; Settings → Permissions does.
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
        // The agenda covers today and tomorrow; roll it forward when the day changes.
        if dayObserver == nil {
            dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.calendar.refresh() }
            }
        }
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

    private static var pendingSettingsCommit: DispatchWorkItem?

    /// A change made in the Settings window. Dragging a slider or typing a shortcut produces a
    /// change per step, so saving and applying wait for a quarter of a second of quiet.
    func settingsEdited() {
        Self.pendingSettingsCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.saveSettings()
                NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
            }
        }
        Self.pendingSettingsCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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
        // The app delegate applies the rest (modules, media sources, clipboard size, hotkey, panels)
        // on this notification.
        NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
    }

    // MARK: Presentation

    func presentation(for display: CGDirectDisplayID) -> IslandPresentation {
        _ = tick
        if let forcedPresentation { return forcedPresentation }
        let now = Date()
        let showsMedia = settings.mediaEnabled
        let inputs = PresenterInputs(
            now: now,
            center: center,
            nowPlaying: showsMedia ? nowPlaying : nil,
            batteryEvent: batteryEvent,
            isExpanded: expandedScreen == display || (isDraggingFile && expandedScreen == display),
            isSuppressed: isSuppressed(display) && expandedScreen != display,
            pausedMedia: showsMedia ? pausedMusic.show(timeout: settings.pausedMusicTimeout, now: now) : .hidden,
            focusedActivityID: controls.focusedActivityID,
            songPeek: showsMedia && settings.songChangePeek ? songPeek.current(now: now) : nil
        )
        return Presenter.present(inputs)
    }

    /// The island on `display` gets out of the way: a fullscreen app is in front (unless its
    /// rule keeps the island), or the front app's rule hides it.
    func isSuppressed(_ display: CGDirectDisplayID) -> Bool {
        let frontRule = settings.rule(for: frontBundleID)
        if frontRule?.hideIsland == true { return true }
        return settings.hideInFullscreen && fullscreenDisplays.contains(display) && frontRule?.showInFullscreen != true
    }

    /// What the island is doing, for deciding whether a new song may show.
    private func songPeekContext(now: Date) -> SongPeek.Context {
        SongPeek.Context(
            enabled: settings.mediaEnabled && settings.songChangePeek,
            isOpen: expandedScreen != nil,
            isHidden: !islandDisplays.isEmpty && islandDisplays.allSatisfy(isSuppressed),
            isBusy: center.currentHUD(now: now) != nil || center.currentSneak(now: now) != nil
        )
    }

    var activities: [Activity] { center.ordered(now: Date()) }

    /// How wide the closed island's wings are on a display: always full width, or the measured
    /// automatic placement (narrow wings, at most `MenuBarLayoutEngine.unmeasuredWing`, until the
    /// menu bar has been measured).
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
        if let under = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.displayID, islandDisplays.contains(under) {
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
            songPeek.cancel()
            agentUsage.refreshClaudeHint()
            Haptics.play(.open)
            if tab == .stats && settings.systemStatsEnabled { statsSampler.start() }
        } else {
            statsSampler.stop()
            pinned = false
            ask.islandDidCollapse()
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
        let now = Date()
        var candidates: [Date] = []
        if let d = center.nextDeadline(now: now) { candidates.append(d) }
        if let d = media.nextDeadline(now: now) { candidates.append(d) }
        if let d = songPeek.nextDeadline(now: now) { candidates.append(d) }
        if let d = pausedMusic.nextDeadline(timeout: settings.pausedMusicTimeout, now: now) { candidates.append(d) }
        if let i = playbackIntent { candidates.append(max(now, i.expires)) }
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
        // A paused player timed out: show whatever is left, or nothing. A track that ran past
        // its end shows as stopped, and a click the player never confirmed shows its real state.
        // (With no player reporting there is nothing to work out, and the demo's song stays.)
        if media.expire(now: now) || !media.snapshots.isEmpty {
            setNowPlaying(media.current(now: now), now: now)
        }
        songPeek.advance(now: now, context: songPeekContext(now: now))
        tick &+= 1
        reschedule()
    }

    /// The one way `nowPlaying` changes, so a new song can be shown for a moment and a pause
    /// can stay in view. A play or pause just clicked shows until the player catches up.
    private func setNowPlaying(_ reported: NowPlaying?, now: Date) {
        var next = reported
        if let intent = playbackIntent {
            if intent.isSettled(by: reported, now: now) {
                playbackIntent = nil
            } else if let r = reported {
                next = intent.applied(to: r, now: now)
            }
        }
        guard next != nowPlaying else { return }
        nowPlaying = next
        songPeek.ingest(next, now: now)
        pausedMusic.ingest(next, now: now)
    }

    // MARK: Inputs

    private func ingestBattery(_ s: BatteryState) {
        battery = s
        keepAwakeBatteryChanged(s)
        batteryDetector.configure(with: settings)
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
                    actions: [ActivityAction(title: "Battery settings", url: batterySettings)], sneak: true
                ))
            case .lowPowerOn, .lowPowerOff:
                let on = ev.kind == .lowPowerOn
                _ = try? commit(ActivitySpec(
                    id: "low-power", source: "battery", title: "Low Power Mode", icon: .symbol(on ? "battery.25percent" : "battery.75percent"),
                    trailing: on ? "On" : "Off", state: .info, tint: on ? "yellow" : "gray", priority: .normal, ttl: 2.5, sneak: true
                ))
            case .pluggedIn:
                remove(activityID: "battery-low")
            case .charged:
                announceCharged(s)
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
        if source == .system {
            // The bridge files browsers under .browser; each report replaces both kinds.
            media.updateFromBridge(np)
        } else if let np { media.update(np) } else { media.clear(source) }
        let now = Date()
        setNowPlaying(media.current(now: now), now: now)
        reschedule()
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
        var alerted = false
        // Keyed by occurrence: every repeat of a meeting shares its event identifier.
        if settings.calendarEnabled {
            for item in visibleAgenda where Agenda.shouldAlert(item, now: now) {
                let key = "\(item.id)@\(Int(item.start.timeIntervalSince1970))"
                guard alertedEvents[key] == nil else { continue }
                alertedEvents[key] = item.start
                alerted = true
                _ = try? applyLocal(Agenda.activity(for: item, now: now))
            }
        }
        if settings.remindersEnabled {
            for r in reminders where Reminders.shouldAlert(r, now: now) {
                let key = "r:\(r.id)@\(Int(r.due?.timeIntervalSince1970 ?? 0))"
                guard alertedEvents[key] == nil else { continue }
                alertedEvents[key] = r.due ?? now
                alerted = true
                _ = try? applyLocal(Reminders.activity(for: r))
            }
        }
        alertedEvents = alertedEvents.filter { now.timeIntervalSince($0.value) < 86_400 }
        // Redraw only when something time-based is on show.
        if alerted || upcomingEvent != nil { tick &+= 1 }
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
        let isNew = spec.id.map { center.activities[$0] == nil } ?? true
        let a = try center.apply(spec, now: now)
        if let after = center.sneak, after.id != before?.id || after.until != before?.until {
            pulse &+= 1
            if a.state == .waiting || a.priority >= .high { Haptics.play(.alert) }
        }
        // The digest counts what arrived while locked, not every progress update.
        if lockedAt != nil, isNew { lockedDigest[a.source, default: 0] += 1 }
        reschedule()
        refineIcon(a)
        return a
    }

    /// Ask the on-device model for an icon when neither the sender nor the keyword rules chose one.
    /// Ask the on-device model for an icon once per activity (not on every update), from its
    /// title and source only, so a changing subtitle can't start a new request each time.
    private func refineIcon(_ a: Activity) {
        guard settings.smartIcons, settings.aiAssist, a.icon == nil, !iconAttempts.contains(a.id),
              SmartIcon.suggest(title: a.title, subtitle: a.subtitle, source: a.source) == nil,
              AIAssist.shared.isAvailable else { return }
        if iconAttempts.count > 500 { iconAttempts.removeAll() }
        iconAttempts.insert(a.id)
        let text = a.title + " (" + a.source + ")"
        AIAssist.shared.suggestSymbol(for: text) { [weak self] symbol in
            guard let self, let symbol, self.center.activities[a.id]?.icon == nil else { return }
            _ = try? self.center.apply(ActivitySpec(id: a.id, icon: .symbol(symbol), sneak: false), now: Date())
            self.tick &+= 1
        }
    }

    // MARK: iPhone-style events

    private func updateCalls() {
        guard settings.callDetection else { return }
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

    /// The "x" on Home's Claude usage hint: hide it for good.
    func dismissClaudeUsageHint() {
        settings.claudeUsageHint = false
        saveSettings()
        startEventSources()
    }

    /// Silence a source: remove its activities now and ignore it from now on.
    func mute(source: String) {
        if !settings.mutedSources.contains(source) { settings.mutedSources.append(source) }
        center.removeAll(source: source)
        saveSettings()
        reschedule()
    }

    private func startLAN() {
        lan.start(port: settings.lanPort, backend: self, version: Self.version)
    }

    private func stopLAN() {
        lan.stop()
    }

    func remove(activityID: String) {
        center.remove(id: activityID)
        reschedule()
        timers.activityRemoved(activityID)
    }

    func perform(_ action: ActivityAction, activityID: String) {
        if let url = action.url {
            // Islet's own links (keep awake's Turn off, for one) are handled here, not via Launch Services.
            if url.scheme == "islet" { AppActions.handle(url: url, model: self) } else { NSWorkspace.shared.open(url) }
        }
        if action.dismiss ?? true { remove(activityID: activityID) }
    }

    // MARK: Media control

    /// Send a command to the player. Play and pause show at once (`PlaybackIntent`), then
    /// follow what the player reports.
    @discardableResult
    func send(_ command: PlaybackCommand, position: Double? = nil) -> Bool {
        let now = Date()
        let intent = nowPlaying.flatMap { PlaybackIntent.intended(command, on: $0, at: now) }
        let sent = route(command, position: position)
        // Only for a player that reports back (not the demo's made-up song).
        if sent, let intent, !media.snapshots.isEmpty {
            playbackIntent = intent
            setNowPlaying(media.current(now: now), now: now)
            reschedule()
        }
        return sent
    }

    private func route(_ command: PlaybackCommand, position: Double?) -> Bool {
        if let routed = sendControl(command, position: position) { return routed }
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
            artist: "M83", album: "Hurry Up, We're Dreaming", isPlaying: true, duration: 243, elapsed: 71, timestamp: now,
            shuffle: true, repeatMode: .off
        )
        battery = BatteryState(level: 76, isCharging: true, isPluggedIn: true, minutesRemaining: 48, adapterWatts: 96)
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
        await MainActor.run { self.activities }
    }

    /// The router leaves mirrored Live Activities out of what scripts read unless the user allows it.
    nonisolated func sharesMirroredActivities() async -> Bool {
        await MainActor.run { self.settings.shareMirroredActivities }
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
            self.timers.activityRemoved(id)
            return removed
        }
    }

    nonisolated func removeActivities(source: String) async -> Int {
        await MainActor.run {
            let n = self.center.removeAll(source: source)
            self.reschedule()
            self.timers.activitiesRemoved(source: source)
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
                activities: self.activities,
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


/// Which settings-controlled services are running, so switching a module on or off in Settings
/// (or in config.json) takes effect at once instead of at the next launch.
struct RunningModules {
    var battery = false
    var audio = false
    var camera = false
    var media = false
    var calendar = false
    var clipboard = false
    var pluginDirectory: URL?
    var apiPort: Int?
    var lanPort: Int?
}

@MainActor
extension AppModel {
    /// Start or stop every module to match the current settings. Safe to call any number of times.
    func applyModules() {
        let s = settings

        if s.batteryEnabled != modules.battery {
            if s.batteryEnabled {
                battery_.onChange = { [weak self] b in self?.ingestBattery(b) }
                battery_.start()
            } else {
                battery_.stop()
                battery = nil
            }
            modules.battery = s.batteryEnabled
        }

        let wantAudio = s.hudEnabled || s.privacyIndicatorsEnabled
        if wantAudio != modules.audio {
            if wantAudio {
                audio.onOutputChange = { [weak self] out in self?.volumeChanged(out) }
                audio.onMicrophoneInUse = { [weak self] inUse in
                    guard let self else { return }
                    self.micInUse = inUse && self.settings.privacyIndicatorsEnabled
                }
                audio.start()
                outputDeviceName = AudioMonitor.readOutput()?.deviceName
            } else {
                audio.stop()
            }
            modules.audio = wantAudio
        }
        if !s.privacyIndicatorsEnabled { micInUse = false }

        if s.privacyIndicatorsEnabled != modules.camera {
            if s.privacyIndicatorsEnabled {
                camera.onChange = { [weak self] on in
                    self?.cameraInUse = on
                    self?.updateCalls()
                }
                camera.start()
            } else {
                camera.stop()
                cameraInUse = false
            }
            modules.camera = s.privacyIndicatorsEnabled
        }

        if s.mediaEnabled != modules.media {
            if s.mediaEnabled { startMedia() } else { stopMedia() }
            modules.media = s.mediaEnabled
        }
        // Sources switched off (in Settings or config.json), and the clipboard size, apply without a restart.
        if Set(s.disabledMediaSources) != media.disabled {
            media.disabled = Set(s.disabledMediaSources)
            let now = Date()
            setNowPlaying(media.current(now: now), now: now)
            reschedule()
        }
        if clipboard.limit != s.clipboardLimit { clipboard.limit = s.clipboardLimit }

        let wantCalendar = s.calendarEnabled && CalendarService.eventAccess == .granted
            || s.remindersEnabled && CalendarService.reminderAccess == .granted
        if wantCalendar != modules.calendar {
            if wantCalendar { startCalendar() } else { stopCalendar() }
            modules.calendar = wantCalendar
        } else if wantCalendar, calendar.includeReminders != s.remindersEnabled {
            calendar.includeReminders = s.remindersEnabled
            calendar.refresh()
        }

        if s.clipboardEnabled != modules.clipboard {
            if s.clipboardEnabled {
                startClipboard()
            } else {
                clipboardMonitor.stop()
                clipboard.clear()
            }
            modules.clipboard = s.clipboardEnabled
        }

        let pluginDir = s.pluginsEnabled
            ? s.pluginDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? IsletPaths.pluginsDirectory
            : nil
        if pluginDir != modules.pluginDirectory {
            stopPlugins()
            if pluginDir != nil { startPlugins() }
            modules.pluginDirectory = pluginDir
        }

        let apiPort = s.apiEnabled ? s.apiPort : nil
        if apiPort != modules.apiPort {
            stopAPI()
            if apiPort != nil { startAPI() }
            modules.apiPort = apiPort
        }

        let lanPort = s.apiEnabled && s.lanBridgeEnabled ? s.lanPort : nil
        if lanPort != modules.lanPort {
            stopLAN()
            if lanPort != nil { startLAN() }
            modules.lanPort = lanPort
        }

        // A tab whose module was switched off falls back to Home.
        if tab == .stats && !s.systemStatsEnabled || tab == .shelf && !s.shelfEnabled
            || tab == .widgets && !s.pluginsEnabled || tab == .clipboard && !s.clipboardEnabled {
            select(tab: .home)
        }
    }

    func stopMedia() {
        systemMedia.stop()
        for p in [music, spotify] as [ScriptablePlayerProvider] { p.stop() }
        for source in MediaSourceKind.allCases { media.clear(source) }
        nowPlaying = nil
        // Switched back on, the song already playing is the first one again, not a new one.
        songPeek.reset()
        pausedMusic = PausedMusic()
        playbackIntent = nil
    }

    func stopCalendar() {
        calendar.stop()
        calendarTimer?.invalidate()
        calendarTimer = nil
        if let o = dayObserver { NotificationCenter.default.removeObserver(o) }
        dayObserver = nil
        agenda = []
        reminders = []
    }

    func stopPlugins() {
        guard let runner = pluginRunner else { return }
        runner.stop()
        pluginRunner = nil
        plugins = [:]
        for a in center.activities.values where a.source.hasPrefix("plugin:") { center.remove(id: a.id) }
        reschedule()
    }

    func stopAPI() {
        guard let server else { return }
        server.stop()
        self.server = nil
        APIDiscoveryStore.remove()
        apiStatus = "Off"
    }
}
