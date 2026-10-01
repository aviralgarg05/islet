import AppKit
import Foundation
import IsletCore
import IsletSystem
import Observation

enum IslandTab: String, CaseIterable, Identifiable {
    case home, today, shelf, widgets, clipboard, stats
    /// Tools: listed under More once turned on in Settings, and not before.
    case shortcuts, weather
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
        case .shortcuts: return "square.stack.3d.up.fill"
        case .weather: return "cloud.sun.fill"
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
        case .shortcuts: return "Shortcuts"
        case .weather: return "Weather"
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
    /// What macOS allows for calendars and reminders, read again when Islet becomes active, when
    /// an Allow is answered and when the island opens while the calendar isn't working.
    private(set) var calendarAccess = CalendarAccessState.current
    /// Calendars or reminders whose Allow macOS answered with no this session: the next press
    /// opens System Settings instead (macOS doesn't ask twice).
    private(set) var calendarRefused: Set<PermissionKind> = []
    /// Meeting reminders: the meetings you joined or dismissed, and those already announced.
    private(set) var meetings = MeetingReminders()
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
    /// When a new song shows for a moment below the notch, for as long as "New activities stay
    /// open for" says.
    private(set) var songPeek = SongPeek()
    /// The display whose closed island the pointer rests on (nil when it's elsewhere, or the
    /// island is open). The island grows a little while it is there.
    private(set) var hoverDisplay: CGDirectDisplayID?
    /// The display showing what's playing because the pointer has rested on its notch while
    /// the island opens on click ("Peek at what's playing"). Ends when the pointer leaves.
    private(set) var hoverPeekDisplay: CGDirectDisplayID?
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
    /// Lyrics, shortcuts, weather, the month calendar, the stopwatch and focus sounds (Tools.swift).
    @ObservationIgnored lazy var tools = Tools(model: self)
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
    private var dayObserver: NSObjectProtocol?
    /// What `applyModules()` has started.
    private var modules = RunningModules()
    /// Reminder alerts already shown, by occurrence, with when they were for.
    private var alertedReminders: [String: Date] = [:]
    /// Where meeting reminders are kept; nil until `start()`, so snapshots never write it.
    @ObservationIgnored private var meetingsURL: URL?
    @ObservationIgnored private var canSaveMeetings = true
    /// The meeting reminders on show, by activity id, and the spec each was last applied with.
    @ObservationIgnored private var shownMeetings: [String: (reminder: MeetingReminder, spec: ActivitySpec)] = [:]
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    /// Activities already sent to the on-device model for an icon.
    private var iconAttempts: Set<String> = []
    private var settingsWatcher: DispatchSourceFileSystemObject?
    /// config.json, which is never written over while it doesn't parse.
    @ObservationIgnored private var configFile: SettingsFile
    /// Set while config.json doesn't parse: Islet keeps its last good settings and saves
    /// nothing until the file is fixed or replaced (Settings → Advanced).
    private(set) var settingsProblem: FileProblem?
    /// Where the settings in use came from while `settingsProblem` is set: the last good copy,
    /// or the defaults when config.json was already broken at launch and there was no copy.
    private(set) var settingsOrigin: SettingsFile.Origin = .file

