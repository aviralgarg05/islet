import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Coding agents: connecting Claude Code, Codex and Cursor, answering their
/// requests in the island, and their plan limits. The hook commands themselves are in Advanced.
struct CodingAgentsSettings: View {
    @Bindable var model: AppModel
    @ViewState private var connections: [CodingAgent: AgentConnection] = [:]
    @ViewState private var notes: [CodingAgent: String] = [:]
    @ViewState private var pending: PendingConnection?

    private static let waits: [Double] = [60, 120, 300, 600, 1800, 3600]

    var body: some View {
        Form {
            Section { SettingsHero(page: .agents) }
            Section {
                ForEach(CodingAgent.allCases) { agent in
                    AgentConnectionRow(agent: agent, connection: connections[agent], note: notes[agent],
                                       moved: model.agentsNeedingUpdate.contains(agent)) {
                        preview(agent)
                    } disconnect: {
                        previewDisconnect(agent)
                    }
                    .settingsAnchor("agents.\(agent.rawValue)")
                }
            } header: {
                Text("Connections")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsFooter("Connecting adds a few lines to the agent's own settings so it can tell Islet what it's doing. You see the change first, your other settings stay as they are, and a backup is kept.")
                    SettingsLink(text: "Set it up by hand in Advanced", page: .advanced, anchor: "advanced.hooks")
                }
            }
            Section {
                Toggle(isOn: $model.settings.approvalsEnabled) {
                    Text("Answer requests in the island")
                    Text("Permission requests, questions and plans appear as a card. Risky commands need a second click.")
                }
                .settingsAnchor("agents.approvals")
                Picker("Hand back to the terminal after", selection: $model.settings.approvalWait) {
                    ForEach(Array(Set(Self.waits + [model.settings.approvalWait])).sorted(), id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds)
                    }
                }
                .disabled(!model.settings.approvalsEnabled)
                .settingsAnchor("agents.wait")
            } header: {
                Text("Approvals")
            } footer: {
                SettingsFooter("A request you don't answer goes back to the terminal, as if Islet weren't there.")
            }
            UsageLimitsSection(model: model)
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: model.settings.approvalWait) { _, _ in refresh() }
        .sheet(item: $pending) { p in
            AgentConnectSheet(plan: p.plan) {
                connect(p.plan)
            } onCancel: {
                pending = nil
            }
        }
    }

    /// How hooks call the CLI: the copy inside the app, or `isletctl` on PATH for dev builds.
    static var executable: String {
        AppActions.isExecutable(AppActions.cliPath) ? AppActions.cliPath : "isletctl"
    }

    private var wait: Int { Int(model.settings.approvalWait) }

    private func refresh() {
        for agent in CodingAgent.allCases {
            connections[agent] = AgentHookSetup.connection(agent, home: IsletPaths.home, executable: Self.executable, wait: wait)
        }
        model.checkAgentHooks()
    }

    private func preview(_ agent: CodingAgent) {
        notes[agent] = nil
        // From a temporary copy macOS made of a download, the hooks would point nowhere after
        // the next launch: offer to move to Applications first.
        switch AppActions.offerMoveToApplications(.connecting(agent.title)) {
        case .moving: return
        case .declined:
            notes[agent] = "Move Islet to Applications first, so \(agent.title) can keep finding it."
            return
        case .notNeeded: break
        }
        do {
            let plan = try AgentHookSetup.plan(agent, home: IsletPaths.home, executable: Self.executable, wait: wait)
            if plan.isUpToDate { refresh() } else { pending = PendingConnection(plan: plan) }
        } catch {
            notes[agent] = Self.message(for: error, agent: agent)
        }
    }

    private func previewDisconnect(_ agent: CodingAgent) {
        notes[agent] = nil
        do {
            let plan = try AgentHookSetup.disconnectPlan(agent, home: IsletPaths.home)
            if plan.isUpToDate { refresh() } else { pending = PendingConnection(plan: plan) }
        } catch {
            notes[agent] = Self.message(for: error, agent: agent)
        }
    }

    private func connect(_ plan: AgentHookPlan) {
        pending = nil
        do {
            try AgentHookSetup.apply(plan)
            switch plan.kind {
            case .disconnect:
                notes[plan.agent] = "Disconnected. \(plan.agent.title) no longer tells Islet what it's doing."
            case .connect:
                notes[plan.agent] = plan.agent == .codex
                    ? "Connected. In Codex, type /hooks once to trust Islet's hooks."
                    : "Connected. New \(plan.agent.title) sessions use it."
            }
        } catch {
            notes[plan.agent] = Self.message(for: error, agent: plan.agent)
        }
        refresh()
    }

    /// The installers' own errors read as sentences; anything else (permissions, disk) as the system says it.
    static func message(for error: Error, agent: CodingAgent) -> String {
        if let e = error as? ClaudeHookInstaller.InstallError {
            return e.description(file: agent.files(home: IsletPaths.home)[0].lastPathComponent)
        }
        if let e = error as? CodexConfigEditor.EditError { return e.description }
        return error.localizedDescription
    }

    static func label(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s % 3600 == 0 { return s == 3600 ? "1 hour" : "\(s / 3600) hours" }
        if s % 60 == 0 { return s == 60 ? "1 minute" : "\(s / 60) minutes" }
        return "\(s) seconds"
    }
}

