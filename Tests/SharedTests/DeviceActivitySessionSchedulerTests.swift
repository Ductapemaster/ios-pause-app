import DeviceActivity
import Foundation
import PauseCore
import XCTest

@MainActor
final class DeviceActivitySessionSchedulerTests: XCTestCase {
    private let ruleID = UUID(uuidString: "1e40b451-cf53-42de-b785-b8c863c16a79")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testExactlyFifteenMinutesUsesExactWholeSecondExpiry() throws {
        let startsAt = date(2026, 8, 19, 10, 4, 23)
        let expiresAt = startsAt.addingTimeInterval(15 * 60)
        var registered: (DeviceActivityName, DeviceActivitySchedule)?
        let scheduler = makeScheduler(callbackDate: expiresAt) { name, schedule in
            registered = (name, schedule)
        }

        let activityName = try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)

        XCTAssertEqual(activityName, SessionActivityName.sessionActivityName(for: ruleID))
        XCTAssertEqual(registered?.0.rawValue, activityName)
        XCTAssertEqual(registered?.1.intervalStart.second, 23)
        XCTAssertEqual(registered?.1.intervalEnd.second, 23)
        XCTAssertEqual(registered?.1.intervalEnd.minute, 19)
        XCTAssertNil(registered?.1.warningTime)
    }

    func testShortSessionCrossingMidnightPlacesWarningAtRecordedExpiry() throws {
        let startsAt = date(2026, 8, 19, 23, 58, 45)
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var schedule: DeviceActivitySchedule?
        let scheduler = makeScheduler(callbackDate: expiresAt) { _, captured in schedule = captured }

        _ = try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)

        XCTAssertEqual(schedule?.intervalStart.day, 19)
        XCTAssertEqual(schedule?.intervalEnd.day, 20)
        XCTAssertEqual(schedule?.intervalEnd.hour, 0)
        XCTAssertEqual(schedule?.intervalEnd.minute, 13)
        XCTAssertEqual(schedule?.intervalEnd.second, 45)
        XCTAssertEqual(schedule?.warningTime, DateComponents(minute: 10))
    }

    func testSpringForwardUsesAbsoluteDatesWithoutShorteningSession() throws {
        let startsAt = isoDate("2026-03-08T01:58:30-08:00")
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var schedule: DeviceActivitySchedule?
        let scheduler = makeScheduler(callbackDate: expiresAt) { _, captured in schedule = captured }

        _ = try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)

        XCTAssertEqual(schedule?.intervalStart.hour, 1)
        XCTAssertEqual(schedule?.intervalStart.minute, 58)
        XCTAssertEqual(schedule?.intervalEnd.hour, 3)
        XCTAssertEqual(schedule?.intervalEnd.minute, 13)
        XCTAssertEqual(schedule?.warningTime, DateComponents(minute: 10))
    }

    func testFallBackAmbiguityFailsBlockedWhenResolvedCallbackIsEarly() {
        let startsAt = isoDate("2026-11-01T01:58:30-07:00")
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var registrationCount = 0
        let scheduler = makeScheduler(callbackDate: expiresAt.addingTimeInterval(-60 * 60)) { _, _ in
            registrationCount += 1
        }

        XCTAssertThrowsError(try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)) {
            XCTAssertEqual($0 as? SessionSchedulingError, .unrepresentableExpiry)
        }
        XCTAssertEqual(registrationCount, 0)
    }

    func testAnyEarlyCallbackIsRejectedBeforeRegistration() {
        let startsAt = date(2026, 8, 19, 10, 4, 23)
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var registrationCount = 0
        let scheduler = makeScheduler(callbackDate: expiresAt.addingTimeInterval(-0.001)) { _, _ in
            registrationCount += 1
        }

        XCTAssertThrowsError(try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)) {
            XCTAssertEqual($0 as? SessionSchedulingError, .unrepresentableExpiry)
        }
        XCTAssertEqual(registrationCount, 0)
    }

    func testCallbackMoreThanFiveSecondsLateIsRejectedBeforeRegistration() {
        let startsAt = date(2026, 8, 19, 10, 4, 23)
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var registrationCount = 0
        let scheduler = makeScheduler(callbackDate: expiresAt.addingTimeInterval(5.001)) { _, _ in
            registrationCount += 1
        }

        XCTAssertThrowsError(try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)) {
            XCTAssertEqual($0 as? SessionSchedulingError, .unrepresentableExpiry)
        }
        XCTAssertEqual(registrationCount, 0)
    }

    func testRegistrationErrorIsPropagated() {
        let startsAt = date(2026, 8, 19, 10, 4, 23)
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        let scheduler = makeScheduler(callbackDate: expiresAt) { _, _ in throw SchedulerTestError.start }

        XCTAssertThrowsError(try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)) {
            XCTAssertEqual($0 as? SchedulerTestError, .start)
        }
    }

    func testStopErrorIsPropagated() {
        let scheduler = DeviceActivitySessionScheduler(
            calendar: calendar,
            resolvedCallbackDate: { _, _ in nil },
            startMonitoring: { _, _ in },
            stopMonitoring: { _ in throw SchedulerTestError.stop }
        )

        XCTAssertThrowsError(try scheduler.stop(activityName: "session.test")) {
            XCTAssertEqual($0 as? SchedulerTestError, .stop)
        }
    }

    private func makeScheduler(
        callbackDate: Date,
        start: @escaping (DeviceActivityName, DeviceActivitySchedule) throws -> Void
    ) -> DeviceActivitySessionScheduler {
        DeviceActivitySessionScheduler(
            calendar: calendar,
            resolvedCallbackDate: { _, _ in callbackDate },
            startMonitoring: start,
            stopMonitoring: { _ in }
        )
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private enum SchedulerTestError: Error, Equatable {
    case start
    case stop
}
