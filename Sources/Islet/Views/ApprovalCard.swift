import AppKit
import IsletCore
import SwiftUI

/// Shows the approval card in place of the expanded island's tabs while one is waiting.
struct ApprovalGate<Content: View>: View {
    let model: AppModel
    let metrics: IslandMetrics
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if let entry = model.approvals.current {
                ApprovalCard(model: model, entry: entry, metrics: metrics)
                    .id(entry.id)
                    .transition(.opacity)
            } else {
                content
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.approvals.current?.id)
    }
}

/// A coding agent asking for something: a permission, an answer or a plan review.
struct ApprovalCard: View {
    let model: AppModel
    let entry: ApprovalQueue.Entry
    let metrics: IslandMetrics
    @Environment(\.snapshotMode) private var snapshotMode

    private var request: ApprovalRequest { entry.request }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch request.kind {
                case .tool: ToolApproval(model: model, entry: entry)
                case .questions(let questions): QuestionApproval(model: model, entry: entry, questions: questions)
                case .plan(let plan): PlanApproval(model: model, entry: entry, plan: plan)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .frame(width: metrics.expanded.width, height: metrics.expanded.height, alignment: .top)
    }

    /// Level with the notch: who is asking on the left; the queue and controls on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                IconView(icon: .symbol(request.provider.symbol), size: 13, tint: Color(tint: request.provider.tint))
                Text(request.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .help(request.agentType.map { "\(request.title) (\($0) subagent)" } ?? request.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: metrics.notch.width + 12)

            HStack(spacing: 9) {
                let behind = model.approvals.waitingBehind
                if behind > 0 {
                    Text("+\(behind)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                        .help(behind == 1 ? "1 more request waiting" : "\(behind) more requests waiting")
                }
                if snapshotMode || TerminalJump.canJump(request.terminal) {
                    HeaderButton(symbol: "macwindow", help: "Show the terminal") { TerminalJump.jump(request.terminal) }
                }
                HeaderButton(symbol: "chevron.up", help: "Hide. The card comes back when the island opens.") { model.approvals.hide() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: max(metrics.notch.height, 28))
    }
}

// MARK: - Tool permission

struct ToolApproval: View {
    let model: AppModel
    let entry: ApprovalQueue.Entry

    var body: some View {
        let r = entry.request
        let risks = r.risks
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let agent = r.agentType { Chip(text: agent).help("Asked by the \(agent) subagent") }
                if risks.isEmpty {
                    Text(r.action)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.islandSecondary)
                        .lineLimit(1)
                } else {
                    Label(risks.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(risks.joined(separator: "\n"))
                }
            }
            ScrollBox(risky: !risks.isEmpty) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(r.subject)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = r.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.islandSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 6) {
                TerminalButton { decide(.terminal) }
                Spacer(minLength: 0)
                Button("Deny") { decide(.deny(ApprovalDecision.deniedMessage)) }
                    .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14)))
                if risks.isEmpty {
                    if r.canAllowForSession {
                        Button("Always") { decide(.allowForSession) }
                            .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14)))
                            .help("Allow \(r.sessionRuleSummary ?? "this") for the rest of this session")
                    }
                    Button("Allow") { decide(.allow) }
                        .buttonStyle(ApprovalButtonStyle(fill: .green.opacity(0.8)))
                } else {
                    HoldToAllowButton { decide(.allow) }
                }
            }
        }
    }

    private func decide(_ d: ApprovalDecision) { model.approvals.decide(d, for: entry) }
}

/// Allow for risky calls: click once to arm, again to confirm, or press and hold.
struct HoldToAllowButton: View {
    var action: () -> Void
    @ViewState private var armed = false
    @ViewState private var pressedAt: Date?
    @ViewState private var fill: CGFloat = 0
    /// A double-click landing as the card appears must not arm it either.
    @ViewState private var shownAt = Date()

    static let hold: TimeInterval = 0.6

    var body: some View {
        Text(armed ? "Confirm" : "Allow")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.orange.opacity(armed ? 0.65 : 0.4))
                    GeometryReader { g in Rectangle().fill(Color.orange).frame(width: g.size.width * fill) }
                }
                .clipShape(Capsule())
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressedAt == nil else { return }
                        pressedAt = Date()
                        withAnimation(.linear(duration: Self.hold)) { fill = 1 }
                    }
                    .onEnded { _ in
                        let held = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
                        pressedAt = nil
                        withAnimation(.easeOut(duration: 0.12)) { fill = 0 }
                        guard Date().timeIntervalSince(shownAt) >= ApprovalController.clickGuard else { return }
                        if armed || held >= Self.hold { action() } else { armed = true }
                    }
            )
            .help("This looks risky. Click twice, or press and hold, to allow.")
    }
}

// MARK: - Questions

