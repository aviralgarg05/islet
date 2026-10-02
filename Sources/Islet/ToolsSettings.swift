import AppKit
import IsletCore
import IsletSystem
import SwiftUI

// Settings for the tools that start off. To-dos, the note, the converter, emoji, Shortcuts,
// Weather, Mirror, Teleprompter, Stocks and Sales are pages of their own, set on the Tools page
// (the first four in NoteToolsSettings.swift, the last four in ToolsSettingsView.swift);
// lyrics, the month calendar, the stopwatch and focus sounds sit on the pages of the features
// they belong to (Now Playing, Calendar & Reminders, Timers).

// MARK: - Tools page

struct ToolsSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { SettingsHero(page: .tools) }
            MutedFromIslandSection(model: model, page: .tools)
            NoteToolsSettingsSections(model: model)
            Section {
                Toggle(isOn: $model.settings.shortcutsEnabled) {
                    Text("Run your shortcuts")
                    Text("A Shortcuts page under More: search for one and click to run it. The Ask box suggests matching ones too.")
                }
                .settingsAnchor("tools.shortcuts")
            } header: {
                Text("Shortcuts")
            } footer: {
                SettingsFooter("Shortcuts run on this Mac, as they do in the Shortcuts app.")
            }
            WeatherSettingsSection(model: model)
            Section("System") {
                Toggle(isOn: $model.settings.systemStatsEnabled) {
                    Text("Show CPU and memory")
                    Text("A System page under More, measured only while it\u{2019}s open.")
                }
                .settingsAnchor("tools.stats")
            }
            MirrorSettingsSection(model: model)
            TeleprompterSettingsSection(model: model)
            StocksSettingsSection(model: model)
            SalesSettingsSection(model: model)
        }
        .formStyle(.grouped)
    }
}

/// The weather's switch, where it is for, and in which unit.
struct WeatherSettingsSection: View {
    @Bindable var model: AppModel
    @ViewState private var locationAccess = LocationProvider.access
    @Environment(\.snapshotMode) private var snapshotMode

    private var usesLocation: Bool { model.settings.weatherUsesLocation }

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.weatherEnabled) {
                Text("Show the weather")
                Text("A Weather page under More, with the weather now and for the week ahead.")
            }
            .settingsAnchor("tools.weather")
            Group {
                Picker(selection: $model.settings.weatherUsesLocation) {
                    Text("A city").tag(false)
                    Text("Where I am").tag(true)
                } label: {
                    Text("Weather location")
                    Text(usesLocation ? "macOS asks once. Only a position rounded to about a kilometre is sent."
                         : model.settings.weatherPlace?.label ?? "No city chosen yet.")
                }
                .settingsAnchor("tools.weatherLocation")
                .onChange(of: model.settings.weatherUsesLocation) { _, on in
                    // Choosing "Where I am" is when macOS asks, never before.
                    guard on, !snapshotMode, LocationProvider.access == .notDetermined else { return }
                    PermissionProbe.request(.location) { _ in locationAccess = LocationProvider.access }
                }
                if usesLocation && locationAccess == .denied && !snapshotMode {
                    AccessRow(text: "Islet isn't allowed to know where this Mac is.", button: "Open System Settings") {
                        NSWorkspace.shared.open(PermissionKind.location.settingsURL)
                    }
                }
                if !usesLocation {
                    CitySearch(model: model)
                }
                Picker("Temperature in", selection: $model.settings.temperatureUnit) {
                    Text("Automatic").tag(TemperatureUnit.automatic)
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                .settingsAnchor("tools.temperature")
            }
            .disabled(!model.settings.weatherEnabled)
        } header: {
            Text("Weather")
        } footer: {
            SettingsFooter("Forecasts come from Open-Meteo, which needs no account. Islet asks for one at most every 30 minutes, and only while the Weather page is open.")
        }
    }
}

/// Type a city, press Return, and pick it from what Open-Meteo finds.
private struct CitySearch: View {
    @Bindable var model: AppModel
    @ViewState private var text = ""
    @ViewState private var searched = ""

    var body: some View {
        let w = model.tools.weather
        LabeledContent("City") {
            HStack(spacing: 8) {
                TextField("City", text: $text, prompt: Text("Search for a city"))
                    // A form right-aligns its fields; text you type starts at the left.
                    .multilineTextAlignment(.leading)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(search)
                Button("Search", action: search)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || w.searching)
            }
        }
        if w.searching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        } else if w.searchFailed {
            Text("The search couldn't reach Open-Meteo. Check the connection and try again.").font(.callout).foregroundStyle(.secondary)
        } else if !searched.isEmpty && w.places.isEmpty {
            Text("No place called “\(searched)”.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(w.places, id: \.self) { place in
            Button {
                model.settings.weatherPlace = place
                w.clearSearch()
                text = ""
                searched = ""
            } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                    Text(place.label)
                    Spacer()
                    if place == model.settings.weatherPlace { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(place.label)
            .accessibilityAddTraits(place == model.settings.weatherPlace ? .isSelected : [])
        }
    }

    private func search() {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        searched = name
        model.tools.weather.search(name)
    }
}

