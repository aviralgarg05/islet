import AppKit
import IsletCore
import IsletSystem
import SwiftUI

// Settings for the note tools (Tools page), the pages in the switcher (General), how long the
// shelf keeps files (Shelf & Clipboard) and Send feedback (About).

// MARK: - Tools: to-dos, note, converter, emoji

struct NoteToolsSettingsSections: View {
    @Bindable var model: AppModel
    @ViewState private var canType = EmojiTyper.canType
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.todosEnabled) {
                Text("To-dos")
                Text("A To-dos page under More: add a line, star what matters, tick it off.")
            }
            .settingsAnchor("tools.todos")
            Toggle(isOn: $model.settings.noteEnabled) {
                Text("Quick note")
                Text("A Note page under More that keeps its text until you clear it.")
            }
            .settingsAnchor("tools.note")
        } header: {
            Text("To-dos and notes")
        } footer: {
            SettingsFooter("Both stay on this Mac.")
        }
        Section {
            Toggle(isOn: $model.settings.converterEnabled) {
                Text("Unit converter")
                Text("A Converter page under More for lengths, weights, temperatures, volumes and speeds. Type something like 5 ft in cm, there or in the Ask box.")
            }
            .settingsAnchor("tools.converter")
            Toggle(isOn: $model.settings.emojiEnabled) {
                Text("Emoji")
                Text("An Emoji page under More: find any emoji by name and click it to copy it.")
            }
            .settingsAnchor("tools.emoji")
            if model.settings.emojiEnabled {
                Toggle(isOn: $model.settings.emojiTypes) {
                    Text("Type emoji where you're typing")
                    Text("A click types the emoji into the app you were typing in, instead of copying it. macOS asks once to let Islet do this.")
                }
                .settingsAnchor("tools.emojiTypes")
                .onChange(of: model.settings.emojiTypes) { _, on in
                    // Switching it on is when macOS asks, never before.
                    guard on, !snapshotMode, !EmojiTyper.canType else { return }
                    PermissionProbe.request(.accessibility) { _ in canType = EmojiTyper.canType }
                }
                if model.settings.emojiTypes && !canType && !snapshotMode {
                    AccessRow(text: "Islet isn't allowed to type for you yet, so emoji are copied instead.", button: "Open System Settings") {
                        NSWorkspace.shared.open(PermissionKind.accessibility.settingsURL)
                    }
                }
            }
        } header: {
            Text("Converter and emoji")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canType = EmojiTyper.canType
        }
    }
}

// MARK: - General: pages in the switcher

/// The pages that are on, in the order the switcher shows them: up to four in the capsule, the
/// rest under More. Drag a row onto another, or onto a heading; each row's menu does the same
/// from the keyboard. A page's switch leaves it out of the switcher without turning it off.
struct IslandPagesEditor: View {
    @Bindable var model: AppModel
    @Environment(\.openSettingsPage) private var openPage

    private var listed: (IslandPage) -> Bool {
        let s = model.settings
        return { $0.isAvailable(s) }
    }

    var body: some View {
        let layout = model.settings.islandPages
        let bar = layout.bar.filter(listed)
        let more = layout.more.filter(listed)
        LabeledContent {
            Button("Reset") { model.settings.islandPages = .standard }
                .disabled(layout == .standard)
        } label: {
            Text("Pages in the switcher")
            // `IslandPageLayout.maxInBar` pages fit in the capsule.
            Text("Drag a page to change its order, or into More. The capsule holds four pages; the rest are in its More menu.")
        }
        .settingsAnchor("general.pages")
        heading("In the capsule", place: .bar)
        ForEach(bar, id: \.self) { page in row(page) }
        heading("Under More", place: .more)
        if more.isEmpty {
            Text("Drag a page here to keep it under More.")
                .font(.callout).foregroundStyle(.secondary)
                .dropDestination(for: String.self) { items, _ in drop(items, to: .more) }
        }
        ForEach(more, id: \.self) { page in row(page) }
        HStack {
            Text("Turn on more pages on the Tools page: to-dos, a note, a converter, emoji and others.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Open Tools") { openPage(.tools, nil) }
        }
    }