struct QuestionApproval: View {
    let model: AppModel
    let entry: ApprovalQueue.Entry
    let questions: [AgentQuestion]
    @ViewState private var index = 0
    @ViewState private var answers: [String: String] = [:]
    @ViewState private var picked: [String] = []
    /// When the next question replaced the last one: its options sit where the old ones were,
    /// so a double-click must not answer it unseen.
    @ViewState private var steppedAt = Date.distantPast

    private var justStepped: Bool { Date().timeIntervalSince(steppedAt) < ApprovalController.clickGuard }

    var body: some View {
        let q = questions[min(index, questions.count - 1)]
        let rows = stride(from: 0, to: q.options.count, by: 2).map { Array(q.options[$0..<min($0 + 2, q.options.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let header = q.header, !header.isEmpty { Chip(text: header) }
                Text(q.question)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(q.question)
                Spacer(minLength: 0)
                if questions.count > 1 {
                    Text("\(index + 1) of \(questions.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.islandTertiary)
                        .fixedSize()
                }
            }
            AdaptiveScroll(scrolls: rows.count > 2) {
                VStack(spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            ForEach(row, id: \.label) { option in optionButton(option, in: q) }
                            if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                TerminalButton { model.approvals.decide(.terminal, for: entry) }
                Spacer(minLength: 0)
                if q.multiSelect {
                    Text("Choose any")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.islandTertiary)
                    Button(index + 1 < questions.count ? "Next" : "Send") {
                        answer(q, with: q.options.map(\.label).filter(picked.contains).joined(separator: ", "))
                    }
                    .buttonStyle(ApprovalButtonStyle(fill: .blue.opacity(picked.isEmpty ? 0.35 : 0.85)))
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func optionButton(_ option: AgentQuestion.Option, in q: AgentQuestion) -> some View {
        let on = picked.contains(option.label)
        return Button {
            guard !justStepped else { return }
            if q.multiSelect {
                if let i = picked.firstIndex(of: option.label) { picked.remove(at: i) } else { picked.append(option.label) }
            } else {
                answer(q, with: option.label)
            }
        } label: {
            HStack(spacing: 5) {
                if q.multiSelect {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundStyle(on ? Color.blue : Color.islandTertiary)
                }
                Text(option.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.blue.opacity(0.3) : Color.islandFill))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help([option.label, option.detail].compactMap { $0 }.joined(separator: "\n"))
    }

    private func answer(_ q: AgentQuestion, with value: String) {
        guard !justStepped else { return }
        answers[q.question] = value
        picked = []
        if index + 1 < questions.count {
            index += 1
            steppedAt = Date()
        } else {
            model.approvals.decide(.answer(answers), for: entry)
        }
    }
}

// MARK: - Plan review

struct PlanApproval: View {
    let model: AppModel
    let entry: ApprovalQueue.Entry
    let plan: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollBox {
                PlanText(blocks: PlanMarkdown.blocks(plan))
            }
            HStack(spacing: 6) {
                TerminalButton { model.approvals.decide(.terminal, for: entry) }
                Spacer(minLength: 0)
                Button("Keep planning") { model.approvals.decide(.deny(ApprovalDecision.keepPlanningMessage), for: entry) }
                    .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14)))
                Button("Approve") { model.approvals.decide(.allow, for: entry) }
                    .buttonStyle(ApprovalButtonStyle(fill: .green.opacity(0.8)))
            }
        }
    }
}

/// A plan laid out from its Markdown blocks.
struct PlanText: View {
    let blocks: [PlanMarkdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text, let level):
                    Text(Self.inline(text))
                        .font(.system(size: level == 1 ? 12.5 : 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 2)
                case .item(let text, let marker, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(marker).foregroundStyle(Color.islandTertiary).monospacedDigit()
                        Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(depth) * 12)
                case .code(let code):
                    Text(code)
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                case .paragraph(let text):
                    Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.88))
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - Pieces

/// A framed box for long text: scrolls, and says so when there's more below.
struct ScrollBox<Content: View>: View {
    var risky = false
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode
    @ViewState private var contentHeight: CGFloat = 0
    @ViewState private var visibleHeight: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let overflows = contentHeight > visibleHeight + 2
        let inner = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 7)
            // Room below the last line for the "More" badge, so scrolling to the end shows
            // every character instead of leaving the tail of a command under the badge.
            .padding(.bottom, overflows ? 28 : 7)
            .textSelection(.enabled)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        Group {
            if snapshotMode {
                inner
            } else {
                ScrollView(.vertical, showsIndicators: true) { inner }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .clipShape(shape)
        .background(shape.fill(Color.white.opacity(0.07)))
        .overlay(shape.strokeBorder(risky ? Color.orange.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if overflows {
                Label("More", systemImage: "arrow.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    .padding(5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// "Terminal": leave the answer to the agent's own prompt, and bring that terminal forward.
struct TerminalButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Terminal", systemImage: "terminal")
        }
        .buttonStyle(ApprovalButtonStyle(fill: .clear, foreground: Color.islandSecondary))
        .help("Answer in the terminal instead")
    }
}

struct ApprovalButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.islandTertiary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.islandSecondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.islandFill))
    }
}
