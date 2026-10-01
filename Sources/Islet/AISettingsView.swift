import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Ask & AI: the Ask box, API keys, the command-line tools and Apple Intelligence.
struct AISettingsView: View {
    @Bindable var model: AppModel
    @ViewState private var fetched: [AskProviderKind: [String]] = [:]
    @ViewState private var fetchError: [AskProviderKind: String] = [:]
    @ViewState private var keyStored: [AskProviderKind: Bool] = [:]
    @ViewState private var cliFound: [AskProviderKind: Bool] = [:]
    @ViewState private var appleReady = AIAssist.shared.isAvailable
    @Environment(\.openSettingsPage) private var openPage

    private var service: AskService { model.ask.service }

    var body: some View {
        Form {
            Section { SettingsHero(page: .ai) }
            Section("Ask") {
                Picker("Answer with", selection: $model.settings.ask.provider) {
                    ForEach(AskProviderKind.allCases) { Text($0.title).tag($0) }
                }
                .settingsAnchor("ai.provider")
                Picker(selection: $model.settings.ask.effort) {
                    ForEach(AskEffort.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Effort")
                    Text("For Claude and ChatGPT. Low answers fastest and costs least.")
                }
                .pickerStyle(.segmented)
                .settingsAnchor("ai.effort")
                Toggle(isOn: $model.settings.ask.followUps) {
                    Text("Keep follow-ups in memory")
                    Text("Sends up to \(AskLimits.followUpTurns) earlier turns with the next question. Nothing is written to disk, and quitting Islet forgets them.")
                }
                .settingsAnchor("ai.followUps")
                LabeledContent("Shortcut") {
                    HStack(spacing: 10) {
                        Text(Hotkey.parse(model.settings.askHotkey)?.label ?? "Off").foregroundStyle(.secondary)
                        Button("Change…") { openPage(.shortcuts, "shortcuts.ask") }
                    }
                }
            }
            Section("Claude") {
                AIKeyRow(kind: .anthropic, service: service) { models in keyChanged(.anthropic, models: models) }
                    .settingsAnchor("ai.anthropic")
                modelPicker(.anthropic)
            }
            Section("ChatGPT") {
                AIKeyRow(kind: .openai, service: service) { models in keyChanged(.openai, models: models) }
                    .settingsAnchor("ai.openai")
                modelPicker(.openai)
            }
            Section {
                cliRow(.claudeCode)
                    .settingsAnchor("ai.cli")
                cliRow(.codex)
            } header: {
                Text("Command-line tools")
            } footer: {
                SettingsFooter("Uses the login you already have in Terminal, so answers count towards that plan. They run with no tools, in an empty folder.")
            }
            Section("Apple Intelligence") {
                LabeledContent("On this Mac") {
                    HStack(spacing: 5) {
                        Circle().fill(appleReady ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text(Self.appleStatus).foregroundStyle(.secondary)
                    }
                }
                .settingsAnchor("ai.apple")
                Toggle(isOn: $model.settings.aiAssist) {
                    Text("Smart icons and short summaries")
                    Text("Only ever on this Mac. Notification, calendar and clipboard text never goes to Claude or ChatGPT.")
                }
            }
            Section {
                Text("On-device answers never leave this Mac. Questions to Claude or ChatGPT go to Anthropic or OpenAI with your key, billed to your account; OpenAI is asked not to keep them. The command-line tools send questions to their maker. Islet keeps no history, and your keys stay in your login keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsAnchor("ai.privacy")
            } header: {
                Text("What leaves this Mac")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // A new default replaces whatever was picked in the island for this session.
        .onChange(of: model.settings.ask.provider) { _, _ in model.ask.sessionProvider = nil }
    }

    /// Apple Intelligence's state in plain words. The raw status is under Advanced → Diagnostics.
    static var appleStatus: String {
        let raw = AIAssist.shared.statusText
        if AIAssist.shared.isAvailable { return "Ready" }
        if raw.contains("macOS 26") { return "Needs macOS 26 or later" }
        if raw.contains("NotEnabled") { return "Turn on Apple Intelligence in System Settings" }
        if raw.contains("NotEligible") { return "This Mac can't run it" }
        if raw.contains("NotReady") { return "Still downloading" }
        return "Not available"
    }

    private func refresh() {
        appleReady = AIAssist.shared.isAvailable
        for kind in [AskProviderKind.anthropic, .openai] {
            keyStored[kind] = service.secrets.contains(kind.keyAccount ?? "")
        }
        for kind in [AskProviderKind.claudeCode, .codex] {
            cliFound[kind] = service.cliBinary(for: kind) != nil
        }
    }

    private func keyChanged(_ kind: AskProviderKind, models: [String]?) {
        keyStored[kind] = models != nil
        if let models, !models.isEmpty { fetched[kind] = models } else if models == nil { fetched[kind] = nil }
        fetchError[kind] = nil
        model.ask.refreshStatuses()
    }

    private func modelPicker(_ kind: AskProviderKind) -> some View {
        let current = model.settings.ask.model(for: kind) ?? ""
        var options = fetched[kind] ?? kind.suggestedModels
        if !current.isEmpty, !options.contains(current) { options.insert(current, at: 0) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("Model", selection: Binding(get: { current }, set: { choice in
                    model.settings.ask.setModel(choice == kind.defaultModel ? nil : choice, for: kind)
                })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                Button("Refresh List") { fetchModels(kind) }
                    .disabled(keyStored[kind] != true)
                    .help("Fetch the models your key can use")
            }
            if let error = fetchError[kind] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func fetchModels(_ kind: AskProviderKind) {
        fetchError[kind] = nil
        Task { @MainActor in
            do {
                let list = try await service.models(for: kind)
                if !list.isEmpty { fetched[kind] = list }
            } catch {
                fetchError[kind] = error.localizedDescription
            }
        }
    }

    private func cliRow(_ kind: AskProviderKind) -> some View {
        let found = cliFound[kind] ?? false
        return LabeledContent {
            HStack(spacing: 10) {
                TextField("Model", text: Binding(get: { model.settings.ask.models[kind.rawValue] ?? "" },
                                                 set: { model.settings.ask.setModel($0, for: kind) }),
                          prompt: Text("Default model"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .disabled(!found)
            }
        } label: {
            Text(kind.title)
            Text(found ? "Ready" : "Not installed")
        }
    }
}

/// Add, replace or remove one API key. The key is checked against the provider first and then
/// stored in the Keychain; afterwards only its last four characters are shown.
struct AIKeyRow: View {
    let kind: AskProviderKind
    let service: AskService
    /// Called with the key's models after a save, or nil after removal.
    var onChange: ([String]?) -> Void
    @ViewState private var masked: String?
    @ViewState private var draft = ""
    @ViewState private var editing = false
    @ViewState private var checking = false
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("API key") {
                if let masked, !editing {
                    HStack(spacing: 8) {
                        Text(masked).font(.system(.body, design: .monospaced))
                        Text("in Keychain").foregroundStyle(.secondary)
                        Button("Replace") { editing = true }
                        Button("Remove", role: .destructive, action: remove)
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("", text: $draft, prompt: Text("Paste your key"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(save)
                        Button(checking ? "Checking…" : "Save", action: save)
                            .disabled(AskKeys.normalized(draft).isEmpty || checking)
                        if editing {
                            Button("Cancel") {
                                editing = false
                                draft = ""
                                error = nil
                            }
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if masked == nil {
                Text(kind == .anthropic ? "Create a key at platform.claude.com. It is checked once, then kept in your Keychain."
                                        : "Create a key at platform.openai.com. It is checked once, then kept in your Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { masked = service.maskedKey(for: kind) }
    }

    private func save() {
        let key = AskKeys.normalized(draft)
        guard !key.isEmpty, !checking else { return }
        checking = true
        error = nil
        Task { @MainActor in
            do {
                let models = try await service.validateAndStore(key: key, for: kind)
                masked = AskKeys.masked(key)
                draft = ""
                editing = false
                onChange(models)
            } catch {
                self.error = error.localizedDescription
            }
            checking = false
        }
    }

    private func remove() {
        do {
            try service.removeKey(for: kind)
            masked = nil
            editing = false
            onChange(nil)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
