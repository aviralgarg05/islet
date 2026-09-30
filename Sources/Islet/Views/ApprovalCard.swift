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
        let layout = ExpandedLayout(metrics: metrics)
        VStack(spacing: 0) {
            header.frame(height: layout.row)
            Group {
                switch request.kind {
                case .tool: ToolApproval(model: model, entry: entry)
                case .questions(let questions): QuestionApproval(model: model, entry: entry, questions: questions)
                case .plan(let plan): PlanApproval(model: model, entry: entry, plan: plan)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, ExpandedLayout.inset)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.m)
        }
        .frame(width: metrics.expanded.width, height: metrics.expanded.height, alignment: .top)
    }

    /// Level with the notch: who is asking on the left; the queue and controls on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: Space.s) {
                IconView(icon: .symbol(request.provider.symbol), size: 14, tint: Color(tint: request.provider.tint))
                Text(request.title)
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .help(request.agentType.map { "\(request.title) (\($0) subagent)" } ?? request.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: metrics.notch.width + Space.m)

            HStack(spacing: Space.xs) {
                let behind = model.approvals.waitingBehind
                if behind > 0 {
                    Text("\(behind) more")
                        .textStyle(.caption, emphasized: true, numeric: true)
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, Space.s)
                        .frame(height: 20)
                        .background(Capsule().fill(Wash.regular))
                        .help(behind == 1 ? "1 more request waiting" : "\(behind) more requests waiting")
                }
                if snapshotMode || TerminalJump.canJump(request.terminal) {
                    HeaderButton(symbol: "macwindow", help: "Show the terminal") { TerminalJump.jump(request.terminal) }
                }
                HeaderButton(symbol: "chevron.up", help: "Hide. The card comes back when the island opens.") { model.approvals.hide() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, ExpandedLayout.inset)
        .padding(.trailing, ExpandedLayout.inset - 6)
    }
}

// MARK: - Tool permission

struct ToolApproval: View {
    let model: AppModel
    let entry: ApprovalQueue.Entry

    var body: some View {
        let r = entry.request
        let risks = r.risks
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if let agent = r.agentType { Chip(text: agent).help("Asked by the \(agent) subagent") }
                if risks.isEmpty {
                    Text(r.action)
                        .textStyle(.body, emphasized: true)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                } else {
                    Label(risks.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                        .textStyle(.caption, emphasized: true)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(risks.joined(separator: "\n"))
                }
            }
            ScrollBox(risky: !risks.isEmpty) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(r.subject)
                        .font(.system(size: TextStyle.caption.size, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = r.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: TextStyle.caption.size, design: .monospaced))
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: Space.s) {
                TerminalButton { decide(.terminal) }
                Spacer(minLength: 0)
                Button("Deny") { decide(.deny(ApprovalDecision.deniedMessage)) }
                    .buttonStyle(ApprovalButtonStyle(fill: Wash.strong))
                if risks.isEmpty {
                    if r.canAllowForSession {
                        Button("Always") { decide(.allowForSession) }
                            .buttonStyle(ApprovalButtonStyle(fill: Wash.strong))
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
            .textStyle(.body, emphasized: true)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.l)
            .frame(height: ApprovalButtonStyle.height)
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
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if let header = q.header, !header.isEmpty { Chip(text: header) }
                Text(q.question)
                    .textStyle(.headline)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(q.question)
                Spacer(minLength: 0)
                if questions.count > 1 {
                    Text("\(index + 1) of \(questions.count)")
                        .textStyle(.caption, numeric: true)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize()
                }
            }
            AdaptiveScroll(scrolls: rows.count > 2) {
                VStack(spacing: Space.xs) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Space.xs) {
                            ForEach(row, id: \.label) { option in optionButton(option, in: q) }
                            if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.s) {
                TerminalButton { model.approvals.decide(.terminal, for: entry) }
                Spacer(minLength: 0)
                if q.multiSelect {
                    Text("Choose any")
                        .textStyle(.caption)
                        .foregroundStyle(Ink.tertiary)
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
            HStack(spacing: Space.s) {
                if q.multiSelect {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundStyle(on ? Color.blue : Ink.tertiary)
                }
                Text(option.label)
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: ApprovalButtonStyle.height)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(on ? Color.blue.opacity(0.3) : Wash.regular))
            .contentShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
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
        VStack(alignment: .leading, spacing: Space.s) {
            ScrollBox {
                PlanText(blocks: PlanMarkdown.blocks(plan))
            }
            HStack(spacing: Space.s) {
                TerminalButton { model.approvals.decide(.terminal, for: entry) }
                Spacer(minLength: 0)
                Button("Keep planning") { model.approvals.decide(.deny(ApprovalDecision.keepPlanningMessage), for: entry) }
                    .buttonStyle(ApprovalButtonStyle(fill: Wash.strong))
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
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text, let level):
                    Text(Self.inline(text))
                        .textStyle(level == 1 ? .headline : .body, emphasized: true)
                        .foregroundStyle(Ink.primary)
                        .padding(.top, Space.hair)
                case .item(let text, let marker, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text(marker).foregroundStyle(Ink.tertiary).monospacedDigit()
                        Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(depth) * 12)
                case .code(let code):
                    Text(code)
                        .font(.system(size: TextStyle.caption.size, design: .monospaced))
                        .padding(Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Wash.subtle))
                case .paragraph(let text):
                    Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textStyle(.body)
        .foregroundStyle(Ink.primary.opacity(0.88))
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
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        let overflows = contentHeight > visibleHeight + 2
        let inner = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
            // Room below the last line for the "More" badge, so scrolling to the end shows
            // every character instead of leaving the tail of a command under the badge.
            .padding(.bottom, overflows ? 28 : Space.s)
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
        .background(shape.fill(Wash.subtle))
        .overlay(shape.strokeBorder(risky ? Color.orange.opacity(0.75) : .clear, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if overflows {
                Label("More", systemImage: "arrow.down")
                    .textStyle(.caption, emphasized: true)
                    .foregroundStyle(.black)
                    .padding(.horizontal, Space.s)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    .padding(Space.xs)
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
        .buttonStyle(ApprovalButtonStyle(fill: .clear, foreground: Ink.secondary))
        .help("Answer in the terminal instead")
    }
}

/// The decisions: the island's capsule, one text size up, since they are the point of the card.
struct ApprovalButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    static let height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.body, emphasized: true)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.m)
            .frame(height: Self.height)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
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
                .foregroundStyle(Ink.tertiary)
                .frame(width: 24, height: 24)
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
            .textStyle(.caption, emphasized: true)
            .foregroundStyle(Ink.secondary)
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .frame(height: 18)
            .background(Capsule().fill(Wash.regular))
    }
}
