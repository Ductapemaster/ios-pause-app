import Foundation

/// The single place that decides which logical day an instant belongs to.
///
/// Phase 1 resets at midnight, so a logical day is a civil date. Phase 2 makes
/// the reset time configurable per weekday, and changes it here rather than at
/// every call site. Session counting and deferred rule changes both ask this
/// type, which is what keeps a rule change and the allowance reset it arrives
/// with on the same instant.
public enum LogicalDay {
    public static func containing(_ date: Date, calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(date: date, calendar: calendar)
    }

    public static func next(after date: Date, calendar: Calendar = .current) -> CalendarDay {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return containing(tomorrow, calendar: calendar)
    }
}
