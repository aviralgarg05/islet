import AppKit
import IsletCore
import SwiftUI

/// Settings → Modules → Timers: the sound when a timer ends and the Pomodoro lengths.
struct TimerSettingsSection: View {
    @Bindable var model: AppModel

    /// macOS system sounds, plus whatever name `config.json` holds.
    private var sounds: [String] {
        let system = ["Glass", "Ping", "Purr", "Hero", "Submarine", "Funk", "Tink", "Blow", "Bottle", "Frog", "Morse", "Pop", "Basso", "Sosumi"]
        let current = model.settings.timerSound
        return ["none"] + system + (current == "none" || system.contains(current) ? [] : [current])
    }

    var body: some View {
        Section("Timers") {
            Picker("Sound when a timer ends", selection: $model.settings.timerSound) {
                ForEach(sounds, id: \.self) { name in
                    Text(name == "none" ? "None" : name).tag(name)
                }
            }
            .onChange(of: model.settings.timerSound) { _, name in
                if name != "none" { NSSound(named: NSSound.Name(name))?.play() }
            }
            Stepper(value: $model.settings.pomodoro.focusMinutes, in: 1...240, step: 5) {
                LabeledContent("Pomodoro focus", value: "\(Int(model.settings.pomodoro.focusMinutes)) min")
            }
            Stepper(value: $model.settings.pomodoro.shortBreakMinutes, in: 1...60) {
                LabeledContent("Short break", value: "\(Int(model.settings.pomodoro.shortBreakMinutes)) min")
            }
            Stepper(value: $model.settings.pomodoro.longBreakMinutes, in: 1...240, step: 5) {
                LabeledContent("Long break", value: "\(Int(model.settings.pomodoro.longBreakMinutes)) min")
            }
            Stepper(value: $model.settings.pomodoro.longBreakEvery, in: 1...12) {
                LabeledContent("Long break after", value: model.settings.pomodoro.longBreakEvery == 1
                               ? "every round" : "every \(model.settings.pomodoro.longBreakEvery) rounds")
            }
            Text("Start timers from Home, with `isletctl timer \"tea 4m\"`, or from Siri with a shortcut. A timer that ends opens the island until you stop, snooze or restart it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
