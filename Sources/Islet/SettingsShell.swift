import AppKit
import IsletCore
import Observation
import SwiftUI

/// Which Settings page is showing, the search text, and the row a search result asked for.
/// Owned by the app delegate, so the last page stays selected for the rest of the session.
@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPage = .general
    var query = ""
    /// The row to scroll to once its page is on screen; cleared when done.
    var reveal: String?
    /// The row that briefly shows a highlight after a search result or a link opened it.
    var highlighted: String?
    /// Bumped by ⌘F to put the cursor in the search field.
    var searchFocusRequest = 0

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var results: [SettingsSearchGroup] { SettingsIndex.search(query) }

    /// Show `page`, scrolled to the row `anchor` names (an id from `SettingsIndex`), if any.
    func open(_ page: SettingsPage, at anchor: String? = nil) {
        self.page = page
        query = ""
        reveal = anchor
        highlighted = anchor
    }

    /// Show a search result: its page, scrolled to its row.
    func open(_ entry: SettingsEntry) { open(entry.page, at: entry.anchor) }
}

/// The Settings window's size and frame.
@MainActor
enum SettingsWindow {
    static let sidebarWidth: CGFloat = 216
    /// Tall enough for every page in the sidebar without scrolling.
    static let defaultSize = NSSize(width: 780, height: 596)
    /// Wide enough for the sidebar and the widest rows (segmented pickers), tall enough for a
    /// page's first sections. Both columns scroll below that.
    static let minimumSize = NSSize(width: 700, height: 440)
    /// The title bar row, which the sidebar's search field and the page title sit under and in.
    static let headerHeight: CGFloat = 52

    /// `window` and `snapshot` are for `--settings-snapshot`, which draws an off-screen window.
    static func make(model: AppModel, navigation: SettingsNavigation, window: NSWindow? = nil, snapshot: Bool = false) -> NSWindow {
        let root = SettingsView(model: model, navigation: navigation).environment(\.snapshotMode, snapshot)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        let w = window ?? NSWindow()
        w.contentViewController = host
        w.title = "Islet Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        // An empty toolbar gives the title bar System Settings' height, so the window buttons
        // line up with the page title.
        let toolbar = NSToolbar(identifier: "IsletSettings")
        toolbar.showsBaselineSeparator = false
        w.toolbar = toolbar
        w.toolbarStyle = .unified
        w.tabbingMode = .disallowed
        w.contentMinSize = minimumSize
        w.setContentSize(defaultSize)
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName(snapshot ? "" : "IsletSettingsWindow")
        if !snapshot, !w.setFrameUsingName("IsletSettingsWindow") { w.center() }
        return w
    }
}

/// The whole Settings window: a sidebar of pages with search, and the selected page.
struct SettingsShell: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(navigation: navigation)
                .frame(width: SettingsWindow.sidebarWidth)
            Divider().ignoresSafeArea()
            SettingsDetail(model: model, navigation: navigation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .frame(minWidth: SettingsWindow.minimumSize.width, minHeight: SettingsWindow.minimumSize.height)
        .environment(\.openSettingsPage) { page, anchor in navigation.open(page, at: anchor) }
        .background {
            // ⌘F from anywhere in the window.
            Button("Search settings") { navigation.searchFocusRequest += 1 }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation
    @Environment(\.snapshotMode) private var snapshotMode
    /// The page list has the keyboard when the window opens, so the arrow keys move between pages.
    @FocusState private var listFocused: Bool

    /// While searching, only pages with a match are listed.
    private var shown: Set<SettingsPage> {
        navigation.isSearching ? Set(navigation.results.map(\.page)) : Set(SettingsPage.allCases)
    }

    /// No page is selected while search results are showing; picking one ends the search.
    private var selection: Binding<SettingsPage?> {
        Binding(get: { navigation.isSearching ? nil : navigation.page },
                set: { if let page = $0 { navigation.open(page) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField(navigation: navigation)
                .padding(.horizontal, 10)
                .padding(.top, SettingsWindow.headerHeight - 12)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                Group {
                    // Snapshots can't draw the system's selection highlight, so they draw their own.
                    if snapshotMode {
                        List { groups(selected: navigation.isSearching ? nil : navigation.page) }
                    } else {
                        List(selection: selection) { groups(selected: nil) }
                            .focused($listFocused)
                    }
                }
                // A page opened from a search result or from elsewhere in Islet may be out of view.
                .onAppear {
                    proxy.scrollTo(navigation.page)
                    if !snapshotMode { DispatchQueue.main.async { listFocused = true } }
                }
                .onChange(of: navigation.page) { _, page in proxy.scrollTo(page) }
            }
        }
        .listStyle(.sidebar)
        // Small rows fit all sixteen pages in the window's usual height.
        .environment(\.sidebarRowSize, .small)
        .scrollContentBackground(.hidden)
        .background(SidebarMaterial(snapshot: snapshotMode).ignoresSafeArea())
    }

    @ViewBuilder private func groups(selected: SettingsPage?) -> some View {
        ForEach(SettingsPageGroup.allCases) { group in
            let pages = group.pages.filter(shown.contains)
            if !pages.isEmpty {
                Section {
                    ForEach(pages) { page in
                        SidebarRow(page: page, drawsSelection: selected == page).tag(page).id(page)
                    }
                } header: {
                    // Groups without a title are set apart by the list's own section spacing.
                    if let title = group.title { Text(title) }
                }
            }
        }
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    var drawsSelection = false

    var body: some View {
        Label {
            Text(page.title)
                .lineLimit(1)
                .foregroundStyle(drawsSelection ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        } icon: {
            SettingsTile(page: page)
        }
        .listRowBackground(drawsSelection
                           ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .controlAccentColor)).padding(.horizontal, 10)
                           : nil)
    }
}

/// A page's symbol on a small rounded square of its colour, as in System Settings.
struct SettingsTile: View {
    let page: SettingsPage
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Self.colour(page.tint).gradient))
            .accessibilityHidden(true)
    }

    static func colour(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "indigo": return .indigo
        case "teal": return .teal
        case "pink": return .pink
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        case "mint": return .mint
        case "yellow": return .yellow
        case "brown": return .brown
        case "purple": return .purple
        case "graphite": return Color(white: 0.32)
        default: return Color(white: 0.56)
        }
    }
}

