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
            Button("Reset", role: .destructive) { model.settings = IsletSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every setting goes back to how Islet came. This can't be undone.")
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
                    Button(copiedToken ? "Copied" : "Copy Token") {
                        AppActions.copyToken()
                        copiedToken = true
                    }
                    Button("API Guide") {
                        if let doc = Bundle.main.url(forResource: "API", withExtension: "md") { NSWorkspace.shared.open(doc) }
                    }
                }
            }
            .settingsAnchor("advanced.token")
            Toggle(isOn: $model.settings.shareMirroredActivities) {
                Text("Let scripts read Live Activities")
                Text("They often hold addresses, names and scores, so they're left out unless you allow it.")
            }
            .settingsAnchor("advanced.shareLive")
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
                Text("xbar and SwiftBar scripts show on the Widgets page. They run with Islet's permissions, so add only scripts you trust.")
            }
            .settingsAnchor("advanced.scripts")
            Group {
                PluginFolderRow(model: model)
                    .settingsAnchor("advanced.pluginsFolder")
                HStack {
                    Spacer()
                    Button("Add Examples") { AppActions.installExamplePlugins(model) }
                    Button("Open Folder") { AppActions.openPluginsFolder(model) }
                }
            }
            .disabled(!model.settings.pluginsEnabled)
        } header: {
            Text("Script widgets")
        }
    }

    private var diagnostics: some View {
        Section {
            LabeledContent("Local API") { Text(model.apiStatus).foregroundStyle(.secondary) }
                .settingsAnchor("advanced.diagnostics")
            LabeledContent("iPhone bridge") { Text(model.lan.status).foregroundStyle(.secondary) }
            LabeledContent("Now Playing helper") {
                Text(model.systemMedia.isRunning ? "Running" : "Not running")
                    .foregroundStyle(model.systemMedia.isRunning ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            LabeledContent("Apple Intelligence") { Text(AIAssist.shared.statusText).foregroundStyle(.secondary) }
            LabeledContent("Accessibility") {
                Text(MediaKeyInterceptor.hasAccessibility ? "Allowed" : "Not allowed").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Show a Test Activity") { AppActions.previewAppearance(model) }
            }
        } header: {
            Text("Diagnostics")
        }
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
            CodeBlock(title: file, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        } label: {
            Text(title)
        }
    }
}
