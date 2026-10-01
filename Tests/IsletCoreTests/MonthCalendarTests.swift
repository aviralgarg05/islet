import Foundation
import Testing
@testable import IsletCore

@Suite struct MonthCalendarTests {
    /// Gregorian in London, weeks starting on Monday (or Sunday).
    func calendar(firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.firstWeekday = firstWeekday
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func octoberStartsOnThursdayInAMondayWeek() {
        let c = calendar()
        let today = date(2026, 10, 1, 9, in: c)
        let g = MonthGrid.make(containing: today, today: today, calendar: c, locale: Locale(identifier: "en_GB"))
        #expect(g.title == "October")
        #expect(g.weekdays == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(g.weeks.count == 5)
        #expect(g.weeks[0].map { $0?.number } == [nil, nil, nil, 1, 2, 3, 4])
        #expect(g.weeks[4].map { $0?.number } == [26, 27, 28, 29, 30, 31, nil])
        #expect(g.weeks.allSatisfy { $0.count == 7 })
        let first = g.weeks[0][3]
        #expect(first?.isToday == true)
        #expect(g.weeks.joined().compactMap { $0 }.filter(\.isToday).count == 1)
        #expect(g.month == date(2026, 10, 1, in: c))
    }

    @Test func sundayWeeksAndOtherYearsShowTheYear() {
        let c = calendar(firstWeekday: 1)
        let today = date(2026, 10, 1, in: c)
        let g = MonthGrid.make(containing: date(2027, 2, 14, in: c), today: today, calendar: c, locale: Locale(identifier: "en_US"))
        #expect(g.title == "February 2027")
        #expect(g.weekdays == ["S", "M", "T", "W", "T", "F", "S"])
        // 1 February 2027 is a Monday.
        #expect(g.weeks[0].map { $0?.number } == [nil, 1, 2, 3, 4, 5, 6])
        #expect(g.weeks.joined().compactMap { $0 }.count == 28)
        #expect(!g.weeks.joined().contains { $0?.isToday == true })
    }

    @Test func sixWeekMonths() {
        let c = calendar()
        // 1 August 2026 is a Saturday: 31 days need six Monday weeks.
        let g = MonthGrid.make(containing: date(2026, 8, 20, in: c), today: date(2026, 10, 1, in: c), calendar: c)
        #expect(g.weeks.count == 6)
    }

    @Test func marksSelectedDaysAndDaysWithEvents() {
        let c = calendar()
        let today = date(2026, 10, 1, in: c)
        let interval = MonthGrid.interval(of: today, calendar: c)
        let items = [
            AgendaItem(id: "a", title: "Stand-up", start: date(2026, 10, 5, 9, in: c), end: date(2026, 10, 5, 9, 15, in: c)),
            // Late night into the next morning: both days.
            AgendaItem(id: "b", title: "Flight", start: date(2026, 10, 9, 23, in: c), end: date(2026, 10, 10, 6, in: c)),
            // An all-day event ends at midnight: one day, not two.
            AgendaItem(id: "c", title: "Holiday", start: date(2026, 10, 20, in: c), end: date(2026, 10, 21, in: c), isAllDay: true),
            // Starts last month, ends on the 2nd.
            AgendaItem(id: "d", title: "Trip", start: date(2026, 9, 28, in: c), end: date(2026, 10, 2, 12, in: c)),
            // Next month: not in this one.
            AgendaItem(id: "e", title: "Later", start: date(2026, 11, 3, 9, in: c), end: date(2026, 11, 3, 10, in: c)),
            // A reminder-like moment with no length.
            AgendaItem(id: "f", title: "Moment", start: date(2026, 10, 30, 12, in: c), end: date(2026, 10, 30, 12, in: c)),
        ]
        let days = MonthGrid.eventDays(items, in: interval, calendar: c)
        let numbers = Set(days.map { c.component(.day, from: $0) })
        #expect(numbers == [1, 2, 5, 9, 10, 20, 30])
        let g = MonthGrid.make(containing: today, today: today, selected: date(2026, 10, 9, 15, in: c), eventDays: days, calendar: c)
        let cells = g.weeks.joined().compactMap { $0 }
        #expect(cells.filter(\.hasEvents).map(\.number) == [1, 2, 5, 9, 10, 20, 30])
        #expect(cells.filter(\.isSelected).map(\.number) == [9])
    }

    @Test func movesBetweenMonths() {
        let c = calendar()
        let jan31 = date(2026, 1, 31, 15, in: c)
        #expect(MonthGrid.shifted(jan31, by: 1, calendar: c) == date(2026, 2, 1, in: c))
        #expect(MonthGrid.shifted(jan31, by: -1, calendar: c) == date(2025, 12, 1, in: c))
        #expect(MonthGrid.interval(of: jan31, calendar: c) == DateInterval(start: date(2026, 1, 1, in: c), end: date(2026, 2, 1, in: c)))
    }

    @Test func aDaysEventsAreThoseTouchingIt() {
        let c = calendar()
        let items = [
            AgendaItem(id: "late", title: "Late", start: date(2026, 10, 9, 23, in: c), end: date(2026, 10, 10, 6, in: c)),
            AgendaItem(id: "early", title: "Early", start: date(2026, 10, 10, 8, in: c), end: date(2026, 10, 10, 9, in: c)),
            AgendaItem(id: "allday", title: "Holiday", start: date(2026, 10, 10, in: c), end: date(2026, 10, 11, in: c), isAllDay: true),
            AgendaItem(id: "next", title: "Next", start: date(2026, 10, 11, 0, in: c), end: date(2026, 10, 11, 1, in: c)),
        ]
        let day = Agenda.on(date(2026, 10, 10, 14, in: c), items, calendar: c)
        #expect(day.timed.map(\.id) == ["late", "early"])
        #expect(day.allDay.map(\.id) == ["allday"])
    }

    @Test func monthCalendarStartsOff() {
        #expect(IsletSettings().monthCalendar == false)
    }
}

@Suite struct MonthCalendarStateTests {
    func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.firstWeekday = 2
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func startsOnThisMonthWithNothingPicked() {
        let c = calendar()
        let s = MonthCalendarState(now: date(2026, 10, 14, 9, in: c), calendar: c)
        #expect(s.month == date(2026, 10, 1, in: c))
        #expect(s.selected == nil)
    }