// MARK: - Lyrics (Now Playing)

struct LyricsSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.lyricsEnabled) {
                Text("Show lyrics")
                Text("Time-synced lyrics beside the song on Home, for Music and Spotify. Click a line to jump to it, or the quote button on the song to hide them.")
            }
            .settingsAnchor("nowPlaying.lyrics")
            Toggle(isOn: $model.settings.lyricsIncludeBrowsers) {
                Text("Also for music in a web browser")
                Text("Songs playing in Chrome, Safari and other browsers, such as YouTube Music. Videos that don\u{2019}t look like songs are left out.")
            }
            .settingsAnchor("nowPlaying.lyricsBrowsers")
            .disabled(!model.settings.lyricsEnabled)
        } header: {
            Text("Lyrics")
        } footer: {
            SettingsFooter("Lyrics come from LRCLIB, a free lyrics library. Only the song\u{2019}s title, artist, album and length are sent, once per song. For music in a browser, that\u{2019}s the title of what it\u{2019}s playing and its artist or channel.")
        }
    }
}

// MARK: - Month calendar (Calendar & Reminders)

struct MonthCalendarSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Today page") {
            Toggle(isOn: $model.settings.monthCalendar) {
                Text("Month calendar on Today")
                Text("The month beside today's events. Days with events are brighter; click one to see what's on.")
            }
            .settingsAnchor("calendar.month")
        }
    }
}

// MARK: - Timers: Pomodoro lengths, focus sound, stopwatch

/// 25 / 5, 50 / 10, 90 / 20, or the lengths below set by hand.
struct PomodoroLengthsPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("Lengths", selection: Binding<String>(
            get: { PomodoroPreset.matching(model.settings.pomodoro)?.id ?? "own" },
            set: { id in
                guard let preset = PomodoroPreset.all.first(where: { $0.id == id }) else { return }
                model.settings.pomodoro = preset.applied(to: model.settings.pomodoro)
            })) {
            ForEach(PomodoroPreset.all) { preset in Text(preset.title).tag(preset.id) }
            if PomodoroPreset.matching(model.settings.pomodoro) == nil {
                Text("Your own").tag("own")
            }
        }
        .settingsAnchor("timers.lengths")
    }
}

struct FocusSoundSettingsSection: View {
    @Bindable var model: AppModel
    @ViewState private var preview = FocusSoundPreview()

    var body: some View {
        let sound = model.settings.focusSound
        Section {
            Picker(selection: $model.settings.focusSound) {
                ForEach(FocusSound.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("Play during focus")
                // "None" needs no line: "Quiet during focus" would only say it again.
                if let detail = Self.detail(sound) { Text(detail) }
            }
            .settingsAnchor("timers.focusSound")
            .onChange(of: sound) { _, s in preview.changed(to: s, volume: model.settings.focusSoundVolume) }
            .onDisappear { preview.stop() }
            Group {
                SettingsSlider(title: "Sound volume", value: $model.settings.focusSoundVolume, range: 0...1, step: 0.05) {
                    "\(Int(($0 * 100).rounded()))%"
                }
                .settingsAnchor("timers.focusVolume")
                .onChange(of: model.settings.focusSoundVolume) { _, v in preview.setVolume(v) }
                LabeledContent("Try it") {
                    Button(preview.playing ? "Stop" : "Listen") { preview.toggle(sound, volume: model.settings.focusSoundVolume) }
                }
            }
            .disabled(!sound.isGenerated)
        } header: {
            Text("Focus sound")
        } footer: {
            SettingsFooter("Plays while a Pomodoro focus round runs and stops for the breaks. Islet makes the sounds itself; nothing is downloaded.")
        }
    }

    static func detail(_ sound: FocusSound) -> String? {
        switch sound {
        case .off: return nil
        case .brownNoise: return "A deep, soft rumble."
        case .pinkNoise: return "Steady, like rain on a window."
        case .waves: return "Rolls in and out, like the sea."
        case .music: return "Your music plays when focus starts and pauses for breaks, if Islet started it."
        }
    }
}

/// "Listen" in Settings: the chosen sound until Stop, another choice, or leaving the page.
@MainActor
@Observable
final class FocusSoundPreview {
    private(set) var playing = false
    @ObservationIgnored private lazy var player = FocusSoundPlayer()

    func toggle(_ sound: FocusSound, volume: Double) {
        if playing { stop() } else if sound.isGenerated {
            player.play(sound, volume: volume)
            playing = true
        }
    }

    func changed(to sound: FocusSound, volume: Double) {
        guard playing else { return }
        if sound.isGenerated { player.play(sound, volume: volume) } else { stop() }
    }

    func setVolume(_ volume: Double) {
        if playing { player.setVolume(volume) }
    }

    func stop() {
        guard playing else { return }
        player.stop()
        playing = false
    }
}

struct StopwatchSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.stopwatchEnabled) {
                Text("Stopwatch")
                Text("Start one from the timer button, with laps. It counts beside the notch while it runs.")
            }
            .settingsAnchor("timers.stopwatch")
        }
    }
}
