import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Advanced: everything technical, kept off the feature pages. The local API, the
/// iPhone bridge, hook commands, the MCP server, script widgets, links, the settings file,
/// diagnostics and reset.
struct AdvancedSettings: View {
    @Bindable var model: AppModel
    @ViewState private var copiedToken = false
    @ViewState private var confirmingReset = false
    @ViewState private var confirmingReplace = false
    @Environment(\.snapshotMode) private var snapshotMode

    private var cli: String { AppActions.cliPath }

    var body: some View {
        Form {
            Section { SettingsHero(page: .advanced) }
            localAPI
            LANBridgeSection(model: model)
            agents
            scripts
            Section {
                CodeBlock(title: "Open these from Shortcuts, scripts or a browser on this Mac",
                          code: "islet://notify?title=Hello\nislet://timer?minutes=5\nislet://media/playpause\nislet://awake?for=1h\nislet://ask?q=…")
                    .settingsAnchor("advanced.urlScheme")
            } header: {
                Text("Links")
            }
            Section("Settings file") {
                if let problem = model.settingsProblem {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            // Already broken at launch with no copy of a good one: say so plainly.
                            Text(problem.sentence(file: "config.json") + (model.settingsOrigin == .defaults
                                ? " Islet is using its default settings for now."
                                : " Islet is using your last good settings."))
                            Text("Nothing is saved over the file until it's fixed. Your changes here still apply.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Replace…") { confirmingReplace = true }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Location") {
                    Text((IsletPaths.configFile.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                .settingsAnchor("advanced.config")
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        model.saveSettings()
                        NSWorkspace.shared.activateFileViewerSelecting([IsletPaths.configFile])
                    }
                    Button("Open config.json") {
                        model.saveSettings()
                        NSWorkspace.shared.open(IsletPaths.configFile)
                    }
                }
            }
            diagnostics
            Section {
                HStack {
                    Text("Reset all settings")
                    Spacer()
                    Button("Reset…", role: .destructive) { confirmingReset = true }
                }
                .settingsAnchor("advanced.reset")
            } footer: {
                SettingsFooter("Puts every setting back to how Islet came, including app rules. API keys, connected agents and launch at login stay as they are.")
            }
        }
        .formStyle(.grouped)
        .alert("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every setting goes back to how Islet came. This can't be undone.")
        }
        .alert("Replace config.json?", isPresented: $confirmingReplace) {
            Button("Replace", role: .destructive) { model.replaceBrokenSettingsFile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text((model.settingsOrigin == .defaults
                  ? "Islet's default settings are written in its place."
                  : "The settings Islet is using now are written in its place.")
                 + " The file as it is now is kept beside it as config.json.broken.")
        }
    }

    private var localAPI: some View {
        Section {
            Toggle(isOn: $model.settings.apiEnabled) {
                Text("Accept requests from apps on this Mac")
                Text("Lets scripts and other apps show things in the island. Only this Mac can reach it, and every request needs the token.")
            }
            .settingsAnchor("advanced.api")
            LabeledContent("Status") { Text(model.apiStatus).foregroundStyle(.secondary) }
            LabeledContent("Port") { PortField(port: $model.settings.apiPort, other: model.settings.lanPort) }
                .settingsAnchor("advanced.apiPort")
            LabeledContent("Token") {
                HStack(spacing: 8) {
                    Button(copiedToken ? "Copied" : "Copy token") {
                        AppActions.copyToken()
                        copiedToken = true
                    }
                    Button("API guide") {
                        if let doc = Bundle.main.url(forResource: "API", withExtension: "md") { NSWorkspace.shared.open(doc) }
                    }
                }
            }
            .settingsAnchor("advanced.token")
            Toggle(isOn: $model.settings.shareMirroredActivities) {
                Text("Let scripts read Live Activities and notifications")
                Text("What Islet mirrors often holds addresses, names and what someone wrote, so it\u{2019}s left out unless you allow it.")
            }
            .settingsAnchor("advanced.shareLive")
            // Moved here from Now Playing's sources: it is the API's, not a player's.
            Toggle(isOn: MediaSourceToggles.binding(.external, model: model)) {
                Text("Scripts can show what\u{2019}s playing")
                Text("Apps and scripts that send a song to the local API show it in the island, as Music and Spotify do.")
            }
            .settingsAnchor("advanced.mediaScripts")
            CodeBlock(title: "Command-line tool: put isletctl on your PATH", code: "ln -sf '\(cli)' /opt/homebrew/bin/isletctl")
                .settingsAnchor("advanced.cli")
        } header: {
            Text("Local API")
        }
    }

    private var agents: some View {
        Section {
            AgentHookDisclosure(title: "Claude Code", file: "~/.claude/settings.json", code: Self.snippet(.claudeCode, cli: cli, wait: wait),
                                expanded: snapshotMode)
                .settingsAnchor("advanced.hooks")
            AgentHookDisclosure(title: "Codex", file: "~/.codex/hooks.json, and hooks = true under [features] in ~/.codex/config.toml",
                                code: Self.snippet(.codex, cli: cli, wait: wait))
            AgentHookDisclosure(title: "Cursor", file: "~/.cursor/hooks.json", code: Self.snippet(.cursor, cli: cli, wait: wait))
            AgentHookDisclosure(title: "MCP server", file: "For Claude Code; other apps take the same command",
                                code: "claude mcp add --scope user islet -- '\(cli)' mcp")
                .settingsAnchor("advanced.mcp")
        } header: {
            Text("Coding agents")
        } footer: {
            SettingsFooter("Connect on the Coding agents page adds these for you. They're here for dotfiles and other setups.")
        }
    }

    private var wait: Int { Int(model.settings.approvalWait) }

    private var scripts: some View {
        Section {
            Toggle(isOn: $model.settings.pluginsEnabled) {
                Text("Run scripts from the plugins folder")
                Text("xbar and SwiftBar scripts show on the Widgets page. They can use what you allowed Islet, such as your calendars, the Downloads folder and control of Music or Spotify, so add only scripts you trust.")
            }
            .settingsAnchor("advanced.scripts")
            Group {
                PluginFolderRow(model: model)
                    .settingsAnchor("advanced.pluginsFolder")
                HStack {
                    Spacer()
                    Button("Add examples") { AppActions.installExamplePlugins(model) }
                    Button("Open folder") { AppActions.openPluginsFolder(model) }
                }
            }
            .disabled(!model.settings.pluginsEnabled)
        } header: {
            Text("Script widgets")
        }
    }

    private var diagnostics: some View {
        Section {
            // The local API's and the bridge's own status rows are in their sections above.
            LabeledContent("Now Playing helper") {
                Text(model.systemMedia.isRunning ? "Running" : "Not running")
                    .foregroundStyle(model.systemMedia.isRunning ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            .settingsAnchor("advanced.diagnostics")
            // In the Ask & AI page's words; what macOS reported is in the help.
            LabeledContent("Apple Intelligence") {
                Text(AISettingsView.appleStatus).foregroundStyle(.secondary).help(AIAssist.shared.statusText)
            }
            LabeledContent("Accessibility") {
                Text(model.accessibilityTrusted ? "Allowed" : "Not allowed").foregroundStyle(.secondary)
            }
            // The Ask box only says a tool isn't installed; where Islet looked is here.
            ForEach([AskProviderKind.claudeCode, .codex], id: \.self) { kind in
                let found = model.ask.service.cliBinary(for: kind)
                LabeledContent {
                    Text(found.map { Self.tilde($0.path) } ?? "Not found")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    Text(kind.title)
                    if found == nil { Text("Looked in \(searchedFolders(kind))").textSelection(.enabled) }
                }
            }
            .settingsAnchor("advanced.cliPaths")
            HStack {
                Spacer()
                Button("Show a test activity") { AppActions.previewAppearance(model) }
            }
        } header: {
            Text("Diagnostics")
        }
    }

    private static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// The folders the Ask box looks in for a command-line tool, as a list.
    private func searchedFolders(_ kind: AskProviderKind) -> String {
        let folders = AskCLI.searchPaths(for: kind, home: IsletPaths.home.path)
            .map { Self.tilde(($0 as NSString).deletingLastPathComponent) }
        guard let last = folders.last else { return "" }
        return folders.count > 1 ? folders.dropLast().joined(separator: ", ") + " and " + last : last
    }

    /// The hooks Connect would add to a fresh file, from the installers themselves.
    static func snippet(_ agent: CodingAgent, cli: String, wait: Int) -> String {
        switch agent {
        case .claudeCode:
            return (try? ClaudeHookInstaller.plan(existing: nil, executable: cli, wait: wait)).map { String(decoding: $0.merged, as: UTF8.self) } ?? ""
        case .codex:
            let hooks = (try? CodexHookInstaller.plan(existing: nil, executable: cli, wait: wait)).map { String(decoding: $0.merged, as: UTF8.self) } ?? ""
            // `notify` is optional: the hooks already report each turn.
            return hooks + "\n# ~/.codex/config.toml\nnotify = [\"\(cli)\", \"hook\", \"codex\"]\n\n[features]\nhooks = true"
        case .cursor:
            return (try? CursorHookInstaller.plan(existing: nil, executable: cli, wait: wait)).map { String(decoding: $0.merged, as: UTF8.self) } ?? ""
        }
    }
}

/// One agent's hook setup, folded away until asked for.
private struct AgentHookDisclosure: View {
    let title: String
    let file: String
    let code: String
    @ViewState private var expanded: Bool

    init(title: String, file: String, code: String, expanded: Bool = false) {
        self.title = title
        self.file = file
        self.code = code
        _expanded = ViewState(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Tall enough to read a whole hook; the rest scrolls, with the bottom edge fading.
            CodeBlock(title: file, code: code.trimmingCharacters(in: .whitespacesAndNewlines), maxHeight: 300)
        } label: {
            Text(title)
        }
    }
}
