import Foundation

/// One day in the month calendar on the Today page.
public struct MonthDay: Equatable, Sendable, Identifiable {
    /// The start of the day.
    public var date: Date
    /// 1...31.
    public var number: Int
    public var isToday: Bool
    /// An event (from a shown calendar) touches this day.
    public var hasEvents: Bool
    public var isSelected: Bool

    public var id: Date { date }
}

/// A month laid out in weeks, starting on the region's first weekday. Days from the months
/// either side are left blank, so only this month's numbers show.
public struct MonthGrid: Equatable, Sendable {
    /// The first day of the month.
    public var month: Date
    /// "October 2026" (or "October" for this year's months when asked for).
    public var title: String
    /// One or two letters per weekday, in the order of the columns.
    public var weekdays: [String]
    /// Rows of seven; nil for the blank days before the 1st and after the last.
    public var weeks: [[MonthDay?]]

    /// The month that holds `date`. `selected` marks a chosen day; `eventDays` are starts of days.
    public static func make(containing date: Date, today: Date, selected: Date? = nil, eventDays: Set<Date> = [],
                            calendar: Calendar = .current, locale: Locale = .current) -> MonthGrid {
        let first = startOfMonth(date, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [MonthDay?] = Array(repeating: nil, count: lead)
        for n in 1...count {
            guard let day = calendar.date(byAdding: .day, value: n - 1, to: first) else { continue }
            cells.append(MonthDay(date: day, number: n, isToday: calendar.isDate(day, inSameDayAs: today),
                                  hasEvents: eventDays.contains(day),
                                  isSelected: selected.map { calendar.isDate(day, inSameDayAs: $0) } ?? false))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }

        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(first, equalTo: today, toGranularity: .year) ? "LLLL" : "LLLL y")
        var symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        if symbols.count == 7 {
            let start = max(0, min(6, calendar.firstWeekday - 1))
            symbols = Array(symbols[start...] + symbols[..<start])
        }
        return MonthGrid(month: first, title: f.string(from: first), weekdays: symbols, weeks: weeks)
    }

    public static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// The first day of the month `months` away from the one holding `date`.
    public static func shifted(_ date: Date, by months: Int, calendar: Calendar = .current) -> Date {
        let first = startOfMonth(date, calendar: calendar)
        return calendar.date(byAdding: .month, value: months, to: first) ?? first
    }

    /// From the 1st to the start of the next month: the events to read for a month.
    public static func interval(of date: Date, calendar: Calendar = .current) -> DateInterval {
        let first = startOfMonth(date, calendar: calendar)
        let next = calendar.date(byAdding: .month, value: 1, to: first) ?? first.addingTimeInterval(31 * 86_400)
        return DateInterval(start: first, end: next)
    }

    /// The month's days with an event, as starts of days. An event touches every day it covers;
    /// one ending exactly at midnight doesn't reach the next day.
    public static func eventDays(_ items: [AgendaItem], in interval: DateInterval, calendar: Calendar = .current) -> Set<Date> {
        var days: Set<Date> = []
        for item in items {
            // A moment-long event counts on the day it happens.
            let itemEnd = item.end > item.start ? item.end : item.start.addingTimeInterval(1)
            let start = max(item.start, interval.start)
            let end = min(itemEnd, interval.end)
            guard start < end else { continue }
            var day = calendar.startOfDay(for: start)
            while day < end {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }
}

extension Agenda {
    /// What happens on `day`: timed events in order, and all-day ones, each touching the day.
    public static func on(_ day: Date, _ items: [AgendaItem], calendar: Calendar = .current) -> (timed: [AgendaItem], allDay: [AgendaItem]) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let touching = items.filter { $0.start < end && ($0.end > start || $0.start == $0.end && $0.start >= start) }
        return (touching.filter { !$0.isAllDay }.sorted { $0.start < $1.start },
                touching.filter(\.isAllDay).sorted { $0.title < $1.title })
    }
}
