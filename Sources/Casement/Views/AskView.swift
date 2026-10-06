import AppKit
import CasementCore
import CasementSystem
import SwiftUI

/// The Ask tab: one line to type a question, a provider chip, and the streaming answer.
struct AskView: View {
    let model: AppModel
    @FocusState private var fieldFocused: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let ask = model.ask
        let kind = ask.provider(in: model.settings.ask)
        let status = ask.status(of: kind)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                AskProviderChip(model: model, kind: kind)
                field(kind: kind, ready: status.isReady)
                actions(ready: status.isReady)
            }
            .frame(height: AskView.fieldHeight)
            if ask.phase == .idle && ask.answer.isEmpty {
                // A conversion ("5 ft in cm") while the converter is on, or else a shortcut whose
                // name matches what is typed, while Shortcuts is on. Either takes the hint's place
                // unless the hint says something needs doing.
                let conversion = AskConversion.match(model)
                let shortcut = conversion == nil ? AskShortcutSuggestion.match(model) : nil
                if let conversion { AskConversion(model: model, conversion: conversion) }
                if let shortcut { AskShortcutSuggestion(model: model, item: shortcut) }
                if conversion == nil && shortcut == nil || !status.isReady { hint(kind: kind, status: status) }
            } else {
                AskAnswerView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if !snapshotMode {
                PanelKeyBridge(active: ask.wantsKeyboard) { model.ask.releaseKeyboard() }
            }
        }
        .onAppear {
            if !snapshotMode { ask.refreshStatuses() }
            if !snapshotMode { model.tools.shortcuts.refresh() }
            if ask.wantsKeyboard { focusSoon() }
        }
        .onDisappear { ask.releaseKeyboard() }
        .onChange(of: ask.focusRequest) { _, _ in focusSoon() }
    }

    static let fieldHeight: CGFloat = 28

    /// Focus once the panel has become key (the bridge makes it key in the same update).
    private func focusSoon() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func placeholder(_ kind: AskProviderKind) -> String {
        if model.settings.ask.followUps && !model.ask.history.isEmpty { return "Ask a follow-up" }
        return kind == .onDevice ? "Ask the on-device model" : "Ask \(kind.title)"
    }

    private func field(kind: AskProviderKind, ready: Bool) -> some View {
        let ask = model.ask
        return ZStack(alignment: .leading) {
            if snapshotMode {
                Text(ask.draft.isEmpty ? placeholder(kind) : ask.draft)
                    .foregroundStyle(ask.draft.isEmpty ? Ink.tertiary : Ink.primary)
                    .lineLimit(1)
            } else {
                TextField(placeholder(kind), text: Binding(get: { model.ask.draft }, set: { model.ask.draft = $0 }))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .focused($fieldFocused)
                    .onSubmit { send() }
                    .onExitCommand { escape() }
                // The panel can't take the keyboard until the field is asked for, so the first
                // click goes here and hands the keyboard over.
                if !ask.wantsKeyboard {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.ask.requestKeyboard() }
                        // VoiceOver presses it to start typing, as a click does.
                        .accessibilityElement()
                        .accessibilityLabel(placeholder(kind))
                        .accessibilityValue(ask.draft)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Starts typing")
                        .accessibilityAction { model.ask.requestKeyboard() }
                }
            }
        }
        .textStyle(.body)
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Capsule().fill(Wash.regular))
        .contrastEdge(Capsule(), normal: Ink.quaternary.opacity(fieldFocused && ask.wantsKeyboard ? 1 : 0))
        .opacity(ready ? 1 : 0.6)
    }

    @ViewBuilder
    private func actions(ready: Bool) -> some View {
        let ask = model.ask
        HStack(spacing: Space.xs) {
            if !ask.answer.isEmpty && !ask.isStreaming {
                AskIconButton(symbol: "doc.on.doc", help: "Copy answer") { ask.copyAnswer() }
            }
            if !ask.history.isEmpty && !ask.isStreaming {
                AskIconButton(symbol: "square.and.pencil", help: "New conversation") { ask.startOver() }
            }
            if ask.isStreaming {
                AskIconButton(symbol: "stop.fill", help: "Stop", prominent: true) { ask.stop() }
            } else {
                let canSend = ready && !ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                AskIconButton(symbol: "arrow.up", help: "Send (Return)", label: "Send", prominent: canSend) { send() }
                    .disabled(!canSend)
            }
        }
        .fixedSize()
    }

    private func send() {
        guard model.ask.status(of: model.ask.provider(in: model.settings.ask)).isReady else { return }
        Haptics.play(.tap)
        model.ask.send(settings: model.settings.ask)
    }

    /// Esc stops an answer in progress; otherwise it closes the island and hands the keyboard back.
    private func escape() {
        if model.ask.isStreaming {
            model.ask.stop()
            return
        }
        model.ask.releaseKeyboard()
        model.pinned = false
        model.setExpanded(nil)
    }

    private func hint(kind: AskProviderKind, status: AskProviderStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(status.message(for: kind))
                .textStyle(.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .needsKey {
                // Straight to the key's row on Ask & AI.
                Button("Add a key…") { AppActions.openSettings(.ai, at: kind == .openai ? "ai.openai" : "ai.anthropic") }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The streamed answer, question first, with a one-line footer. The answer shows whole lines:
/// its window ends on a line, and when more follows, the last line fades over its bottom few
/// points instead of being cut through. Longer answers scroll.
struct AskAnswerView: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode
    /// The answer's full height, to fade the last line only when more follows it.
    @ViewState private var contentHeight: CGFloat = 0

    /// The space between the answer's lines.
    static let leading: CGFloat = 2
    /// One line of the answer (`TextStyle.body`, as Text lays it out: 15 points at 12) and the
    /// space under it.
    static let pitch: CGFloat = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: TextStyle.body.size)) + leading
    /// How much of the last line fades when more follows, and how faint its foot gets: its
    /// descenders stay in sight, so it reads as more to come rather than as cut off.
    static let fade: CGFloat = 6
    static let faintest: Double = 0.2

    /// The tallest window of whole lines in `height` points.
    static func window(in height: CGFloat) -> CGFloat {
        let lines = max(1, ((height + leading) / pitch).rounded(.down))
        return min(height, lines * pitch - leading)
    }

    var body: some View {
        let ask = model.ask
        if case .failed(let message, needsKey: true) = ask.phase {
            // A missing or refused key: what happened, and the button to the key, as the hint
            // says it before anything is sent.
            VStack(alignment: .leading, spacing: Space.s) {
                Text(message)
                    .textStyle(.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                keyButton(ask)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            answer(ask)
        }
    }

    private func answer(_ ask: AskController) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if !ask.question.isEmpty {
                Text(ask.question)
                    .textStyle(.caption, emphasized: true)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                let window = Self.window(in: geo.size.height)
                let overflows = snapshotMode || contentHeight > window + 0.5
                ScrollViewReader { proxy in
                    AdaptiveScroll(scrolls: !snapshotMode) {
                        content(ask)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    // Follow the answer while it streams (at most 20 times a second, like the text).
                    .onChange(of: ask.answer.shown.utf8.count) { _, _ in
                        if ask.isStreaming { proxy.scrollTo(Self.end, anchor: .bottom) }
                    }
                }
                .frame(width: geo.size.width, height: window, alignment: .topLeading)
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(overflows ? Self.faintest : 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fade)
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(_ ask: AskController) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if case .refused(let why) = ask.phase {
                Text("\(ask.answeredBy?.title ?? "The model") declined to answer this." + (why.map { " \($0)" } ?? ""))
                    .textStyle(.body)
                    .foregroundStyle(Ink.secondary)
            } else if ask.answer.isEmpty && ask.isStreaming {
                HStack(spacing: Space.s) {
                    SpinnerArc(tint: Ink.secondary, lineWidth: 1.5).frame(width: 10, height: 10)
                    Text("Thinking").textStyle(.body).foregroundStyle(Ink.secondary)
                }
            } else if !ask.answer.isEmpty {
                Text(Self.render(ask.answer.shown))
                    .textStyle(.body)
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(Self.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footer = footer(ask) {
                Text(footer.text)
                    .textStyle(.caption)
                    .foregroundStyle(footer.warning ? Color.orange : Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
            Color.clear.frame(height: 1).id(Self.end)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Straight to the key's row on Ask & AI: "Add a key…" when there is none, else to change it.
    private func keyButton(_ ask: AskController) -> some View {
        let kind = ask.answeredBy ?? .anthropic
        return Button(ask.status(of: kind) == .needsKey ? "Add a key…" : "Change the key…") {
            AppActions.openSettings(.ai, at: kind == .openai ? "ai.openai" : "ai.anthropic")
        }
        .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
    }

    private static let end = "ask-end"

    private func footer(_ ask: AskController) -> (text: String, warning: Bool)? {
        switch ask.phase {
        case .failed(_, needsKey: true): return nil
        case .failed(let message, needsKey: false): return (message, true)
        case .stopped: return ("Stopped", false)
        case .done:
            var parts: [String] = []
            if let by = ask.answeredBy { parts.append(Self.modelLabel(ask.usage?.model, provider: by)) }
            if let out = ask.usage?.outputTokens { parts.append("\(out) tokens") }
            if let cost = ask.usage?.costUSD, cost > 0 { parts.append(String(format: "$%.3f", cost)) }
            if ask.usage?.wasCut == true { parts.append("cut short at the length limit") }
            if ask.answer.isTrimmed { parts.append("Copy for the full answer") }
            return parts.isEmpty ? nil : (parts.joined(separator: " · "), false)
        default:
            return nil
        }
    }

    /// The model as Settings names it: "Claude Opus 5.5" from "claude-opus-5-5", "GPT-6.1 Sol"
    /// from "gpt-6.1-sol". The provider when the answer didn't say.
    static func modelLabel(_ id: String?, provider: AskProviderKind) -> String {
        guard let id, !id.isEmpty else { return provider.title }
        return AskModelName.title(id)
    }

    /// Inline Markdown (bold, italics, code, links) as models tend to write it. Links may only
    /// open web pages: a link in an answer must not open a file, launch an app or run casement://.
    static func render(_ text: String) -> AttributedString {
        guard var s = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(text)
        }
        let unsafe = s.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let url = run.link else { return nil }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? nil : run.range
        }
        for range in unsafe { s[range].link = nil }
        return s
    }
}

/// Provider picker with a cloud glyph when the question leaves the Mac.
struct AskProviderChip: View {
    let model: AppModel
    let kind: AskProviderKind
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            label
        } else {
            Menu {
                Picker("Ask with", selection: Binding(get: { kind }, set: { AppActions.chooseAskProvider(model, $0) })) {
                    ForEach(AskProviderKind.allCases) { k in
                        Text(k.title + (model.ask.status(of: k).shortReason.map { " (\($0))" } ?? "")).tag(k)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Ask & AI Settings…") { AppActions.openSettings(.ai) }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(kind.recipient.map { "\(kind.title): your question is sent to \($0)" } ?? "On-device: nothing leaves this Mac")
            .accessibilityLabel("Ask with")
            .accessibilityValue(kind.title + (kind.leavesMac ? ", leaves this Mac" : ""))
        }
    }

    private var label: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold))
            Text(kind.title).textStyle(.body, emphasized: true).lineLimit(1).fixedSize()
            if kind.leavesMac {
                Image(systemName: "cloud.fill").font(.system(size: 9)).foregroundStyle(Ink.tertiary)
            }
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.tertiary)
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, Space.m)
        .frame(height: AskView.fieldHeight)
        .background(Capsule().fill(Wash.regular))
        .contrastEdge(Capsule())
        .contentShape(Capsule())
    }
}

struct AskIconButton: View {
    let symbol: String
    let help: String
    /// What VoiceOver says, when the help says more ("Send (Return)").
    var label: String?
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(prominent ? Color.black : Ink.secondary)
                .frame(width: AskView.fieldHeight, height: AskView.fieldHeight)
                .background(Circle().fill(prominent ? Color.white.opacity(isEnabled ? 0.92 : 0.3) : Wash.regular.opacity(isEnabled ? 1 : 0.5)))
                .contrastEdge(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label ?? help)
    }
}

/// Lets the island panel take the keyboard while `active`, and reports when it loses it
/// (the user clicked into another app).
struct PanelKeyBridge: NSViewRepresentable {
    var active: Bool
    var onResign: () -> Void

    func makeNSView(context: Context) -> KeyBridgeView { KeyBridgeView() }

    func updateNSView(_ view: KeyBridgeView, context: Context) {
        view.onResign = onResign
        view.setActive(active)
    }

    static func dismantleNSView(_ view: KeyBridgeView, coordinator: ()) {
        view.setActive(false)
    }
}

final class KeyBridgeView: NSView {
    var onResign: (() -> Void)?
    private var active = false
    private weak var panel: IslandPanel?
    private var observer: NSObjectProtocol?

    func setActive(_ on: Bool) {
        active = on
        apply()
    }

    /// Never takes clicks: it only watches the window.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        if active, let p = window as? IslandPanel {
            panel = p
            p.beginKeyboardInput()
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
                    self?.onResign?()
                }
            }
        } else if !active {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            panel?.endKeyboardInput()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