private struct PendingConnection: Identifiable {
    let id = UUID()
    let plan: AgentHookPlan
}

/// One agent: its mark, where its connection stands, and the buttons that connect, update
/// or disconnect it.
private struct AgentConnectionRow: View {
    let agent: CodingAgent
    let connection: AgentConnection?
    let note: String?
    /// Its hooks call an isletctl that isn't there any more.
    let moved: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentMark(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let connection {
                    HStack(spacing: 5) {
                        Circle().fill(colour(connection)).frame(width: 6, height: 6)
                        Text(detail(connection)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            switch connection {
            case .connected?:
                Button("Disconnect…", action: disconnect).buttonStyle(.borderless).foregroundStyle(.secondary)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Connected")
            case .needsUpdate?:
                Button("Disconnect…", action: disconnect).buttonStyle(.borderless).foregroundStyle(.secondary)
                Button("Update…", action: connect)
            case .problem?, nil:
                EmptyView()
            default:
                Button("Connect…", action: connect)
            }
        }
        .padding(.vertical, 1)
    }

    private func detail(_ c: AgentConnection) -> String {
        switch c {
        case .problem(let why): return why
        case .needsUpdate:
            return moved ? "Islet has moved since it was connected, so \(agent.title) can't reach it. Update it to fix this."
                : "Connected to an older setup. Update it so it keeps working as you set below."
        case .notFound: return "Not found on this Mac yet. You can still connect it."
        default: return c.label
        }
    }

    private func colour(_ c: AgentConnection) -> Color {
        switch c {
        case .connected: return .green
        case .needsUpdate, .problem: return .orange
        default: return Color.secondary.opacity(0.5)
        }
    }
}

/// A small tile for an agent that has no app icon to show.
struct AgentMark: View {
    let agent: CodingAgent

    var body: some View {
        let (symbol, colour): (String, Color) = switch agent {
        case .claudeCode: ("asterisk", Color(red: 0.85, green: 0.47, blue: 0.34))
        case .codex: ("terminal.fill", Color(white: 0.16))
        case .cursor: ("cursorarrow", Color(white: 0.3))
        }
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(colour.gradient))
            .accessibilityHidden(true)
    }
}

/// What connecting changes, file by file, before anything is written.
private struct AgentConnectSheet: View {
    let plan: AgentHookPlan
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var disconnecting: Bool { plan.kind == .disconnect }
    private var verb: String { disconnecting ? "Disconnect" : plan.wasConnected ? "Update" : "Connect" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentMark(agent: plan.agent)
                Text("\(verb) \(plan.agent.title)?").font(.headline)
            }
            Text(disconnecting
                 ? "Islet takes its own hooks out of \(plan.agent.title)'s settings. Your own settings and hooks stay as they are, and the file is copied to a .bak file first."
                 : "Islet adds its hooks to \(plan.agent.title)'s settings. Your own settings and hooks stay as they are, and each file is copied to a .bak file first.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            ForEach(plan.changedFiles, id: \.url) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text((file.url.path as NSString).abbreviatingWithTildeInPath).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(file.changes.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
            }
            if plan.agent == .codex && !disconnecting {
                Text("Codex asks once before it runs new hooks: type /hooks in Codex and trust Islet's.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(verb, role: disconnecting ? .destructive : nil, action: onConfirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
