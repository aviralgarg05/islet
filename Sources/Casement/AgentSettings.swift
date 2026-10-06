import AppKit
import CasementCore
import CasementSystem
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
            MutedFromIslandSection(model: model, page: .agents)
            Section {
                // Agents reach Casement through the same door as scripts: with it shut, a connected
                // agent's updates and requests go nowhere.
                if !model.settings.apiEnabled {
                    AccessRow(text: "Casement isn\u{2019}t accepting requests from apps, so connected agents can\u{2019}t reach it.",
                              button: "Turn on") {
                        model.settings.apiEnabled = true
                    }
                }
                ForEach(CodingAgent.allCases) { agent in
                    AgentConnectionRow(agent: agent, connection: connections[agent], note: notes[agent],
                                       moved: model.agentsNeedingUpdate.contains(agent),
                                       unreachable: !model.settings.apiEnabled) {
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
                    SettingsFooter("Connecting adds a few lines to the agent's own settings so it can tell Casement what it's doing. You see the change first, your other settings stay as they are, and a backup is kept.")
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
                SettingsFooter("A request you don't answer goes back to the terminal, as if Casement weren't there.")
            }
            UsageLimitsSection(model: model)
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // Hooks connected or removed by hand while this page shows.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: model.settings.approvalWait) { _, _ in refresh() }
        .sheet(item: $pending) { p in
            AgentConnectSheet(plan: p.plan) {
                connect(p.plan)
            } onCancel: {
                pending = nil
            }
        }
    }

    /// How hooks call the CLI: the copy inside the app, or `casementctl` on PATH for dev builds.
    static var executable: String {
        AppActions.isExecutable(AppActions.cliPath) ? AppActions.cliPath : "casementctl"
    }

    private var wait: Int { Int(model.settings.approvalWait) }

    private func refresh() {
        for agent in CodingAgent.allCases {
            connections[agent] = AgentHookSetup.connection(agent, home: CasementPaths.home, executable: Self.executable, wait: wait)
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
            notes[agent] = "Move Casement to Applications first, so \(agent.title) can keep finding it."
            return
        case .notNeeded: break
        }
        do {
            let plan = try AgentHookSetup.plan(agent, home: CasementPaths.home, executable: Self.executable, wait: wait)
            if plan.isUpToDate { refresh() } else { pending = PendingConnection(plan: plan) }
        } catch {
            notes[agent] = Self.message(for: error, agent: agent)
        }
    }

    private func previewDisconnect(_ agent: CodingAgent) {
        notes[agent] = nil
        do {
            let plan = try AgentHookSetup.disconnectPlan(agent, home: CasementPaths.home)
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
                notes[plan.agent] = "Disconnected. \(plan.agent.title) no longer tells Casement what it's doing."
            case .connect:
                notes[plan.agent] = plan.agent == .codex
                    ? "Connected. In Codex, type /hooks once and trust Casement\u{2019}s."
                    : "Connected. New \(plan.agent.title) sessions use it."
            }
        } catch {
            notes[plan.agent] = Self.message(for: error, agent: plan.agent)
        }
        refresh()
    }

    /// The installers' own errors, and anything else (permissions, disk), as plain sentences.
    static func message(for error: Error, agent: CodingAgent) -> String {
        AgentConnection.problemText(for: error, agent: agent)
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
    /// Its hooks call an casementctl that isn't there any more.
    let moved: Bool
    /// Casement isn't accepting requests from apps, so even a connected agent can't reach it.
    let unreachable: Bool
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
                    // The dot sits on the first line when the detail runs to two.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        StatusDot(colour: colour(connection))
                        Text(detail(connection)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            // "Connected" is said once, by the dot; every action is a button of the same kind.
            switch connection {
            case .connected?:
                Button("Disconnect…", action: disconnect)
            case .needsUpdate?:
                Button("Disconnect…", action: disconnect)
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
            return moved ? "Casement has moved since it was connected, so \(agent.title) can't reach it. Update it to fix this."
                : "Connected to an older setup. Update it so it keeps working as you set below."
        case .notFound: return "Not found on this Mac yet. You can still connect it."
        case .connected where unreachable: return "Connected, but can\u{2019}t reach Casement"
        default: return c.label
        }
    }

    private func colour(_ c: AgentConnection) -> Color {
        switch c {
        case .connected: return unreachable ? .orange : .green
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
            // A faint edge, so a dark tile still reads against the dark card.
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A status dot that sits on the first line of the text beside it.
struct StatusDot: View {
    let colour: Color
    var size: CGFloat = 6

    var body: some View {
        Circle().fill(colour).frame(width: size, height: size)
            // Centred on the x-height of a caption line.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3.5 }
            .accessibilityHidden(true)
    }
}

/// What connecting changes, in plain words, before anything is written. The exact lines,
/// file by file, are folded away for whoever wants to check them.
struct AgentConnectSheet: View {
    let plan: AgentHookPlan
    var onConfirm: () -> Void
    var onCancel: () -> Void
    @ViewState private var showsChange: Bool

    init(plan: AgentHookPlan, showsChange: Bool = false, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.plan = plan
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _showsChange = ViewState(initialValue: showsChange)
    }

    private var disconnecting: Bool { plan.kind == .disconnect }
    private var verb: String { disconnecting ? "Disconnect" : plan.wasConnected ? "Update" : "Connect" }

    private var summary: String {
        let agent = plan.agent.title
        let kept = " Your own settings stay as they are, and a backup copy is kept."
        if disconnecting { return "Casement takes its lines out of \(agent)\u{2019}s settings, so \(agent) stops telling Casement what it\u{2019}s doing." + kept }
        let what = "so it can tell Casement what it\u{2019}s doing and you can answer its requests in the island."
        if plan.wasConnected { return "Casement brings its lines in \(agent)\u{2019}s settings up to date, " + what + kept }
        return "Casement adds a few lines to \(agent)\u{2019}s settings " + what + kept
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentMark(agent: plan.agent)
                Text("\(verb) \(plan.agent.title)?").font(.headline)
            }
            Text(summary)
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Show the exact change", isExpanded: $showsChange) {
                VStack(alignment: .leading, spacing: 8) {
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
                }
                .padding(.top, 4)
            }
            .font(.callout)
            if plan.agent == .codex && !disconnecting {
                Text("Codex checks with you once: type /hooks in Codex and trust Casement\u{2019}s.")
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
