import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// The Shortcuts page (under More once turned on): a search field like Ask's and the user's
/// shortcuts, two to a row. Clicking one runs it on this Mac; Return runs the first match.
struct ShortcutsTab: View {
    let model: AppModel
    @FocusState private var focused: Bool
    /// The field has the keyboard (the island's panel only takes it when asked).
    @ViewState private var typing = false
    @Environment(\.snapshotMode) private var snapshotMode

    static let rowHeight: CGFloat = 26

    var body: some View {
        let c = model.tools.shortcuts
        Group {
            if !model.settings.shortcutsEnabled {
                EmptyHint(symbol: "square.stack.3d.up",
                          text: "Run your shortcuts from the island: search for one and click it. They run on this Mac, as they do in the Shortcuts app.") {
                    Button("Turn on") { model.setTool(\.shortcutsEnabled, true) }
                        .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                }
            } else if c.unavailable {
                EmptyHint(symbol: "square.stack.3d.up", text: "The Shortcuts app isn't on this Mac.")
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    field
                    list(c)
                }
            }
        }
        // On opening the page, and again once it is turned on.
        .task(id: model.settings.shortcutsEnabled) { if !snapshotMode { c.refresh() } }
        .onDisappear {
            guard typing else { return }
            typing = false
            IslandKeyboard.giveBack()
        }
    }

    private var field: some View {
        let c = model.tools.shortcuts
        return HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if snapshotMode {
                    Text(c.query.isEmpty ? "Search shortcuts" : c.query)
                        .foregroundStyle(c.query.isEmpty ? Ink.tertiary : Ink.primary)
                        .lineLimit(1)
                } else {
                    TextField("Search shortcuts", text: Binding(get: { c.query }, set: { c.query = $0 }))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Ink.primary)
                        .focused($focused)
                        .onSubmit { if let first = c.results.first { c.run(first) } }
                        .onExitCommand(perform: escape)
                        .accessibilityLabel("Search shortcuts")
                    // The first click hands the keyboard to the island, then the field takes it.
                    if !typing {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                typing = true
                                IslandKeyboard.take(on: model.expandedScreen)
                                DispatchQueue.main.async { focused = true }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textStyle(.body)
        .padding(.horizontal, Space.m)
        .frame(height: 26)
        .background(Capsule().fill(Wash.regular))
    }

    /// Esc clears the search, then gives the keyboard back.
    private func escape() {
        let c = model.tools.shortcuts
        if !c.query.isEmpty {
            c.query = ""
        } else {
            typing = false
            focused = false
            IslandKeyboard.giveBack()
        }
    }

    @ViewBuilder
    private func list(_ c: ShortcutsController) -> some View {
        let results = c.results
        if !c.loaded {
            HStack(spacing: Space.s) {
                SpinnerArc(tint: Ink.tertiary, lineWidth: 1.5).frame(width: 10, height: 10)
                Text("Reading your shortcuts").textStyle(.body).foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Space.xs)
        } else if c.items.isEmpty {
            HStack(spacing: Space.s) {
                Text("No shortcuts yet.").textStyle(.body).foregroundStyle(Ink.tertiary)
                Button("Open Shortcuts") { ShortcutsLink.openApp() }.buttonStyle(CapsuleButtonStyle())
            }
            .padding(.horizontal, Space.xs)
        } else if results.isEmpty {
            Text("No shortcut called “\(c.query)”").textStyle(.body).foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .padding(.horizontal, Space.xs)
        } else {
            AdaptiveScroll(scrolls: results.count > 4) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                          alignment: .leading, spacing: 2) {
                    ForEach(results.prefix(snapshotMode ? 4 : 200)) { item in
                        ShortcutRow(item: item, state: c.runs[item.id]) { c.run(item) }
                    }
                }
            }
            .padding(.horizontal, -Space.xs)
        }
    }
}

/// One shortcut: its name, and while it runs a spinner, then a tick or what went wrong.
struct ShortcutRow: View {
    let item: ShortcutItem
    let state: ShortcutRunState?
    /// Said at rest on the right ("Run shortcut" in the Ask box).
    var caption: String?
    var run: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: Space.s) {
                AppIconView(bundleID: ShortcutsLink.bundleID, size: 14)
                    .frame(width: 14, height: 14)
                Text(item.name)
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, Space.s)
            .frame(height: ShortcutsTab.rowHeight)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel("Run \(item.name)")
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .running:
            SpinnerArc(tint: Ink.secondary, lineWidth: 1.5).frame(width: 10, height: 10)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Color.orange)
        case nil:
            if let caption {
                Text(caption).textStyle(.caption).foregroundStyle(hovering ? Ink.secondary : Ink.tertiary).lineLimit(1).fixedSize()
            } else if hovering {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.tertiary)
            }
        }
    }

    private var help: String {
        switch state {
        case .running: return "Running"
        case .done: return "Done"
        case .failed(let reason): return reason ?? "It didn't finish"
        case nil: return "Run “\(item.name)”"
        }
    }
}

/// The Ask box offers the shortcut whose name best matches what is being typed, while
/// Shortcuts is on. One at most, so the box stays calm.
struct AskShortcutSuggestion: View {
    let model: AppModel
    let item: ShortcutItem

    static func match(_ model: AppModel) -> ShortcutItem? {
        guard model.settings.shortcutsEnabled else { return nil }
        return ShortcutsCatalog.suggestions(for: model.ask.draft, in: model.tools.shortcuts.items, limit: 1).first
    }

    var body: some View {
        let c = model.tools.shortcuts
        ShortcutRow(item: item, state: c.runs[item.id], caption: "Run shortcut") { c.run(item) }
            .padding(.horizontal, -Space.xs)
    }
}

enum ShortcutsLink {
    static let bundleID = "com.apple.shortcuts"

    static func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
