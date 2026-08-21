import PauseCore
import XCTest

final class LogicalDayTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTheLogicalDayContainingAnInstantIsItsCivilDate() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        XCTAssertEqual(
            LogicalDay.containing(now, calendar: calendar),
            CalendarDay(date: now, calendar: calendar)
        )
    }

    func testTheNextLogicalDayFollowsTheOneContainingTheInstant() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        let expected = CalendarDay(
            date: date(year: 2026, month: 8, day: 21),
            calendar: calendar
        )
        XCTAssertEqual(LogicalDay.next(after: now, calendar: calendar), expected)
    }

    func testTheNextLogicalDayCrossesAMonthBoundary() {
        let now = date(year: 2026, month: 8, day: 31, hour: 12)
        let expected = CalendarDay(
            date: date(year: 2026, month: 9, day: 1),
            calendar: calendar
        )
        XCTAssertEqual(LogicalDay.next(after: now, calendar: calendar), expected)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
