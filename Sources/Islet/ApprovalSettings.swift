import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Integrations → Coding agents: approvals from the notch and the Claude Code installer.
struct ApprovalSettingsRows: View {
    @Bindable var model: AppModel
    @ViewState private var plan: ClaudeHookInstaller.Plan?
    @ViewState private var confirming = false
    @ViewState private var status: String?

    private static let waits: [Double] = [60, 120, 300, 600, 1800, 3600]

    var body: some View {
        Toggle("Answer agent approvals in the notch", isOn: $model.settings.approvalsEnabled)
        Picker("Hand back to the terminal after", selection: $model.settings.approvalWait) {
            ForEach(Array(Set(Self.waits + [model.settings.approvalWait])).sorted(), id: \.self) { seconds in
                Text(Self.label(seconds)).tag(seconds)
            }
        }
        .disabled(!model.settings.approvalsEnabled)
        HStack {
            Button("Install for Claude Code…") { preview() }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        Text("Permission requests, questions and plans from Claude Code, Codex and Cursor appear as a card in the notch. Risky commands need a second click. Unanswered cards go back to the terminal. For Codex, add the hook from the docs and trust it once with /hooks.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .alert("Add Islet's hooks to Claude Code?", isPresented: $confirming, presenting: plan) { _ in
                Button("Install") { install() }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text("These go into ~/.claude/settings.json. Your own hooks and settings stay as they are, and the current file is kept as settings.json.bak.\n\n" + plan.changes.joined(separator: "\n"))
            }
    }

    /// How hooks call the CLI: the copy inside the app, or `isletctl` on PATH for dev builds.
    private var executable: String {
        FileManager.default.isExecutableFile(atPath: AppActions.cliPath) ? AppActions.cliPath : "isletctl"
    }

    private var wait: Int { Int(model.settings.approvalWait) }

    private func preview() {
        do {
            let p = try ClaudeHookSetup.plan(executable: executable, wait: wait)
            if p.isUpToDate {
                status = "Already installed."
            } else {
                plan = p
                confirming = true
            }
        } catch {
            status = String(describing: error)
        }
    }

    private func install() {
        do {
            let p = try ClaudeHookSetup.install(executable: executable, wait: wait)
            status = p.isUpToDate ? "Already installed." : "Installed. New Claude Code sessions use it."
        } catch {
            status = String(describing: error)
        }
    }

    static func label(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s % 3600 == 0 { return s == 3600 ? "1 hour" : "\(s / 3600) hours" }
        if s % 60 == 0 { return s == 60 ? "1 minute" : "\(s / 60) minutes" }
        return "\(s) seconds"
    }
}
