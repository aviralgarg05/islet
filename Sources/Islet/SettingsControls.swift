import AppKit
import IsletCore
import ServiceManagement
import SwiftUI

/// Launch at login, read from and written to Login Items. There is no copy in config.json, so
/// the switch shows what macOS has (also after a change in System Settings).
struct LaunchAtLoginToggle: View {
    @ViewState private var status = SMAppService.mainApp.status

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
    }

    private func change(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Islet: login item: %@", error.localizedDescription)
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

/// A global shortcut, set by pressing it. Saved as text ("ctrl+option+i"), the form
/// config.json uses. Delete turns it off; Esc keeps the one there was.
struct ShortcutField: View {
    @Binding var text: String
    /// Islet's own shortcut, which the reset button goes back to.
    let standard: String
    @ViewState private var recording = false
    @ViewState private var hint: String?
    @ViewState private var monitor = Monitor()

    final class Monitor { var token: Any? }

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
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let token = monitor.token { NSEvent.removeMonitor(token) }
        monitor.token = nil
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
                    Button("Use Default") { model.settings.pluginDirectory = nil }
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
