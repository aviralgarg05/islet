import Foundation
import IsletCore
import IsletSystem
import Observation

/// Plan usage for coding agents, kept current by `UsageWatcher` while the feature is on.
/// Crossing 90% or 100% of a window posts one normal activity; otherwise the closed island
/// shows nothing about usage.
@MainActor
@Observable
final class AgentUsageModel {
    private(set) var claude: AgentUsage?
    private(set) var codex: AgentUsage?
    /// What Home says about Claude before its figures arrive (`ClaudeUsageHint`).
    private(set) var claudeHint: ClaudeUsageHint?

    @ObservationIgnored let watcher: UsageWatcher
    /// Claude Code's settings folder (`~/.claude`). Only read, and only for the hint; Settings
    /// writes the status line after the user confirms it.
    @ObservationIgnored let claudeDirectory: URL
    @ObservationIgnored private var alerts = UsageAlertTracker()
    @ObservationIgnored private var post: ((ActivitySpec) -> Void)?
    @ObservationIgnored private var settings = IsletSettings()

    var claudeSettingsFile: URL { ClaudeCodeInstall.settingsFile(in: claudeDirectory) }

    init(watcher: UsageWatcher = UsageWatcher(),
         claudeDirectory: URL = ClaudeCodeInstall.configDirectory(home: IsletPaths.home)) {
        self.watcher = watcher
        self.claudeDirectory = claudeDirectory
    }

    /// Start or stop each source to match the settings. Safe to call on every settings change.
    func apply(_ settings: IsletSettings, post: @escaping (ActivitySpec) -> Void) {
        self.settings = settings
        self.post = post
        watcher.onClaude = { [weak self] u in self?.update(.claude, u) }
        watcher.onCodex = { [weak self] u in self?.update(.codex, u) }
        if settings.claudeUsageEnabled {
            watcher.startClaude()
        } else if watcher.isWatchingClaude {
            watcher.stopClaude()
            claude = nil
        }
        if settings.codexUsageEnabled {
            watcher.startCodex()
        } else if watcher.isWatchingCodex {
            watcher.stopCodex()
            codex = nil
        }
        refreshClaudeHint()
    }

    /// Look again at whether Claude Code is installed and has Islet's status line: one small
    /// file, read at launch, on settings changes, after Settings adds or removes the status
    /// line and when the island opens. Nothing is read once figures have arrived.
    func refreshClaudeHint() {
        // Nothing to read when no hint could show anyway.
        let worthLooking = settings.claudeUsageEnabled && settings.claudeUsageHint && claude == nil
        let installed = worthLooking && ClaudeCodeInstall.looksInstalled(configDirectory: claudeDirectory)
        let status = installed ? ClaudeStatusLineSetup.status(of: try? Data(contentsOf: claudeSettingsFile)) : nil
        let hint = ClaudeUsageHint.decide(enabled: settings.claudeUsageEnabled, dismissed: !settings.claudeUsageHint,
                                          claudeInstalled: installed, statusLine: status, hasUsage: claude != nil,
                                          canInstall: FileManager.default.isExecutableFile(atPath: AppActions.cliPath))
        if hint != claudeHint { claudeHint = hint }
    }

    private func update(_ provider: UsageProvider, _ usage: AgentUsage?) {
        // A reading queued just before its source was switched off must not bring the card back.
        guard provider == .claude ? watcher.isWatchingClaude : watcher.isWatchingCodex else { return }
        switch provider {
        case .claude:
            claude = usage
            refreshClaudeHint()
        case .codex: codex = usage
        }
        guard let usage else { return }
        let now = Date()
        for alert in alerts.ingest(usage, now: now) { post?(alert.activity(now: now)) }
    }

    /// Agents worth a card right now.
    func visible(now: Date) -> [AgentUsage] {
        [claude, codex].compactMap { $0 }.filter { $0.isRelevant(at: now) }
    }

    /// A fixed hint for offline snapshots (nothing is read).
    func showDemoHint(_ hint: ClaudeUsageHint?) {
        claude = nil
        claudeHint = hint
    }

    /// Fixed figures for offline snapshots.
    func showDemo(now: Date) {
        claude = AgentUsage(provider: .claude, windows: [
            UsageWindow(id: "five_hour", usedPercent: 62, windowMinutes: 300, resetsAt: now.addingTimeInterval(72 * 60)),
            UsageWindow(id: "seven_day", usedPercent: 91, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600)),
        ], model: "Opus 5.5", contextPercent: 42, sessionID: "demo", project: "islet", updatedAt: now)
        codex = AgentUsage(provider: .codex, windows: [
            UsageWindow(id: "primary", usedPercent: 23, windowMinutes: 300, resetsAt: now.addingTimeInterval(4 * 3600 + 5 * 60)),
            UsageWindow(id: "secondary", usedPercent: 5, windowMinutes: 10080, resetsAt: now.addingTimeInterval(6 * 86400)),
        ], planType: "plus", updatedAt: now)
    }
}
