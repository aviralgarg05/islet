import AppKit
import IsletCore
import IsletSystem
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AskProviderChip(model: model, kind: kind)
                field(kind: kind, ready: status.isReady)
                actions(ready: status.isReady)
            }
            .frame(height: 26)
            if ask.phase == .idle && ask.answer.isEmpty {
                hint(kind: kind, status: status)
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
            if ask.wantsKeyboard { focusSoon() }
        }
        .onDisappear { ask.releaseKeyboard() }
        .onChange(of: ask.focusRequest) { _, _ in focusSoon() }
    }

    /// Focus once the panel has become key (the bridge makes it key in the same update).
    private func focusSoon() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func placeholder(_ kind: AskProviderKind) -> String {
        model.settings.ask.followUps && !model.ask.history.isEmpty ? "Ask a follow-up" : "Ask \(kind.title)"
    }

    private func field(kind: AskProviderKind, ready: Bool) -> some View {
        let ask = model.ask
        return ZStack(alignment: .leading) {
            if snapshotMode {
                Text(ask.draft.isEmpty ? placeholder(kind) : ask.draft)
                    .foregroundStyle(ask.draft.isEmpty ? Color.islandTertiary : Color.white)
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
                }
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Capsule().fill(Color.islandFill))
        .overlay(Capsule().strokeBorder(Color.white.opacity(fieldFocused && ask.wantsKeyboard ? 0.22 : 0), lineWidth: 1))
        .opacity(ready ? 1 : 0.6)
    }

    @ViewBuilder
    private func actions(ready: Bool) -> some View {
        let ask = model.ask
        HStack(spacing: 2) {
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
                AskIconButton(symbol: "arrow.up", help: "Send (Return)", prominent: canSend) { send() }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(status.message(for: kind))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.islandSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .needsKey {
                Button("Open Settings") { AppActions.openSettings() }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// The streamed answer, question first, with a one-line footer.
struct AskAnswerView: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let ask = model.ask
        ScrollViewReader { proxy in
            AdaptiveScroll(scrolls: !snapshotMode) {
                VStack(alignment: .leading, spacing: 4) {
                    if !ask.question.isEmpty {
                        Text(ask.question)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.islandTertiary)
                            .lineLimit(2)
                    }
                    if case .refused(let why) = ask.phase {
                        Text("\(ask.answeredBy?.title ?? "The model") declined to answer this." + (why.map { " \($0)" } ?? ""))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.islandSecondary)
                    } else if ask.answer.isEmpty && ask.isStreaming {
                        HStack(spacing: 6) {
                            SpinnerArc(tint: Color.islandSecondary, lineWidth: 1.5).frame(width: 10, height: 10)
                            Text("Thinking").font(.system(size: 12)).foregroundStyle(Color.islandSecondary)
                        }
                    } else if !ask.answer.isEmpty {
                        Text(Self.render(ask.answer.shown))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white)
                            .lineSpacing(1.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let footer = footer(ask) {
                        Text(footer.text)
                            .font(.system(size: 10))
                            .foregroundStyle(footer.warning ? Color.orange : Color.islandTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    Color.clear.frame(height: 1).id(Self.end)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            // Follow the answer while it streams (at most 20 times a second, like the text).
            .onChange(of: ask.answer.shown.utf8.count) { _, _ in
                if ask.isStreaming { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private static let end = "ask-end"

    private func footer(_ ask: AskController) -> (text: String, warning: Bool)? {
        switch ask.phase {
        case .failed(let message): return (message, true)
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

    /// "Claude Opus 5.5" from "claude-opus-5-5"; other ids as they are.
    static func modelLabel(_ id: String?, provider: AskProviderKind) -> String {
        guard let id, !id.isEmpty else { return provider.title }
        guard id.hasPrefix("claude-") else { return id }
        let parts: [String] = id.components(separatedBy: "-").dropFirst().filter { $0.count < 8 }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return "Claude \(family.capitalized)" + (version.isEmpty ? "" : " \(version)")
    }

    /// Inline Markdown (bold, italics, code, links) as models tend to write it.
    static func render(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
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
                Picker("Ask with", selection: Binding(get: { kind }, set: { model.ask.sessionProvider = $0 })) {
                    ForEach(AskProviderKind.allCases) { k in
                        Text(k.title + (model.ask.status(of: k).shortReason.map { " (\($0))" } ?? "")).tag(k)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Open Settings…") { AppActions.openSettings() }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(kind.recipient.map { "\(kind.title): your question is sent to \($0)" } ?? "On-device: nothing leaves this Mac")
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol).font(.system(size: 10.5, weight: .semibold))
            Text(kind.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
            if kind.leavesMac {
                Image(systemName: "cloud.fill").font(.system(size: 8.5)).foregroundStyle(Color.islandTertiary)
            }
            Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Color.islandTertiary)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.islandFill))
        .contentShape(Capsule())
    }
}

struct AskIconButton: View {
    let symbol: String
    let help: String
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
                .foregroundStyle(prominent ? Color.black : Color.islandSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(prominent ? Color.white.opacity(isEnabled ? 0.92 : 0.3) : Color.islandFill.opacity(isEnabled ? 1 : 0.5)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The sparkles button in the island's top strip that opens the Ask tab.
struct AskStripButton: View {
    let model: AppModel

    var body: some View {
        let selected = model.tab == .ask
        Button {
            Haptics.play(.tap)
            model.select(tab: .ask)
        } label: {
            Image(systemName: IslandTab.ask.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.islandTertiary)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.islandFill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(IslandTab.ask.title)
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
