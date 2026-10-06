import CasementCore
import SwiftUI

/// Settings → General → Gestures.
struct GestureSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.gesturesEnabled) {
                Text("Two-finger swipes on the island")
                Text("Directions are the way your fingers move, whatever your scrolling setting.")
            }
            .settingsAnchor("general.gestures")
            Group {
                Toggle("Swipe down to open", isOn: $model.settings.swipeDownToOpen)
                Toggle("Swipe up to close", isOn: $model.settings.swipeUpToClose)
                // One row: off, or what the swipe does.
                Picker("Swipe sideways over music", selection: $model.settings.mediaSwipe) {
                    Text("Off").tag(MediaSwipeAction?.none)
                    Divider()
                    Text("Next or previous song").tag(MediaSwipeAction?.some(.track))
                    Text("Skip 10 seconds").tag(MediaSwipeAction?.some(.seek))
                }
                Toggle("Swipe sideways to switch between activities", isOn: $model.settings.swipeCyclesActivities)
                Toggle(isOn: $model.settings.reverseSideSwipes) {
                    Text("Reverse sideways swipes")
                    Text("Swipe right for the next song or activity, and left for the one before.")
                }
                .disabled(!model.settings.swipeMedia && !model.settings.swipeCyclesActivities)
            }
            .disabled(!model.settings.gesturesEnabled)
        } header: {
            Text("Gestures")
        }
    }
}

/// Settings → Notifications & Levels → Battery: when to warn.
struct BatteryAlertRows: View {
    @Bindable var model: AppModel

    var body: some View {
        let low = model.settings.batteryLowThreshold
        let critical = model.settings.batteryCriticalThreshold
        Picker("Low battery warning", selection: $model.settings.batteryLowThreshold) {
            ForEach(Self.levels([10, 15, 20, 25, 30, 40, 50], keeping: low), id: \.self) { Text("\($0)%").tag($0) }
        }
        .onChange(of: low) { _, newLow in
            // The critical warning must stay below the low one (the config file clamps it the same way).
            if model.settings.batteryCriticalThreshold >= newLow {
                model.settings.batteryCriticalThreshold = Self.criticalPresets.last { $0 < newLow } ?? max(1, newLow - 1)
            }
        }
        Picker("Critical battery warning", selection: $model.settings.batteryCriticalThreshold) {
            ForEach(Self.levels(Self.criticalPresets.filter { $0 < low }, keeping: critical), id: \.self) { Text("\($0)%").tag($0) }
        }
        Picker("Tell me when charged to", selection: $model.settings.batteryChargedAlert) {
            Text("Off").tag(0)
            ForEach(Self.levels([80, 85, 90, 95, 100], keeping: model.settings.batteryChargedAlert), id: \.self) { Text("\($0)%").tag($0) }
        }
    }

    static let criticalPresets = [3, 5, 8, 10, 15]

    /// The preset levels plus the current value, so a hand-edited config still shows.
    static func levels(_ presets: [Int], keeping current: Int) -> [Int] {
        Array(Set(presets + (current > 0 ? [current] : []))).sorted()
    }
}
