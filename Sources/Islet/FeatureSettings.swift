import AppKit
import IsletCore
import IsletSystem
import SwiftUI

// One Settings page per feature. Each starts with the feature's switch and a line on what it
// does; the rest of the page is dimmed while it is off.

// MARK: - Now Playing

struct NowPlayingSettings: View {
    @Bindable var model: AppModel

    private var on: Bool { model.settings.mediaEnabled }

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .nowPlaying, switchTitle: "Show what's playing", isOn: $model.settings.mediaEnabled)
                    .settingsAnchor("nowPlaying.enabled")
            }
            Section {
                IslandPreview(settings: model.settings, showsOpen: false)
                    .settingsAnchor("nowPlaying.preview")
            }
            Section {
                MediaSourceToggles(model: model)
            } header: {
                Text("Sources").settingsAnchor("nowPlaying.sources")
            }
            .disabled(!on)
            Section("Closed island") {
                Picker(selection: $model.settings.pausedMusicTimeout) {
                    ForEach(pausedChoices, id: \.self) { Text(Self.pausedLabel($0)).tag($0) }
                } label: {
                    Text("Hide paused music after")
                    Text("The artwork dims and the indicator settles, then the island goes back to the notch.")
                }
                .settingsAnchor("nowPlaying.paused")
                Toggle(isOn: $model.settings.songChangePeek) {
                    Text("Show the new song for a moment")
                    Text("When the track changes, the island opens a little with the artwork, title and artist.")
                }
                .settingsAnchor("nowPlaying.peek")
            }
            .disabled(!on)
            Section("Open island") {
                Toggle(isOn: $model.settings.mediaShowsRemainingTime) {
                    Text("Show time left")
                    Text("Beside the progress bar, instead of the song's length. Clicking the time in the island switches it too.")
                }
                .settingsAnchor("nowPlaying.remaining")
            }
            .disabled(!on)
            Section {
                IndicatorStylePicker(model: model)
                    .settingsAnchor("nowPlaying.indicator")
                Picker("Colour", selection: indicatorColour) {
                    Text("From the artwork").tag(VisualiserColour.artwork)
                    // With the accent on "auto" it is the artwork's colour, so it isn't offered twice.
                    if model.settings.accentColor != "auto" {
                        Text("Accent colour").tag(VisualiserColour.accent)
                    }
                    Text("White").tag(VisualiserColour.white)
                }
                .disabled(model.settings.visualiserStyle == .off)
                .settingsAnchor("nowPlaying.indicatorColour")
            } header: {
                Text("Playing indicator")
            } footer: {
                HStack(spacing: 4) {
                    SettingsFooter("It settles and dims when you pause, and springs back when you play.")
                    SettingsLink(text: "Accent colour", page: .appearance, anchor: "appearance.accent").fixedSize()
                }
            }
            .disabled(!on)
        }
        .formStyle(.grouped)
    }

    /// The offered times, and a hand-edited one from config.json.
    private var pausedChoices: [Double] {
        var choices = IsletSettings.pausedMusicChoices
        let current = model.settings.pausedMusicTimeout
        if !choices.contains(current) {
            choices.insert(current, at: choices.firstIndex { $0 < 0 || $0 > current } ?? choices.endIndex)
        }
        return choices
    }

    static func pausedLabel(_ seconds: Double) -> String {
        if seconds < 0 { return "Never" }
        if seconds == 0 { return "Right away" }
        let s = Int(seconds.rounded())
        if s % 60 == 0 { return s == 60 ? "1 minute" : "\(s / 60) minutes" }
        return s == 1 ? "1 second" : "\(s) seconds"
    }

    /// "Accent colour" on "auto" shows as "From the artwork", which is what it draws.
    private var indicatorColour: Binding<VisualiserColour> {
        Binding(get: {
            let c = model.settings.visualiserColour
            return c == .accent && model.settings.accentColor == "auto" ? .artwork : c
        }, set: { model.settings.visualiserColour = $0 })
    }
}

/// The playing indicator's looks, each drawn as it moves in the island.
struct IndicatorStylePicker: View {
    @Bindable var model: AppModel

    private static let styles: [VisualiserStyle] = [.bars, .slim, .dots, .wave, .pulse, .off]

    static func name(_ style: VisualiserStyle) -> String {
        switch style {
        case .bars: return "Bars"
        case .slim: return "Slim bars"
        case .dots: return "Dots"
        case .wave: return "Wave"
        case .pulse: return "Pulse"
        case .off: return "None"
        }
    }

