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
                MediaSourceToggles(model: model)
            } header: {
                Text("Sources").settingsAnchor("nowPlaying.sources")
            }
            .disabled(!on)
            Section("Closed island") {
                Toggle(isOn: $model.settings.showPausedMedia) {
                    Text("Show paused music in the closed island")
                    Text("Keeps the artwork beside the notch after you pause.")
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
                Picker("Colour", selection: $model.settings.visualiserColour) {
                    Text("From the artwork").tag(VisualiserColour.artwork)
                    Text("Accent colour").tag(VisualiserColour.accent)
                    Text("White").tag(VisualiserColour.white)
                }
                .disabled(model.settings.visualiserStyle == .off)
                .settingsAnchor("nowPlaying.indicatorColour")
            } header: {
                Text("Playing indicator")
            } footer: {
                HStack(spacing: 4) {
                    SettingsFooter("It settles to a dim line when you pause and springs back when you play.")
                    SettingsLink(text: "Accent colour", page: .appearance, anchor: "appearance.accent").fixedSize()
                }
            }
            .disabled(!on)
        }
        .formStyle(.grouped)
    }
}

/// The playing indicator's looks, each drawn as it moves in the island.
private struct IndicatorStylePicker: View {
    @Bindable var model: AppModel

    private static let styles: [(VisualiserStyle, String)] = [(.bars, "Bars"), (.slim, "Slim bars"), (.dots, "Dots"), (.off, "None")]

    /// With no song playing, "from the artwork" shows the sample artwork's colour.
    private var tint: Color {
        model.settings.visualiserColour == .artwork ? IslandSketch.artwork[0] : model.visualiserTint(nil)
    }

    var body: some View {
        SettingsRow(title: "Look") {
            HStack(spacing: 10) {
                ForEach(Self.styles, id: \.0) { style, name in
                    let selected = model.settings.visualiserStyle == style
                    Button { model.settings.visualiserStyle = style } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                                if style == .off {
                                    Image(systemName: "nosign").foregroundStyle(.white.opacity(0.45))
                                } else {
                                    PlayingIndicator(tint: tint, playing: true).environment(\.visualiserStyle, style)
                                }
                            }
                            .frame(width: 54, height: 34)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                            }
                            Text(name).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
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

struct ShelfSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .shelf, switchTitle: "File shelf and AirDrop", isOn: $model.settings.shelfEnabled)
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
