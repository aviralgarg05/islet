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
                } else {
                    Toggle(isOn: $model.settings.peekOnHover) {
                        Text("Peek at what's playing")
                        Text("While the pointer rests on the notch, the island shows the song without opening.")
                    }
                    .settingsAnchor("general.peekOnHover")
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
                Picker(selection: $model.settings.notchlessStyle) {
                    Text("Floating pill").tag(NotchlessStyle.pill)
                    Text("Notch shape").tag(NotchlessStyle.notch)
                    Text("Only on hover").tag(NotchlessStyle.hover)
                    Text("Don't show").tag(NotchlessStyle.hidden)
                } label: {
                    Text("On displays without a notch")
                    Text(Self.notchlessDetail(model.settings.notchlessStyle))
                }
                .settingsAnchor("general.nonNotch")
                Picker(selection: $model.settings.fullscreenBehaviour) {
                    Text("Keep showing").tag(FullscreenBehaviour.show)
                    Text("Hide music only").tag(FullscreenBehaviour.hideMusic)
                    Text("Hide everything").tag(FullscreenBehaviour.hide)
                } label: {
                    Text("In full screen")
                    Text(Self.fullscreenDetail(model.settings.fullscreenBehaviour))
                }
                .settingsAnchor("general.fullscreen")
                Toggle(isOn: $model.settings.hideFromScreenCapture) {
                    Text("Hide from screenshots")
                    Text("Some screen-sharing and recording apps still show it. The island's glass turns solid while this is on.")
                }
                .settingsAnchor("general.capture")
            }
            GestureSettingsSection(model: model)
            Section("Island pages") {
                Toggle(isOn: $model.settings.systemStatsEnabled) {
                    Text("System stats")
                    Text("CPU and memory on the System page, measured only while it's open.")
                }
                .settingsAnchor("general.stats")
                IslandPagesEditor(model: model)
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralSettings {
    static func notchlessDetail(_ style: NotchlessStyle) -> String {
        switch style {
        case .pill: return "A pill floating in the menu bar, clear of the screen's edge."
        case .notch: return "A notch drawn at the top edge, like a MacBook's."
        case .hover: return "Nothing until the pointer reaches the top edge, then the pill."
        case .hidden: return "The island shows only on a display with a notch."
        }
    }

    static func fullscreenDetail(_ behaviour: FullscreenBehaviour) -> String {
        switch behaviour {
        case .show: return "The island stays over full screen apps."
        case .hideMusic: return "What\u{2019}s playing goes; timers, activities and HUDs stay. On the Apps page, pick apps that keep everything."
        case .hide: return "Only HUDs and urgent alerts show. On the Apps page, pick apps that keep the island."
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Bindable var model: AppModel
    @Environment(\.openSettingsPage) private var openPage
    @ViewState private var confirmingReset = false

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
                    Button("Show a sample in the island") { AppActions.previewAppearance(model) }
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
                        Text("Only the part over the notch is black, and the island is glass from the bottom of the menu bar. Towards Black, the black melts further down.")
                    }
                    Toggle(isOn: $model.settings.glassOnNotchless) {
                        Text("Glass on displays without a notch")
                        Text("The closed island there is glass too. Beside a notch it stays black to match it.")
                    }
                    .settingsAnchor("appearance.glassNotchless")
                }
                Toggle(isOn: $model.settings.outline) {
                    Text("Subtle outline")
                    Text("A faint edge so the island shows on a dark wallpaper. Always on with Increase Contrast.")
                }
                .settingsAnchor("appearance.outline")
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
                Picker("Width", selection: $model.settings.closedLayout) {
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
                NotchFitRows(model: model)
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
                if s.animationStyle != .off {
                    Picker("Animation speed", selection: $model.settings.animationSpeed) {
                        Text("Relaxed").tag(AnimationSpeed.relaxed)
                        Text("Normal").tag(AnimationSpeed.normal)
                        Text("Quick").tag(AnimationSpeed.quick)
                    }
                    .pickerStyle(.segmented)
                    .settingsAnchor("appearance.speed")
                }
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
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("Square").font(.caption).foregroundStyle(.secondary)
                        Slider(value: artworkCorners, in: IsletSettings.artworkCornerRange) { Text("Artwork corners") }
                            .labelsHidden()
                            .frame(minWidth: 120, maxWidth: 200)
                        Text("Round").font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Artwork corners")
                    Text("Beside the notch, in a new song's peek and in the open island.")
                }
                .settingsAnchor("appearance.artworkCorners")
                LabeledContent("Playing indicator") {
                    HStack(spacing: 10) {
                        Text(Self.indicatorSummary(s)).foregroundStyle(.secondary)
                        Button("Change…") { openPage(.nowPlaying, "nowPlaying.indicator") }
                    }
                }
                .settingsAnchor("appearance.indicator")
            }
            Section {
                LabeledContent {
                    Button("Reset appearance…") { confirmingReset = true }
                        .disabled(s.resettingAppearance() == s)
                } label: {
                    Text("Back to the original look")
                    Text("Theme, colours, sizes, motion and the music's look. Fit to the notch stays as it is.")
                }
                .settingsAnchor("appearance.reset")
                .confirmationDialog("Reset the island's appearance?", isPresented: $confirmingReset) {
                    Button("Reset appearance", role: .destructive) {
                        model.settings = model.settings.resettingAppearance()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Everything on this page goes back to how Islet came, and so do the playing indicator, the music colour and the song progress ring on Now Playing. Fit to the notch stays as it is.")
                }
            } header: {
                Text("Reset")
            }
        }
        .formStyle(.grouped)
    }

    static func indicatorSummary(_ s: IsletSettings) -> String {
        guard s.visualiserStyle != .off else { return "Off" }
        // A sticker keeps its own colours.
        if s.visualiserStyle == .gif { return "Sticker" }
        let style = IndicatorStylePicker.name(s.visualiserStyle)
        switch s.musicColour {
        case .artwork: return "\(style), artwork colour"
        // With the accent on "auto" the accent is the artwork's colour.
        case .accent: return s.accentColor == "auto" ? "\(style), artwork colour" : "\(style), accent colour"
        case .white: return "\(style), white"
        }
    }

    /// Half-point steps, so a hand-dragged value saves as a tidy number.
    private var artworkCorners: Binding<Double> {
        Binding(get: { model.settings.artworkCornerRadius },
                set: { model.settings.artworkCornerRadius = ($0 * 2).rounded() / 2 })
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
                            .modifier(TileOutline(selected: selection == theme, cornerRadius: 8, hairline: 0.12))
                            .accessibilityHidden(true)
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
    @Environment(\.colorSchemeContrast) private var contrast

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
                .accessibilityLabel(name == "auto" ? "From the artwork" : name == "gray" ? "Grey" : name.capitalized)
                .accessibilityAddTraits(selection.lowercased() == name ? .isSelected : [])
            }
            Button(action: pickColour) {
                ZStack {
                    swatch(isCustom ? AnyShapeStyle(Color(tint: selection)) : AnyShapeStyle(Color.primary.opacity(0.08)), selected: isCustom)
                    if !isCustom {
                        Image(systemName: "eyedropper").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                // A picked colour can look like a preset; the dropper says this one is your own.
                .overlay(alignment: .bottomTrailing) {
                    if isCustom {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 11, height: 11)
                            .background(Circle().fill(Color.black.opacity(0.65)))
                            .offset(x: 3, y: 3)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isCustom ? "\(selection). Click to pick another colour." : "Pick any colour")
            .accessibilityLabel("Pick any colour")
            .accessibilityValue(isCustom ? selection : "")
            .accessibilityAddTraits(isCustom ? .isSelected : [])
        }
    }

    /// Any colour, from the system colour panel. Each change is saved as `#RRGGBB`.
    private func pickColour() {
        ColourPanelRelay.pick(starting: isCustom ? selection : nil) { selection = $0 }
    }

    private func swatch(_ fill: AnyShapeStyle, selected: Bool) -> some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.15), lineWidth: contrast == .increased ? 1 : 0.5)
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

    /// Open the system colour panel at `hex` (orange when nil); each change comes back as
    /// `#RRGGBB`. The accent and the app colours both pick this way.
    static func pick(starting hex: String?, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if let c = RGBA.parse(hex ?? "#FF8800") {
            panel.color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
        shared.onChange = { colour in
            if let c = colour.usingColorSpace(.sRGB) {
                onChange(RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent).hex)
            }
        }
        panel.setTarget(shared)
        panel.setAction(#selector(ColourPanelRelay.changed(_:)))
        panel.orderFront(nil)
    }
}

