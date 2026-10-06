import CasementCore
import SwiftUI

/// A coding agent's plan limits in Home's column: its name, then a slim bar per window.
/// Nothing shows until an agent has reported usage.
struct AgentUsageGlance: View {
    let usage: AgentUsage
    let now: Date

    var body: some View {
        let tint = Color(tint: usage.provider.tint)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Image(systemName: usage.provider.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(usage.provider.displayName).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary)
                if let detail {
                    Text(detail).textStyle(.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 16)
            .spokenGroup(usage.provider.displayName, value: detail)
            .accessibilityAddTraits(.isHeader)
            .help(usage.project.map { "Latest session: \($0)" } ?? "")
            ForEach(usage.windows) { w in UsageWindowRow(window: w, now: now, tint: tint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Opus 5.5" while a session is recent; the session cost with no plan limits (API
    /// billing); otherwise the plan name.
    private var detail: String? {
        if usage.hasRecentSession(at: now) {
            if let m = usage.model { return m }
            if usage.windows.isEmpty, let cost = usage.costUSD { return String(format: "$%.2f", cost) }
        }
        if let plan = usage.planType, !plan.isEmpty { return plan.capitalized }
        return nil
    }
}

/// "5h ▮▮▮▮▯▯ 62%", with the reset time on hover.
struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date
    let tint: Color

    var body: some View {
        let reset = window.hasReset(at: now)
        let used = reset ? 0 : window.usedPercent
        HStack(spacing: Space.s) {
            // Centred under the provider's mark, which is centred in the same 18 points.
            Text(window.shortLabel)
                .foregroundStyle(Ink.tertiary)
                .frame(width: 18, alignment: .center)
            LevelBar(value: used / 100, tint: color(for: used), height: 4)
                .frame(minWidth: 24)
            Text(UsageFormat.percent(used))
                .foregroundStyle(used >= 90 ? Color(tint: "red") : Ink.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .textStyle(.caption, numeric: true)
        .frame(height: 12)
        .help(resetText(reset: reset) ?? "")
        // "5-hour limit", "62% used, resets in 1 hour 12 minutes".
        .spokenGroup(SpokenText.usage(window, now: now).label, value: SpokenText.usage(window, now: now).value)
    }

    private func resetText(reset: Bool) -> String? {
        guard let at = window.resetsAt else { return nil }
        if reset { return "Reset" }
        return "Resets in \(UsageFormat.remaining(until: at, now: now)), at \(UsageFormat.clockTime(at, now: now))"
    }

    private func color(for used: Double) -> Color {
        if used >= 90 { return Color(tint: "red") }
        if used >= 75 { return Color(tint: "orange") }
        return tint
    }
}

/// Claude on Home before its figures arrive. Claude Code keeps no usage on disk; it passes it
/// to its status line. So until Casement's status line is added this offers to show usage
/// (Settings explains the change and asks before making it), and after that it says Casement is
/// waiting for Claude Code. The "x" hides it for good (`claudeUsageHint`).
struct ClaudeUsageHintRow: View {
    let hint: ClaudeUsageHint
    let model: AppModel

    var body: some View {
        let provider = UsageProvider.claude
        let tint = Color(tint: provider.tint)
        // The same header as Claude's card will have: the mark and the name.
        let header = HStack(spacing: Space.s) {
            Image(systemName: provider.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(provider.displayName).textStyle(.body, emphasized: true).foregroundStyle(Ink.primary).lineLimit(1)
            Spacer(minLength: 0)
        }
        switch hint {
        case .offer:
            HStack(spacing: Space.xs) {
                header
                Button("Show usage") { AppActions.openSettings(.agents, at: "agents.claudeUsage") }
                    .buttonStyle(CapsuleButtonStyle(tint: tint))
                    .fixedSize()
                    .help("Claude's 5-hour and weekly limits. Settings shows what changes before anything does.")
                dismissButton
            }
            .frame(height: 24)
        case .waiting:
            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.xs) {
                    header
                    dismissButton
                }
                .frame(height: 16)
                // Under the name, as every glance's detail is.
                Group {
                    Text("Waiting for Claude Code").foregroundStyle(Ink.secondary).lineLimit(1)
                    Text("Updates as it runs in a terminal")
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textStyle(.caption)
                .padding(.leading, Self.textIndent)
                .help("Claude Code hands its usage to its status line, which it shows while it runs in a terminal.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where the name starts: past the 18-point mark and the gap after it.
    static let textIndent: CGFloat = 18 + Space.s

    private var dismissButton: some View {
        Button { model.dismissClaudeUsageHint() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Don't show this again")
        .accessibilityLabel("Don't show this again")
    }
}
