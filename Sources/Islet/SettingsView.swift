import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// The Settings window's content: a sidebar of pages (SettingsShell.swift) and the page itself.
/// Feature pages are in FeatureSettings.swift, Coding agents in AgentSettings.swift, Ask & AI in
/// AISettingsView.swift and Advanced in AdvancedSettings.swift.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        SettingsShell(model: model, navigation: navigation)
            .onChange(of: model.settings) { _, _ in model.settingsEdited() }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { SettingsHero(page: .general) }
            Section("Behaviour") {
                LaunchAtLoginToggle()
                    .settingsAnchor("general.login")
                Picker("Open the island", selection: $model.settings.hoverToOpen) {
                    Text("When the pointer reaches it").tag(true)
                    Text("When I click it").tag(false)
                }
                .settingsAnchor("general.open")
                if model.settings.hoverToOpen {
                    SettingsSlider(title: "Hover delay", value: $model.settings.openDelay, range: IsletSettings.openDelayRange,
                                   step: 0.05, format: SettingsSlider.seconds)
                }
                SettingsSlider(title: "Close delay", value: $model.settings.closeDelay, range: IsletSettings.closeDelayRange,
                               step: 0.05, format: SettingsSlider.seconds)
                    .settingsAnchor("general.closeDelay")
            }
            Section("Placement") {
                Picker("Show the island on", selection: $model.settings.displayMode) {
                    Text("The display with a notch").tag(DisplayMode.notchedScreen)
                    Text("The main display").tag(DisplayMode.mainScreen)
                    Text("Every display").tag(DisplayMode.allScreens)
                }
                .settingsAnchor("general.display")
                Toggle("Show on displays without a notch", isOn: $model.settings.showOnNonNotchDisplays)
                    .settingsAnchor("general.nonNotch")
                Toggle(isOn: $model.settings.hideInFullscreen) {
                    Text("Hide when an app is fullscreen")
                    Text("Apps can keep it in fullscreen from the Apps page.")
                }
                .settingsAnchor("general.fullscreen")
                Toggle("Hide from screenshots and screen sharing", isOn: $model.settings.hideFromScreenCapture)
                    .settingsAnchor("general.capture")
            }
            GestureSettingsSection(model: model)
            Section("Island pages") {
                Toggle(isOn: $model.settings.systemStatsEnabled) {
                    Text("System stats")
                    Text("CPU and memory on the System page, measured only while it's open.")
                }
                .settingsAnchor("general.stats")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Bindable var model: AppModel
    @Environment(\.openSettingsPage) private var openPage

    static let accents = ["auto", "white", "blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "teal"]

    private var s: IsletSettings { model.settings }

    var body: some View {
        Form {
            Section {
                IslandPreview(settings: s)
                    .settingsAnchor("appearance.preview")
                HStack {
                    Text("Changes show here and in the island straight away.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show a Sample in the Island") { AppActions.previewAppearance(model) }
                        .controlSize(.small)
                }
            }
            Section("Theme") {
                ThemePicker(selection: $model.settings.theme, settings: s)
                    .settingsAnchor("appearance.theme")
                if s.theme == .glass {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text("Black").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $model.settings.glassLevel, in: IsletSettings.glassLevelRange) { Text("Glass level") }
                                .labelsHidden()
                                .frame(minWidth: 120, maxWidth: 200)
                            Text("Glass").font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Glass level")
                        Text("The strip beside the notch stays black; below it the island melts into glass.")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent colour")
                    AccentPicker(selection: $model.settings.accentColor)
                }
                .settingsAnchor("appearance.accent")
                Toggle("Rounded text", isOn: $model.settings.roundedFont)
                    .settingsAnchor("appearance.rounded")
                Toggle(isOn: $model.settings.smartIcons) {
                    Text("Smart icons and colours for activities")
                    Text("Picks an icon and colour for activities that don't bring their own.")
                }
                .settingsAnchor("appearance.smartIcons")
            }
            Section("Size") {
                Picker("Island size", selection: presetBinding) {
                    Text("Compact").tag(SizePreset.compact)
                    Text("Standard").tag(SizePreset.standard)
                    Text("Large").tag(SizePreset.large)
                    Text("Custom").tag(SizePreset.custom)
                }
                .pickerStyle(.segmented)
                .settingsAnchor("appearance.size")
                SettingsSlider(title: "Open width", value: size(\.expandedWidth) { $0.expandedSize.width },
                               range: IsletSettings.expandedWidthRange, step: 10, format: SettingsSlider.points)
                    .settingsAnchor("appearance.width")
                SettingsSlider(title: "Open height", value: size(\.expandedHeight) { $0.expandedSize.height },
                               range: IsletSettings.expandedHeightRange, step: 10, format: SettingsSlider.points)
                    .settingsAnchor("appearance.height")
            }
            Section {
                Picker("Closed island width", selection: $model.settings.closedLayout) {
                    Text("Fit the menu bar").tag(ClosedLayoutPreference.auto)
                    Text("Always full width").tag(ClosedLayoutPreference.wings)
                }
                .pickerStyle(.segmented)
                .settingsAnchor("appearance.closed")
                SettingsSlider(title: "Wing width", value: size(\.wingWidth) { $0.effectiveWingWidth },
                               range: IsletSettings.wingWidthRange, step: 2, format: SettingsSlider.points)
                    .settingsAnchor("appearance.wing")
                if s.closedLayout == .auto && !MenuBarInspector.isAvailable {
                    AccessRow(text: "Islet needs Accessibility to see the menu bar. Until then it uses narrow wings.",
                              button: "Allow…") { MediaKeyInterceptor.requestAccessibility() }
                }
            } header: {
                Text("Closed island")
            } footer: {
                SettingsFooter(s.closedLayout == .auto
                               ? "The island sits beside the notch and shrinks to the free space in the menu bar, down to an icon each side. The wing width is the most it takes."
                               : "The island sits beside the notch at the wing width, even if that covers menu bar icons near the notch.")
            }
            Section("Motion") {
                Picker("Animation", selection: $model.settings.animationStyle) {
                    Text("Fluid").tag(AnimationStyle.fluid)
                    Text("Snappy").tag(AnimationStyle.snappy)
                    Text("Smooth").tag(AnimationStyle.smooth)
                    Text("Minimal").tag(AnimationStyle.minimal)
                    Text("Off").tag(AnimationStyle.off)
                }
                .pickerStyle(.segmented)
                .settingsAnchor("appearance.animation")
                Toggle("Bounce when something new arrives", isOn: $model.settings.bounceOnActivity)
                    .settingsAnchor("appearance.bounce")
                Toggle("Glow while something needs you", isOn: $model.settings.urgentGlow)
                    .settingsAnchor("appearance.glow")
                Toggle("Reduce motion", isOn: $model.settings.reduceMotion)
                    .settingsAnchor("appearance.reduceMotion")
                Picker("Trackpad haptics", selection: $model.settings.hapticsMode) {
                    Text("Off").tag(HapticsMode.off)
                    Text("When I use the island").tag(HapticsMode.direct)
                    Text("Also for important alerts").tag(HapticsMode.all)
                }
                .settingsAnchor("appearance.haptics")
                SettingsSlider(title: "New activities stay open for", value: $model.settings.alertDuration,
                               range: IsletSettings.alertDurationRange, step: 0.5, format: SettingsSlider.seconds)
                    .settingsAnchor("appearance.alertDuration")
            }
            Section("Several at once") {
                Picker("Activities shown together", selection: $model.settings.maxConcurrent) {
                    Text("One").tag(1)
                    Text("Two").tag(2)
                    Text("Three").tag(3)
                }
                .pickerStyle(.segmented)
                .settingsAnchor("appearance.together")
                Picker("Extra activities appear", selection: $model.settings.bubblePlacement) {
                    Text("Right of the notch").tag(BubblePlacement.right)
                    Text("Left of the notch").tag(BubblePlacement.left)
                }
                .disabled(s.maxConcurrent == 1)
                .settingsAnchor("appearance.bubbles")
            }
            Section("Now Playing") {
                LabeledContent("Playing indicator") {
                    HStack(spacing: 10) {
                        Text(Self.indicatorSummary(s)).foregroundStyle(.secondary)
                        Button("Change…") { openPage(.nowPlaying, "nowPlaying.indicator") }
                    }
                }
                .settingsAnchor("appearance.indicator")
            }
        }
        .formStyle(.grouped)
    }

    static func indicatorSummary(_ s: IsletSettings) -> String {
        let style: String
        switch s.visualiserStyle {
        case .bars: style = "Bars"
        case .slim: style = "Slim bars"
        case .dots: style = "Dots"
        case .off: return "Off"
        }
        switch s.visualiserColour {
        case .artwork: return "\(style), artwork colour"
        case .accent: return "\(style), accent colour"
        case .white: return "\(style), white"
        }
    }

    /// Picking Custom starts from the size on show, so nothing jumps.
    private var presetBinding: Binding<SizePreset> {
        Binding(get: { model.settings.sizePreset }, set: { preset in
            var settings = model.settings
            if preset == .custom, let d = settings.sizePreset.dimensions {
                settings.expandedWidth = d.width
                settings.expandedHeight = d.height
                settings.wingWidth = d.wing
            }
            settings.sizePreset = preset
            model.settings = settings
        })
    }

    /// A size slider shows the size in use. Moving it switches to Custom, starting from the
    /// preset's sizes, so the other two stay where they were.
    private func size(_ key: WritableKeyPath<IsletSettings, Double>, effective: @escaping (IsletSettings) -> Double) -> Binding<Double> {
        Binding(get: { effective(model.settings) }, set: { value in
            var settings = model.settings
            if settings.sizePreset != .custom, let d = settings.sizePreset.dimensions {
                settings.expandedWidth = d.width
                settings.expandedHeight = d.height
                settings.wingWidth = d.wing
                settings.sizePreset = .custom
            }
            settings[keyPath: key] = value
            model.settings = settings
        })
    }
}

