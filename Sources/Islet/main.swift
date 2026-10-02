import AppKit
import IsletCore
import IsletSystem
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var controllers: [IslandWindowController] = []
    private lazy var pointer = PointerCoordinator(model: model)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    /// The page Settings shows, kept for the session.
    private let settingsNavigation = SettingsNavigation()
    /// Status menu items for scripts and config, shown only while Option is held.
    private var advancedMenuItems: [NSMenuItem] = []
    private var rebuildWork: DispatchWorkItem?
    private let brightness = BrightnessMonitor()
    private let keys = MediaKeyInterceptor()
    private let hotkey = GlobalHotkey()
    private let askHotkey = GlobalHotkey()
    private let demo: Bool

    init(demo: Bool) {
        self.demo = demo
        model = AppModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance only: a second launch just opens the island of the running one.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if Bundle.main.bundleIdentifier != nil, !others.isEmpty {
            NSWorkspace.shared.open(URL(string: "islet://open")!)
            NSApp.terminate(nil)
            return
        }

        AppActions.openSettingsHandler = { [weak self] page, anchor in self?.showSettings(page, at: anchor) }
        EditMenu.install()
        IslandContrast.increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        model.start()
        if demo { model.loadDemo() }
        setUpHUD()
        setUpHotkey()
        rebuildPanels()
        lastTrusted = MediaKeyInterceptor.hasAccessibility
        panelSettings = PanelSettings(model.settings)
        pointer.start()
        setUpStatusItem()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        nc.addObserver(forName: .isletSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        nc.addObserver(forName: .isletMenuBarChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMenuBarMeasure(after: 0.1) }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityMayHaveChanged() }
        }
        // Posted when any app's Accessibility permission changes; the new answer can take a
        // moment to read back.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil,
                                                            queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.accessibilityMayHaveChanged() }
            }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRebuild() }
            }
        }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
        // Fast user switching: in the background session nothing reads the menu bar, banners or
        // keys, and the pointer isn't followed. It all starts again on the way back.
        wnc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSessionActive(false) }
        }
        wnc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSessionActive(true) }
        }
        // The space beside the notch changes when app menus change (switching apps) or when
        // status items come and go (apps launching and quitting).
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if note.name == NSWorkspace.didLaunchApplicationNotification { MenuBarInspector.appLaunched(app.processIdentifier) }
                    if note.name == NSWorkspace.didTerminateApplicationNotification { MenuBarInspector.appTerminated(app.processIdentifier) }
                }
                MainActor.assumeIsolated { self?.scheduleMenuBarMeasure() }
            }
        }
        // Increase Contrast (and the other display options) changed in System Settings.
        wnc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.contrastChanged() }
        }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        // Opened straight from Downloads, so macOS runs a temporary copy: offer to move to
        // Applications once the island is up.
        if !demo {
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = AppActions.offerMoveToApplications(.launch) } }
        }
    }

    /// The island's ink follows Increase Contrast. SwiftUI doesn't redraw colours for it, so the
    /// panels are drawn afresh, once, when the setting changes.
    private func contrastChanged() {
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard increased != IslandContrast.increased else { return }
        IslandContrast.increased = increased
        rebuildPanels(force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        AppActions.handle(url: url, model: model)
    }

    // MARK: Panels

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        let s = model.settings
        var chosen: [NSScreen]
        switch s.displayMode {
        case .allScreens: chosen = screens
        case .mainScreen: chosen = Array(screens.prefix(1))
        case .notchedScreen: chosen = [screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first].compactMap { $0 }
        }
        if s.notchlessStyle == .hidden { chosen = chosen.filter { $0.safeAreaInsets.top > 0 } }
        return chosen
    }

    // MARK: Sleep, session and permission changes

    private var wakeWork: [DispatchWorkItem] = []

    /// Back from sleep: the panels are made again once the displays have settled, and looked at
    /// once more later (`DisplayPolicy.wakeLooks`); the key tap and the shortcuts are set up
    /// afresh, since either can be lost across sleep.
    private func didWake() {
        wakeWork.forEach { $0.cancel() }
        wakeWork = DisplayPolicy.wakeLooks.map { look in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.rebuildPanels(force: look.force) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + look.delay, execute: work)
            return work
        }
        keys.stop()
        setUpHUD()
        setUpHotkey()
    }

    private func setSessionActive(_ active: Bool) {
        guard model.sessionActive != active else { return }
        model.sessionActive = active
        model.startEventSources()
        if SessionWork.runs(sessionActive: active) {
            setUpHUD()
            pointer.start()
            scheduleRebuild()
        } else {
            keys.stop()
            pointer.stop()
        }
    }

    /// What Islet last knew about its Accessibility permission.
    private var lastTrusted: Bool?

    /// Accessibility granted in System Settings (or taken away) while Islet was running: start
    /// or stop what uses it now, rather than at the next launch. Called when macOS says
    /// Accessibility changed and when Islet comes to the front; never polled.
    private func accessibilityMayHaveChanged() {
        model.recheckAccessibility()
        let trusted = model.accessibilityTrusted
        let rebuildTap = SessionWork.rebuildsKeyTap(wasTrusted: lastTrusted, isTrusted: trusted)
        defer { lastTrusted = trusted }
        if SessionWork.restartsOnTrustChange(wasTrusted: lastTrusted, isTrusted: trusted, settings: model.settings) {
            model.startEventSources()
            scheduleMenuBarMeasure(after: 0.1)
        }
        if rebuildTap {
            // The tap made before is dead either way: made again with the permission, left down
            // without it (so the brightness HUD shows from the monitor). No prompt: the switch
            // was already on.
            keys.stop()
            setUpHUD()
        } else {
            retryKeyTap()
        }
    }

    /// Displays settle in several steps after plugging, waking or changing arrangement.
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private var measureWork: DispatchWorkItem?

    /// Re-measure the menu bar shortly after a change settles (menus redraw after activation).
    func scheduleMenuBarMeasure(after delay: TimeInterval = 0.35) {
        measureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.controllers.forEach { $0.measureMenuBar() } }
        }
        measureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// - Parameter force: make the panels again even when the displays look the same (after
    ///   waking, when a panel may no longer draw though nothing about the display changed).
    private func rebuildPanels(force: Bool = false) {
        let screens = targetScreens()
        let wanted = screens.map(IslandWindowController.describe)
        guard DisplayPolicy.needsRebuild(current: controllers.map(\.descriptor), wanted: wanted, force: force) else {
            controllers.forEach { $0.panel.orderFrontRegardless() }
            return
        }
        controllers.forEach { $0.close() }
        controllers = screens.map { IslandWindowController(model: model, screen: $0) }
        pointer.controllers = controllers
        model.islandDisplays = controllers.sorted { ($0.metrics.isSynthetic ? 1 : 0) < ($1.metrics.isSynthetic ? 1 : 0) }.map(\.display)
        model.notchlessDisplays = Set(controllers.filter(\.metrics.isSynthetic).map(\.display))
        // The display the island was open on may be gone (unplugged, lid closed, new ID after wake).
        if let open = model.expandedScreen, !model.islandDisplays.contains(open) {
            model.pinned = false
            model.setExpanded(nil)
        }
        scheduleMenuBarMeasure(after: 0.1)
    }

    /// The settings that change where panels go or how big they are.
    private struct PanelSettings: Equatable {
        var displayMode: DisplayMode
        var size: SizePreset
        var width: Double, height: Double, wing: Double
        var notchless: NotchlessStyle, hideFromCapture: Bool
        var layout: ClosedLayoutPreference
        /// "Fit to the notch" moves the notch, and everything placed from it.
        var notchAdjust: CGSize

        init(_ s: IsletSettings) {
            displayMode = s.displayMode; size = s.sizePreset
            width = s.expandedWidth; height = s.expandedHeight; wing = s.wingWidth
            notchless = s.notchlessStyle; hideFromCapture = s.hideFromScreenCapture
            layout = s.closedLayout
            notchAdjust = s.notchAdjust
        }
    }

    private var panelSettings: PanelSettings?

    private func settingsChanged() {
        Haptics.mode = model.settings.hapticsMode
        model.applyTiming()
        model.startEventSources()
        // Reset or a hand edit of config.json may have muted or unmuted sources.
        model.applyMutes()
        setUpHotkey()
        pointer.applySettings()
        setUpHUD()
        // Only geometry changes need fresh panels; everything else updates in place.
        let panels = PanelSettings(model.settings)
        guard panels != panelSettings else { return }
        panelSettings = panels
        controllers.forEach { $0.close() }
        controllers = []
        rebuildPanels()
    }

    private func setUpHotkey() {
        if let key = Hotkey.parse(model.settings.hotkey) {
            hotkey.onPress = { [weak self] in self?.toggleIsland() }
            hotkey.register(key)
        } else {
            hotkey.unregister()
        }
        if let key = Hotkey.parse(model.settings.askHotkey) {
            askHotkey.onPress = { [weak self] in
                guard let self else { return }
                // A second press closes the Ask box again.
                if self.model.expandedScreen != nil, self.model.tab == .ask {
                    self.model.setExpanded(nil)
                } else {
                    AppActions.openAsk(self.model, query: nil, provider: nil)
                }
            }
            askHotkey.register(key)
        } else {
            askHotkey.unregister()
        }
    }

    // MARK: HUD

    /// Whether replacing the system HUD was on at the last setup; nil until the first, at launch.
    private var replacedHUD: Bool?

    private func setUpHUD() {
        // In the background session (fast user switching) the key tap stays off.
        guard model.sessionActive else {
            keys.stop()
            return
        }
        if model.settings.brightnessHUDEnabled {
            brightness.onChange = { [weak self] v in
                // Intercepted keys show the HUD themselves; otherwise macOS takes the keys and this shows it.
                guard let self, self.model.settings.brightnessHUDEnabled, !self.keys.isRunning else { return }
                Task { await self.model.showHUD(kind: .brightness, value: v, muted: false, label: nil) }
            }
            brightness.start()
        } else {
            brightness.onChange = nil
        }
        if model.settings.replaceSystemHUD {
            keys.onKey = { [weak self] key, fine in self?.handleKey(key, fine: fine) }
            keys.shouldIntercept = { [weak self] key, flags in
                MainActor.assumeIsolated { self?.shouldIntercept(key, flags: flags) ?? false }
            }
            // Without Accessibility the keys are left to macOS. Ask for it only as the option is
            // switched on; at launch a revoked permission shows in Settings instead of a prompt.
            if !keys.start(), PermissionPrompt.shouldAsk(wasOn: replacedHUD, isOn: true) {
                MediaKeyInterceptor.requestAccessibility()
            }
        } else {
            keys.stop()
        }
        replacedHUD = model.settings.replaceSystemHUD
    }

    /// Accessibility granted while Settings wasn't showing it (the HUD's Grant button, or System
    /// Settings directly): start the key tap now rather than at the next launch. Called when
    /// macOS says Accessibility changed and when Islet comes to the front; never polled.
    private func retryKeyTap() {
        guard model.sessionActive, model.settings.replaceSystemHUD, !keys.isRunning, MediaKeyInterceptor.hasAccessibility else { return }
        keys.start()
    }

    /// Whether the key tap takes `key` (`KeyInterceptPolicy`). Read fresh for each press, so a
    /// display, output or app that changed since is always counted.
    private func shouldIntercept(_ key: MediaKeyInterceptor.Key, flags: NSEvent.ModifierFlags) -> Bool {
        var s = KeyInterceptState(optionHeld: flags.contains(.option), shiftHeld: flags.contains(.shift))
        switch key {
        case .volumeUp, .volumeDown:
            s.volumeSettable = AudioMonitor.isVolumeSettable()
        case .mute:
            s.muteSettable = AudioMonitor.isMuteSettable()
        case .brightnessUp, .brightnessDown:
            let builtIn = BrightnessMonitor.builtInDisplay
            s.builtInDisplayOnline = builtIn != nil
            s.canSetBrightness = BrightnessMonitor.canSet && BrightnessMonitor.read(builtIn) != nil
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            s.pointerOnBuiltInDisplay = builtIn != nil && screen?.displayID == builtIn
            s.displayToolRunning = KeyInterceptPolicy.displayToolRunning(NSWorkspace.shared.runningApplications.lazy.compactMap(\.bundleIdentifier))
        case .backlightUp, .backlightDown:
            s.canSetKeyboardBacklight = KeyboardBacklight.isAvailable
        }
        return KeyInterceptPolicy.shouldIntercept(key, s)
    }

    private func handleKey(_ key: MediaKeyInterceptor.Key, fine: Bool) {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        // The keys still do their job with a HUD switched off; only the display is skipped. The
        // HUD shows only what really changed: a set call that failed shows nothing.
        func show(_ kind: HUDKind, _ v: Double, muted: Bool = false) {
            guard model.settings.showsHUD(kind) else { return }
            Task { await model.showHUD(kind: kind, value: v, muted: muted, label: nil) }
        }
        switch key {
        case .volumeUp, .volumeDown:
            model.volumeKeyHandled()
            guard let cur = AudioMonitor.readOutput()?.volume else { return }
            let v = min(1, max(0, (cur / step).rounded() * step + (key == .volumeUp ? step : -step)))
            if AudioMonitor.setOutputVolume(v) { show(.volume, v) }
        case .mute:
            model.volumeKeyHandled()
            guard let out = AudioMonitor.readOutput() else { return }
            if AudioMonitor.setMuted(!out.muted) { show(.volume, out.volume, muted: !out.muted) }
        case .brightnessUp, .brightnessDown:
            guard let cur = BrightnessMonitor.read() else { return }
            let v = min(1, max(0, cur + (key == .brightnessUp ? step : -step)))
            if BrightnessMonitor.set(v) { show(.brightness, v) }
        case .backlightUp, .backlightDown:
            guard let cur = KeyboardBacklight.read() else { return }
            let v = min(1, max(0, cur + (key == .backlightUp ? step : -step)))
            if KeyboardBacklight.set(v) { show(.keyboardBrightness, v) }
        }
    }

    // MARK: Status item & settings

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Open island", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        // For scripts and dotfiles; they show while Option is held as the menu opens.
        advancedMenuItems = [.separator()]
        for (title, action) in [("Copy API token", #selector(copyToken)), ("Open plugins folder", #selector(openPlugins)),
                                ("Edit config.json", #selector(openConfig))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            advancedMenuItems.append(item)
        }
        advancedMenuItems.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleIsland() {
        let target = model.targetDisplay()
        model.pinned = model.expandedScreen == nil
        model.setExpanded(model.expandedScreen == nil ? target : nil)
    }

    @objc private func openSettingsAction() { showSettings() }
    @objc private func copyToken() { AppActions.copyToken() }
    @objc private func openPlugins() { AppActions.openPluginsFolder(model) }
    @objc private func openConfig() {
        model.saveSettings()
        NSWorkspace.shared.open(IsletPaths.configFile)
    }

    /// Open Settings on `page` at the row `anchor` names, or on the page it showed last.
    func showSettings(_ page: SettingsPage? = nil, at anchor: String? = nil) {
        if let page { settingsNavigation.open(page, at: anchor) }
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(model: model, navigation: settingsNavigation)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.title = model.expandedScreen == nil ? "Open island" : "Close island"
        let option = NSEvent.modifierFlags.contains(.option)
        advancedMenuItems.forEach { $0.isHidden = !option }
    }
}

// MARK: - Entry point

let args = CommandLine.arguments

// Snapshots and the demo fill the island with sample content; keep it out of the real shelf,
// config and API files.
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("islet-demo-\(ProcessInfo.processInfo.processIdentifier)")
if args.contains("--snapshot") || args.contains("--snapshot-motion") || args.contains("--demo") {
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    if ProcessInfo.processInfo.environment["ISLET_SUPPORT_DIR"] == nil {
        setenv("ISLET_SUPPORT_DIR", scratch.appendingPathComponent("support").path, 1)
    }
    if ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] == nil {
        setenv("XDG_CONFIG_HOME", scratch.appendingPathComponent("config").path, 1)
    }
}

