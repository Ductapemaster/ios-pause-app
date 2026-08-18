import Foundation
import XCTest
@testable import PauseCore

final class RulesEngineTests: XCTestCase {
    private let ruleID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    private let otherRuleID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: CalendarDay {
        CalendarDay(date: Date(timeIntervalSince1970: 1_768_464_000), calendar: calendar)
    }

    private var now: Date {
        Date(timeIntervalSince1970: 1_768_464_000)
    }

    func testFreshRuleAllowsFirstSession() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(logicalDay: today, sessionsStarted: 0)

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .allowed(sessionNumber: 1, lengthMinutes: 5)
        )
    }

    func testAllowsLastRemainingSession() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(logicalDay: today, sessionsStarted: 2)

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .allowed(sessionNumber: 3, lengthMinutes: 5)
        )
    }

    func testRefusesWhenDailyAllowanceIsExhausted() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(logicalDay: today, sessionsStarted: 3)

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .refused(.dailyAllowanceExhausted(limit: 3))
        )
    }

    func testRefusesWhileAnUnexpiredSessionIsOpen() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(
            logicalDay: today,
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: SessionActivityName.sessionActivityName(for: ruleID),
                expiresAt: now.addingTimeInterval(60),
                state: .active
            )
        )

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .refused(.sessionAlreadyOpen(until: now.addingTimeInterval(60)))
        )
    }

    func testExpiredOpenSessionDoesNotBlockTheNextAllowance() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(
            logicalDay: today,
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: SessionActivityName.sessionActivityName(for: ruleID),
                expiresAt: now.addingTimeInterval(-1),
                state: .active
            )
        )

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .allowed(sessionNumber: 2, lengthMinutes: 5)
        )
    }

    func testRuntimeFromYesterdayStartsAnewDailyCount() throws {
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        let yesterday = CalendarDay(date: now.addingTimeInterval(-86_400), calendar: calendar)
        let runtime = RuleRuntime(logicalDay: yesterday, sessionsStarted: 3)

        XCTAssertEqual(
            RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
            .allowed(sessionNumber: 1, lengthMinutes: 5)
        )
    }

    func testSeparateRuleIDsHaveIndependentRuntimeCounts() throws {
        let firstRule = try AppRule(id: ruleID, sessionsPerDay: 1, sessionLengthMinutes: 5)
        let secondRule = try AppRule(id: otherRuleID, sessionsPerDay: 1, sessionLengthMinutes: 5)
        let firstRuntime = RuleRuntime(logicalDay: today, sessionsStarted: 1)
        let secondRuntime = RuleRuntime(logicalDay: today, sessionsStarted: 0)

        XCTAssertEqual(
            RulesEngine.decision(rule: firstRule, runtime: firstRuntime, today: today, now: now),
            .refused(.dailyAllowanceExhausted(limit: 1))
        )
        XCTAssertEqual(
            RulesEngine.decision(rule: secondRule, runtime: secondRuntime, today: today, now: now),
            .allowed(sessionNumber: 1, lengthMinutes: 5)
        )
    }

    func testInvalidRuleValuesAreRejected() {
        XCTAssertThrowsError(try AppRule(id: ruleID, sessionsPerDay: 0, sessionLengthMinutes: 5))
        XCTAssertThrowsError(try AppRule(id: ruleID, sessionsPerDay: 1, sessionLengthMinutes: 0))
    }

    func testInvalidPauseValueIsRejected() {
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 0))
    }
}