/// The three themes as small pictures of the open island.
private struct ThemePicker: View {
    @Binding var selection: IslandTheme
    let settings: IsletSettings

    private static let themes: [(IslandTheme, String)] = [(.glass, "Glass"), (.black, "Black"), (.graphite, "Graphite")]

    /// The pictures show a standard island whatever the size, so it always fits the card.
    private var standard: IsletSettings {
        var s = settings
        s.sizePreset = .standard
        return s
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.themes, id: \.0) { theme, name in
                Button { selection = theme } label: {
                    VStack(spacing: 6) {
                        IslandSketch(settings: standard, theme: theme, open: true, scale: 0.19, detailed: false)
                            .frame(width: 118, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selection == theme ? Color.accentColor : Color.primary.opacity(0.12),
                                                  lineWidth: selection == theme ? 2.5 : 1)
                            }
                        Text(name).font(.callout)
                            .foregroundStyle(selection == theme ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// Accent swatches, "auto" (from the artwork) first and any colour last.
private struct AccentPicker: View {
    @Binding var selection: String

    private var isCustom: Bool { !AppearanceSettings.accents.contains(selection.lowercased()) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceSettings.accents, id: \.self) { name in
                Button { selection = name } label: {
                    swatch(name == "auto" ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                                          : AnyShapeStyle(Color(tint: name)),
                           selected: selection.lowercased() == name)
                }
                .buttonStyle(.plain)
                .help(name == "auto" ? "From the artwork" : name.capitalized)
            }
            Button(action: pickColour) {
                ZStack {
                    swatch(isCustom ? AnyShapeStyle(Color(tint: selection)) : AnyShapeStyle(Color.primary.opacity(0.08)), selected: isCustom)
                    if !isCustom {
                        Image(systemName: "eyedropper").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isCustom ? "\(selection). Click to pick another colour." : "Pick any colour")
        }
    }

    /// Any colour, from the system colour panel. Each change is saved as `#RRGGBB`.
    private func pickColour() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if let c = RGBA.parse(isCustom ? selection : "#FF8800") {
            panel.color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
        ColourPanelRelay.shared.onChange = { colour in
            if let c = colour.usingColorSpace(.sRGB) {
                selection = RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent).hex
            }
        }
        panel.setTarget(ColourPanelRelay.shared)
        panel.setAction(#selector(ColourPanelRelay.changed(_:)))
        panel.orderFront(nil)
    }

    private func swatch(_ fill: AnyShapeStyle, selected: Bool) -> some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            if selected { Circle().stroke(Color.primary, lineWidth: 2).padding(-3) }
        }
        .frame(width: 16, height: 16)
        .padding(3)
        .contentShape(Rectangle())
    }
}

/// Hands the colour panel's changes to whichever picker opened it last.
@MainActor
final class ColourPanelRelay: NSObject {
    static let shared = ColourPanelRelay()
    var onChange: ((NSColor) -> Void)?

    @objc func changed(_ sender: NSColorPanel) { onChange?(sender.color) }
}

/// The closed and the open island with the current look: theme, glass level, accent, size,
/// wings, text and playing indicator.
struct IslandPreview: View {
    let settings: IsletSettings
    @ViewState private var width: CGFloat = 500

    var body: some View {
        // Both drawings keep one scale whatever the size, so a bigger island looks bigger.
        let open = min(0.42, (width - 24) / IsletSettings.expandedWidthRange.upperBound)
        let closed = min(0.62, (width - 24) / (IslandSketch.notch.width + 2 * IsletSettings.wingWidthRange.upperBound))
        VStack(spacing: 8) {
            scene("Closed", IslandSketch(settings: settings, theme: settings.theme, open: false, scale: closed),
                  height: IslandSketch.notch.height * closed + 24)
            scene("Open", IslandSketch(settings: settings, theme: settings.theme, open: true, scale: open),
                  height: settings.expandedSize.height * open + 20)
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in width = w }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement()
        .accessibilityLabel("Preview of the island")
    }

    private func scene(_ label: String, _ sketch: IslandSketch, height: CGFloat) -> some View {
        sketch
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
    }
}

/// A drawing of the island for Settings: the menu bar with the notch, and the island in it,
/// closed or open. Not the real island: cheap, static, and drawable in snapshots.
struct IslandSketch: View {
    let settings: IsletSettings
    var theme: IslandTheme
    var open: Bool
    /// Sketch points per island point.
    var scale: CGFloat
    /// Real text and the playing indicator; off for the small theme pictures.
    var detailed = true

    /// The notch of a 14-inch MacBook Pro.
    static let notch = CGSize(width: 185, height: 32)
    static let artwork = [Color(red: 1.0, green: 0.62, blue: 0.32), Color(red: 0.93, green: 0.3, blue: 0.48)]

    private var accent: Color { settings.accentColor == "auto" ? Self.artwork[0] : Color(tint: settings.accentColor) }

    private var indicatorTint: Color {
        switch settings.visualiserColour {
        case .artwork: return Self.artwork[0]
        case .accent: return settings.accentColor == "auto" ? .accentColor : Color(tint: settings.accentColor)
        case .white: return .white
        }
    }

    var body: some View {
        let row = Self.notch.height * scale
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: row)
            if open { openIsland(row: row) } else { closedIsland(row: row) }
        }
    }