    var body: some View {
        SettingsRow(title: "Look") {
            HStack(spacing: 8) {
                ForEach(Self.styles, id: \.self) { style in
                    let selected = model.settings.visualiserStyle == style
                    Button { model.settings.visualiserStyle = style } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                                if style == .off {
                                    Image(systemName: "nosign").foregroundStyle(.white.opacity(0.45))
                                } else {
                                    PlayingIndicator(tint: IslandSketch.indicatorTint(model.settings), playing: true)
                                        .environment(\.visualiserStyle, style)
                                }
                            }
                            .frame(width: 52, height: 34)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                            }
                            Text(Self.name(style)).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                                .lineLimit(1).fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.name(style))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Calendar & Reminders

struct CalendarSettings: View {
    @Bindable var model: AppModel
    @ViewState private var calendarAccess = CalendarService.eventAccess
    @ViewState private var reminderAccess = CalendarService.reminderAccess
    @Environment(\.snapshotMode) private var snapshotMode

    /// Snapshots show made-up calendars, never the ones on this Mac.
    private var calendars: [(id: String, title: String, color: String?)] {
        snapshotMode ? [("home", "Home", "#34C759"), ("work", "Work", "#0A84FF"), ("family", "Family", "#FF9F0A")]
            : model.calendar.calendars()
    }

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .calendar, switchTitle: "Show your calendar", isOn: $model.settings.calendarEnabled)
                    .settingsAnchor("calendar.enabled")
                if model.settings.calendarEnabled && calendarAccess != .granted {
                    access(calendarAccess, what: "calendars", pane: "Privacy_Calendars") {
                        model.requestCalendarAccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { calendarAccess = CalendarService.eventAccess }
                    }
                }
            }
            if calendarAccess == .granted {
                Section("Calendars shown") {
                    ForEach(calendars, id: \.id) { c in
                        Toggle(isOn: Binding(
                            get: { !model.settings.hiddenCalendars.contains(c.id) },
                            set: { show in
                                if show { model.settings.hiddenCalendars.removeAll { $0 == c.id } }
                                else if !model.settings.hiddenCalendars.contains(c.id) { model.settings.hiddenCalendars.append(c.id) }
                            })) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(tint: c.color, fallback: .blue)).frame(width: 9, height: 9)
                                Text(c.title)
                            }
                        }
                    }
                }
                .disabled(!model.settings.calendarEnabled)
            }
            Section {
                Toggle(isOn: $model.settings.remindersEnabled) {
                    Text("Reminders due today")
                    Text("On the Today page, with an alert when each one is due.")
                }
                .settingsAnchor("calendar.reminders")
                if model.settings.remindersEnabled && reminderAccess != .granted {
                    access(reminderAccess, what: "reminders", pane: "Privacy_Reminders") {
                        model.requestReminderAccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { reminderAccess = CalendarService.reminderAccess }
                    }
                }
            } header: {
                Text("Reminders")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if snapshotMode {
                calendarAccess = .granted
                reminderAccess = .granted
            }
        }
    }

    private func access(_ status: CalendarService.Access, what: String, pane: String, request: @escaping () -> Void) -> some View {
        AccessRow(text: status == .denied ? "Islet isn't allowed to see your \(what)." : "Islet needs your permission to see your \(what).",
                  button: status == .denied ? "Open System Settings" : "Allow…") {
            if status == .denied {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
            } else {
                request()
            }
        }
    }
}

// MARK: - Notifications & HUDs

struct NotificationsSettings: View {
    @Bindable var model: AppModel
    @ViewState private var axTrusted = MediaKeyInterceptor.hasAccessibility

