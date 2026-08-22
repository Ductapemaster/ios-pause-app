import Foundation

/// The single place that decides which allowance day an instant belongs to.
///
/// An allowance day begins at the configured reset and runs twenty-four hours,
/// and is named for the civil date it begins on. Session counting and deferred
/// rule changes both ask this type, which is what keeps a rule change and the
/// allowance reset it arrives with on the same instant.
public enum LogicalDay {
    public static func containing(
        _ date: Date,
        resetMinuteOfDay: Int,
        calendar: Calendar
    ) -> CalendarDay {
        // Shifting the instant back by the reset offset turns "which period is
        // this in" into "what civil date is this", which the calendar answers
        // across month, year and leap boundaries without special cases.
        let shifted = date.addingTimeInterval(-Double(resetMinuteOfDay) * 60)
        return CalendarDay(date: shifted, calendar: calendar)
    }

    public static func next(
        after date: Date,
        resetMinuteOfDay: Int,
        calendar: Calendar
    ) -> CalendarDay {
        let shifted = date.addingTimeInterval(-Double(resetMinuteOfDay) * 60)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: shifted) ?? shifted
        return CalendarDay(date: tomorrow, calendar: calendar)
    }
}