    private func closedIsland(row: CGFloat) -> some View {
        let wing = settings.effectiveWingWidth * scale
        let width = Self.notch.width * scale + wing * 2
        return IslandShape(topRadius: 4 * scale, bottomRadius: 10 * scale)
            .fill(Color.black)
            .frame(width: width, height: row)
            .overlay(alignment: .leading) {
                artworkTile(size: row * 0.62).padding(.leading, max(4, wing / 2 - row * 0.31) + 4 * scale)
            }
            .overlay(alignment: .trailing) {
                if settings.visualiserStyle != .off {
                    IndicatorSketch(style: settings.visualiserStyle, tint: indicatorTint, height: row * 0.5)
                        .padding(.trailing, max(4, wing / 2 - row * 0.3) + 4 * scale)
                }
            }
    }

    private func openIsland(row: CGFloat) -> some View {
        let size = settings.expandedSize
        let w = size.width * scale, h = size.height * scale
        let shape = IslandShape(topRadius: 6 * scale, bottomRadius: 30 * scale)
        let design: Font.Design = settings.roundedFont ? .rounded : .default
        return ZStack(alignment: .topLeading) {
            surface(shape: shape, row: row, height: h)
            HStack(alignment: .center, spacing: max(4, 12 * scale)) {
                artworkTile(size: min(h - row - 10, 64 * scale))
                if detailed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evening walk").font(.system(size: 10, weight: .semibold, design: design)).foregroundStyle(.white)
                        Text("Islet radio").font(.system(size: 9, design: design)).foregroundStyle(.white.opacity(0.6))
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in Capsule().fill(accent).frame(width: g.size.width * 0.42) }
                            }
                            .padding(.top, 3)
                    }
                    .lineLimit(1)
                    if settings.visualiserStyle != .off {
                        IndicatorSketch(style: settings.visualiserStyle, tint: indicatorTint, height: 10)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: w * 0.32, height: 3)
                        Capsule().fill(Color.white.opacity(0.4)).frame(width: w * 0.22, height: 3)
                        Capsule().fill(accent).frame(width: w * 0.4, height: 2.5).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, max(8, 26 * scale))
            .frame(width: w, height: h - row)
            .offset(y: row)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder private func surface(shape: IslandShape, row: CGFloat, height: CGFloat) -> some View {
        switch theme {
        case .black:
            shape.fill(Color.black)
        case .graphite:
            shape.fill(Color(white: 0.105)).overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 1))
        case .glass:
            // Black over the notch row, melting into a tinted, see-through body; how soon follows the level.
            let top = min(0.95, row / max(height, 1))
            let melt = top + (1 - top) * (1 - settings.glassLevel) * 0.85
            shape.fill(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: top),
                .init(color: .black.opacity(0.92), location: min(1, max(top, melt - 0.08))),
                .init(color: .black.opacity(0.42), location: min(1, melt + 0.12)),
                .init(color: .black.opacity(0.36), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.75))
        }
    }

    private func artworkTile(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: Self.artwork, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

/// The playing indicator at rest, in the chosen look.
struct IndicatorSketch: View {
    let style: VisualiserStyle
    let tint: Color
    var height: CGFloat = 14

    var body: some View {
        let heights: [CGFloat] = style == .slim ? [0.55, 0.9, 0.45, 0.75, 0.6, 0.8] : [0.45, 0.8, 0.35, 0.65]
        HStack(alignment: style == .dots ? .center : .bottom, spacing: height * (style == .slim ? 0.1 : style == .dots ? 0.22 : 0.15)) {
            if style == .dots {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(tint).frame(width: height * 0.3, height: height * 0.3).offset(y: -height * [0.2, 0.38, 0.12][i])
                }
            } else if style != .off {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: height * 0.09).fill(tint)
                        .frame(width: height * (style == .slim ? 0.12 : 0.2), height: height * h)
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { SettingsHero(page: .shortcuts) }
            Section {
                SettingsRow(title: "Open or close the island", detail: "Opens it pinned, so it stays open until you press the keys again.") {
                    ShortcutField(text: $model.settings.hotkey, standard: IsletSettings().hotkey)
                }
                .settingsAnchor("shortcuts.island")
                SettingsRow(title: "Open the Ask box", detail: "Ready to type a question. Press the keys again to close it.") {
                    ShortcutField(text: $model.settings.askHotkey, standard: IsletSettings().askHotkey)
                }
                .settingsAnchor("shortcuts.ask")
            } footer: {
                SettingsFooter("Click a shortcut, then press the keys you want, with at least one of ⌃, ⌥ or ⌘. Delete turns a shortcut off and Esc keeps the one you had.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apps

/// Per-app customisation: colour, visibility and notifications.
struct AppRulesSettings: View {
    @Bindable var model: AppModel
    @ViewState private var added: String?

    private var runningApps: [NSRunningApplication] {
        let existing = Set(model.settings.appRules.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !existing.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    SettingsHero(page: .apps) { addMenu }
                }
                if model.settings.appRules.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "app.dashed").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                            Text("No apps yet").font(.headline)
                            Text("Add an app to change how the island treats it.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                } else {
                    Section {
                        ForEach($model.settings.appRules) { $rule in
                            AppRuleRow(rule: $rule) {
                                model.settings.appRules.removeAll { $0.bundleID == rule.bundleID }
                            }
                            .id(rule.bundleID)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            // A newly added app goes to the end of the list; bring it into view.
            .onChange(of: added) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var addMenu: some View {
        Menu("Add App") {
            ForEach(runningApps, id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier!) { add(app.bundleIdentifier!) }
            }
            if !runningApps.isEmpty { Divider() }
            Button("Other App…", action: chooseApp)
        }
        .fixedSize()
        .settingsAnchor("apps.add")
    }

    private func add(_ bundleID: String) {
        guard !model.settings.appRules.contains(where: { $0.bundleID == bundleID }) else { return }
        model.settings.appRules.append(AppRule(bundleID: bundleID))
        added = bundleID
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }
}

struct AppRuleRow: View {
    @Binding var rule: AppRule
    var onDelete: () -> Void

    static let tints = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "teal", "gray"]

    private var name: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? rule.bundleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppIconView(bundleID: rule.bundleID, size: 24)
                Text(name).font(.body.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                // Menus draw their icons in one colour, so the chosen colour shows beside the menu.
                Circle()
                    .fill(rule.tint.map { Color(tint: $0) } ?? Color.clear)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(rule.tint == nil ? 0.25 : 0.12), lineWidth: 1))
                    .frame(width: 12, height: 12)
                Picker("Colour", selection: Binding(get: { rule.tint ?? "" }, set: { rule.tint = $0.isEmpty ? nil : $0 })) {
                    Text("Its own colour").tag("")
                    Divider()
                    ForEach(Self.tints, id: \.self) { tint in
                        Text(tint == "gray" ? "Grey" : tint.capitalized).tag(tint)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove \(name)")
            }
            HStack(spacing: 16) {
                Toggle("Hide the island in front", isOn: Binding(get: { rule.hideIsland ?? false }, set: { rule.hideIsland = $0 ? true : nil }))
                Toggle("Keep it in fullscreen", isOn: Binding(get: { rule.showInFullscreen ?? false }, set: { rule.showInFullscreen = $0 ? true : nil }))
                Toggle("Mute notifications", isOn: Binding(get: { rule.muteNotifications ?? false }, set: { rule.muteNotifications = $0 ? true : nil }))
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(.leading, 34)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Capsule().fill(Color.black).frame(width: 46, height: 16).offset(y: -18)
                    }
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    Text("Islet").font(.title.bold())
                    Text("Version \(AppModel.version)").foregroundStyle(.secondary).textSelection(.enabled)
                        .settingsAnchor("about.version")
                    Text("An open-source Dynamic Island for the Mac notch.")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } footer: {
                Text("MIT licence. No accounts, no licence server, no tracking.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
    }
}
