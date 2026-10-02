import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Settings → Permissions: each macOS permission Islet can use, what uses it, whether Islet has
/// it, and a button that asks for it or opens its page in System Settings. Checked when the pane
/// appears and when Islet becomes active again (say, back from System Settings); never polled.
/// Closing the Settings window doesn't make SwiftUI call `onDisappear` (or `onAppear` on reopening),
/// so the window's own visibility gates the checks, and it becoming key counts as appearing.
struct PermissionsSettings: View {
    @Bindable var model: AppModel
    @ViewState private var statuses: [PermissionKind: PermissionStatus] = [:]
    @ViewState private var visible = false
    @ViewState private var host = HostWindow.Box()
    /// Reading the Downloads folder can prompt, so it's only read once the user has asked
    /// or the downloads module (which reads it anyway) is on.
    @ViewState private var askedForDownloads = false
    @Environment(\.snapshotMode) private var snapshotMode

    private var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    var body: some View {
        Form {
            Section { SettingsHero(page: .permissions) }
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, uses: kind.uses(model.settings, osMajor: osMajor), status: status(of: kind),
                                  label: label(for: kind), hint: hint(for: kind),
                                  note: kind.note(osMajor: osMajor, status: status(of: kind))) { act(on: kind) }
                        .settingsAnchor("permissions.\(kind.rawValue)")
                }
            } footer: {
                SettingsFooter("macOS asks the first time you turn on a feature that uses one, or when you press Allow here.")
            }
        }
        .formStyle(.grouped)
        .background(HostWindow(box: host))
        .onAppear {
            visible = true
            refresh()
        }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshIfShown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = host.window, note.object as? NSWindow === window { refreshIfShown() }
        }
    }

    /// Check again only while this is the selected tab of a Settings window that is on screen.
    private func refreshIfShown() {
        if visible, host.window?.isVisible == true { refresh() }
    }

    private func refresh() {
        // Calendars and reminders come from the model, which starts them as access arrives.
        // (Snapshots draw the access they were given.)
        if !snapshotMode { model.recheckCalendarAccess() }
        let readDownloads = askedForDownloads || model.settings.downloadsEnabled
        for kind in PermissionKind.allCases where !Self.isCalendar(kind) {
            PermissionProbe.status(of: kind, readDownloads: readDownloads) { update(kind, $0) }
        }
    }

    private static func isCalendar(_ kind: PermissionKind) -> Bool { kind == .calendars || kind == .reminders }

    private func status(of kind: PermissionKind) -> PermissionStatus? {
        switch kind {
        case .calendars: return .calendar(model.calendarAccess.events, refused: model.calendarRefused.contains(.calendars))
        case .reminders: return .calendar(model.calendarAccess.reminders, refused: model.calendarRefused.contains(.reminders))
        default: return statuses[kind]
        }
    }

    /// The status in a few words; for calendars and reminders, what the Calendar page says.
    private func label(for kind: PermissionKind) -> String {
        Self.isCalendar(kind) ? model.calendarAdvice(kind).status : kind.statusLabel(status(of: kind))
    }

    /// For calendars and reminders that aren't allowed: what to switch in System Settings.
    private func hint(for kind: PermissionKind) -> String? {
        guard Self.isCalendar(kind) else { return nil }
        let advice = model.calendarAdvice(kind)
        return advice.action == .ask || advice.isAllowed ? nil : advice.detail
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
        if Self.isCalendar(kind) {
            // Asks macOS when it hasn't; otherwise opens the right page of System Settings.
            model.requestCalendarAccess(kind, turnOn: false) { refresh() }
            return
        }
        switch (statuses[kind] ?? .unknown).action {
        case .openSettings:
            NSWorkspace.shared.open(kind.settingsURL)
        case .request:
            request(kind)
        case .openApp:
            openApp(for: kind)
        case .none:
            break
        }
    }

    /// Automation can only be checked while the app is open: open it. The app comes to the
    /// front, and the row checks again when Islet does.
    private func openApp(for kind: PermissionKind) {
        guard let bundleID = kind.automationTarget,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func request(_ kind: PermissionKind) {
        if kind == .downloadsFolder { askedForDownloads = true }
        PermissionProbe.request(kind) { update(kind, $0) }
    }
}

/// Keeps track of the window a view is in, without holding on to it.
private struct HostWindow: NSViewRepresentable {
    final class Box { weak var window: NSWindow? }
    let box: Box

    func makeNSView(context: Context) -> NSView { Probe(box: box) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        let box: Box
        init(box: Box) {
            self.box = box
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box.window = window
        }
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let uses: [PermissionUse]
    let status: PermissionStatus?
    /// The status in a few words (`PermissionKind.statusLabel`, or the Calendar page's words).
    let label: String
    /// One line on what to switch in System Settings.
    var hint: String?
    /// What the permission lets Islet do, in plain words (`PermissionKind.note`).
    var note: String?
    let action: () -> Void

    /// Wide enough for "Open System Settings", so every row's status ends at the same place.
    private static let buttonColumn: CGFloat = 164
    /// The text under the title starts where the title does.
    private static let inset: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                icon.frame(width: 22, height: 22)
                Text(kind.title).layoutPriority(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(label).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if let status, let title = kind.buttonTitle(status) {
                        Button(title, action: action)
                    }
                }
                .frame(width: Self.buttonColumn, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(uses, id: \.feature) { use in
                    Text(use.isOn ? use.feature : "\(use.feature) (off)")
                        .font(.caption)
                        .foregroundStyle(use.isOn ? .secondary : .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    // Secondary, not the tertiary of a feature that is off: it explains, it isn't an item.
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.leading, Self.inset)
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
        case .location: return "location.fill"
        case .camera: return "camera"
        case .downloadsFolder: return "arrow.down.circle"
        case .automationMusic, .automationSpotify: return "applescript"
        }
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied, .writeOnly, .restricted: return .orange
        default: return Color.secondary.opacity(0.5)
        }
    }
}
