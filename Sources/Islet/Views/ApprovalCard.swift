import AppKit
import IsletCore
import SwiftUI

/// Shows the approval card in place of the expanded island's tabs while one is waiting.
struct ApprovalGate<Content: View>: View {
    let model: AppModel
    let metrics: IslandMetrics
    @ViewBuilder var content: Content
    @Environment(\.islandMotion) private var motion

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
        .animation(motion == .off ? nil : .easeOut(duration: 0.18), value: model.approvals.current?.id)
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
            // The pages' own bottom inset: every card's footer sits on the same line, as far
            // from the shell's edge as the controls along the bottom of any page.
            .padding(.bottom, ExpandedLayout.bottom)
        }
        .frame(width: metrics.expanded.width, height: metrics.expanded.height, alignment: .top)
    }

    /// Level with the notch: who is asking on the left; the queue and controls on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: Space.s) {
                IconView(icon: .symbol(request.provider.symbol), size: 14, tint: Color(tint: request.provider.tint))
                    .accessibilityHidden(true)
                Text(request.title)
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .help(request.agentLabel.map { "\(request.title) (\($0) subagent)" } ?? request.title)
                    .accessibilityLabel(SpokenText.phrase(request.title))
            }
            .accessibilityAddTraits(.isHeader)
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
                        .contrastEdge(Capsule())
                        .help(behind == 1 ? "1 more request waiting" : "\(behind) more requests waiting")
                        .accessibilityLabel(behind == 1 ? "1 more request waiting" : "\(behind) more requests waiting")
                }
                if snapshotMode || TerminalJump.canJump(request.terminal) {
                    HeaderButton(symbol: "macwindow", label: "Show the terminal", help: "Show the terminal") { TerminalJump.jump(request.terminal) }
                }
                HeaderButton(symbol: "chevron.up", label: "Hide", help: "Hide. The card comes back when the island opens.") {
                    model.approvals.hide()
                }
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
    /// The risky Allow has had its first click.
    @ViewState private var armed = false

    var body: some View {
        let r = entry.request
        let risks = r.risks
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if let agent = r.agentLabel { Chip(text: agent).help("Asked by the \(agent) subagent") }
                if let summary = RiskRules.summary(risks) {
                    // One line, so the command keeps its room: the most serious risk, and how
                    // many more; every one in the help.
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .textStyle(.caption, emphasized: true)
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .help(risks.joined(separator: "\n"))
                        .accessibilityLabel("Risky: " + risks.joined(separator: ", "))
                    Spacer(minLength: Space.s)
                    // Says what the risky Allow asks for, where the risk is named.
                    Text(armed ? "Click again to allow" : "Click twice to allow")
                        .textStyle(.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                } else {
                    Text(r.action)
                        .textStyle(.body, emphasized: true)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
            }
            ScrollBox(risky: !risks.isEmpty, lineFont: Self.subjectFont) {
                Self.requestText(r)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The file's name and where it is, never the whole path with the user's name in it.
            .help(r.file.map { $0.name + ($0.folder.map { " in " + $0 } ?? "") } ?? "")
            ApprovalFooter(terminal: { decide(.terminal) }) {
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
                    HoldToAllowButton(armed: $armed) { decide(.allow) }
                }
            }
        }
    }

    static var subjectFont: Font { .system(size: TextStyle.caption.size, weight: .medium, design: .monospaced) }
    static var detailFont: Font { .system(size: TextStyle.caption.size, design: .monospaced) }

    /// The request as one run of lines: the command, path or input, or for a file tool the
    /// file's name and its folder after it, then the description or the change in grey. One
    /// text, so every line is the same height and the box can stop between two of them.
    static func requestText(_ r: ApprovalRequest) -> Text {
        var text: Text
        if let file = r.file {
            text = Text(file.name).font(subjectFont).foregroundStyle(Ink.primary)
            if let folder = file.folder {
                text = text + Text("  " + folder).font(detailFont).foregroundStyle(Ink.secondary)
            }
        } else {
            text = Text(r.subject).font(subjectFont).foregroundStyle(Ink.primary)
        }
        if let detail = r.detail, !detail.isEmpty {
            text = text + Text("\n" + detail).font(detailFont).foregroundStyle(Ink.secondary)
        }
        return text
    }

    private func decide(_ d: ApprovalDecision) { model.approvals.decide(d, for: entry) }
}