    /// With no `settings`, they are read from config.json (or, when it doesn't parse, from the
    /// copy of the last one that did). `ask` is replaceable so Settings snapshots keep API keys
    /// in memory instead of the Keychain.
    init(settings: IsletSettings? = nil, ask: AskController? = nil) {
        var file = SettingsFile(url: IsletPaths.configFile, lastGood: IsletPaths.lastGoodConfigFile)
        var origin = SettingsFile.Origin.file
        let start: IsletSettings
        if let settings {
            start = settings
        } else {
            let opened = file.open()
            start = opened.settings
            origin = opened.origin
        }
        let settings = start
        configFile = file
        settingsProblem = file.problem
        settingsOrigin = origin
        self.settings = settings
        self.ask = ask ?? AskController()
        shelf = shelfService.shelf
        clipboard = ClipboardHistory(limit: settings.clipboardLimit)
        clipboard.ignoredApps = Set(settings.clipboardIgnoredApps)
        clipboard.skipsSecrets = settings.clipboardSkipSecrets
        songPeek.duration = settings.alertDuration
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
        tools.stopwatch.start()
        loadMeetings()
        startEventSources()
        watchSettingsFile()
        // Once per launch: hooks left pointing at an isletctl that moved fail silently.
        checkAgentHooks()
        // Back from System Settings, calendar access may have changed; it starts at once.
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckCalendarAccess() }
        })
        // Timers don't count time asleep: catch up on what fell due (a meeting that started).
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireNow() }
        })
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
        applyTools()
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
        // A new song stays as long as a new activity does.
        songPeek.duration = settings.alertDuration
        Motion.pace = settings.animationSpeed.multiplier
        // "Hide paused music after" may have moved the moment paused music goes.
        reschedule()
    }

    func stop() {
        releaseKeepAwake()
        tools.focus.stopAll()
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
            self?.bridgeFailed = true
            self?.syncPlayers()
        }
        bridgeFailed = false
        systemMedia.start()
        syncPlayers()
    }

    /// The system bridge said it can't deliver (it may still be running), so the players fetch
    /// their own details. Reset when media starts again.
    @ObservationIgnored private var bridgeFailed = false

    /// Music and Spotify run only while their source is on in Settings; a source switched off
    /// sends no AppleScript at all, even with the system bridge down.
    func syncPlayers() {
        let disabled = media.disabled
        let bridgeUp = systemMedia.isRunning && !bridgeFailed
        for p in [music, spotify] as [ScriptablePlayerProvider] {
            guard PlayerIntegration.runs(p.source, disabled: disabled) else {
                p.enrich = false
                p.stop()
                continue
            }
            // Before start(), which begins enriching straight away when asked to.
            p.enrich = PlayerIntegration.enriches(p.source, disabled: disabled, bridgeRunning: bridgeUp)
            p.onUpdate = { [weak self, source = p.source] np in self?.mediaUpdate(np, source: source) }
            p.start()
        }
    }

    func startCalendar() {
        calendar.includeReminders = settings.remindersEnabled
        calendar.onAgenda = { [weak self] items in
            self?.agenda = items
            self?.calendarChanged()
        }
        calendar.onReminders = { [weak self] items in
            self?.reminders = items
            self?.calendarChanged()
        }
        calendar.start()
        // The agenda covers today and tomorrow; roll it forward when the day changes.
        if dayObserver == nil {
            dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.calendar.refresh() }
            }
        }
    }

    /// Events from calendars the user hasn't hidden. Reads `tick`, so what depends on the time
    /// of day (the next event, what is left today) is drawn again at each deadline.
    var visibleAgenda: [AgendaItem] {
        _ = tick
        return Agenda.visible(agenda, hiding: Set(settings.hiddenCalendars))
    }

    func completeReminder(_ id: String) {
        Haptics.play(.tap)
        if calendar.complete(reminderID: id) { reminders.removeAll { $0.id == id } }
    }

    var dueReminders: [ReminderItem] { settings.remindersEnabled ? Reminders.dueSoon(reminders, now: Date()) : [] }

    // MARK: Calendar access

    /// What to say about calendar (`.calendars`) or reminders (`.reminders`) access, and the button.
    func calendarAdvice(_ kind: PermissionKind) -> CalendarAccessAdvice {
        CalendarAccessAdvice.advice(kind == .reminders ? calendarAccess.reminders : calendarAccess.events, kind: kind,
                                    refused: calendarRefused.contains(kind))
    }

    /// "Allow…" for calendars or reminders. macOS is asked when it hasn't been; after a refusal,
    /// or with "Add events only", System Settings opens at the right page instead, since asking
    /// again would return at once and look stuck. Access arriving starts the feature straight away
    /// (and, with `turnOn`, switches it on).
    func requestCalendarAccess(_ kind: PermissionKind = .calendars, turnOn: Bool = true, answered: (() -> Void)? = nil) {
        readCalendarAccess()
        switch calendarAdvice(kind).action {
        case nil:
            if turnOn { switchOnCalendarFeature(kind) }
            answered?()
        case .openSettings(let url)?:
            NSWorkspace.shared.open(url)
            answered?()
        case .ask?:
            let done: (Bool) -> Void = { [weak self] granted in
                guard let self else { return }
                if !granted { self.calendarRefused.insert(kind) }
                if granted, turnOn { self.switchOnCalendarFeature(kind) } else { self.recheckCalendarAccess(force: true) }
                answered?()
            }
            if kind == .reminders { calendar.requestReminderAccess(completion: done) } else { calendar.requestAccess(completion: done) }
        }
    }

    private func switchOnCalendarFeature(_ kind: PermissionKind) {
        if kind == .reminders { settings.remindersEnabled = true } else { settings.calendarEnabled = true }
        saveSettings()
        recheckCalendarAccess(force: true)
    }

    /// Read access again and start (or stop) the calendar to match, without a relaunch.
    func recheckCalendarAccess(force: Bool = false) {
        guard readCalendarAccess() || force else { return }
        applyModules()
    }

    /// Reads calendar and reminders access. Returns whether either changed. Access just granted
    /// gives the service a new event store, which a store made before it may need.
    @discardableResult
    private func readCalendarAccess() -> Bool {
        let fresh = CalendarAccessState.current
        guard fresh != calendarAccess else { return false }
        let gained = fresh.events.canRead && !calendarAccess.events.canRead || fresh.reminders.canRead && !calendarAccess.reminders.canRead
        calendarAccess = fresh
        if fresh.events.canRead { calendarRefused.remove(.calendars) }
        if fresh.reminders.canRead { calendarRefused.remove(.reminders) }
        if gained { calendar.accessChanged() }
        return true
    }

    /// Whether a calendar feature that is on can't read what it needs (so opening the island
    /// checks access again).
    private var calendarIsBlocked: Bool {
        settings.calendarEnabled && !calendarAccess.events.canRead || settings.remindersEnabled && !calendarAccess.reminders.canRead
    }

    /// `--settings-snapshot` and `--snapshot` draw the access states without asking macOS.
    func setCalendarAccessForSnapshot(events: CalendarAccess, reminders: CalendarAccess, refused: Set<PermissionKind> = []) {
        calendarAccess = CalendarAccessState(events: events, reminders: reminders)
        calendarRefused = refused
    }

    /// For `GET /v1/state`: the access and how many timed events are left today, never titles.
    var calendarStatus: CalendarStatus {
        let left = settings.calendarEnabled ? Agenda.restOfToday(visibleAgenda, now: Date()).timed.count : 0
        return CalendarStatus(events: calendarAccess.events, reminders: calendarAccess.reminders, upcoming: left)
    }

    // MARK: Meeting reminders

    /// The meetings showing as reminders now, earliest first.
    var liveMeetings: [MeetingReminder] {
        meetings.live(visibleAgenda, now: Date(), options: MeetingReminderOptions(settings))
    }

    private func loadMeetings() {
        let url = IsletPaths.supportDirectory.appendingPathComponent("meetings.json")
        meetingsURL = url
        let restored = MeetingReminders.start(from: url)
        if let saved = restored.value { meetings = saved }
        canSaveMeetings = restored.canSave
        if let moved = restored.setAside { NSLog("Islet: meetings.json couldn't be read; kept as %@", moved.lastPathComponent) }
    }

    private func saveMeetings() {
        guard let url = meetingsURL, canSaveMeetings else { return }
        do {
            try meetings.save(to: url)
        } catch {
            NSLog("Islet: couldn't save meetings.json: %@", error.localizedDescription)
        }
    }

    /// The agenda or reminders changed: show what is due, and wake for what comes next.
    private func calendarChanged() {
        let now = Date()
        syncMeetings(now: now)
        checkReminderAlerts(now: now)
        tick &+= 1
        reschedule()
    }

    /// Show each meeting due a reminder as an activity, and take away those that are over.
    /// Only real changes are applied (the countdown once a minute), so the island doesn't redraw
    /// or reorder for nothing.
    private func syncMeetings(now: Date) {
        let options = MeetingReminderOptions(settings)
        // Worked on a copy, so views watching `meetings` redraw only when something changed.
        var updated = meetings
        updated.forget(before: now)
        var live = updated.live(visibleAgenda, now: now, options: options)
        // A call already going on in the meeting's app counts as joining it, however it was
        // joined and however early (within `joinWindow`), so the reminder never glows at you
        // while you are in the meeting.
        if settings.callDetection {
            let joined = MeetingReminders.joinedByCalls(calls.ongoing, live: live)
            if !joined.isEmpty {
                for r in joined { updated.join(r.item) }
                live = updated.live(visibleAgenda, now: now, options: options)
            }
        }
        let announce = updated.announce(live)
        let changed = updated != meetings
        if changed { meetings = updated }
        var shown: [String: (reminder: MeetingReminder, spec: ActivitySpec)] = [:]
        for r in live {
            var spec = MeetingReminders.activity(for: r, now: now, icon: MeetingReminders.icon(for: r, installed: AppActions.isInstalled),
                                                 sneak: false, time: { $0.formatted(date: .omitted, time: .shortened) })
            if let previous = shownMeetings[r.id], previous.spec == spec, center.activities[r.id] != nil {
                shown[r.id] = previous
                continue
            }
            let plain = spec
            spec.sneak = announce.contains(r.key)
            // A muted calendar shows nothing; it is tried again at the next change.
            if (try? applyLocal(spec)) != nil { shown[r.id] = (r, plain) }
        }
        for id in shownMeetings.keys where shown[id] == nil { center.remove(id: id) }
        shownMeetings = shown
        if changed { saveMeetings() }
    }

    /// The meeting reminder an activity shows, if it is one and still on show (muting the
    /// calendar takes it away before the next sync).
    func meetingReminder(for activityID: String) -> MeetingReminder? {
        guard center.activities[activityID] != nil else { return nil }
        return shownMeetings[activityID]?.reminder
    }

    /// Join: open the call link and count the meeting as joined, so its reminder goes.
    func join(_ item: AgendaItem) {
        guard let url = item.meetingURL else { return }
        Haptics.play(.tap)
        NSWorkspace.shared.open(url)
        meetings.join(item)
        saveMeetings()
        let now = Date()
        syncMeetings(now: now)
        reschedule()
    }

    /// A meeting reminder's activity went (its ×, a swipe, Dismiss, a script): it stays dismissed.
    private func meetingActivityRemoved(_ id: String) {
        guard let shown = shownMeetings.removeValue(forKey: id) else { return }
        meetings.dismiss(shown.reminder.item)
        saveMeetings()
    }

    /// `--snapshot`: these events, and the meeting reminders they would show at `now`.
    func showMeetingsForSnapshot(_ items: [AgendaItem], now: Date) {
        agenda = items
        meetings = MeetingReminders()
        syncMeetings(now: now)
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

    /// Writes the settings to config.json, keeping keys this build doesn't know. Writes
    /// nothing while the file doesn't parse (`settingsProblem`).
    func saveSettings() {
        do {
            try configFile.save(settings)
        } catch {
            NSLog("Islet: couldn't save config.json: %@", error.localizedDescription)
        }
        noteSettingsProblem(configFile.problem)
    }

    /// Settings → Advanced, while config.json doesn't parse: keep a copy of it as
    /// config.json.broken and write the settings in use over it.
    func replaceBrokenSettingsFile() {
        do {
            try configFile.replace(with: settings)
        } catch {
            NSLog("Islet: couldn't replace config.json: %@", error.localizedDescription)
        }
        noteSettingsProblem(configFile.problem)
    }

    /// Settings → Advanced → Reset: every setting back to how Islet came. A config.json that
    /// doesn't parse is kept as config.json.broken.
    func resetSettings() {
        settings = IsletSettings()
        replaceBrokenSettingsFile()
        NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
    }

    private func noteSettingsProblem(_ problem: FileProblem?) {
        if settingsProblem != problem { settingsProblem = problem }
        // A file that parses again (or was replaced) is where the settings come from once more.
        if problem == nil, settingsOrigin != .file { settingsOrigin = .file }
    }

    /// `--settings-snapshot` draws Advanced as it looks while config.json has an error.
    func setSettingsProblemForSnapshot(_ problem: FileProblem?, origin: SettingsFile.Origin = .lastGood) {
        settingsProblem = problem
        settingsOrigin = problem == nil ? .file : origin
    }

    /// Agents whose hooks call an `isletctl` that is gone (Islet.app moved or was deleted).
    /// Settings shows a dot on Coding agents; Update there fixes it.
    private(set) var agentsNeedingUpdate: Set<CodingAgent> = []

    /// Reads each agent's hooks file once, off the main thread: at launch and when the Coding
    /// agents page refreshes. Never writes, never polls.
    func checkAgentHooks() {
        let home = IsletPaths.home
        let exists = AppActions.isExecutable
        Task { @MainActor in
            let stale = await Task.detached(priority: .utility) {
                Set(CodingAgent.allCases.filter { !AgentHookSetup.missingExecutables($0, home: home, exists: exists).isEmpty })
            }.value
            if agentsNeedingUpdate != stale { agentsNeedingUpdate = stale }
        }
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

    /// A file that doesn't parse (a typo mid-edit) changes nothing: the last good settings stay,
    /// and Settings → Advanced says which line. A deleted file changes nothing either; the next
    /// save writes it again.
    private func reloadSettingsFromDisk() {
        let read = configFile.read()
        noteSettingsProblem(configFile.problem)
        guard case .loaded(let fresh) = read, fresh != settings else { return }
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
        // "Hide music only" over a full screen app: the music goes, everything else stays.
        let showsMedia = settings.mediaEnabled && fullscreenBehaviour(on: display) != .hideMusic
        let inputs = PresenterInputs(
            now: now,
            center: center,
            nowPlaying: showsMedia ? nowPlaying : nil,
            batteryEvent: batteryEvent,
            isExpanded: expandedScreen == display || (isDraggingFile && expandedScreen == display),
            isSuppressed: isSuppressed(display) && expandedScreen != display,
            pausedMedia: showsMedia ? pausedMusic.show(timeout: settings.pausedMusicTimeout, now: now) : .hidden,
            focusedActivityID: controls.focusedActivityID,
            songPeek: Presenter.hoverPeek(showsMedia ? nowPlaying : nil, hovering: hoverPeekDisplay == display, settings: settings)
                ?? (showsMedia && settings.songChangePeek ? songPeek.current(now: now) : nil)
        )
        let p = Presenter.present(inputs)
        // "Only on hover" on a display without a notch: nothing until the pointer is there.
        if settings.notchlessStyle == .hover, notchlessDisplays.contains(display), hoverDisplay != display {
            return Presenter.untilHover(p)
        }
        return p
    }

    /// What full screen asks of the island on `display` now (`show` when nothing is in full
    /// screen there, or the front app's rule keeps the island).
    func fullscreenBehaviour(on display: CGDirectDisplayID) -> FullscreenBehaviour {
        settings.fullscreenEffect(isFullscreen: fullscreenDisplays.contains(display), frontApp: frontBundleID)
    }

    /// The pointer reached the closed island on `display`, or left it (nil).
    func setHover(_ display: CGDirectDisplayID?) {
        if hoverDisplay != display { hoverDisplay = display }
        if hoverPeekDisplay != nil, hoverPeekDisplay != display { hoverPeekDisplay = nil }
    }

    /// The pointer has rested on the notch long enough: peek at what's playing there.
    func peekOnHover(_ display: CGDirectDisplayID) {
        guard expandedScreen == nil, hoverDisplay == display, hoverPeekDisplay != display,
              Presenter.hoverPeek(nowPlaying, hovering: true, settings: settings) != nil else { return }
        hoverPeekDisplay = display
    }

    /// The island on `display` gets out of the way: an app is in full screen there and "In full
    /// screen" says to hide everything (unless the app's rule keeps the island), or the front
    /// app's rule hides it.
    func isSuppressed(_ display: CGDirectDisplayID) -> Bool {
        if settings.rule(for: frontBundleID)?.hideIsland == true { return true }
        return fullscreenBehaviour(on: display) == .hide
    }

    /// What the island is doing, for deciding whether a new song may show.
    private func songPeekContext(now: Date) -> SongPeek.Context {
        SongPeek.Context(
            enabled: settings.mediaEnabled && settings.songChangePeek,
            isOpen: expandedScreen != nil,
            isHidden: !islandDisplays.isEmpty && islandDisplays.allSatisfy { isSuppressed($0) || fullscreenBehaviour(on: $0) == .hideMusic },
            isBusy: center.currentHUD(now: now) != nil || center.currentSneak(now: now) != nil
        )
    }

    var activities: [Activity] { center.ordered(now: Date()) }

    /// How wide the closed island's wings are on a display: always full width, or the measured
    /// automatic placement (narrow wings, at most `MenuBarLayoutEngine.unmeasuredWing`, until the
    /// menu bar has been measured).
    func placement(for display: CGDirectDisplayID, metrics: IslandMetrics) -> ClosedPlacement {
        let preference = settings.closedLayout
        guard let measured = closedPlacements[display] else {
            return .unmeasured(preference, wing: metrics.wingWidth, hasMenuBar: true)
        }
        // A measurement taken before "Always full width" was chosen has narrower wings; until the
        // next one, keep bubbles out of the row rather than trust its room.
        if preference == .wings, measured.wing != metrics.wingWidth {
            return .unmeasured(preference, wing: metrics.wingWidth, hasMenuBar: true)
        }
        return measured
    }

    var upcomingEvent: AgendaItem? { settings.calendarEnabled ? Agenda.upcoming(visibleAgenda, now: Date()) : nil }

    /// Displays that have an island, notched ones first. Set when panels are rebuilt.
    var islandDisplays: [CGDirectDisplayID] = []
    /// The displays among them without a notch.
    var notchlessDisplays: Set<CGDirectDisplayID> = []

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
            hoverDisplay = nil
            hoverPeekDisplay = nil
            agentUsage.refreshClaudeHint()
            // Access may have come from System Settings without Islet becoming active.
            if calendarIsBlocked { recheckCalendarAccess() }
            Haptics.play(.open)
            if tab == .stats && settings.systemStatsEnabled { statsSampler.start() }
        } else {
            statsSampler.stop()
            pinned = false
            ask.islandDidCollapse()
            controlHint = nil
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

    /// Snapshots: the song paused a moment ago (`pause`), or playing as before.
    func setPausedForSnapshot(_ pause: Bool, now: Date) {
        guard var np = nowPlaying else { return }
        pausedMusic = PausedMusic()
        np.isPlaying = true
        pausedMusic.ingest(np, now: now)
        np.isPlaying = !pause
        nowPlaying = np
        pausedMusic.ingest(np, now: now)
    }

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
        // The calendar: a meeting reminder showing, starting, counting down or going; a reminder
        // falling due; an event starting or ending (what Home and Today show changes then).
        if !agenda.isEmpty {
            let visible = visibleAgenda
            if let d = meetings.nextDeadline(visible, now: now, options: MeetingReminderOptions(settings)) { candidates.append(d) }
            if settings.calendarEnabled, let d = Agenda.nextChange(visible, now: now) { candidates.append(d) }
        }
        if settings.remindersEnabled, let d = Reminders.nextDue(reminders, now: now) { candidates.append(d) }
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
        syncMeetings(now: now)
        checkReminderAlerts(now: now)
        if let b = batteryEvent, b.until <= now { batteryEvent = nil }
        // A paused player timed out: show whatever is left, or nothing. A track that ran past
        // its end shows as stopped, and a click the player never confirmed shows its real state.
        // (With no player reporting there is nothing to work out, and the demo's song stays.)
        if media.expire(now: now) || !media.snapshots.isEmpty {
            setNowPlaying(media.current(now: now), now: now)
        }
        // A click whose window has ended never arms the timer again, even if the player went.
        if let i = playbackIntent, now >= i.expires { playbackIntent = nil }
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

    /// A timed reminder reaching its due minute shows once. Woken at the due time (`reschedule`),
    /// never by checking every minute.
    private func checkReminderAlerts(now: Date) {
        guard settings.remindersEnabled else { return }
        for r in reminders where Reminders.shouldAlert(r, now: now) {
            let key = "r:\(r.id)@\(Int(r.due?.timeIntervalSince1970 ?? 0))"
            guard alertedReminders[key] == nil else { continue }
            alertedReminders[key] = r.due ?? now
            _ = try? applyLocal(Reminders.activity(for: r))
        }
        alertedReminders = alertedReminders.filter { now.timeIntervalSince($0.value) < 86_400 }
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
        // An app given a priority on the Apps page ranks its activities there.
        let a = try center.apply(settings.prioritised(spec), now: now)
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
        var started = false
        for change in calls.update(micUsers: lastMicUsers, cameraOn: cameraInUse, now: Date()) {
            switch change {
            case .started(let spec):
                _ = try? applyLocal(spec)
                started = true
            case .updated(let spec): _ = try? applyLocal(spec)
            case .ended(let id): remove(activityID: id)
            }
        }
        // A call in a meeting's app counts as joining it (`syncMeetings`).
        if started {
            syncMeetings(now: Date())
            reschedule()
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
        // Nothing arrived: nothing to say, so the island stays as it was.
        guard let since = lockedAt,
              let spec = WelcomeBack.activity(counts: lockedDigest, lockedFor: Date().timeIntervalSince(since), name: Self.friendlySource)
        else { return }
        _ = try? commit(spec)
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
        meetingActivityRemoved(activityID)
        reschedule()
        timers.activityRemoved(activityID)
        tools.stopwatch.activityRemoved(activityID)
    }

    func perform(_ action: ActivityAction, activityID: String) {
        // A meeting reminder's Join counts as joining, not as dismissing it.
        if let r = meetingReminder(for: activityID), let link = r.item.meetingURL, action.url == link {
            join(r.item)
            return
        }
        if let url = action.url {
            // Islet's own links (keep awake's Turn off, for one) are handled here, not via Launch Services.
            if url.scheme == "islet" { AppActions.handle(url: url, model: self) } else { NSWorkspace.shared.open(url) }
        }
        if action.dismiss ?? true { remove(activityID: activityID) }
    }

    /// Whether a swipe up or an × may dismiss an activity in the closed island: meeting reminders.
    func isDismissableReminder(_ a: Activity) -> Bool { meetingReminder(for: a.id) != nil }

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
        // A press that went nowhere because macOS hasn't allowed Islet to control the player
        // says so, instead of doing nothing.
        let hint = nowPlaying.flatMap { np -> String? in
            let r = mediaRoute(for: np)
            return PlayerIntegration.controlHint(route: r, sent: sent, canScript: r == .player(.spotify) ? spotify.canScript : music.canScript)
        }
        if controlHint != hint { controlHint = hint }
        return sent
    }

    /// "Allow Islet to control Music": the player whose controls just went nowhere, until a
    /// control works or the island closes.
    private(set) var controlHint: String?

    /// `--snapshot` draws the hint.
    func setControlHintForSnapshot(_ player: String?) { controlHint = player }

    /// The hint's Allow button: Settings → Permissions, at that player's row.
    func openControlPermission() {
        let kind: PermissionKind = controlHint == "Spotify" ? .automationSpotify : .automationMusic
        controlHint = nil
        AppActions.openSettings(.permissions, at: "permissions.\(kind.rawValue)")
    }

    /// Commands go to the player on show (the one picked in the island, or the newest): the
    /// bridge only when it is that app's, Music and Spotify otherwise through their own
    /// integration, so a press on Spotify never pauses a video in Chrome.
    private func route(_ command: PlaybackCommand, position: Double?) -> Bool {
        guard let np = nowPlaying else {
            // Nothing on show: the bridge controls whatever macOS considers "now playing".
            return systemMedia.isRunning && systemMedia.send(command, position: position)
        }
        let r = mediaRoute(for: np)
        if let routed = sendControl(command, position: position, bridge: r == .bridge) { return routed }
        switch r {
        case .bridge: return systemMedia.send(command, position: position)
        case .player(.spotify): return spotify.send(command, position: position)
        case .player(.appleMusic): return music.send(command, position: position)
        case .player, .none: return false
        }
    }

    func mediaRoute(for np: NowPlaying) -> MediaRoute {
        MediaRoute.route(for: np, bridgeRunning: systemMedia.isRunning, bridgePlayer: media.bridgePlayer)
    }

    // MARK: Players

    /// The players live now, one per app, newest first. More than one shows as chips in the open island.
    var players: [NowPlaying] {
        _ = tick
        return settings.mediaEnabled ? media.available(now: Date()) : []
    }

    /// A player chip: show and control that player. The closed island follows it.
    func pickPlayer(_ np: NowPlaying) {
        Haptics.play(.tap)
        let now = Date()
        media.pick(player: MediaArbiter.playerID(np), at: now)
        controlHint = nil
        playbackIntent = nil
        setNowPlaying(media.current(now: now), now: now)
        reschedule()
    }

    /// `--snapshot`: several players at once (a Chrome video and a Spotify song), or, with
    /// none, back to the demo's song alone.
    func loadPlayersForSnapshot(_ list: [NowPlaying], bridge: NowPlaying?, now: Date, song: NowPlaying? = nil) {
        media = MediaArbiter(disabled: media.disabled)
        for np in list { media.update(np) }
        media.updateFromBridge(bridge)
        nowPlaying = song ?? media.current(now: now)
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
    /// "Clear unpinned" on the Clipboard page.
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
            self.meetingActivityRemoved(id)
            self.reschedule()
            self.timers.activityRemoved(id)
            self.tools.stopwatch.activityRemoved(id)
            return removed
        }
    }

    nonisolated func removeActivities(source: String) async -> Int {
        await MainActor.run {
            let n = self.center.removeAll(source: source)
            for id in self.shownMeetings.keys where self.center.activities[id] == nil { self.meetingActivityRemoved(id) }
            self.reschedule()
            self.timers.activitiesRemoved(source: source)
            if source == Stopwatch.source { self.tools.stopwatch.activityRemoved(Stopwatch.activityID) }
            return n
        }
    }

    nonisolated func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async {
        await MainActor.run {
            // From the keys, the brightness monitor, the API or a link: each kind has its switch.
            guard self.settings.showsHUD(kind) else { return }
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
            // Checked from the command line after a change in System Settings: read it afresh.
            self.recheckCalendarAccess()
            let display = self.expandedScreen ?? NSScreen.main?.displayID ?? 0
            return StateSnapshot(
                version: Self.version,
                presentation: String(describing: self.presentation(for: display)).components(separatedBy: "(").first ?? "",
                activities: self.activities,
                nowPlaying: self.nowPlaying.map { NowPlayingSummary($0, now: Date()) },
                battery: self.battery,
                calendar: self.calendarStatus
            )
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}


/// Calendar and reminders access, as macOS reports it now.
struct CalendarAccessState: Equatable {
    var events: CalendarAccess
    var reminders: CalendarAccess

    static var current: CalendarAccessState {
        CalendarAccessState(events: CalendarService.eventAccess, reminders: CalendarService.reminderAccess)
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
            // Music or Spotify switched off stops altogether; switched on, it starts.
            if s.mediaEnabled { syncPlayers() }
            let now = Date()
            setNowPlaying(media.current(now: now), now: now)
            reschedule()
        }
        if clipboard.limit != s.clipboardLimit { clipboard.limit = s.clipboardLimit }
        if clipboard.ignoredApps != Set(s.clipboardIgnoredApps) { clipboard.ignoredApps = Set(s.clipboardIgnoredApps) }
        if clipboard.skipsSecrets != s.clipboardSkipSecrets { clipboard.skipsSecrets = s.clipboardSkipSecrets }

        readCalendarAccess()
        let wantCalendar = s.calendarEnabled && calendarAccess.events.canRead || s.remindersEnabled && calendarAccess.reminders.canRead
        if wantCalendar != modules.calendar {
            if wantCalendar { startCalendar() } else { stopCalendar() }
            modules.calendar = wantCalendar
        } else if wantCalendar, calendar.includeReminders != s.remindersEnabled {
            calendar.includeReminders = s.remindersEnabled
            calendar.refresh()
        }
        // Reminder settings or hidden calendars may have changed what shows, and when.
        syncMeetings(now: Date())
        reschedule()

        if s.clipboardEnabled != modules.clipboard {
            if s.clipboardEnabled {
                startClipboard()
            } else {
                clipboardMonitor.stop()
                // Off means nothing is kept, pinned entries included.
                clipboard.removeAll()
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
        if let o = dayObserver { NotificationCenter.default.removeObserver(o) }
        dayObserver = nil
        agenda = []
        reminders = []
        syncMeetings(now: Date())
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