/// Search box at the top of the sidebar. ⌘F puts the cursor in it, Return opens the first
/// result, and Esc clears it.
struct SettingsSearchField: View {
    @Bindable var navigation: SettingsNavigation
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField("Search", text: $navigation.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    if let first = navigation.results.first?.entries.first { navigation.open(first) }
                }
                .onExitCommand { navigation.query = "" }
            if !navigation.query.isEmpty {
                Button { navigation.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: focused ? 2 : 1)
        }
        .onChange(of: navigation.searchFocusRequest) { _, _ in focused = true }
    }
}

/// Behind-window sidebar material, like System Settings' sidebar.
private struct SidebarMaterial: View {
    var snapshot: Bool

    var body: some View {
        // Snapshots draw off screen, where there's nothing behind the window to blur.
        if snapshot { Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(0.035)) } else { Effect() }
    }

    private struct Effect: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .sidebar
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}

// MARK: - Detail

struct SettingsDetail: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation

    private var title: String {
        navigation.isSearching ? "Search results" : navigation.page.title
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(height: SettingsWindow.headerHeight)
                .background(WindowDragArea())
            Divider()
            Group {
                if navigation.isSearching {
                    SettingsSearchResults(navigation: navigation)
                } else {
                    ScrollViewReader { proxy in
                        SettingsPageView(model: model, page: navigation.page)
                            .id(navigation.page)
                            .environment(\.settingsHighlight, navigation.highlighted)
                            .onAppear { reveal(proxy) }
                            .onChange(of: navigation.reveal) { _, _ in reveal(proxy) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Scroll to the row a search result named once the page has laid out, and let its
    /// highlight fade after a moment.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let anchor = navigation.reveal else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(anchor, anchor: .center)
            navigation.reveal = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if navigation.highlighted == anchor {
                withAnimation(.easeOut(duration: 0.4)) { navigation.highlighted = nil }
            }
        }
    }
}

/// One Settings page, by its sidebar entry.
struct SettingsPageView: View {
    @Bindable var model: AppModel
    let page: SettingsPage

    var body: some View {
        switch page {
        case .general: GeneralSettings(model: model)
        case .appearance: AppearanceSettings(model: model)
        case .shortcuts: ShortcutSettings(model: model)
        case .nowPlaying: NowPlayingSettings(model: model)
        case .liveActivities: LiveActivitiesSettings(model: model)
        case .calendar: CalendarSettings(model: model)
        case .timers: TimersSettings(model: model)
        case .notifications: NotificationsSettings(model: model)
        case .shelf: ShelfSettings(model: model)
        case .downloads: DownloadsSettings(model: model)
        case .tools: ToolsSettings(model: model)
        case .ai: AISettingsView(model: model)
        case .agents: CodingAgentsSettings(model: model)
        case .apps: AppRulesSettings(model: model)
        case .permissions: PermissionsSettings(model: model)
        case .about: AboutSettings()
        case .advanced: AdvancedSettings(model: model)
        }
    }
}

/// Search results, grouped by page. Choosing one opens its page at that row.
struct SettingsSearchResults: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        let groups = navigation.results
        if groups.isEmpty {
            ZStack {
                // An empty grouped form, so the background matches every page's.
                Form {}.formStyle(.grouped).allowsHitTesting(false).accessibilityHidden(true)
                ContentUnavailableView {
                    Label("No results", systemImage: "magnifyingglass")
                } description: {
                    Text("Nothing matches “\(navigation.query.trimmingCharacters(in: .whitespaces))”. Try another word, such as a feature or an app.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            Button { navigation.open(entry) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.title).foregroundStyle(.primary)
                                        if let section = entry.section, section != entry.title {
                                            Text(section).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if entry == groups.first?.entries.first {
                                        Text("Return").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label { Text(group.page.title) } icon: { SettingsTile(page: group.page, size: 16) }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Rows

private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct OpenSettingsPageKey: EnvironmentKey {
    static let defaultValue: @MainActor (SettingsPage, String?) -> Void = { _, _ in }
}

extension EnvironmentValues {
    /// The row a search result just opened.
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }

    /// Opens another Settings page, scrolled to a row, from a link on a page.
    var openSettingsPage: @MainActor (SettingsPage, String?) -> Void {
        get { self[OpenSettingsPageKey.self] }
        set { self[OpenSettingsPageKey.self] = newValue }
    }
}

private struct SettingsAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        content
            .id(id)
            .background {
                if highlight == id {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .padding(.horizontal, -8)
                        .padding(.vertical, -4)
                }
            }
    }
}

extension View {
    /// Marks the row a search result scrolls to (the `anchor` of an entry in `SettingsIndex`).
    func settingsAnchor(_ id: String) -> some View { modifier(SettingsAnchor(id: id)) }
}

/// The first row of a page: its tile, what it does in a line, and the feature's switch.
/// Pages without one switch show the tile and the line alone.
struct SettingsHero<Accessory: View>: View {
    let page: SettingsPage
    /// The switch's label, as an action ("Show what's playing").
    var switchTitle: String?
    var isOn: Binding<Bool>?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsTile(page: page, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                if let switchTitle { Text(switchTitle).font(.body.weight(.semibold)) }
                Text(page.summary)
                    .font(switchTitle == nil ? .body : .callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory
            if let isOn {
                Toggle(switchTitle ?? page.title, isOn: isOn).labelsHidden().toggleStyle(.switch)
            }
        }
        .padding(.vertical, 3)
    }
}

extension SettingsHero where Accessory == EmptyView {
    init(page: SettingsPage, switchTitle: String? = nil, isOn: Binding<Bool>? = nil) {
        self.init(page: page, switchTitle: switchTitle, isOn: isOn) { EmptyView() }
    }
}

/// A row with a title, an optional line under it, and a control centred on the right. For
/// controls taller than a line, which `LabeledContent` would pin to the top.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// Explanatory text under a section, aligned to the leading edge like System Settings.
struct SettingsFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet line that sends the user to another page ("Set up your own scripts in Advanced").
struct SettingsLink: View {
    let text: String
    let page: SettingsPage
    var anchor: String?
    @Environment(\.openSettingsPage) private var openPage

    var body: some View {
        Button { openPage(page, anchor) } label: {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.link)
    }
}

/// A line saying a permission is missing, with the button that fixes it.
struct AccessRow: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(button, action: action)
        }
    }
}

/// A slider with its value on the right, the same width on every page.
struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    /// Rounded to the step here rather than by the slider, which would draw a tick per step.
    private var stepped: Binding<Double> {
        Binding(get: { value }, set: { v in
            let rounded = (v / step).rounded() * step
            value = min(range.upperBound, max(range.lowerBound, (rounded * 1000).rounded() / 1000))
        })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: stepped, in: range) { Text(title) }
                    .labelsHidden()
                    .frame(minWidth: 140, maxWidth: 220)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    static func seconds(_ v: Double) -> String { String(format: v < 1 ? "%.2f s" : "%.1f s", v) }
    static func points(_ v: Double) -> String { "\(Int(v.rounded())) pt" }
}

/// Lets the page title strip, which sits in the title bar, move the window like a title bar.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