/// Allow for risky calls: click once to arm, again to confirm, or press and hold. A full
/// orange at rest would read as safe to click; a faint one reads as switched off.
struct HoldToAllowButton: View {
    @Binding var armed: Bool
    var action: () -> Void
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
                    Capsule().fill(Color.orange.opacity(armed ? 0.85 : 0.6))
                    GeometryReader { g in Rectangle().fill(Color.orange).frame(width: g.size.width * fill) }
                }
                .clipShape(Capsule())
            }
            .contrastEdge(Capsule())
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
            // A drag gesture isn't a button to VoiceOver: pressing it arms it, and again allows.
            .accessibilityElement()
            .accessibilityLabel(armed ? "Confirm" : "Allow")
            .accessibilityHint("This looks risky. Press twice to allow.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard Date().timeIntervalSince(shownAt) >= ApprovalController.clickGuard else { return }
                if armed { action() } else { armed = true }
            }
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
    /// The options' height and the room they have: past it, they scroll rather than push the
    /// footer off its line.
    @ViewState private var optionsHeight: CGFloat = 0
    @ViewState private var optionsRoom: CGFloat = .infinity

    private var justStepped: Bool { Date().timeIntervalSince(steppedAt) < ApprovalController.clickGuard }

    /// An option: the height of a standard push button, so two rows and the footer fit the
    /// smallest island.
    static let optionHeight: CGFloat = 22

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
            AdaptiveScroll(scrolls: rows.count > 2 || optionsHeight > optionsRoom + 0.5) {
                VStack(spacing: Space.xs) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Space.xs) {
                            ForEach(row, id: \.label) { option in optionButton(option, in: q) }
                            if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { optionsHeight = $0 }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { optionsRoom = $0 }
            ApprovalFooter(terminal: { model.approvals.decide(.terminal, for: entry) }) {
                if q.multiSelect {
                    Text("Choose one or more")
                        .textStyle(.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                    Button(index + 1 < questions.count ? "Next" : "Send") {
                        answer(q, with: q.options.map(\.label).filter(picked.contains).joined(separator: ", "))
                    }
                    // One fill: with nothing picked the button itself looks switched off.
                    .buttonStyle(ApprovalButtonStyle(fill: .blue.opacity(0.85)))
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
            .frame(maxWidth: .infinity, minHeight: Self.optionHeight)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(on ? Color.blue.opacity(0.3) : Wash.regular))
            .contrastEdge(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .help([option.label, option.detail].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel(option.label)
        .accessibilityHint(option.detail ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            ApprovalFooter(terminal: { model.approvals.decide(.terminal, for: entry) }) {
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

/// A framed box for long text. It is as tall as its text, up to the room it has; past that it
/// scrolls, stops between two lines (with `lineFont`), fades its last line out so a cut line
/// reads as going on, and, when it is tall enough to spare a strip, says "More below" under
/// the text, never over it.
struct ScrollBox<Content: View>: View {
    var risky = false
    /// The font of text set in lines of one size, so the box can stop between two of them.
    var lineFont: Font? = nil
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode
    @ViewState private var contentHeight: CGFloat = 0
    @ViewState private var room: CGFloat = 0
    @ViewState private var line: CGFloat = 0

    var body: some View {
        let fit = TextBoxFit(content: contentHeight, room: room, line: lineFont == nil ? 0 : line,
                             pad: TextBoxFit.pad, strip: TextBoxFit.strip)
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
            .overlay(alignment: .top) { box(fit) }
            .background(alignment: .topLeading) {
                if let lineFont {
                    Text("Ag").font(lineFont).fixedSize().hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { line = $0 }
                        .accessibilityHidden(true)
                }
            }
    }

    private func box(_ fit: TextBoxFit) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        // Over the last part of a line that is cut: the bottom padding for lines of one size,
        // a little more for a mix of them.
        let fade: CGFloat = fit.overflows ? (lineFont == nil ? Space.l : TextBoxFit.pad) : 0
        let inner = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.m)
            .padding(.top, TextBoxFit.pad)
            // Scrolled to the end, the last line clears the fade.
            .padding(.bottom, max(TextBoxFit.pad, fade))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        return VStack(spacing: 0) {
            Group {
                if fit.overflows && !snapshotMode {
                    ScrollView(.vertical, showsIndicators: true) { inner }
                } else {
                    inner
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: fit.text, alignment: .top)
            .clipped()
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    // Quickly at first, so the top of a cut line shows only as a hint of more.
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.35), location: 0.35),
                                           .init(color: .black.opacity(0), location: 0.85)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                }
            }
            if fit.hint {
                HStack {
                    Spacer(minLength: 0)
                    Label("More below", systemImage: "arrow.down")
                        .textStyle(.caption, emphasized: true)
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, Space.s)
                        .frame(height: 16)
                        .background(Capsule().fill(Wash.regular))
                }
                .padding(.horizontal, Space.s)
                .frame(height: TextBoxFit.strip)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(Wash.subtle))
        .clipShape(shape)
        // Orange round a risky command, always; Increase Contrast edges the others.
        .contrastEdge(shape, normal: .clear)
        .overlay(shape.strokeBorder(risky ? Color.orange.opacity(0.75) : .clear, lineWidth: 1))
    }
}

/// Every card's last line: the way back to the terminal on the left, the decisions on the
/// right, one button high, so footers sit on the same line from card to card.
struct ApprovalFooter<Trailing: View>: View {
    var terminal: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s) {
            TerminalButton(action: terminal)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: ApprovalButtonStyle.height)
    }
}

/// Leave the answer to the agent's own prompt, and bring that terminal forward.
struct TerminalButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Answer in the terminal", systemImage: "terminal")
        }
        .buttonStyle(ApprovalButtonStyle(fill: .clear, foreground: Ink.secondary))
        .help("Answer at the agent\u{2019}s own prompt, and bring its terminal forward")
    }
}

/// The decisions: the island's capsule, one text size up, since they are the point of the card.
/// Switched off, it is a plain wash with quiet text, never a dimmed colour.
struct ApprovalButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    static let height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        ApprovalButtonBody(configuration: configuration, fill: fill, foreground: foreground)
    }
}

private struct ApprovalButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .textStyle(.body, emphasized: true)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? foreground : Ink.tertiary)
            .padding(.horizontal, Space.m)
            .frame(height: ApprovalButtonStyle.height)
            .background(Capsule().fill(isEnabled ? fill.opacity(configuration.isPressed ? 0.7 : 1) : Wash.regular))
            .contrastEdge(Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
    }
}

private struct HeaderButton: View {
    let symbol: String
    /// What VoiceOver says, when the help says more.
    let label: String
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
        .accessibilityLabel(label)
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
            .contrastEdge(Capsule())
    }
}
