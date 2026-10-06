import AppKit
import CasementCore
import CasementSystem
import SwiftUI

/// Today with the month calendar on: the month on the left, the picked day's events beside it,
/// and the reminders in a column of their own when the island is wide enough (under the day's
/// events otherwise).
struct TodayWithMonth: View {
    let model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    /// Wide enough for the reminders to have their own column.
    static let threeColumnWidth: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let gridWidth = min(196, max(140, (geo.size.width * 0.33).rounded()))
            let separateReminders = geo.size.width >= Self.threeColumnWidth && model.settings.remindersEnabled
            HStack(alignment: .top, spacing: 0) {
                MonthGridView(model: model, height: h)
                    .frame(width: gridWidth, height: h, alignment: .top)
                ColumnRule().frame(height: h).padding(.horizontal, Space.l)
                MonthDayColumn(model: model, height: h, includesReminders: !separateReminders)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if separateReminders {
                    ColumnRule().frame(height: h).padding(.horizontal, Space.l)
                    TodayReminders(model: model, height: h)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        // Opening Today starts from this month and today, whatever was picked last time.
        .onAppear { if !snapshotMode { model.tools.month.appeared(model) } }
        // New, moved or deleted events (the agenda follows the calendar store).
        .onChange(of: model.agenda) { _, _ in if !snapshotMode { model.tools.month.load(model, force: true) } }
    }
}

/// The month: its name with arrows to the months either side, the weekdays, and the days.
/// Days with an event are bright, the rest quiet; today is filled red; a picked day is circled.
struct MonthGridView: View {
    let model: AppModel
    let height: CGFloat

    private static let header: CGFloat = 16
    private static let weekdayRow: CGFloat = 12
    /// Rows closer than this and the digits touch, and today's circle meets the date below.
    static let minimumCell: CGFloat = 13

    /// The height of a row of days, and whether the weekday letters fit above them: they give
    /// way first when the island is too short for every week at `minimumCell`.
    static func layout(height: CGFloat, weeks: Int) -> (cell: CGFloat, weekdays: Bool) {
        let rows = CGFloat(max(weeks, 1))
        let full = (height - header - weekdayRow - Space.xs) / rows
        if full >= minimumCell { return (min(20, full), true) }
        return (max(10, min(20, (height - header) / rows)), false)
    }

    var body: some View {
        let month = model.tools.month
        let grid = month.grid(model)
        let layout = Self.layout(height: height, weeks: grid.weeks.count)
        let cell = layout.cell
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { month.today(model) } label: {
                    Text(grid.title)
                        .textStyle(.caption, emphasized: true)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Today")
                Spacer(minLength: Space.xs)
                IconButton(symbol: "chevron.left", help: "Previous month", size: 18, glyph: 9, ink: Ink.tertiary) {
                    month.show(monthsFrom: -1, model)
                }
                IconButton(symbol: "chevron.right", help: "Next month", size: 18, glyph: 9, ink: Ink.tertiary) {
                    month.show(monthsFrom: 1, model)
                }
            }
            .frame(height: Self.header)
            if layout.weekdays {
                HStack(spacing: 0) {
                    ForEach(Array(grid.weekdays.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Ink.quaternary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.weekdayRow)
                .padding(.top, Space.xs)
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Group {
                            if let day = week[i] { DayCell(day: day, size: cell) { month.select(day.date) } } else { Color.clear }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: cell)
            }
        }
    }
}

private struct DayCell: View {
    let day: MonthDay
    let size: CGFloat
    var pick: () -> Void

