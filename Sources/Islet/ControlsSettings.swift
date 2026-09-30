import IsletCore
import SwiftUI

/// Settings → General → Gestures.
struct GestureSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Gestures") {
            Toggle("Two-finger swipes on the island", isOn: $model.settings.gesturesEnabled)
            Group {
                Toggle("Swipe down to open", isOn: $model.settings.swipeDownToOpen)
                Toggle("Swipe up to close", isOn: $model.settings.swipeUpToClose)
                Toggle("Swipe sideways over music", isOn: $model.settings.swipeMedia)
                if model.settings.swipeMedia {
                    Picker("Sideways swipe on music", selection: $model.settings.swipeMediaAction) {
                        Text("Next or previous track").tag(MediaSwipeAction.track)
                        Text("Skip 10 seconds").tag(MediaSwipeAction.seek)
                    }
                }
                Toggle("Swipe sideways over activities to switch between them", isOn: $model.settings.swipeCyclesActivities)
            }
            .disabled(!model.settings.gesturesEnabled)
            Text("Swipe left for next, right for previous. Follows your scroll direction setting.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Settings → Modules → Battery alerts.
struct BatteryAlertSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let low = model.settings.batteryLowThreshold
        let critical = model.settings.batteryCriticalThreshold
        Section("Battery alerts") {
            Picker("Low battery warning", selection: $model.settings.batteryLowThreshold) {
                ForEach(Self.levels([10, 15, 20, 25, 30, 40, 50], keeping: low), id: \.self) { Text("\($0)%").tag($0) }
            }
            Picker("Critical warning", selection: $model.settings.batteryCriticalThreshold) {
                ForEach(Self.levels([3, 5, 8, 10, 15].filter { $0 < low }, keeping: critical), id: \.self) { Text("\($0)%").tag($0) }
            }
            Picker("Tell me when charged to", selection: $model.settings.batteryChargedAlert) {
                Text("Off").tag(0)
                ForEach(Self.levels([80, 85, 90, 95, 100], keeping: model.settings.batteryChargedAlert), id: \.self) { Text("\($0)%").tag($0) }
            }
            Text("Keep awake turns itself off below \(KeepAwake.lowBatteryLevel)% on battery.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!model.settings.batteryEnabled)
    }

    /// The preset levels plus the current value, so a hand-edited config still shows.
    static func levels(_ presets: [Int], keeping current: Int) -> [Int] {
        Array(Set(presets + (current > 0 ? [current] : []))).sorted()
    }
}
