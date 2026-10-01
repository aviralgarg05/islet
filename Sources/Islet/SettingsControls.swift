import AppKit
import IsletCore
import IsletSystem
import ServiceManagement
import SwiftUI

/// Launch at login, read from and written to Login Items. There is no copy in config.json, so
/// the switch shows what macOS has (also after a change in System Settings).
struct LaunchAtLoginToggle: View {
    @ViewState private var status = SMAppService.mainApp.status
    /// Why the last change didn't take, in macOS's words.
    @ViewState private var problem: String?

    /// Running from Downloads or a translocated copy (only checked for the real app bundle).
    private var unsettled: Bool {
        AppLocation.offersMove(bundlePath: AppActions.bundleURL.path, home: NSHomeDirectory(), isAppBundle: AppActions.runsAsApp,
                               moment: .asked)
    }

    var body: some View {
        Toggle("Launch at login", isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: change))
            .onAppear { status = SMAppService.mainApp.status }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                status = SMAppService.mainApp.status
            }
        if status == .requiresApproval {
            HStack {
                Text("Allow Islet in Login Items to finish.").font(.caption)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let problem {
            Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        if unsettled {
            AccessRow(text: "Move Islet to Applications so it opens at login.", button: "Move to Applications…") {
                AppActions.offerMoveToApplications(.asked)
            }
        }
    }

    private func change(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = nil
        } catch {
            problem = "Couldn't change it: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}

/// Settings → Now Playing: which sources can appear, one switch each.
struct MediaSourceToggles: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(MediaSourceKind.allCases, id: \.self) { source in
            Toggle(isOn: Binding(
                get: { !model.settings.disabledMediaSources.contains(source) },
                set: { on in
                    model.settings.disabledMediaSources.removeAll { $0 == source }
                    if !on { model.settings.disabledMediaSources.append(source) }
                })) {
                Label {
                    Text(Self.name(source))
                } icon: {
                    Image(systemName: Self.symbol(source)).foregroundStyle(.secondary).frame(width: 20)
                }
            }
        }
    }

    static func name(_ source: MediaSourceKind) -> String {
        switch source {
        case .system: return "Other apps"
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        case .browser: return "Web browsers"
        case .external: return "Your own scripts"
        }
    }

    static func symbol(_ source: MediaSourceKind) -> String {
        switch source {
        case .system: return "square.grid.2x2"
        case .appleMusic: return "music.note"
        case .spotify: return "waveform"
        case .browser: return "globe"
        case .external: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Settings → Shelf & Clipboard: how many clipboard items are kept (pinned ones are never dropped).
struct ClipboardLimitPicker: View {
    @Bindable var model: AppModel

    private var choices: [Int] {
        Set([10, 20, 30, 50, 100, 200, 500, model.settings.clipboardLimit])
            .filter(IsletSettings.clipboardLimitRange.contains).sorted()
    }

    var body: some View {
        Picker("Items kept", selection: $model.settings.clipboardLimit) {
            ForEach(choices, id: \.self) { Text("\($0)").tag($0) }
        }
    }
}

/// "Add app": the apps running now, then any app from the Applications folder. Used by the
/// Apps page and by clipboard history's ignore list.
struct AddAppMenu: View {
    var title = "Add app"
    /// Bundle ids already on the list, which the menu leaves out.
    let existing: Set<String>
    let add: (String) -> Void

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier.map { !existing.contains($0) } ?? false }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Menu(title) {
            ForEach(runningApps, id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier!) { add(app.bundleIdentifier!) }
            }
            if !runningApps.isEmpty { Divider() }
            Button("Other app…", action: chooseApp)
        }
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }

    /// An app's name from its bundle id, or the id when it isn't installed.
    static func name(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
}

/// A list of apps with an Add menu and a minus button on each: the apps clipboard history never
/// keeps copies from, or whose media Now Playing never shows.
struct IgnoredAppsList: View {
    @Binding var apps: [String]
    let title: String
    let detail: String
    let anchor: String

    var body: some View {
        LabeledContent {
            AddAppMenu(existing: Set(apps)) { id in
                if !apps.contains(id) { apps.append(id) }
            }
        } label: {
            Text(title)
            Text(detail)
        }
        .settingsAnchor(anchor)
        ForEach(apps, id: \.self) { id in
            HStack(spacing: 10) {
                AppIconView(bundleID: id, size: 20)
                Text(AddAppMenu.name(id)).lineLimit(1)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    apps.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop ignoring \(AddAppMenu.name(id))")
            }
        }
    }
}

/// Settings → Shelf & Clipboard: apps whose copies clipboard history never keeps.
struct ClipboardIgnoredApps: View {
    @Bindable var model: AppModel

    var body: some View {
        IgnoredAppsList(apps: $model.settings.clipboardIgnoredApps, title: "Ignore apps",
                        detail: "Nothing copied in these apps is kept. Password managers are always ignored.",
                        anchor: "shelf.clipboardIgnore")
    }
}

/// A global shortcut, set by pressing it. Saved as text ("ctrl+option+i"), the form
/// config.json uses. Delete turns it off; Esc keeps the one there was. While it records,
/// Islet's own shortcuts are let through, so one of them can be pressed and recorded.
struct ShortcutField: View {
    @Binding var text: String
    /// Islet's own shortcut, which the reset button goes back to.
    let standard: String
    /// Islet's other shortcut, and what it does ("open the Ask box"): the same keys are refused.
    var other: (text: String, does: String)?
    @ViewState private var recording = false
    @ViewState private var hint: String?
    @ViewState private var monitor = Monitor()

    final class Monitor {
        var token: Any?
        /// Islet's shortcuts, held off while this field records.
        let shortcuts = ShortcutRecording()
    }

    private var label: String { Hotkey.parse(text)?.label ?? (text.isEmpty ? "Off" : "Not valid") }

    var body: some View {
        HStack(spacing: 6) {
            Button { text = standard } label: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Back to \(Hotkey.parse(standard)?.label ?? standard)")
                .opacity(!recording && text != standard ? 1 : 0)
                .disabled(recording || text == standard)
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? (hint ?? "Press keys") : label)
                    .foregroundStyle(recording ? AnyShapeStyle(Color.accentColor)
                                     : Hotkey.parse(text) == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .frame(minWidth: 96)
            }
            .help(recording ? "Press the new shortcut, or Esc to keep the old one." : "Click, then press the keys you want.")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        hint = nil
        // Islet's shortcuts would fire before the field saw the keys. Switching to another app,
        // or closing or leaving the Settings window, ends recording, so they never stay off.
        monitor.shortcuts.onEnd = { stop() }
        monitor.shortcuts.begin()
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let token = monitor.token { NSEvent.removeMonitor(token) }
        monitor.token = nil
        monitor.shortcuts.end()
        monitor.shortcuts.onEnd = nil
        recording = false
        hint = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if flags.isEmpty {
            switch event.keyCode {
            case 53: return stop()                          // Esc keeps the old shortcut
            case 51, 117:                                   // Delete turns it off
                text = ""
                return stop()
            default: break
            }
        }
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if let recorded = Hotkey.text(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
            if let other, Hotkey.sameKeys(recorded, other.text) {
                hint = "Already used to \(other.does)"
                return
            }
            text = recorded
            stop()
        } else {
            hint = "Add ⌃, ⌥ or ⌘"
        }
    }
}

/// A port number, saved only when it is usable: in range and not the other server's port.
/// Typing restarts nothing; Return or leaving the field saves it.
struct PortField: View {
    @Binding var port: Int
    let other: Int
    @ViewState private var text = ""
    @ViewState private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TextField("", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            text = String(port)
            problem = nil
        }
        .onChange(of: port) { _, value in if !focused { text = String(value) } }
    }

    private func commit() {
        let value = Int(text.trimmingCharacters(in: .whitespaces))
        problem = IsletSettings.portProblem(value, other: other)
        if problem == nil, let value, value != port { port = value }
    }
}

/// Settings → Advanced → Script widgets: where the scripts live.
struct PluginFolderRow: View {
    @Bindable var model: AppModel

    var body: some View {
        LabeledContent("Folder") {
            HStack {
                Text((AppActions.pluginsFolder(model).path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Choose…", action: choose)
                if model.settings.pluginDirectory != nil {
                    Button("Use default") { model.settings.pluginDirectory = nil }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppActions.pluginsFolder(model)
        panel.prompt = "Choose"
        panel.message = "Scripts in this folder run as widgets, with Islet's permissions."
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        model.settings.pluginDirectory = url == IsletPaths.pluginsDirectory.standardizedFileURL
            ? nil : (url.path as NSString).abbreviatingWithTildeInPath
    }
}
