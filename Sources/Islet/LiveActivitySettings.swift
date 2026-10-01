import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Live Activities: mirroring what macOS shows in the menu bar. Whether scripts may
/// read them through the local API is in Advanced.
struct LiveActivitiesSettings: View {
    @Bindable var model: AppModel
    @ViewState private var axTrusted = MenuBarLiveActivityMonitor.isAvailable

    private var on: Bool { model.settings.mirrorMenuBarActivities }

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .liveActivities, switchTitle: "Show Live Activities", isOn: $model.settings.mirrorMenuBarActivities)
                    .settingsAnchor("live.enabled")
                if on && !axTrusted {
                    AccessRow(text: "Islet needs Accessibility to read the menu bar.", button: "Allow…") {
                        MediaKeyInterceptor.requestAccessibility()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            axTrusted = MenuBarLiveActivityMonitor.isAvailable
                            model.startEventSources()
                        }
                    }
                } else if on && MenuBarLiveActivityMonitor.iPhoneActivitiesEnabled == false {
                    AccessRow(text: "This Mac is set not to show Live Activities from your iPhone, so only the Mac's own appear.",
                              button: "Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            } footer: {
                SettingsFooter("They appear with their app's icon. Clicking one opens Apple's own view of it.")
            }
            Section {
                Toggle(isOn: $model.settings.mirrorOnlyHiddenActivities) {
                    Text("Only when the notch hides them")
                    Text("When the menu bar is full, macOS tucks Live Activities behind the notch. Show only those, so nothing appears twice.")
                }
                .settingsAnchor("live.hiddenOnly")
            }
            .disabled(!on)
        }
        .formStyle(.grouped)
        .onAppear { axTrusted = MenuBarLiveActivityMonitor.isAvailable }
    }
}
