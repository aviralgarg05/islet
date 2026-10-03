import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Live Activities: mirroring what macOS shows in the menu bar. Whether scripts may
/// read them through the local API is in Advanced.
struct LiveActivitiesSettings: View {
    @Bindable var model: AppModel

    /// Before macOS 26 the menu bar has no Live Activities: the page says so, its switches
    /// stay off and it asks for nothing.
    private var supported: Bool { model.liveActivitiesSupported }
    private var on: Bool { supported && model.settings.mirrorMenuBarActivities }

    var body: some View {
        Form {
            Section {
                SettingsHero(page: .liveActivities, switchTitle: "Show Live Activities",
                             isOn: supported ? $model.settings.mirrorMenuBarActivities : .constant(false))
                    .disabled(!supported)
                    .settingsAnchor("live.enabled")
                if !supported {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary).font(.callout)
                        Text("Needs macOS 26 or later.").font(.callout).foregroundStyle(.secondary)
                    }
                } else if on && !model.accessibilityTrusted {
                    AccessRow(text: "Islet needs Accessibility to read the menu bar.", button: "Allow…") {
                        MediaKeyInterceptor.requestAccessibility()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            model.recheckAccessibility()
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
            MutedFromIslandSection(model: model, page: .liveActivities)
            Section("When to show them") {
                Toggle(isOn: $model.settings.mirrorOnlyHiddenActivities) {
                    Text("Only when the notch hides them")
                    Text("When the menu bar is full, macOS tucks Live Activities behind the notch. Show only those, so nothing appears twice.")
                }
                .settingsAnchor("live.hiddenOnly")
                // Covering the menu bar's own only makes sense while every activity is in the
                // island, so this switch takes over from the one above and dims it.
                .disabled(model.settings.hideMenuBarActivities)
                Toggle(isOn: $model.settings.hideMenuBarActivities) {
                    Text("Hide the menu bar’s own")
                    Text("macOS offers no way to hide them, so Islet covers each one in the menu bar with black. Every activity then shows in the island, whether or not the notch hides it.")
                }
                .settingsAnchor("live.hideOwn")
            }
            .disabled(!on)
        }
        .formStyle(.grouped)
    }
}