    @Test func openingTodayAgainCatchesUpWithTheClock() {
        // Left on 30 September with a day picked; opened again on 1 October.
        let c = calendar()
        var s = MonthCalendarState(now: date(2026, 9, 30, 23, in: c), calendar: c)
        s.pick(date(2026, 9, 12, in: c), now: date(2026, 9, 30, 23, in: c), calendar: c)
        #expect(s.selected == date(2026, 9, 12, in: c))
        s.reset(now: date(2026, 10, 1, 8, in: c), calendar: c)
        #expect(s.month == date(2026, 10, 1, in: c))
        #expect(s.selected == nil)
    }

    @Test func aPickedDayGoesWithItsMonth() {
        // The right-hand column reads the shown month's events, so a day from another month
        // can't stay picked (it would say "Nothing on this day" when it has events).
        let c = calendar()
        let now = date(2026, 10, 1, 9, in: c)
        var s = MonthCalendarState(now: now, calendar: c)
        s.pick(date(2026, 10, 14, 15, in: c), now: now, calendar: c)
        #expect(s.selected == date(2026, 10, 14, in: c))
        s.shift(by: 1, calendar: c)
        #expect(s.month == date(2026, 11, 1, in: c))
        #expect(s.selected == nil)
        s.shift(by: -2, calendar: c)
        #expect(s.month == date(2026, 9, 1, in: c))
    }

    @Test func pickingTodayOrThePickedDayAgainGoesBackToToday() {
        let c = calendar()
        let now = date(2026, 10, 1, 9, in: c)
        var s = MonthCalendarState(now: now, calendar: c)
        s.pick(date(2026, 10, 1, 18, in: c), now: now, calendar: c)
        #expect(s.selected == nil)
        s.pick(date(2026, 10, 20, in: c), now: now, calendar: c)
        s.pick(date(2026, 10, 20, 12, in: c), now: now, calendar: c)
        #expect(s.selected == nil)
    }
}
