import AppKit
import IsletCore
import SwiftUI

/// Settings → Integrations → Usage limits: sources for plan limits, and the Claude Code
/// status line installer. `~/.claude/settings.json` is only written when the user confirms
/// the exact change in a sheet. Home's "Show usage" opens Settings here.
struct UsageLimitsSection: View {
    @Bindable var model: AppModel
    @ViewState private var claudeStatus: ClaudeStatusLineSetup.Status?
    @ViewState private var pending: PendingStatusLineEdit?
    @ViewState private var message: String?

    static var codexSessions: URL { IsletPaths.home.appendingPathComponent(".codex/sessions") }

    private var claudeSettingsFile: URL { model.agentUsage.claudeSettingsFile }
    private var cliAvailable: Bool { FileManager.default.isExecutableFile(atPath: AppActions.cliPath) }
    /// Where the change is made, as people see it in Finder and the terminal.
    private var claudeSettingsPath: String { (claudeSettingsFile.path as NSString).abbreviatingWithTildeInPath }

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
            StatusLineChangeSheet(change: p, file: claudeSettingsFile) {
                apply(p)
            } onCancel: {
                pending = nil
            }
        }
    }

    @ViewBuilder private var claudeButton: some View {
        switch claudeStatus {
        case .notInstalled?:
            Button("Show Claude usage…") { plan(install: true) }.disabled(!cliAvailable)
        case .installed?:
            Button("Remove…") { plan(install: false) }
        default:
            EmptyView()
        }
    }

    /// What the button changes and when the figures update, in plain words.
    private var claudeText: String {
        let why = "Claude Code saves its plan usage nowhere Islet can read. It only hands it to its status line, the line under its prompt in the terminal."
        let change = "Only statusLine in \(claudeSettingsPath) changes, and the old file is kept as settings.json.bak."
        let updates = "The figures update whenever Claude Code shows its status line in a terminal."
        switch claudeStatus {
        case .notInstalled(let current)?:
            guard cliAvailable else { return "isletctl isn't in this copy of Islet, so its status line can't be added." }
            let adds = current.map { "Show Claude usage adds Islet's status line around yours (\($0)), which keeps showing as before." }
                ?? "Show Claude usage adds Islet's status line there."
            return [why, adds, change, updates].joined(separator: " ")
        case .installed(let original)?:
            let own = original.map { " Your own (\($0)) still runs inside it." } ?? ""
            let state = model.agentUsage.claude == nil
                ? "Waiting for Claude Code: the figures arrive the next time it shows its status line in a terminal."
                : updates
            return "Islet's status line is in Claude Code.\(own) \(state)"
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
        claudeStatus = ClaudeStatusLineSetup.status(of: try? Data(contentsOf: claudeSettingsFile))
        // Home's hint follows: from the offer to waiting, or gone.
        model.agentUsage.refreshClaudeHint()
    }

    private func plan(install: Bool) {
        message = nil
        let current = try? Data(contentsOf: claudeSettingsFile)
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
            try ClaudeStatusLineSetup.apply(p.edit, to: claudeSettingsFile)
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
            Text(change.install ? "Add Islet's status line to Claude Code" : "Remove Islet's status line").font(.headline)
            Text("Islet will change only the statusLine setting in \((file.path as NSString).abbreviatingWithTildeInPath). The rest of the file stays as it is, and the current file is kept as settings.json.bak.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            commandBox("Now", change.edit.before)
            commandBox("After", change.edit.after)
            if change.install, change.edit.before != nil {
                Text("Your status line keeps working: Islet runs it with the same input and shows its output.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if change.install {
                Text("Claude Code runs its status line in the terminal after each reply, and that is when the figures update. Islet saves them to a private file and never contacts the network.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(change.install ? "Add" : "Remove", action: onConfirm).keyboardShortcut(.defaultAction)
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