// Settings snapshots read the home folder (~/.claude, ~/.codex, ~/.cursor), so they run in a
// child process whose home, config and support folders are all temporary. The home folder
// has to be set before the process starts: Foundation reads it once.
if let i = args.firstIndex(of: "--settings-snapshot") {
    let dir = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "settings-snapshots").standardizedFileURL
    if let home = ProcessInfo.processInfo.environment["ISLET_SNAPSHOT_HOME"] {
        let rendered = MainActor.assumeIsolated { SettingsSnapshots.render(to: dir, home: URL(fileURLWithPath: home)) }
        exit(rendered ? 0 : 1)
    }
    let home = scratch.appendingPathComponent("home")
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    var env = ProcessInfo.processInfo.environment
    env["ISLET_SNAPSHOT_HOME"] = home.path
    env["CFFIXED_USER_HOME"] = home.path
    env["HOME"] = home.path
    env["XDG_CONFIG_HOME"] = home.appendingPathComponent(".config").path
    env["ISLET_SUPPORT_DIR"] = scratch.appendingPathComponent("support").path
    let child = Process()
    child.executableURL = Bundle.main.executableURL
    // The standard blue accent, whatever this Mac uses, so controls draw as most people see them.
    child.arguments = ["--settings-snapshot", dir.path, "-AppleAccentColor", "4", "-AppleHighlightColor",
                       "0.698039 0.843137 1.000000 Blue"]
    child.environment = env
    var status: Int32 = 1
    do {
        try child.run()
        child.waitUntilExit()
        status = child.terminationStatus
    } catch {
        print("Could not start the snapshot renderer: \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: scratch)
    exit(status)
}

// The island's transitions as contact sheets, each frame frozen part of the way through.
if let i = args.firstIndex(of: "--snapshot-motion") {
    let dir = i + 1 < args.count ? args[i + 1] : "motion-snapshots"
    MainActor.assumeIsolated { Snapshots.renderMotion(to: URL(fileURLWithPath: dir)) }
    try? FileManager.default.removeItem(at: scratch)
    exit(0)
}

if let i = args.firstIndex(of: "--snapshot") {
    let dir = i + 1 < args.count ? args[i + 1] : "snapshots"
    MainActor.assumeIsolated {
        Snapshots.render(to: URL(fileURLWithPath: dir))
        Snapshots.renderReadme(to: URL(fileURLWithPath: dir))
    }
    try? FileManager.default.removeItem(at: scratch)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// A write to a helper or client that has gone away returns an error instead of ending the app.
signal(SIGPIPE, SIG_IGN)

// Quit cleanly on SIGTERM/SIGINT (removes the API discovery file).
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalSources = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { NSApp.terminate(nil) }
    src.resume()
    return src
}
let delegate = MainActor.assumeIsolated { AppDelegate(demo: args.contains("--demo")) }
app.delegate = delegate
app.run()