/// The closed and the open island with the current look: theme, glass level, accent, size,
/// wings, notch fit, artwork corners, text and playing indicator. The closed island moves as it
/// does beside the notch, and its button pauses and plays the sample song, so the pause can be
/// judged without music playing.
struct IslandPreview: View {
    let settings: IsletSettings
    /// The Now Playing page shows the closed island alone.
    var showsOpen = true
    @ViewState private var width: CGFloat = 500
    @ViewState private var playing = true

    var body: some View {
        // Both drawings keep one scale whatever the size, so a bigger island looks bigger. The
        // closed one has room for the widest wings and notch fit, so it never runs off the edge.
        let open = min(0.42, (width - 24) / IsletSettings.expandedWidthRange.upperBound)
        let widest = IslandSketch.notch.width + IsletSettings.notchWidthAdjustRange.upperBound + 2 * IsletSettings.wingWidthRange.upperBound
        let closed = min(showsOpen ? 0.62 : 1, (width - 24) / widest)
        VStack(spacing: 8) {
            scene("Closed", IslandSketch(settings: settings, theme: settings.theme, open: false, scale: closed, playing: playing),
                  height: IslandSketch.notch.height * closed + 24)
                .overlay(alignment: .bottomTrailing) {
                    PreviewPlayButton(playing: $playing).padding(6)
                }
            if showsOpen {
                scene("Open", IslandSketch(settings: settings, theme: settings.theme, open: true, scale: open),
                      height: settings.expandedSize.height * open + 20)
            }
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
    }

    private func scene(_ label: String, _ sketch: IslandSketch, height: CGFloat) -> some View {
        sketch
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
            .accessibilityElement()
            .accessibilityLabel("Preview of the \(label.lowercased()) island")
    }
}

/// Pauses and plays the preview's sample song. The glyph morphs, as the island's own does.
private struct PreviewPlayButton: View {
    @Binding var playing: Bool

