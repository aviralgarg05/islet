import AppKit
import IsletCore
import SwiftUI

/// Settings → Coding agents → Usage limits: sources for plan limits, and the Claude Code
/// status line installer. `~/.claude/settings.json` is only written when the user confirms
/// the exact change in a sheet. Home's "Show usage" opens Settings here.
struct UsageLimitsSection: View {
    @Bindable var model: AppModel
    @ViewState private var claudeStatus: ClaudeStatusLineSetup.Status?
    @ViewState private var pending: PendingStatusLineEdit?
    @ViewState private var message: String?
    @Environment(\.snapshotMode) private var snapshotMode

    static var codexSessions: URL { IsletPaths.home.appendingPathComponent(".codex/sessions") }

    private var claudeSettingsFile: URL { model.agentUsage.claudeSettingsFile }
    /// Snapshots run from the build folder, which has no `isletctl` beside the app.
    private var cliAvailable: Bool { snapshotMode || FileManager.default.isExecutableFile(atPath: AppActions.cliPath) }

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.claudeUsageEnabled) {
                Text("Claude Code limits")
                Text("Its 5-hour and weekly limits, on Home.")
            }
            .settingsAnchor("agents.claudeUsage")
            if model.settings.claudeUsageEnabled {
                HStack(alignment: .center, spacing: 10) {
                    Text(claudeText).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    claudeButton
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Toggle(isOn: $model.settings.codexUsageEnabled) {
                Text("Codex limits")
                Text(model.settings.codexUsageEnabled ? codexText : "Its 5-hour and weekly limits, on Home.")
            }
            .settingsAnchor("agents.codexUsage")
            MoreUsageRows(model: model)
        } header: {
            Text("Usage limits")
        } footer: {
            SettingsFooter("Claude Code, Codex and Ollama are read on this Mac. OpenRouter and Copilot are asked with your own key when the island opens, at most every few minutes; no other app's sign-in is ever read. The closed island stays quiet until a Claude or Codex limit reaches 90%.")
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
            Button("Show usage…") { plan(install: true) }.disabled(!cliAvailable)
        case .installed?:
            Button("Remove…") { plan(install: false) }
        default:
            EmptyView()
        }
    }

    /// Where the figures come from and what the button changes, in plain words. The exact
    /// change to Claude Code's settings is shown in the sheet before anything is written.
    private var claudeText: String {
        switch claudeStatus {
        case .notInstalled(let current)?:
            guard cliAvailable else { return "This copy of Islet can't add the status line Claude Code needs to share its limits." }
            return current == nil
                ? "Claude Code shares its limits only with its status line, the line under its prompt. Show usage adds Islet's line there."
                : "Claude Code shares its limits only with its status line, the line under its prompt. Show usage adds Islet's around yours, which keeps showing."
        case .installed?:
            return model.agentUsage.claude == nil
                ? "Waiting for Claude Code. The figures arrive the next time it shows its status line."
                : "On. The figures update whenever Claude Code shows its status line."
        case .unsupported(let why)?:
            return why
        case nil:
            return ""
        }
    }

    private var codexText: String {
        FileManager.default.fileExists(atPath: Self.codexSessions.path)
            ? "Its 5-hour and weekly limits, on Home. They update as Codex works."
            : "Codex hasn't run on this Mac yet. Its limits appear after its first session; then switch this off and on again."
    }

    private func refresh() {
        claudeStatus = ClaudeStatusLineSetup.status(of: try? Data(contentsOf: claudeSettingsFile))
        // Home's hint follows: from the offer to waiting, or gone.
        model.agentUsage.refreshClaudeHint()
    }

    private func plan(install: Bool) {
        message = nil
        // The status line names isletctl inside Islet: from a temporary copy of a download it
        // would point nowhere after the next launch, so offer to move to Applications first.
        if install {
            switch AppActions.offerMoveToApplications(.connecting("Claude Code")) {
            case .moving: return
            case .declined:
                message = "Move Islet to Applications first, so Claude Code can keep finding it."
                return
            case .notNeeded: break
            }
        }
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
