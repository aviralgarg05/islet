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

/// Settings → Modules → Media: which Now Playing sources can appear.
struct MediaSourceToggles: View {
    @Bindable var model: AppModel

    var body: some View {
        DisclosureGroup("Sources") {
            ForEach(MediaSourceKind.allCases, id: \.self) { source in
                Toggle(Self.name(source), isOn: Binding(
                    get: { !model.settings.disabledMediaSources.contains(source) },
                    set: { on in
                        model.settings.disabledMediaSources.removeAll { $0 == source }
                        if !on { model.settings.disabledMediaSources.append(source) }
                    }))
            }
        }
        .disabled(!model.settings.mediaEnabled)
    }

    static func name(_ source: MediaSourceKind) -> String {
        switch source {
        case .system: return "Other apps (system-wide bridge)"
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        case .browser: return "Web browsers"
        case .external: return "Apps and scripts using the local API"
        }
    }
}

/// Settings → Modules: how many clipboard items are kept (pinned ones are never dropped).
struct ClipboardLimitPicker: View {
    @Bindable var model: AppModel

    private var choices: [Int] {
        Set([10, 20, 30, 50, 100, 200, 500, model.settings.clipboardLimit])
            .filter(IsletSettings.clipboardLimitRange.contains).sorted()
    }

    var body: some View {
        Picker("Clipboard items kept", selection: $model.settings.clipboardLimit) {
            ForEach(choices, id: \.self) { Text("\($0)").tag($0) }
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
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
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

/// Settings → Integrations → Script widgets: where the scripts live.
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