    var body: some View {
        Button { playing.toggle() } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: playing)
        .help(playing ? "Pause the sample song" : "Play the sample song")
        .accessibilityLabel(playing ? "Pause the sample song" : "Play the sample song")
    }
}

/// A drawing of the island for Settings: the menu bar with the notch, and the island in it,
/// closed or open. Not the real island: cheap, and drawable in snapshots. The closed island's
/// playing indicator is the real one, so it moves in the Settings window.
struct IslandSketch: View {
    let settings: IsletSettings
    var theme: IslandTheme
    var open: Bool
    /// Sketch points per island point.
    var scale: CGFloat
    /// Real text and the playing indicator; off for the small theme pictures.
    var detailed = true
    /// Whether the sample song plays (the closed island).
    var playing = true
    @Environment(\.stickerLibrary) private var stickers

    /// The notch of a 14-inch MacBook Pro.
    static let notch = CGSize(width: 185, height: 32)
    static let artwork = [Color(red: 1.0, green: 0.62, blue: 0.32), Color(red: 0.93, green: 0.3, blue: 0.48)]

    /// The music colour on the sample song. "Accent" on "auto" is the artwork's.
    static func indicatorTint(_ s: IsletSettings) -> Color {
        switch s.musicColour {
        case .artwork: return artwork[0]
        case .accent: return s.accentColor == "auto" ? artwork[0] : Color(tint: s.accentColor)
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
        .environment(\.islandReduceMotion, settings.reduceMotion || settings.animationStyle == .off)
    }

    /// The closed island with the sample song, sized like the real one: the notch with its fit,
    /// the wings, 20 pt artwork with the chosen corners, and the indicator.
    private func closedIsland(row: CGFloat) -> some View {
        let notch = NotchGeometry.metrics(for: Self.screen, adjust: settings.notchAdjust).notch
        let wing = settings.effectiveWingWidth * scale
        let width = notch.width * scale + wing * 2
        let height = notch.height * scale
        let art = 20 * scale
        let inset = Wings<EmptyView, EmptyView>.inset(for: settings.effectiveWingWidth) * scale
        let shape = IslandShape(topRadius: 6 * scale, bottomRadius: min(12, notch.height / 2.4) * scale)
        let vinylDot = max(5, DotNSView.diameter * scale)
        return shape
            .fill(Color.black)
            .overlay { if settings.outline { IslandEdge(shape: shape).stroke(Color.white.opacity(0.18), lineWidth: 0.5) } }
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                let vinyl = settings.visualiserStyle == .vinyl
                let corner = vinyl ? art / 2 : CGFloat(settings.artworkCorner(size: 20, standard: 5)) * scale
                Group {
                    if vinyl {
                        VinylDisc(image: Self.artworkImage, size: art, tint: Self.indicatorTint(settings), playing: playing)
                    } else {
                        artworkTile(size: art, corner: corner)
                    }
                }
                    .overlay {
                        if settings.songProgressRing {
                            let pad = (ClosedArtwork.ringGap + ClosedArtwork.ringLine) * scale
                            let line = ClosedArtwork.ringLine * scale
                            ZStack {
                                SongRingShape(corner: corner + pad, inset: line / 2)
                                    .stroke(Color.white.opacity(SongRingNSView.trackOpacity), lineWidth: line)
                                SongRingShape(corner: corner + pad, inset: line / 2).trim(from: 0, to: 0.42)
                                    .stroke(Self.indicatorTint(settings), style: StrokeStyle(lineWidth: line, lineCap: .round))
                            }
                            .frame(width: art + 2 * pad, height: art + 2 * pad)
                        }
                    }
                    .opacity(playing ? 1 : PausedLook.artworkOpacity)
                    .animation(.easeInOut(duration: PausedLook.fade), value: playing)
                    .padding(.leading, inset)
            }
            .overlay(alignment: .trailing) {
                if settings.visualiserStyle == .gif, let stickers {
                    StickerSketch(library: stickers, settings: settings, scale: scale, playing: playing)
                        .padding(.trailing, inset)
                } else if settings.visualiserStyle == .vinyl {
                    // The record's dot, kept big enough to see at the drawing's size.
                    Circle().fill(Self.indicatorTint(settings))
                        .frame(width: vinylDot, height: vinylDot)
                        .scaleEffect(playing ? 1 : 0.8)
                        .opacity(playing ? 1 : Double(PausedLook.indicatorOpacity))
                        .frame(width: 14 * scale)
                        .padding(.trailing, inset)
                } else {
                    PlayingIndicator(tint: Self.indicatorTint(settings), playing: playing, height: 14 * scale)
                        .environment(\.visualiserStyle, settings.visualiserStyle)
                        .padding(.trailing, inset)
                }
            }
    }

