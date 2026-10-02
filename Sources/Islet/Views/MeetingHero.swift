import AppKit
import IsletCore
import SwiftUI

/// Home while a meeting reminder is on show: the meeting, when it starts, and a large Join
/// button. Join opens the call and counts as joining; the quiet × dismisses the reminder.
struct MeetingHero: View {
    let model: AppModel
    let reminder: MeetingReminder

    var body: some View {
        let item = reminder.item
        let tint = Color(tint: item.calendarColor, fallback: .blue)
        // Ticks when the rounded-up minutes change, and counts from now rather than from the
        // tick, so the hero says what the wing and the sneak peek say ("9 min").
        TimelineView(.periodic(from: Format.minuteAnchor(for: item.start, now: Date()), by: 60)) { _ in
            let now = Date()
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    IconView(icon: MeetingReminders.icon(for: reminder, installed: AppActions.isInstalled), size: 24, tint: tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(item.title).textStyle(.title).foregroundStyle(Ink.primary).lineLimit(2)
                        Text(Self.when(reminder, now: now))
                            .textStyle(.body, numeric: true)
                            .foregroundStyle(reminder.phase == .now ? Color.green : Ink.secondary)
                            .lineLimit(1)
                    }
                    .spokenGroup(item.title, value: SpokenText.when(
                        start: item.start, now: now, ongoing: reminder.phase != .soon,
                        startText: item.start.formatted(date: .omitted, time: .shortened),
                        endText: item.end.formatted(date: .omitted, time: .shortened)))
                    Spacer(minLength: Space.s)
                    DismissButton { model.remove(activityID: reminder.id) }
                }
                HStack(spacing: Space.s) {
                    if item.meetingURL != nil {
                        Button { model.join(item) } label: {
                            Label("Join", systemImage: "video.fill")
                        }
                        .buttonStyle(LargeCapsuleButtonStyle(tint: .green))
                        .help(reminder.app.map { $0 == .other ? "Open the call" : "Open in \($0.name)" } ?? "Open the call")
                        if let app = reminder.app, app != .other {
                            Text(app.name).textStyle(.caption).foregroundStyle(Ink.tertiary)
                        }
                    } else {
                        Button("Got it") { model.remove(activityID: reminder.id) }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
            }
        }
    }

    /// "In 9 min · 10:00" before it starts, then "Now · until 10:30".
    static func when(_ r: MeetingReminder, now: Date) -> String {
        let time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        return r.phase == .soon ? "In \(r.trailing(now: now)) · \(time(r.item.start))" : "Now · until \(time(r.item.end))"
    }
}

/// The one big action on a page (Join): a filled capsule, taller than `CapsuleButtonStyle`.
struct LargeCapsuleButtonStyle: ButtonStyle {
    var tint: Color
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.headline.font())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, Space.xl)
            .frame(height: 32)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.62 : hovering ? 0.95 : 0.82)))
            .contrastEdge(Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.settle, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
