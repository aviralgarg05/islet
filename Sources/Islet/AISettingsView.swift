import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → AI: Apple Intelligence, the Ask box, API keys and the local CLIs.
struct AISettingsView: View {
    @Bindable var model: AppModel
    @ViewState private var fetched: [AskProviderKind: [String]] = [:]
    @ViewState private var fetchError: [AskProviderKind: String] = [:]
    @ViewState private var keyStored: [AskProviderKind: Bool] = [:]
    @ViewState private var cliPaths: [AskProviderKind: String] = [:]
    @ViewState private var appleStatus = AIAssist.shared.statusText

    private var service: AskService { model.ask.service }

    var body: some View {
        Form {
            Section("Apple Intelligence") {
                LabeledContent("Status") { Text(appleStatus).foregroundStyle(.secondary) }
                Toggle("On-device AI for icons and summaries", isOn: $model.settings.aiAssist)
                Text("Smart icons and notification summaries only ever use the on-device model. Notification, calendar and clipboard text never goes to a cloud provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ask") {
                Picker("Default provider", selection: $model.settings.ask.provider) {
                    ForEach(AskProviderKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Effort", selection: $model.settings.ask.effort) {
                    ForEach(AskEffort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("For Claude and ChatGPT. Low answers fastest and costs least.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Shortcut", text: $model.settings.askHotkey, prompt: Text("ctrl+option+a"))
                Text("Opens the Ask box ready to type, from any app. Leave empty to turn it off.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep follow-ups in memory", isOn: $model.settings.ask.followUps)
                Text("Sends up to \(AskLimits.followUpTurns) earlier turns with the next question. Nothing is written to disk, and quitting Islet forgets them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude (Anthropic API)") {
                AIKeyRow(kind: .anthropic, service: service) { models in keyChanged(.anthropic, models: models) }
                modelPicker(.anthropic)
            }
            Section("ChatGPT (OpenAI API)") {
                AIKeyRow(kind: .openai, service: service) { models in keyChanged(.openai, models: models) }
                modelPicker(.openai)
            }
            Section("Command-line tools") {
                cliRow(.claudeCode)
                cliRow(.codex)
                Text("Uses the login you already have in Terminal, so answers count towards that plan. Runs with no tools and no hooks, in an empty folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What leaves this Mac") {
                Text("""
                On-device answers never leave this Mac. Questions to Claude or ChatGPT go to Anthropic or OpenAI with your key and are billed to your account; OpenAI is asked not to store them. The command-line tools send questions to their vendor. Islet keeps no history on disk, and an islet://ask link only fills in the question: it never sends it.
                """)
                .font(.caption).foregroundStyle(.secondary)
                Text("Keys are protected by your login keychain. Builds signed with a Developer ID add a code-identity check.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // A new default replaces whatever was picked in the island for this session.
        .onChange(of: model.settings.ask.provider) { _, _ in model.ask.sessionProvider = nil }
    }

    private func refresh() {
        appleStatus = AIAssist.shared.statusText
        for kind in [AskProviderKind.anthropic, .openai] {
            keyStored[kind] = service.secrets.contains(kind.keyAccount ?? "")
        }
        for kind in [AskProviderKind.claudeCode, .codex] {
            cliPaths[kind] = service.cliBinary(for: kind)?.path
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
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(kind.title) {
                Text(cliPaths[kind].map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not found")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            TextField("Model", text: Binding(get: { model.settings.ask.models[kind.rawValue] ?? "" },
                                             set: { model.settings.ask.setModel($0, for: kind) }),
                      prompt: Text("Default"))
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
                        SecureField("", text: $draft, prompt: Text(kind == .anthropic ? "sk-ant-…" : "sk-…"))
                            .frame(minWidth: 180)
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
