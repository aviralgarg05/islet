import AppKit
import IsletCore
import SwiftUI

/// Settings → Timers: the sound when a timer ends and the Pomodoro lengths. Timers have no
/// switch: nothing runs until one is started.
struct TimersSettings: View {
    @Bindable var model: AppModel

    /// macOS system sounds, plus whatever name `config.json` holds.
    private var sounds: [String] {
        let system = ["Glass", "Ping", "Purr", "Hero", "Submarine", "Funk", "Tink", "Blow", "Bottle", "Frog", "Morse", "Pop", "Basso", "Sosumi"]
        let current = model.settings.timerSound
        return ["none"] + system + (current == "none" || system.contains(current) ? [] : [current])
    }

    var body: some View {
        Form {
            Section { SettingsHero(page: .timers) }
            Section {
                Picker("Sound when a timer ends", selection: $model.settings.timerSound) {
                    ForEach(sounds, id: \.self) { name in
                        Text(name == "none" ? "None" : name).tag(name)
                    }
                }
                .onChange(of: model.settings.timerSound) { _, name in
                    if name != "none" { NSSound(named: NSSound.Name(name))?.play() }
                }
                .settingsAnchor("timers.sound")
            } footer: {
                SettingsFooter("Start a timer from Home or ask Siri with a shortcut. When one ends, the island stays open until you stop, snooze or restart it.")
            }
            // Each value sits beside its stepper, on the right, like System Settings.
            Section("Pomodoro") {
                PomodoroLengthsPicker(model: model)
                minutes("Focus", $model.settings.pomodoro.focusMinutes, 1...240, step: 5)
                    .settingsAnchor("timers.focus")
                minutes("Short break", $model.settings.pomodoro.shortBreakMinutes, 1...60, step: 1)
                minutes("Long break", $model.settings.pomodoro.longBreakMinutes, 1...240, step: 5)
                LabeledContent("Long break after") {
                    HStack(spacing: 6) {
                        Text(model.settings.pomodoro.longBreakEvery == 1 ? "every round" : "every \(model.settings.pomodoro.longBreakEvery) rounds")
                            .monospacedDigit()
                        Stepper("Long break after", value: $model.settings.pomodoro.longBreakEvery, in: 1...12).labelsHidden()
                    }
                }
            }
            FocusSoundSettingsSection(model: model)
            StopwatchSettingsSection(model: model)
        }
        .formStyle(.grouped)
    }

    /// The value, then the arrows at the row's right edge, so every row's arrows line up.
    private func minutes(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(Int(value.wrappedValue)) min").monospacedDigit()
                Stepper(title, value: value, in: range, step: step).labelsHidden()
            }
        }
    }
}