    /// The sample song's artwork as a picture, for the Vinyl look's turning record.
    static let artworkImage: CGImage? = {
        let side = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: artwork.map { NSColor($0).cgColor } as CFArray, locations: [0, 1])
        else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        return ctx.makeImage()
    }()

    /// The notched display the sketch is drawn for.
    private static let screen = ScreenDescriptor(id: 0, name: "Sketch", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                 safeAreaTop: notch.height, auxiliaryLeftWidth: (1512 - notch.width) / 2,
                                                 auxiliaryRightWidth: (1512 - notch.width) / 2)

    private func openIsland(row: CGFloat) -> some View {
        let size = settings.expandedSize
        let w = size.width * scale, h = size.height * scale
        // The Glass theme's stem-and-body shape: a notch-wide stem, then the body below the row.
        let stemmed = theme == .glass
        let notch = NotchGeometry.metrics(for: Self.screen, adjust: settings.notchAdjust).notch
        let shape = stemmed
            ? IslandShape(topRadius: IslandLayout.stemFlare * scale, bottomRadius: 30 * scale, stemWidth: notch.width * scale, stemHeight: row)
            : IslandShape(topRadius: 6 * scale, bottomRadius: 30 * scale)
        let design: Font.Design = settings.roundedFont ? .rounded : .default
        let art = min(h - row - 10, 64 * scale)
        return ZStack(alignment: .topLeading) {
            surface(shape: shape, row: row, height: h)
            if settings.outline { IslandEdge(shape: shape).stroke(Color.white.opacity(0.18), lineWidth: 0.5) }
            HStack(alignment: .center, spacing: max(4, 12 * scale)) {
                // The open island's 72 pt artwork, at this size.
                artworkTile(size: art, corner: CGFloat(settings.artworkCorner(size: 72, standard: Radius.m)) * art / 72)
                if detailed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evening walk").font(.system(size: 10, weight: .semibold, design: design)).foregroundStyle(.white)
                        Text("Islet radio").font(.system(size: 9, design: design)).foregroundStyle(.white.opacity(0.6))
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in Capsule().fill(Self.indicatorTint(settings)).frame(width: g.size.width * 0.42) }
                            }
                            .padding(.top, 3)
                    }
                    .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: w * 0.32, height: 3)
                        Capsule().fill(Color.white.opacity(0.4)).frame(width: w * 0.22, height: 3)
                        Capsule().fill(Self.indicatorTint(settings)).frame(width: w * 0.4, height: 2.5).padding(.top, 2)
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
            // Black in the menu bar row, as every theme is, then graphite below it.
            let top = min(0.95, row / max(height, 1))
            shape.fill(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: top),
                .init(color: Color(white: 0.105), location: min(1, top + 12 * scale / max(height, 1))),
            ], startPoint: .top, endPoint: .bottom))
            .overlay(IslandEdge(shape: shape).stroke(Color.white.opacity(0.08), lineWidth: 1))
        case .glass:
            // Black in the stem over the notch, melting into a tinted, see-through glass below
            // the menu bar: a short melt at the Glass end, down to half the body at the Black end,
            // as the island does (`GlassMelt`).
            let top = min(0.95, row / max(height, 1))
            let melt = GlassMelt.depth(body: (height - row) / max(scale, 0.01), level: settings.glassLevel) * scale
            shape.fill(Color.black.opacity(GlassMelt.smoke(level: settings.glassLevel)))
                .overlay(shape.fill(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: top),
                    .init(color: .black.opacity(0), location: min(1, top + melt / max(height, 1))),
                ], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)))
            // Its edge is the outline's, drawn only when Subtle outline is on.
        }
    }

    private func artworkTile(size: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: Self.artwork, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

/// Settings → Appearance → Closed island: nudges the notch's width and height so the closed
/// island lines up with the hardware. Folded away, since most Macs need nothing here; it opens
/// when a value is set or a search leads to it. While a value changes, a sample activity holds
/// the closed island on screen so its edges can be matched by eye.
private struct NotchFitRows: View {
    @Bindable var model: AppModel
    @ViewState private var expanded = false
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.settingsHighlight) private var highlight

    private var adjusted: Bool { model.settings.notchAdjust != .zero }

    var body: some View {
        // One row that folds the sliders away, with its title in line with the rows above.
        LabeledContent {
            HStack(spacing: 6) {
                Text(adjusted ? Self.summary(model.settings) : "No change").foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        } label: {
            Text("Fit to the notch")
            Text("If the island's edges don't meet the notch's, move them here.")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        // Tab reaches it with Full Keyboard Access, and Space or Return opens it, as a click does.
        .focusable(interactions: .activate)
        .onKeyPress(keys: [.space, .return]) { _ in
            toggle()
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Hides the adjustments" : "Shows the adjustments")
        .accessibilityAction { toggle() }
        .settingsAnchor("appearance.fitNotch")
        .onAppear {
            if snapshotMode || adjusted || highlight?.hasPrefix("appearance.fit") == true { expanded = true }
        }
        if expanded {
            SettingsSlider(title: "Notch width", value: binding(\.notchWidthAdjust), range: IsletSettings.notchWidthAdjustRange,
                           step: 1, format: Self.signedPoints)
            SettingsSlider(title: "Notch height", value: binding(\.notchHeightAdjust), range: IsletSettings.notchHeightAdjustRange,
                           step: 1, format: Self.signedPoints)
            HStack {
                Text("Something shows beside the notch while you change these.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    model.settings.notchWidthAdjust = 0
                    model.settings.notchHeightAdjust = 0
                }
                .controlSize(.small)
                .disabled(!adjusted)
            }
        }
    }

    private func toggle() { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }

    private func binding(_ key: WritableKeyPath<IsletSettings, Double>) -> Binding<Double> {
        Binding(get: { model.settings[keyPath: key] }, set: { value in
            guard value != model.settings[keyPath: key] else { return }
            model.settings[keyPath: key] = value
            AppActions.previewNotchFit(model)
        })
    }

    static func signedPoints(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n == 0 ? "0 pt" : n > 0 ? "+\(n) pt" : "\u{2212}\(-n) pt"
    }

    static func summary(_ s: IsletSettings) -> String {
        var parts: [String] = []
        if s.notchWidthAdjust != 0 { parts.append("width \(signedPoints(s.notchWidthAdjust))") }
        if s.notchHeightAdjust != 0 { parts.append("height \(signedPoints(s.notchHeightAdjust))") }
        return parts.joined(separator: ", ").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { SettingsHero(page: .shortcuts) }
            Section {
                SettingsRow(title: "Open or close the island", detail: "Opens it pinned, so it stays open until you press the keys again.") {
                    ShortcutField(name: "Open or close the island", text: $model.settings.hotkey, standard: IsletSettings().hotkey,
                                  other: (model.settings.askHotkey, "open the Ask box"))
                }
                .settingsAnchor("shortcuts.island")
                SettingsRow(title: "Open the Ask box", detail: "Ready to type a question. Press the keys again to close it.") {
                    ShortcutField(name: "Open the Ask box", text: $model.settings.askHotkey, standard: IsletSettings().askHotkey,
                                  other: (model.settings.hotkey, "open the island"))
                }
                .settingsAnchor("shortcuts.ask")
            } footer: {
                SettingsFooter("Click a shortcut, then press the keys you want, with at least one of ⌃, ⌥ or ⌘. Delete turns a shortcut off, and Esc or Tab keeps the one you had.")
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

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    SettingsHero(page: .apps) { addMenu }
                } footer: {
                    // With muted sources below, an empty card would say the page has nothing on it.
                    if model.settings.appRules.isEmpty && !model.settings.mutedSources.isEmpty {
                        SettingsFooter("No app rules yet. Use Add app to give one a colour or a priority.")
                    }
                }
                if model.settings.appRules.isEmpty {
                    if model.settings.mutedSources.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("No apps yet", systemImage: SettingsPage.apps.symbol)
                            } description: {
                                Text("Use Add app to give one a colour or a priority, hide the island for it, or mute it.")
                            }
                            .padding(.vertical, 12)
                        }
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
                // What "Mute" in the island's right-click menu silenced, so it can be heard again.
                if !model.settings.mutedSources.isEmpty {
                    Section("Muted") {
                        Text("Muted from the island's right-click menu. Unmute one to see its activities again.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .settingsAnchor("apps.muted")
                        ForEach(model.settings.mutedSources, id: \.self) { source in
                            HStack {
                                Text(AppModel.mutedName(source)).lineLimit(1)
                                Spacer(minLength: 8)
                                Button("Unmute") { model.unmute(source: source) }
                            }
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
        AddAppMenu(existing: Set(model.settings.appRules.map(\.bundleID)), add: add)
            .settingsAnchor("apps.add")
    }

    private func add(_ bundleID: String) {
        guard !model.settings.appRules.contains(where: { $0.bundleID == bundleID }) else { return }
        model.settings.appRules.append(AppRule(bundleID: bundleID))
        added = bundleID
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
                // Two columns of fixed width, so the pickers and the colour dot line up from row to
                // row: the priority ends at one edge, and the colour, with its dot, starts at the next.
                priorityPicker
                HStack(spacing: 2) {
                    // Menus draw their icons in one colour, so the chosen colour shows beside the menu.
                    // Clicking it picks any colour, as the accent's custom swatch does.
                    Button(action: pickColour) {
                        Circle()
                            .fill(rule.tint.map { Color(tint: $0) } ?? Color.clear)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(rule.tint == nil ? 0.25 : 0.12), lineWidth: 1))
                            .frame(width: 12, height: 12)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Pick any colour")
                    .accessibilityLabel("Pick any colour for \(name)")
                    Picker("Colour", selection: tintChoice) {
                        Text("App\u{2019}s own colour").tag("")
                        Divider()
                        ForEach(Self.tints, id: \.self) { tint in
                            Text(tint == "gray" ? "Grey" : tint.capitalized).tag(tint)
                        }
                        Divider()
                        if let custom = customTint {
                            Text("Custom").tag(custom)
                        }
                        Text("Other colour…").tag(Self.otherColour)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .frame(width: Self.colourWidth, alignment: .leading)
                .padding(.leading, 8)
                Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove \(name)")
            }
            // One line when the window is wide enough, else one under another, never wrapped.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { options }
                VStack(alignment: .leading, spacing: 6) { options }
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(.leading, 34)
        }
        .padding(.vertical, 3)
    }

    /// The menu item that opens the colour panel instead of choosing a colour.
    private static let otherColour = "other"

    /// A colour picked from the panel (a hex value), which the menu shows as "Custom".
    private var customTint: String? {
        guard let t = rule.tint, !Self.tints.contains(t.lowercased()) else { return nil }
        return t
    }

    private var tintChoice: Binding<String> {
        Binding(get: { rule.tint ?? "" }, set: { choice in
            if choice == Self.otherColour {
                pickColour()
            } else {
                rule.tint = choice.isEmpty ? nil : choice
            }
        })
    }

    private func pickColour() {
        ColourPanelRelay.pick(starting: customTint) { rule.tint = $0 }
    }

    private static let priorityWidth: CGFloat = 150
    private static let colourWidth: CGFloat = 156

    @ViewBuilder private var options: some View {
        Toggle("Hide the island while it\u{2019}s in front", isOn: Binding(get: { rule.hideIsland ?? false }, set: { rule.hideIsland = $0 ? true : nil }))
            .fixedSize()
        Toggle("Keep the island in full screen", isOn: Binding(get: { rule.showInFullscreen ?? false }, set: { rule.showInFullscreen = $0 ? true : nil }))
            .fixedSize()
        Toggle("Mute notifications and calls", isOn: Binding(get: { rule.muteNotifications ?? false }, set: { rule.muteNotifications = $0 ? true : nil }))
            .fixedSize()
    }

    /// Where the app's activities and notifications rank when several want the island.
    private var priorityPicker: some View {
        Picker("Priority", selection: Binding(get: { rule.priority }, set: { rule.priority = $0 })) {
            Text("Usual priority").tag(ActivityPriority?.none)
            Divider()
            Text("Low priority").tag(ActivityPriority?.some(.low))
            Text("Normal priority").tag(ActivityPriority?.some(.normal))
            Text("High priority").tag(ActivityPriority?.some(.high))
            Text("Urgent").tag(ActivityPriority?.some(.critical))
        }
        .labelsHidden()
        .frame(width: Self.priorityWidth, alignment: .trailing)
        .help("How its activities and notifications rank when several want the island. Urgent ones also show over full screen apps.")
    }
}

// MARK: - About

/// Islet's picture: a black capsule on a dusk gradient. On About, and on Islet's own alerts
/// when it runs without its app icon (a build from the command line).
struct IsletTile: View {
    var size: CGFloat

    var body: some View {
        let unit = size / 80
        ZStack {
            RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Capsule().fill(Color.black).frame(width: 46 * unit, height: 16 * unit).offset(y: -18 * unit)
        }
        .frame(width: size, height: size)
    }
}

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    IsletTile(size: 80)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    Text("Islet").font(.title.bold())
                    // Without a build's "-dev" suffix; the full version is in the help and in feedback.
                    Text("Version \(Format.version(AppModel.version))").foregroundStyle(.secondary).textSelection(.enabled)
                        .help("Version \(AppModel.version)")
                        .settingsAnchor("about.version")
                    Text("An open-source Dynamic Island for the Mac notch.")
                        .multilineTextAlignment(.center)
                    // Inside the card, so it centres on the card rather than on the footer's inset.
                    Text("MIT licence. No accounts, no licence server, no tracking.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            Section { FeedbackRow() }
            // The status item can end up behind the notch or in the menu bar's overflow, so
            // Islet can also be quit from here, the island's right-click menu and its More menu.
            Section {
                LabeledContent {
                    Button("Quit Islet") { NSApp.terminate(nil) }
                } label: {
                    Text("Quit")
                    Text("Also in the island's right-click menu and its More menu.")
                }
                .settingsAnchor("about.quit")
            }
        }
        .formStyle(.grouped)
    }
}
