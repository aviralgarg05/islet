import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// The tabs of the Settings window.
enum SettingsPane: Hashable {
    case general, appearance, modules, apps, integrations, ai, permissions, about
}

/// A section of Settings that something else can send the user to (`AppActions.openSettings(_:at:)`).
enum SettingsSection: Hashable {
    /// Integrations → Usage limits.
    case usageLimits

    var pane: SettingsPane {
        switch self {
        case .usageLimits: return .integrations
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsPane) {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsPane.general)
            AppearanceSettings(model: model).tabItem { Label("Appearance", systemImage: "paintbrush") }.tag(SettingsPane.appearance)
            ModulesSettings(model: model).tabItem { Label("Modules", systemImage: "square.grid.2x2") }.tag(SettingsPane.modules)
            AppRulesSettings(model: model).tabItem { Label("Apps", systemImage: "app.badge") }.tag(SettingsPane.apps)
            IntegrationsSettings(model: model).tabItem { Label("Integrations", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(SettingsPane.integrations)
            AISettingsView(model: model).tabItem { Label("AI", systemImage: "sparkles") }.tag(SettingsPane.ai)
            PermissionsSettings(model: model).tabItem { Label("Permissions", systemImage: "hand.raised") }.tag(SettingsPane.permissions)
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsPane.about)
        }
        .frame(width: 620, height: 540)
        .onChange(of: model.settings) { _, _ in model.settingsEdited() }
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Placement") {
                Picker("Show island on", selection: $model.settings.displayMode) {
                    Text("Notched display (or main)").tag(DisplayMode.notchedScreen)
                    Text("Main display").tag(DisplayMode.mainScreen)
                    Text("All displays").tag(DisplayMode.allScreens)
                }
                Toggle("Show on displays without a notch", isOn: $model.settings.showOnNonNotchDisplays)
                Toggle("Hide when an app is fullscreen", isOn: $model.settings.hideInFullscreen)
                Toggle("Hide from screenshots and screen sharing", isOn: $model.settings.hideFromScreenCapture)
            }
            Section("Behaviour") {
                Picker("Open the island", selection: $model.settings.hoverToOpen) {
                    Text("On hover").tag(true)
                    Text("On click").tag(false)
                }
                if model.settings.hoverToOpen {
                    LabeledContent("Hover delay") {
                        Slider(value: $model.settings.openDelay, in: IsletSettings.openDelayRange, step: 0.05) { Text("") }
                        Text(String(format: "%.2fs", model.settings.openDelay)).monospacedDigit().frame(width: 44)
                    }
                }
                LabeledContent("Close delay") {
                    Slider(value: $model.settings.closeDelay, in: IsletSettings.closeDelayRange, step: 0.05) { Text("") }
                    Text(String(format: "%.2fs", model.settings.closeDelay)).monospacedDigit().frame(width: 44)
                }
                LabeledContent("Shortcut to open or close") {
                    TextField("", text: $model.settings.hotkey, prompt: Text(verbatim: "ctrl+option+i"))
                        .labelsHidden()
                        .frame(width: 140)
                    Text(Hotkey.parse(model.settings.hotkey)?.label ?? (model.settings.hotkey.isEmpty ? "Off" : "Invalid"))
                        .foregroundStyle(.secondary).frame(width: 60)
                }
                LaunchAtLoginToggle()
            }
            GestureSettingsSection(model: model)
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettings: View {
    @Bindable var model: AppModel

    private static let accents = ["auto", "white", "blue", "purple", "pink", "red", "orange", "yellow", "green", "teal"]

    var body: some View {
        Form {
            Section("Size") {
                Picker("Island size", selection: $model.settings.sizePreset) {
                    Text("Compact").tag(SizePreset.compact)
                    Text("Standard").tag(SizePreset.standard)
                    Text("Large").tag(SizePreset.large)
                    Text("Custom").tag(SizePreset.custom)
                }
                .pickerStyle(.segmented)
                if model.settings.sizePreset == .custom {
                    LabeledContent("Expanded width") {
                        Slider(value: $model.settings.expandedWidth, in: IsletSettings.expandedWidthRange, step: 10) { Text("") }
                        Text("\(Int(model.settings.expandedWidth))").monospacedDigit().frame(width: 44)
                    }
                    LabeledContent("Expanded height") {
                        Slider(value: $model.settings.expandedHeight, in: IsletSettings.expandedHeightRange, step: 10) { Text("") }
                        Text("\(Int(model.settings.expandedHeight))").monospacedDigit().frame(width: 44)
                    }
                    LabeledContent("Closed wing width") {
                        Slider(value: $model.settings.wingWidth, in: IsletSettings.wingWidthRange, step: 2) { Text("") }
                        Text("\(Int(model.settings.wingWidth))").monospacedDigit().frame(width: 44)
                    }
                }
            }
            Section("Menu bar") {
                Picker("Closed island", selection: $model.settings.closedLayout) {
                    Text("Fit the menu bar").tag(ClosedLayoutPreference.auto)
                    Text("Always full width").tag(ClosedLayoutPreference.wings)
                }
                .pickerStyle(.segmented)
                Text(model.settings.closedLayout == .auto
                     ? "Sits beside the notch and shrinks to the free space in the menu bar, down to just an icon each side. On a very crowded menu bar that icon may overlap the nearest menu bar item."
                     : "Sits beside the notch at the full width for the island size above. May cover menu bar icons close to the notch.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.settings.closedLayout == .auto && !MenuBarInspector.isAvailable {
                    HStack {
                        Text("Without Accessibility Islet can't see the menu bar, so it uses narrow wings that may touch icons on a crowded bar.")
                            .font(.caption)
                        Spacer()
                        Button("Allow…") { MediaKeyInterceptor.requestAccessibility() }
                    }
                }
            }
            Section("Look") {
                Picker("Theme", selection: $model.settings.theme) {
                    Text("Glass").tag(IslandTheme.glass)
                    Text("Black").tag(IslandTheme.black)
                    Text("Graphite").tag(IslandTheme.graphite)
                }
                .pickerStyle(.segmented)
                if model.settings.theme == .glass {
                    LabeledContent("Glass level") {
                        HStack(spacing: 8) {
                            Text("Black").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $model.settings.glassLevel, in: IsletSettings.glassLevelRange) { Text("Glass level") }
                                .labelsHidden()
                            Text("Glass").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("The strip beside the notch stays black so it blends with the hardware; below it the open island melts into glass.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Accent") {
                    HStack(spacing: 6) {
                        ForEach(Self.accents, id: \.self) { name in
                            Button { model.settings.accentColor = name } label: {
                                ZStack {
                                    if name == "auto" {
                                        Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                                    } else {
                                        Circle().fill(Color(tint: name))
                                    }
                                    if model.settings.accentColor == name { Circle().stroke(Color.primary, lineWidth: 2).padding(-3) }
                                }
                                .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .help(name == "auto" ? "Follow album art" : name.capitalized)
                        }
                    }
                }
                Toggle("Rounded text", isOn: $model.settings.roundedFont)
                Toggle("Smart icons and colors for activities", isOn: $model.settings.smartIcons)
            }
            Section("Motion & feel") {
                Picker("Animation", selection: $model.settings.animationStyle) {
                    Text("Fluid").tag(AnimationStyle.fluid)
                    Text("Snappy").tag(AnimationStyle.snappy)
                    Text("Smooth").tag(AnimationStyle.smooth)
                    Text("Minimal").tag(AnimationStyle.minimal)
                    Text("Off").tag(AnimationStyle.off)
                }
                .pickerStyle(.segmented)
                Toggle("Bounce when something new arrives", isOn: $model.settings.bounceOnActivity)
                Toggle("Glow while something needs you", isOn: $model.settings.urgentGlow)
                Picker("Trackpad haptics", selection: $model.settings.hapticsMode) {
                    Text("Off").tag(HapticsMode.off)
                    Text("When I use the island").tag(HapticsMode.direct)
                    Text("Also for important alerts").tag(HapticsMode.all)
                }
                Toggle("Reduce motion", isOn: $model.settings.reduceMotion)
                LabeledContent("New activity stays open") {
                    Slider(value: $model.settings.alertDuration, in: IsletSettings.alertDurationRange, step: 0.5) { Text("") }
                    Text(String(format: "%.1fs", model.settings.alertDuration)).monospacedDigit().frame(width: 40)
                }
                LabeledContent("Volume/brightness HUD") {
                    Slider(value: $model.settings.hudDuration, in: IsletSettings.hudDurationRange, step: 0.2) { Text("") }
                    Text(String(format: "%.1fs", model.settings.hudDuration)).monospacedDigit().frame(width: 40)
                }
                Button("Preview") { AppActions.previewAppearance(model) }
            }
            Section("Several things at once") {
                Picker("Activities shown together", selection: $model.settings.maxConcurrent) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                Picker("Extra activities appear", selection: $model.settings.bubblePlacement) {
                    Text("Right of the notch").tag(BubblePlacement.right)
                    Text("Left of the notch").tag(BubblePlacement.left)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Per-app customisation: tint, icon, visibility and notification handling.
struct AppRulesSettings: View {
    @Bindable var model: AppModel
    @ViewState private var selection: String?

    private var runningApps: [NSRunningApplication] {
        let existing = Set(model.settings.appRules.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !existing.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Customise how each app appears in the island.").foregroundStyle(.secondary)
                Spacer()
                Menu("Add App") {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            model.settings.appRules.append(AppRule(bundleID: app.bundleIdentifier!))
                            selection = app.bundleIdentifier
                        }
                    }
                }
                .fixedSize()
            }
            if model.settings.appRules.isEmpty {
                ContentUnavailableView("No app rules yet", systemImage: "app.dashed",
                                       description: Text("Add an app to give it a color, hide the island while it's in front, keep the island in fullscreen, or mute its notifications."))
            } else {
                List(selection: $selection) {
                    ForEach($model.settings.appRules) { $rule in
                        AppRuleRow(rule: $rule) {
                            model.settings.appRules.removeAll { $0.bundleID == rule.bundleID }
                        }
                        .tag(rule.bundleID)
                    }
                }
            }
        }
        .padding()
    }
}

struct AppRuleRow: View {
    @Binding var rule: AppRule
    var onDelete: () -> Void

    private var name: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? rule.bundleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AppIconView(bundleID: rule.bundleID, size: 20)
                Text(name).bold()
                Spacer()
                Picker("", selection: Binding(get: { rule.tint ?? "" }, set: { rule.tint = $0.isEmpty ? nil : $0 })) {
                    Text("Default color").tag("")
                    ForEach(["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "gray"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                .frame(width: 140)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HStack(spacing: 14) {
                Toggle("Hide island when in front", isOn: Binding(get: { rule.hideIsland ?? false }, set: { rule.hideIsland = $0 ? true : nil }))
                Toggle("Show in fullscreen", isOn: Binding(get: { rule.showInFullscreen ?? false }, set: { rule.showInFullscreen = $0 ? true : nil }))
                Toggle("Mute notifications", isOn: Binding(get: { rule.muteNotifications ?? false }, set: { rule.muteNotifications = $0 ? true : nil }))
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct ModulesSettings: View {
    @Bindable var model: AppModel
    @ViewState private var calendarAccess = CalendarService.eventAccess
    @ViewState private var reminderAccess = CalendarService.reminderAccess
    @ViewState private var axTrusted = MediaKeyInterceptor.hasAccessibility

    var body: some View {
        Form {
            Section("Media") {
                Toggle("Now Playing", isOn: $model.settings.mediaEnabled)
                MediaSourceToggles(model: model)
                Toggle("Show paused media in the closed island", isOn: $model.settings.showPausedMedia)
                Toggle("Show the new song for a moment", isOn: $model.settings.songChangePeek)
                    .disabled(!model.settings.mediaEnabled)
                Text("When the track changes, the closed island opens a little below the notch with the artwork, title and artist, then closes again.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("System-wide bridge") {
                    Text(model.systemMedia.isRunning ? "Running" : "Unavailable")
                        .foregroundStyle(model.systemMedia.isRunning ? .green : .orange)
                }
            }
            Section("Heads-up display") {
                Toggle("Volume HUD", isOn: $model.settings.hudEnabled)
                Toggle("Brightness HUD", isOn: $model.settings.brightnessHUDEnabled)
                Toggle("Replace the system HUD (uses Accessibility)", isOn: $model.settings.replaceSystemHUD)
                if model.settings.replaceSystemHUD && !axTrusted {
                    HStack {
                        Text("Grant Accessibility so Islet can take over the volume and brightness keys.").font(.caption)
                        Button("Grant…") {
                            MediaKeyInterceptor.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { axTrusted = MediaKeyInterceptor.hasAccessibility }
                        }
                    }
                }
            }
            LiveActivitySettingsSection(model: model)
            Section("iPhone-style events") {
                Toggle("Call timer when FaceTime, Zoom, Meet… use the mic", isOn: $model.settings.callDetection)
                Toggle("Download progress from ~/Downloads", isOn: $model.settings.downloadsEnabled)
                Toggle("“Welcome back” summary when you unlock", isOn: $model.settings.unlockSplash)
                HStack {
                    Toggle("Mirror notifications from every app (experimental)", isOn: $model.settings.notificationMirroring)
                    if model.settings.notificationMirroring && !axTrusted {
                        Button("Grant Access…") {
                            MediaKeyInterceptor.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                axTrusted = MediaKeyInterceptor.hasAccessibility
                                model.startEventSources()
                            }
                        }
                    }
                }
                Text("Includes iPhone notifications that macOS already forwards. Uses Accessibility to read banners; nothing is stored or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("On-device AI for icons and summaries", isOn: $model.settings.aiAssist)
                LabeledContent("Apple Intelligence") { Text(AIAssist.shared.statusText).foregroundStyle(.secondary) }
            }
            TimerSettingsSection(model: model)
            Section("Everything else") {
                Toggle("Battery & charging", isOn: $model.settings.batteryEnabled)
                HStack {
                    Toggle("Calendar", isOn: $model.settings.calendarEnabled)
                    Spacer()
                    if calendarAccess != .granted {
                        Button(calendarAccess == .denied ? "Open Privacy Settings" : "Grant Access") {
                            if calendarAccess == .denied {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            } else {
                                model.requestCalendarAccess()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { calendarAccess = CalendarService.eventAccess }
                            }
                        }
                    }
                }
                if calendarAccess == .granted && model.settings.calendarEnabled {
                    DisclosureGroup("Calendars shown") {
                        ForEach(model.calendar.calendars(), id: \.id) { c in
                            Toggle(isOn: Binding(
                                get: { !model.settings.hiddenCalendars.contains(c.id) },
                                set: { show in
                                    if show { model.settings.hiddenCalendars.removeAll { $0 == c.id } }
                                    else if !model.settings.hiddenCalendars.contains(c.id) { model.settings.hiddenCalendars.append(c.id) }
                                })) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(tint: c.color, fallback: .blue)).frame(width: 8, height: 8)
                                    Text(c.title)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Toggle("Reminders due today", isOn: $model.settings.remindersEnabled)
                    Spacer()
                    if reminderAccess != .granted {
                        Button(reminderAccess == .denied ? "Open Privacy Settings" : "Grant Access") {
                            if reminderAccess == .denied {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                            } else {
                                model.requestReminderAccess()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { reminderAccess = CalendarService.reminderAccess }
                            }
                        }
                    }
                }
                Toggle("File shelf & AirDrop", isOn: $model.settings.shelfEnabled)
                Toggle("Clipboard history (local only, skips passwords)", isOn: $model.settings.clipboardEnabled)
                if model.settings.clipboardEnabled { ClipboardLimitPicker(model: model) }
                Toggle("Camera & microphone indicators", isOn: $model.settings.privacyIndicatorsEnabled)
                Toggle("System stats", isOn: $model.settings.systemStatsEnabled)
            }
            BatteryAlertSettingsSection(model: model)
        }
        .formStyle(.grouped)
    }
}

struct IntegrationsSettings: View {
    @Bindable var model: AppModel
    @ViewState private var copied = false

    var body: some View {
        // Home's "Show usage" opens this tab scrolled to Usage limits.
        ScrollViewReader { proxy in
            form
                .onAppear { scroll(proxy) }
                .onChange(of: model.settingsScrollTarget) { _, _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = model.settingsScrollTarget, target.pane == .integrations else { return }
        // After this pass, so the form has laid out the section.
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
            model.settingsScrollTarget = nil
        }
    }

    private var hookSnippet: String {
        let cli = AppActions.cliPath
        return """
        "hooks": {
          "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\(cli) hook claude"}]}],
          "PreToolUse":       [{"hooks": [{"type": "command", "command": "\(cli) hook claude"}]}],
          "Notification":     [{"hooks": [{"type": "command", "command": "\(cli) hook claude"}]}],
          "Stop":             [{"hooks": [{"type": "command", "command": "\(cli) hook claude"}]}],
          "SessionEnd":       [{"hooks": [{"type": "command", "command": "\(cli) hook claude"}]}]
        }
        """
    }

    private var form: some View {
        Form {
            Section("Local API") {
                Toggle("Enable local API (127.0.0.1 only, token required)", isOn: $model.settings.apiEnabled)
                LabeledContent("Status") { Text(model.apiStatus).foregroundStyle(.secondary) }
                LabeledContent("Port") { PortField(port: $model.settings.apiPort, other: model.settings.lanPort) }
                LabeledContent("iPhone bridge port") { PortField(port: $model.settings.lanPort, other: model.settings.apiPort) }
                HStack {
                    Button(copied ? "Copied" : "Copy Token") {
                        AppActions.copyToken()
                        copied = true
                    }
                    Button("Open API Docs") {
                        if let doc = Bundle.main.url(forResource: "API", withExtension: "md") { NSWorkspace.shared.open(doc) }
                    }
                }
            }
            Section("Command line") {
                Text("Link the bundled CLI onto your PATH:").font(.caption)
                Text("ln -sf \"\(AppActions.cliPath)\" /opt/homebrew/bin/isletctl")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("Coding agents") {
                ApprovalSettingsRows(model: model)
                Text("Add to ~/.claude/settings.json to see agent status in the notch:").font(.caption)
                Text(hookSnippet).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Text("Codex: add  notify = [\"\(AppActions.cliPath)\", \"hook\", \"codex\"]  to ~/.codex/config.toml")
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }
            UsageLimitsSection(model: model)
                .id(SettingsSection.usageLimits)
            LANBridgeSection(model: model)
            Section("Script widgets") {
                Toggle("Run scripts from the plugins folder", isOn: $model.settings.pluginsEnabled)
                PluginFolderRow(model: model)
                HStack {
                    Button("Open Plugins Folder") { AppActions.openPluginsFolder(model) }
                    Button("Install Examples") { AppActions.installExamplePlugins(model) }
                }
            }
            Section("URL scheme") {
                Text("islet://notify?title=Hello  ·  islet://timer?minutes=5  ·  islet://media/playpause  ·  islet://awake?for=1h")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "capsule.fill").font(.system(size: 44)).foregroundStyle(.primary)
            Text("Islet").font(.title.bold())
            Text("Version \(AppModel.version)").foregroundStyle(.secondary)
            Text("An open-source Dynamic Island for the Mac notch.\nMIT licensed. No accounts, no license server, no telemetry.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Settings live in ~/.config/islet/config.json")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
