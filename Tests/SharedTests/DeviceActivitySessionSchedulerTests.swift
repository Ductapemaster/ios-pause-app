import DeviceActivity
import Foundation
import PauseCore
import XCTest

final class DeviceActivitySessionSchedulerTests: XCTestCase {
    private let ruleID = UUID(uuidString: "1e40b451-cf53-42de-b785-b8c863c16a79")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testLongSessionUsesExactExpiryAndIncludesSeconds() throws {
        let startsAt = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 10, minute: 4, second: 23
        ))!
        let expiresAt = startsAt.addingTimeInterval(16 * 60)
        var registered: (DeviceActivityName, DeviceActivitySchedule)?
        let scheduler = DeviceActivitySessionScheduler(
            calendar: calendar,
            startMonitoring: { name, schedule in registered = (name, schedule) },
            stopMonitoring: { _ in }
        )

        let activityName = try scheduler.register(
            ruleID: ruleID,
            startsAt: startsAt,
            expiresAt: expiresAt
        )

        XCTAssertEqual(activityName, SessionActivityName.sessionActivityName(for: ruleID))
        XCTAssertEqual(registered?.0.rawValue, activityName)
        XCTAssertEqual(registered?.1.intervalStart.second, 23)
        XCTAssertEqual(registered?.1.intervalEnd.second, 23)
        XCTAssertNil(registered?.1.warningTime)
        XCTAssertEqual(registered?.1.intervalEnd.minute, 20)
    }

    func testShortSessionUsesFifteenMinuteIntervalAndWarningAtProductExpiry() throws {
        let startsAt = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 10, minute: 4, second: 23
        ))!
        let expiresAt = startsAt.addingTimeInterval(3 * 60)
        var registeredSchedule: DeviceActivitySchedule?
        let scheduler = DeviceActivitySessionScheduler(
            calendar: calendar,
            startMonitoring: { _, schedule in registeredSchedule = schedule },
            stopMonitoring: { _ in }
        )

        _ = try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)

        XCTAssertEqual(registeredSchedule?.intervalStart.second, 23)
        XCTAssertEqual(registeredSchedule?.intervalEnd.second, 23)
        XCTAssertEqual(registeredSchedule?.intervalEnd.minute, 19)
        XCTAssertEqual(registeredSchedule?.warningTime, DateComponents(minute: 12))
    }

    func testUnrepresentableExpiryDoesNotStartMonitoring() {
        let startsAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiresAt = startsAt.addingTimeInterval(5 * 60)
        var registrationCount = 0
        let scheduler = DeviceActivitySessionScheduler(
            calendar: calendar,
            resolvedCallbackDate: { _, _ in expiresAt.addingTimeInterval(5.001) },
            startMonitoring: { _, _ in registrationCount += 1 },
            stopMonitoring: { _ in }
        )

        XCTAssertThrowsError(
            try scheduler.register(ruleID: ruleID, startsAt: startsAt, expiresAt: expiresAt)
        ) {
            XCTAssertEqual($0 as? SessionSchedulingError, .unrepresentableExpiry)
        }
        XCTAssertEqual(registrationCount, 0)
    }
}
