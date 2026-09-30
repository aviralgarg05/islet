import IsletCore
import SwiftUI

/// "Agents" on the Home tab: a card per coding agent with a bar for each plan window.
/// Shows nothing until an agent has reported usage.
struct AgentUsageSection: View {
    let model: AppModel

    static func isShown(_ model: AppModel) -> Bool { !model.agentUsage.visible(now: Date()).isEmpty }

    var body: some View {
        // Redraws once a minute for the countdowns, and only while the expanded island is on screen.
        // The timeline's dates sit on minute boundaries, so the countdown uses the actual time.
        TimelineView(.everyMinute) { _ in
            let now = Date()
            VStack(spacing: 6) {
                ForEach(model.agentUsage.visible(now: now)) { usage in
                    AgentUsageCard(usage: usage, now: now, theme: model.settings.theme,
                                   roomy: model.settings.expandedSize.width >= 540)
                }
            }
        }
    }
}

struct AgentUsageCard: View {
    let usage: AgentUsage
    let now: Date
    var theme: IslandTheme = .black
    /// Room for "resets in …" rather than just the time left.
    var roomy = false

    var body: some View {
        let tint = Color(tint: usage.provider.tint)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: usage.provider.symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint)
                Text(usage.provider.displayName).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(Color.islandSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .help(usage.project.map { "Latest session: \($0)" } ?? "")
            ForEach(usage.windows) { w in UsageWindowRow(window: w, now: now, tint: tint, roomy: roomy) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandCard(theme)
    }

    /// "Opus 5.5 · 42% context" while a session is recent; the session cost when there are
    /// no plan limits (API billing); otherwise the plan name.
    private var detail: String? {
        var parts: [String] = []
        if usage.hasRecentSession(at: now) {
            if let m = usage.model { parts.append(m) }
            if let c = usage.contextPercent { parts.append("\(UsageFormat.percent(c)) context") }
            if usage.windows.isEmpty, let cost = usage.costUSD { parts.append(String(format: "$%.2f", cost)) }
        }
        if parts.isEmpty, let plan = usage.planType, !plan.isEmpty { parts.append("\(plan.capitalized) plan") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// "5h ▮▮▮▮▯▯ 62%  resets in 1 h 12 min"
struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date
    let tint: Color
    var roomy = false

    var body: some View {
        let reset = window.hasReset(at: now)
        let used = reset ? 0 : window.usedPercent
        HStack(spacing: 6) {
            Text(window.shortLabel)
                .foregroundStyle(Color.islandSecondary)
                .frame(width: 17, alignment: .leading)
            LevelBar(value: used / 100, tint: color(for: used), height: 4)
                .frame(minWidth: 28)
            Text(UsageFormat.percent(used))
                .foregroundStyle(used >= 90 ? Color(tint: "red") : .white)
                .frame(width: 30, alignment: .trailing)
            // A fixed column keeps the bars of one card the same length.
            Text(resetText(reset: reset) ?? "")
                .foregroundStyle(Color.islandTertiary)
                .lineLimit(1)
                .frame(width: roomy ? 108 : 70, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .help(window.resetsAt.map { "Resets \(UsageFormat.clockTime($0, now: now))" } ?? "")
    }

    private func resetText(reset: Bool) -> String? {
        guard let at = window.resetsAt else { return nil }
        if reset { return "reset" }
        let left = UsageFormat.remaining(until: at, now: now)
        return roomy ? "resets in \(left)" : "in \(left)"
    }

    private func color(for used: Double) -> Color {
        if used >= 90 { return Color(tint: "red") }
        if used >= 75 { return Color(tint: "orange") }
        return tint
    }
}