    private func heading(_ title: String, place: IslandPageLayout.Place) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in drop(items, to: place) }
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ page: IslandPage) -> some View {
        let tab = IslandTab(rawValue: page.rawValue)
        let shown = model.settings.islandPages.isShown(page)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: tab?.symbol ?? "square")
                .frame(width: 18)
                .foregroundStyle(shown ? .primary : .tertiary)
                .accessibilityHidden(true)
            Text(page.title).foregroundStyle(shown ? .primary : .secondary)
            Spacer(minLength: 8)
            Menu {
                Button("Move up") { nudge(page, -1) }
                Button("Move down") { nudge(page, 1) }
                if model.settings.islandPages.place(of: page) == .bar {
                    Button("Move to More") { move(page, to: .more) }.disabled(page == .home)
                } else {
                    Button("Move to the capsule") { move(page, to: .bar) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Move \(page.title)")
            if page == .home {
                Text("Always shown").font(.callout).foregroundStyle(.secondary)
            } else {
                Toggle("Show \(page.title)", isOn: Binding(get: { model.settings.islandPages.isShown(page) },
                                                           set: { model.settings.islandPages.setShown(page, $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .draggable(page.rawValue) {
            Label(page.title, systemImage: tab?.symbol ?? "square").padding(6)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = IslandPage(rawValue: raw) else { return false }
            model.settings.islandPages.move(dragged, onto: page, listed: listed)
            return true
        }
    }

    private func drop(_ items: [String], to place: IslandPageLayout.Place) -> Bool {
        guard let raw = items.first, let page = IslandPage(rawValue: raw) else { return false }
        move(page, to: place)
        return true
    }

    private func move(_ page: IslandPage, to place: IslandPageLayout.Place) {
        model.settings.islandPages.move(page, to: place, atStart: place == .more, listed: listed)
    }

    private func nudge(_ page: IslandPage, _ step: Int) {
        model.settings.islandPages.nudge(page, by: step, listed: listed)
    }
}

// MARK: - Shelf: how long files stay

struct ShelfKeepPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        let current = model.settings.shelfKeepFor
        // A time set in config.json that isn't one of the choices is offered too.
        let choices = IsletSettings.shelfKeepChoices.contains(current)
            ? IsletSettings.shelfKeepChoices : [current] + IsletSettings.shelfKeepChoices
        Picker(selection: $model.settings.shelfKeepFor) {
            ForEach(choices, id: \.self) { Text(Shelf.keepTitle($0)).tag($0) }
        } label: {
            Text("Keep files on the shelf for")
            Text("Then they leave the shelf. The files themselves stay where they are.")
        }
        .settingsAnchor("shelf.keepFor")
    }
}

// MARK: - About: send feedback

struct FeedbackRow: View {
    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                ForEach(Feedback.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { AppActions.sendFeedback(kind) }
                }
            }
        } label: {
            Text("Send feedback")
            Text("Opens a form on GitHub in your browser with the Islet and macOS versions filled in. Nothing is sent until you submit it there.")
        }
        .settingsAnchor("about.feedback")
    }
}

extension AppActions {
    /// The issue form on GitHub, in the browser, with the versions filled in.
    static func sendFeedback(_ kind: Feedback.Kind) {
        NSWorkspace.shared.open(Feedback.url(kind, version: AppModel.version, macOS: macOSVersion))
    }

    /// "macOS 27.0.1 (26A123)", as About This Mac writes it.
    static var macOSVersion: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build: String?
        if size > 0 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 { build = String(cString: bytes) }
        }
        return Feedback.macOSVersion(ProcessInfo.processInfo.operatingSystemVersion, build: build)
    }
}
