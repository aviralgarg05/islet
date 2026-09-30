import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Permissions: each macOS permission Islet can use, what uses it, whether Islet has
/// it, and a button that asks for it or opens its page in System Settings. Checked when the pane
/// appears and when Islet becomes active again (say, back from System Settings); never polled.
struct PermissionsSettings: View {
    @Bindable var model: AppModel
    @ViewState private var statuses: [PermissionKind: PermissionStatus] = [:]
    @ViewState private var visible = false
    /// Reading the Downloads folder can prompt, so it's only read once the user has asked
    /// or the downloads module (which reads it anyway) is on.
    @ViewState private var askedForDownloads = false

    var body: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, uses: kind.uses(model.settings), status: statuses[kind]) { act(on: kind) }
                }
            } footer: {
                Text("None of these is needed to run Islet. macOS asks the first time you turn on a feature that uses one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            visible = true
            refresh()
        }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if visible { refresh() }
        }
    }

    private func refresh() {
        let readDownloads = askedForDownloads || model.settings.downloadsEnabled
        for kind in PermissionKind.allCases {
            PermissionProbe.status(of: kind, readDownloads: readDownloads) { update(kind, $0) }
        }
    }

    /// A newly granted permission lets switched-on features start now rather than at next launch.
    private func update(_ kind: PermissionKind, _ status: PermissionStatus) {
        let was = statuses[kind]
        statuses[kind] = status
        if status == .granted, was != nil, was != .granted {
            NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
        }
    }

    private func act(on kind: PermissionKind) {
        switch (statuses[kind] ?? .unknown).action {
        case .openSettings:
            NSWorkspace.shared.open(kind.settingsURL)
        case .request:
            request(kind)
        case .none:
            break
        }
    }

    private func request(_ kind: PermissionKind) {
        switch kind {
        case .calendars:
            model.calendar.requestAccess { _ in calendarAnswered() }
        case .reminders:
            model.calendar.requestReminderAccess { _ in calendarAnswered() }
        default:
            if kind == .downloadsFolder { askedForDownloads = true }
            PermissionProbe.request(kind) { update(kind, $0) }
        }
    }

    private func calendarAnswered() {
        refresh()
        model.startEventSources()
        if model.settings.calendarEnabled || model.settings.remindersEnabled { model.calendar.refresh() }
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let uses: [PermissionUse]
    let status: PermissionStatus?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                ForEach(uses, id: \.feature) { use in
                    Text(use.isOn ? use.feature : "\(use.feature) (off)")
                        .font(.caption)
                        .foregroundStyle(use.isOn ? .secondary : .tertiary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            if let status, let title = buttonTitle(status) {
                Button(title, action: action).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        if let bundleID = kind.automationTarget {
            AppIconView(bundleID: bundleID, size: 22)
        } else {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch kind {
        case .accessibility: return "accessibility"
        case .calendars: return "calendar"
        case .reminders: return "checklist"
        case .downloadsFolder: return "arrow.down.circle"
        case .automationMusic, .automationSpotify: return "applescript"
        }
    }

    private var label: String {
        switch status {
        case nil: return "Checking…"
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not allowed yet"
        case .appNotRunning: return "Open \(kind == .automationMusic ? "Music" : "Spotify") to check"
        case .appNotInstalled: return "Not installed"
        case .unknown: return "Asked on first use"
        }
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        default: return Color.secondary.opacity(0.5)
        }
    }

    private func buttonTitle(_ status: PermissionStatus) -> String? {
        switch status.action {
        case .request: return "Allow…"
        case .openSettings: return "Open Settings"
        case .none: return nil
        }
    }
}
