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

    @ObservationIgnored let watcher: UsageWatcher
    @ObservationIgnored private var alerts = UsageAlertTracker()
    @ObservationIgnored private var post: ((ActivitySpec) -> Void)?

    init(watcher: UsageWatcher = UsageWatcher()) {
        self.watcher = watcher
    }

    /// Start or stop each source to match the settings. Safe to call on every settings change.
    func apply(_ settings: IsletSettings, post: @escaping (ActivitySpec) -> Void) {
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
    }

    private func update(_ provider: UsageProvider, _ usage: AgentUsage?) {
        switch provider {
        case .claude: claude = usage
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
