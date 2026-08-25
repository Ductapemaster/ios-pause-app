import Foundation
import XCTest
@testable import PauseCore

final class RuleRuntimeTests: XCTestCase {
    private let day = CalendarDay(
        date: Date(timeIntervalSince1970: 1_768_464_000),
        calendar: RuleRuntimeTests.utcGregorian
    )

    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testReserveActivatesAndRollsBackAProvisionalSession() throws {
        var runtime = RuleRuntime(logicalDay: day, sessionsStarted: 0)
        let expiry = Date(timeIntervalSince1970: 1_768_464_060)

        try runtime.reserve(activityName: "session.rule", expiresAt: expiry)
        XCTAssertEqual(runtime.sessionsStarted, 1)
        XCTAssertEqual(runtime.openSession?.state, .provisional)

        try runtime.rollBackReservedSession()
        XCTAssertEqual(runtime.sessionsStarted, 0)
        XCTAssertNil(runtime.openSession)

        try runtime.reserve(activityName: "session.rule", expiresAt: expiry)
        try runtime.activateReservedSession()
        XCTAssertEqual(runtime.openSession?.state, .active)
        XCTAssertThrowsError(try runtime.rollBackReservedSession())
    }

    func testReserveRejectsAnAlreadyOpenSession() throws {
        var runtime = RuleRuntime(logicalDay: day, sessionsStarted: 0)
        try runtime.reserve(activityName: "session.rule", expiresAt: Date(timeIntervalSince1970: 1_768_464_060))

        XCTAssertThrowsError(
            try runtime.reserve(activityName: "session.other", expiresAt: Date(timeIntervalSince1970: 1_768_464_120))
        )
        XCTAssertEqual(runtime.sessionsStarted, 1)
    }

    func testRolloverResetsCountButKeepsAnUnexpiredSession() throws {
        var runtime = RuleRuntime(
            logicalDay: day,
            sessionsStarted: 2,
            openSession: OpenSession(
                activityName: "session.rule",
                expiresAt: Date(timeIntervalSince1970: 1_768_464_060),
                state: .active
            )
        )
        let nextDay = CalendarDay(
            date: Date(timeIntervalSince1970: 1_768_550_400),
            calendar: Self.utcGregorian
        )

        runtime.rollOver(to: nextDay)

        XCTAssertEqual(runtime.logicalDay, nextDay)
        XCTAssertEqual(runtime.sessionsStarted, 0)
        XCTAssertNotNil(runtime.openSession)
    }

    func testClearExpiredSessionRemovesTheOpenSession() throws {
        var runtime = RuleRuntime(
            logicalDay: day,
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: "session.rule",
                expiresAt: Date(timeIntervalSince1970: 1_768_464_060),
                state: .provisional
            )
        )

        runtime.clearExpiredSession(at: Date(timeIntervalSince1970: 1_768_464_060))

        XCTAssertNil(runtime.openSession)
        XCTAssertEqual(runtime.sessionsStarted, 1)
    }

    /// The stamp is the session's own expiry, not the instant the clear ran. A
    /// callback delivered late, or missed and repaired at the app's next launch,
    /// must not push the cooldown out by however long that took.
    func testClearExpiredSessionStampsTheSessionsExpiryNotTheClearingInstant() throws {
        let expiry = Date(timeIntervalSince1970: 1_768_464_060)
        var runtime = RuleRuntime(
            logicalDay: day,
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: "session.rule",
                expiresAt: expiry,
                state: .active
            )
        )

        runtime.clearExpiredSession(at: expiry.addingTimeInterval(3600))

        XCTAssertEqual(runtime.lastSessionExpiry, expiry)
    }

    func testClearingWithNothingExpiredLeavesTheStampAlone() throws {
        var runtime = RuleRuntime(
            logicalDay: day,
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: "session.rule",
                expiresAt: Date(timeIntervalSince1970: 1_768_464_060),
                state: .active
            )
        )

        runtime.clearExpiredSession(at: Date(timeIntervalSince1970: 1_768_464_000))

        XCTAssertNil(runtime.lastSessionExpiry)
        XCTAssertNotNil(runtime.openSession)
    }

    /// A grant that rolled back spent no session, so it starts no cooldown.
    func testRollingBackAReservedSessionLeavesNoStamp() throws {
        var runtime = RuleRuntime(logicalDay: day, sessionsStarted: 0)
        try runtime.reserve(
            activityName: "session.rule",
            expiresAt: Date(timeIntervalSince1970: 1_768_464_060)
        )

        try runtime.rollBackReservedSession()

        XCTAssertNil(runtime.lastSessionExpiry)
        XCTAssertEqual(runtime.sessionsStarted, 0)
    }

    /// The reset returns the allowance and leaves the cooldown standing.
    func testRolloverKeepsTheLastSessionStamp() throws {
        let expiry = Date(timeIntervalSince1970: 1_768_464_060)
        var runtime = RuleRuntime(
            logicalDay: day,
            sessionsStarted: 2,
            openSession: nil,
            lastSessionExpiry: expiry
        )
        let nextDay = CalendarDay(
            date: Date(timeIntervalSince1970: 1_768_550_400),
            calendar: Self.utcGregorian
        )

        runtime.rollOver(to: nextDay)

        XCTAssertEqual(runtime.sessionsStarted, 0)
        XCTAssertEqual(runtime.lastSessionExpiry, expiry)
    }
}
