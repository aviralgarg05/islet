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
    private var rebuildWork: DispatchWorkItem?
    private let brightness = BrightnessMonitor()
    private let keys = MediaKeyInterceptor()
    private let hotkey = GlobalHotkey()
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

        AppActions.openSettingsHandler = { [weak self] in self?.showSettings() }
        model.start()
        if demo { model.loadDemo() }
        setUpHUD()
        setUpHotkey()
        rebuildPanels()
        pointer.start()
        setUpStatusItem()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        nc.addObserver(forName: .isletSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRebuild() }
            }
        }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
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
        if !s.showOnNonNotchDisplays { chosen = chosen.filter { $0.safeAreaInsets.top > 0 } }
        return chosen
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

    private func rebuildPanels() {
        let screens = targetScreens()
        let current = controllers.map { ($0.display, $0.descriptor) }
        let wanted = screens.map { (($0.displayID ?? 0), IslandWindowController.describe($0)) }
        if current.count == wanted.count, zip(current, wanted).allSatisfy({ $0.0 == $1.0 && $0.1 == $1.1 }) {
            controllers.forEach { $0.panel.orderFrontRegardless() }
            return
        }
        controllers.forEach { $0.close() }
        controllers = screens.map { IslandWindowController(model: model, screen: $0) }
        pointer.controllers = controllers
    }

    private func settingsChanged() {
        Haptics.mode = model.settings.hapticFeedback ? model.settings.hapticsMode : .off
        model.applyTiming()
        model.startEventSources()
        setUpHotkey()
        pointer.applySettings()
        setUpHUD()
        // Geometry-affecting settings need fresh panels.
        controllers.forEach { $0.close() }
        controllers = []
        rebuildPanels()
    }

    private func setUpHotkey() {
        guard let key = Hotkey.parse(model.settings.hotkey) else {
            hotkey.unregister()
            return
        }
        hotkey.onPress = { [weak self] in self?.toggleIsland() }
        hotkey.register(key)
    }

    // MARK: HUD

    private func setUpHUD() {
        if model.settings.brightnessHUDEnabled {
            brightness.onChange = { [weak self] v in
                guard let self, !self.model.settings.replaceSystemHUD else { return }
                Task { await self.model.showHUD(kind: .brightness, value: v, muted: false, label: nil) }
            }
            brightness.start()
        }
        if model.settings.replaceSystemHUD {
            keys.onKey = { [weak self] key, fine in self?.handleKey(key, fine: fine) }
            if !keys.start() { MediaKeyInterceptor.requestAccessibility() }
        } else {
            keys.stop()
        }
    }

    private func handleKey(_ key: MediaKeyInterceptor.Key, fine: Bool) {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        func show(_ kind: HUDKind, _ v: Double, muted: Bool = false) {
            Task { await model.showHUD(kind: kind, value: v, muted: muted, label: nil) }
        }
        switch key {
        case .volumeUp, .volumeDown:
            let cur = AudioMonitor.readOutput()?.volume ?? 0.5
            let v = min(1, max(0, (cur / step).rounded() * step + (key == .volumeUp ? step : -step)))
            AudioMonitor.setOutputVolume(v)
            show(.volume, v)
        case .mute:
            let out = AudioMonitor.readOutput()
            AudioMonitor.setMuted(!(out?.muted ?? false))
            show(.volume, out?.volume ?? 0, muted: !(out?.muted ?? false))
        case .brightnessUp, .brightnessDown:
            let cur = BrightnessMonitor.read() ?? 0.5
            let v = min(1, max(0, cur + (key == .brightnessUp ? step : -step)))
            BrightnessMonitor.set(v)
            show(.brightness, v)
        case .backlightUp, .backlightDown:
            let cur = KeyboardBacklight.read() ?? 0.5
            let v = min(1, max(0, cur + (key == .backlightUp ? step : -step)))
            KeyboardBacklight.set(v)
            show(.keyboardBrightness, v)
        }
    }

    // MARK: Status item & settings

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Island", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy API Token", action: #selector(copyToken), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Plugins Folder", action: #selector(openPlugins), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Edit config.json", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleIsland() {
        let target = controllers.first?.display
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

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Islet Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot") {
    let dir = i + 1 < args.count ? args[i + 1] : "snapshots"
    MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: dir)) }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

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
