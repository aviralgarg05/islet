import AppKit
import IsletCore
import SwiftUI

/// Settings → Integrations → Usage limits: sources for plan limits, and the Claude Code
/// status line installer. `~/.claude/settings.json` is only written when the user confirms
/// the exact change in a sheet.
struct UsageLimitsSection: View {
    @Bindable var model: AppModel
    @ViewState private var claudeStatus: ClaudeStatusLineSetup.Status?
    @ViewState private var pending: PendingStatusLineEdit?
    @ViewState private var message: String?

    static var claudeSettingsFile: URL { IsletPaths.home.appendingPathComponent(".claude/settings.json") }
    static var codexSessions: URL { IsletPaths.home.appendingPathComponent(".codex/sessions") }

    private var cliAvailable: Bool { FileManager.default.isExecutableFile(atPath: AppActions.cliPath) }

    var body: some View {
        Section("Usage limits") {
            Toggle("Claude Code 5-hour and weekly limits", isOn: $model.settings.claudeUsageEnabled)
            if model.settings.claudeUsageEnabled {
                HStack(alignment: .firstTextBaseline) {
                    Text(claudeText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    claudeButton
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Toggle("Codex 5-hour and weekly limits", isOn: $model.settings.codexUsageEnabled)
            if model.settings.codexUsageEnabled {
                Text(codexText).font(.caption).foregroundStyle(.secondary)
            }
            Text("Islet reads these figures from files on this Mac and never sends them anywhere. The closed island stays quiet until a limit reaches 90%.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
        .sheet(item: $pending) { p in
            StatusLineChangeSheet(change: p, file: Self.claudeSettingsFile) {
                apply(p)
            } onCancel: {
                pending = nil
            }
        }
    }

    @ViewBuilder private var claudeButton: some View {
        switch claudeStatus {
        case .notInstalled?:
            Button("Install status line for Claude Code…") { plan(install: true) }.disabled(!cliAvailable)
        case .installed?:
            Button("Remove…") { plan(install: false) }
        default:
            EmptyView()
        }
    }

    private var claudeText: String {
        switch claudeStatus {
        case .notInstalled(let current?)?:
            return "Claude Code has its own status line (\(current)). Islet wraps it, so it keeps working."
        case .notInstalled?:
            return cliAvailable ? "Claude Code passes your plan's usage to its status line. Install Islet's to read it."
                : "isletctl isn't in this copy of Islet, so the status line can't be installed."
        case .installed(let original?)?:
            return "Status line installed. Your own (\(original)) still runs inside it."
        case .installed?:
            return "Status line installed."
        case .unsupported(let why)?:
            return why
        case nil:
            return ""
        }
    }

    private var codexText: String {
        guard FileManager.default.fileExists(atPath: Self.codexSessions.path) else {
            return "Codex hasn't run on this Mac yet. After its first session, switch this off and on again."
        }
        return "Read from the newest session log in ~/.codex/sessions when it changes."
    }

    private func refresh() {
        claudeStatus = ClaudeStatusLineSetup.status(of: try? Data(contentsOf: Self.claudeSettingsFile))
    }

    private func plan(install: Bool) {
        message = nil
        let current = try? Data(contentsOf: Self.claudeSettingsFile)
        do {
            let edit = install ? try ClaudeStatusLineSetup.install(into: current, cli: AppActions.cliPath)
                : try ClaudeStatusLineSetup.remove(from: current)
            if edit.changesFile { pending = PendingStatusLineEdit(install: install, edit: edit) } else { refresh() }
        } catch {
            message = String(describing: error)
        }
    }

    private func apply(_ p: PendingStatusLineEdit) {
        pending = nil
        do {
            try ClaudeStatusLineSetup.apply(p.edit, to: Self.claudeSettingsFile)
            message = nil
        } catch {
            message = String(describing: error)
        }
        refresh()
    }
}

struct PendingStatusLineEdit: Identifiable {
    let id = UUID()
    var install: Bool
    var edit: ClaudeStatusLineSetup.Edit
}

/// Shows exactly what changes in `settings.json` before anything is written.
struct StatusLineChangeSheet: View {
    let change: PendingStatusLineEdit
    let file: URL
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(change.install ? "Install the status line for Claude Code" : "Remove Islet's status line").font(.headline)
            Text("Islet will change only the statusLine setting in \((file.path as NSString).abbreviatingWithTildeInPath). The rest of the file stays as it is, and the current file is kept as settings.json.bak.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            commandBox("Now", change.edit.before)
            commandBox("After", change.edit.after)
            if change.install, change.edit.before != nil {
                Text("Your status line keeps working: Islet runs it with the same input and shows its output.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if change.install {
                Text("Claude Code runs the status line after each reply. Islet saves the figures to a private file and never contacts the network.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(change.install ? "Install" : "Remove", action: onConfirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func commandBox(_ label: String, _ command: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Text(command ?? "No status line")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(command == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }
}