    var body: some View {
        Form {
            Section { SettingsHero(page: .notifications) }
            Section("Notifications") {
                Toggle(isOn: $model.settings.notificationMirroring) {
                    Text("Mirror notifications from every app")
                    Text("Banners from your apps, and from your iPhone when macOS shows them, appear in the island. Nothing is kept or sent anywhere.")
                }
                .settingsAnchor("notifications.mirror")
                if model.settings.notificationMirroring && !axTrusted {
                    askForAccessibility("Islet needs Accessibility to read banners.")
                }
                Toggle(isOn: $model.settings.unlockSplash) {
                    Text("Welcome back summary when you unlock")
                    Text("What arrived while the screen was locked.")
                }
                .settingsAnchor("notifications.welcome")
            }
            Section("Volume and brightness") {
                Toggle(isOn: $model.settings.hudEnabled) {
                    Text("Volume")
                    Text("When you change the volume or mute.")
                }
                .settingsAnchor("notifications.volume")
                Toggle(isOn: $model.settings.brightnessHUDEnabled) {
                    Text("Brightness")
                    Text("When you change the display's brightness.")
                }
                .settingsAnchor("notifications.brightness")
                Toggle(isOn: $model.settings.replaceSystemHUD) {
                    Text("Replace the system volume and brightness display")
                    Text("Shows only Islet's when you press the keys.")
                }
                .settingsAnchor("notifications.replaceHUD")
                if model.settings.replaceSystemHUD && !axTrusted {
                    askForAccessibility("Islet needs Accessibility to take over the keys.")
                }
                SettingsSlider(title: "Stays on screen for", value: $model.settings.hudDuration, range: IsletSettings.hudDurationRange,
                               step: 0.2, format: SettingsSlider.seconds)
                    .disabled(!model.settings.hudEnabled && !model.settings.brightnessHUDEnabled)
                    .settingsAnchor("notifications.hudDuration")
                Picker(selection: $model.settings.hudColour) {
                    Text("White").tag(HUDColour.white)
                    Text("Accent colour").tag(HUDColour.accent)
                    Text("Colourful").tag(HUDColour.colourful)
                } label: {
                    Text("Colour")
                    Text(hudColourDetail)
                }
                .disabled(!model.settings.hudEnabled && !model.settings.brightnessHUDEnabled)
                .settingsAnchor("notifications.hudColour")
            }
            Section {
                Toggle(isOn: $model.settings.batteryEnabled) {
                    Text("Battery and charging")
                    Text("Plugging in, charging and low battery.")
                }
                .settingsAnchor("notifications.battery")
                BatteryAlertRows(model: model)
                    .disabled(!model.settings.batteryEnabled)
            } header: {
                Text("Battery")
            } footer: {
                SettingsFooter("Keep awake turns itself off below \(KeepAwake.lowBatteryLevel)% on battery.")
            }
            Section("Calls, camera and microphone") {
                Toggle(isOn: $model.settings.callDetection) {
                    Text("Call timer")
                    Text("While FaceTime, Zoom, Meet or another call app uses the microphone.")
                }
                .settingsAnchor("notifications.calls")
                Toggle(isOn: $model.settings.privacyIndicatorsEnabled) {
                    Text("Camera and microphone in use")
                    Text("A dot beside the notch while an app uses them.")
                }
                .settingsAnchor("notifications.privacy")
            }
        }
        .formStyle(.grouped)
    }

    private var hudColourDetail: String {
        switch model.settings.hudColour {
        case .white: return "Like the rest of the closed island."
        case .accent:
            return model.settings.accentColor == "auto"
                ? "The playing artwork's colour, or your Mac's accent colour."
                : "The accent colour from Appearance."
        case .colourful: return "Volume green, brightness yellow, keyboard light blue."
        }
    }

    private func askForAccessibility(_ text: String) -> some View {
        AccessRow(text: text, button: "Allow…") {
            MediaKeyInterceptor.requestAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                axTrusted = MediaKeyInterceptor.hasAccessibility
                model.startEventSources()
            }
        }
    }
}

// MARK: - Shelf & Clipboard

/// Two features that switch on and off apart, so each has its own switch under the page's line.
struct ShelfSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { SettingsHero(page: .shelf) }
            Section("Shelf") {
                Toggle(isOn: $model.settings.shelfEnabled) {
                    Text("File shelf and AirDrop")
                    Text("Drop files on the island to keep them handy, then drag them out or AirDrop them.")
                }
                .settingsAnchor("shelf.enabled")
            }
            Section("Clipboard") {
                Toggle(isOn: $model.settings.clipboardEnabled) {
                    Text("Clipboard history")
                    Text("What you copy, on the Clipboard page. It stays on this Mac and skips passwords. Turning it off clears it.")
                }
                .settingsAnchor("shelf.clipboard")
                ClipboardLimitPicker(model: model)
                    .disabled(!model.settings.clipboardEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Downloads

struct DownloadsSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .downloads, switchTitle: "Show download progress", isOn: $model.settings.downloadsEnabled)
                    .settingsAnchor("downloads.enabled")
            } footer: {
                SettingsFooter("Islet watches your Downloads folder. macOS asks once before it can.")
            }
        }
        .formStyle(.grouped)
    }
}
