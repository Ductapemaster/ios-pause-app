import PauseCore
import XCTest

final class LogicalDayTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTheLogicalDayContainingAnInstantIsItsCivilDate() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        XCTAssertEqual(
            LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
            CalendarDay(date: now, calendar: calendar)
        )
    }

    func testTheNextLogicalDayFollowsTheOneContainingTheInstant() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        let expected = CalendarDay(
            date: date(year: 2026, month: 8, day: 21),
            calendar: calendar
        )
        XCTAssertEqual(
            LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: calendar),
            expected
        )
    }

    func testTheNextLogicalDayCrossesAMonthBoundary() {
        let now = date(year: 2026, month: 8, day: 31, hour: 12)
        let expected = CalendarDay(
            date: date(year: 2026, month: 9, day: 1),
            calendar: calendar
        )
        XCTAssertEqual(
            LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: calendar),
            expected
        )
    }

    /// A fixed calendar so these read the same wherever they run.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.date(from: iso)!
    }

    func testBeforeTheResetTheInstantBelongsToYesterday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T05:59:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-09T12:00:00Z"), calendar: utc))
    }

    func testAtTheResetTheInstantBelongsToToday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T06:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testAfterTheResetTheInstantBelongsToToday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T23:59:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testMidnightResetMatchesTheCivilDate() {
        let day = LogicalDay.containing(
            instant("2026-03-10T00:00:00Z"),
            resetMinuteOfDay: 0,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testCrossingAMonthBoundaryBackwards() {
        let day = LogicalDay.containing(
            instant("2026-04-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-31T12:00:00Z"), calendar: utc))
    }

    func testCrossingAYearBoundaryBackwards() {
        let day = LogicalDay.containing(
            instant("2026-01-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2025-12-31T12:00:00Z"), calendar: utc))
    }

    func testCrossingALeapDayBackwards() {
        let day = LogicalDay.containing(
            instant("2028-03-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2028-02-29T12:00:00Z"), calendar: utc))
    }

    func testNextIsTheDayAfterTheOneContainingTheInstant() {
        let day = LogicalDay.next(
            after: instant("2026-03-10T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