    var body: some View {
        let font = min(11, (size * 0.8).rounded())
        Button(action: pick) {
            Text("\(day.number)")
                .font(.system(size: font, weight: day.isToday || day.hasEvents ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? Color.white : day.hasEvents ? Ink.primary : Ink.tertiary)
                // No taller than the row, so today's circle never meets the date below.
                .frame(width: size + 3, height: size)
                .background {
                    if day.isToday {
                        Circle().fill(Color.red)
                    } else if day.isSelected {
                        Circle().fill(Wash.strong)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + (day.hasEvents ? ", has events" : ""))
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
    }
}

/// The picked day's events (the rest of today when none is picked), then today's reminders
/// when they don't have their own column.
struct MonthDayColumn: View {
    let model: AppModel
    let height: CGFloat
    var includesReminders: Bool
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let now = Date()
        let picked = model.tools.month.selected
        let events = model.tools.month.events
        let (timed, allDay) = picked.map { Agenda.on($0, Agenda.visible(events, hiding: Set(model.settings.hiddenCalendars))) }
            ?? Agenda.restOfToday(model.visibleAgenda, now: now)
        let reminders = includesReminders && picked == nil ? model.dueReminders : []
        let lines = timed.count + reminders.count + (allDay.isEmpty ? 0 : 1)
        // Snapshots can't scroll, so they show the lines that fit.
        let fit = Self.fitting(height: height, allDay: !allDay.isEmpty, timed: timed.count, reminders: reminders.count)
        VStack(alignment: .leading, spacing: Space.xs) {
            // No count beside it: after a date ("Wed, 14 Oct"), or "Today" on the 2nd, a number
            // reads as part of the date. The events are listed right under it.
            SectionLabel(title: picked.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "Today")
                .frame(height: 16)
            if !(model.settings.calendarEnabled && model.calendarAccess.events.canRead) {
                // Off, or macOS not letting Casement read it: what is wrong, and the button that helps.
                let advice = model.calendarAdvice(.calendars)
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(advice.isAllowed || advice.action == .ask ? "Your events, with a Join button for calls." : advice.detail ?? advice.status)
                        .textStyle(.body).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(advice.isAllowed ? "Turn on" : advice.action == .ask ? "Allow Calendar" : advice.button ?? "Open System Settings") {
                        model.requestCalendarAccess(.calendars)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
                }
            } else if lines == 0 {
                Text(picked == nil ? "Nothing else today" : "Nothing on this day").textStyle(.body).foregroundStyle(Ink.tertiary)
            } else {
                AdaptiveScroll(scrolls: CGFloat(lines) * (TodayTab.rowHeight + Space.s) > height - 20) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        if !allDay.isEmpty {
                            HStack(spacing: Space.s) {
                                Circle().fill(Color(tint: allDay[0].calendarColor, fallback: .blue)).frame(width: 5, height: 5).frame(width: 3)
                                Text(allDay.map(\.title).joined(separator: ", ")).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                            }
                            .frame(height: TodayTab.allDayHeight)
                        }
                        ForEach(timed.prefix(snapshotMode ? fit.timed : 30)) { e in AgendaLine(item: e, now: now) { model.join(e) } }
                        if !reminders.isEmpty && (!snapshotMode || fit.reminders > 0) {
                            SectionLabel(title: "Reminders", count: reminders.count).frame(height: 16)
                            ForEach(reminders.prefix(snapshotMode ? fit.reminders : 30)) { r in
                                ReminderLine(item: r, now: now) { model.completeReminder(r.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension MonthDayColumn {
    /// How many events, then reminders (with their label), fit under the day's label.
    static func fitting(height: CGFloat, allDay: Bool, timed: Int, reminders: Int) -> (timed: Int, reminders: Int) {
        let row = TodayTab.rowHeight + Space.s
        var room = height - 16 - Space.xs + Space.s - (allDay ? TodayTab.allDayHeight + Space.s : 0)
        let t = min(timed, max(0, Int(room / row)))
        room -= CGFloat(t) * row
        let label: CGFloat = 16 + Space.s
        let r = room >= label + row ? min(reminders, Int((room - label) / row)) : 0
        return (t, r)
    }
}

/// Today's reminders in their own column (on a wide island).
struct TodayReminders: View {
    let model: AppModel
    let height: CGFloat
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let now = Date()
        let reminders = model.dueReminders
        let fit = TodayTab.rows(in: height)
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title: "Reminders", count: reminders.count).frame(height: 16)
            if !model.calendarAccess.reminders.canRead {
                let advice = model.calendarAdvice(.reminders)
                Button(advice.action == .ask ? "Allow Reminders" : advice.button ?? "Open System Settings") {
                    model.requestCalendarAccess(.reminders)
                }
                .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
            } else if reminders.isEmpty {
                Text("All done").textStyle(.body).foregroundStyle(Ink.tertiary)
            } else {
                AdaptiveScroll(scrolls: reminders.count > fit) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(reminders.prefix(snapshotMode ? fit : 30)) { r in
                            ReminderLine(item: r, now: now) { model.completeReminder(r.id) }
                        }
                    }
                }
            }
        }
    }
}
