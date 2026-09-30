import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Modules → Live Activities: mirroring what macOS shows in the menu bar.
struct LiveActivitySettingsSection: View {
    @Bindable var model: AppModel
    @ViewState private var axTrusted = MenuBarLiveActivityMonitor.isAvailable

    var body: some View {
        Section("Live Activities") {
            Toggle("Show Live Activities from the menu bar", isOn: $model.settings.mirrorMenuBarActivities)
            Text("Rides, deliveries, scores and flights from your iPhone, and Mac ones such as a running shortcut, appear in the island with their app's icon. Clicking one opens Apple's view of it.")
                .font(.caption).foregroundStyle(.secondary)
            if model.settings.mirrorMenuBarActivities {
                if !axTrusted {
                    HStack {
                        Text("Needs Accessibility to read the menu bar.").font(.caption)
                        Spacer()
                        Button("Allow…") {
                            MediaKeyInterceptor.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                axTrusted = MenuBarLiveActivityMonitor.isAvailable
                                model.startEventSources()
                            }
                        }
                    }
                } else if MenuBarLiveActivityMonitor.iPhoneActivitiesEnabled == false {
                    Text("macOS is set not to show iPhone Live Activities on this Mac, so only Mac ones will appear.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Only when the notch hides them", isOn: $model.settings.mirrorOnlyHiddenActivities)
                Text("When the menu bar is full, macOS tucks Live Activities away behind the notch. With this on, only those appear in the island, so nothing shows twice.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Let scripts read them through the local API", isOn: $model.settings.shareMirroredActivities)
                Text("They often contain addresses, names and scores. Off keeps them out of the API.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { axTrusted = MenuBarLiveActivityMonitor.isAvailable }
    }
}
