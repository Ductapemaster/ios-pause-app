import Foundation
import PauseCore
import XCTest

final class RuleLookupTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testEvaluationRollsOverTheDayAndClearsAnExpiredSession() throws {
        let now = date(year: 2026, month: 8, day: 18, hour: 9)
        let rule = try AppRule(sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(
            logicalDay: CalendarDay(date: date(year: 2026, month: 8, day: 17), calendar: calendar),
            sessionsStarted: 3,
            openSession: OpenSession(
                activityName: "session.expired",
                expiresAt: now.addingTimeInterval(-1),
                state: .active
            )
        )

        let evaluation = RuleLookup.evaluate(
            rule: rule,
            runtime: runtime,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(evaluation.runtime.logicalDay, CalendarDay(date: now, calendar: calendar))
        XCTAssertEqual(evaluation.runtime.sessionsStarted, 0)
        XCTAssertNil(evaluation.runtime.openSession)
        XCTAssertEqual(evaluation.decision, .allowed(sessionNumber: 1, lengthMinutes: 5))
    }

    func testEvaluationPreservesAnUnexpiredSessionAndRefusesAnother() throws {
        let now = date(year: 2026, month: 8, day: 18, hour: 9)
        let expiry = now.addingTimeInterval(60)
        let rule = try AppRule(sessionsPerDay: 3, sessionLengthMinutes: 5)
        let runtime = RuleRuntime(
            logicalDay: CalendarDay(date: now, calendar: calendar),
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: "session.open",
                expiresAt: expiry,
                state: .provisional
            )
        )

        let evaluation = RuleLookup.evaluate(
            rule: rule,
            runtime: runtime,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(evaluation.runtime, runtime)
        XCTAssertEqual(evaluation.decision, .refused(.sessionAlreadyOpen(until: expiry)))
    }

    func testAllowedPresentationShowsTheProspectiveSessionCount() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .allowed(sessionNumber: 2, lengthMinutes: 5)
        )

        XCTAssertEqual(presentation.subtitle, "Next session: 2 of 4")
        XCTAssertEqual(presentation.primaryButtonTitle, "Pause to open")
    }

    func testExhaustedPresentationShowsTheRefusalCopy() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .refused(.dailyAllowanceExhausted(limit: 4))
        )

        XCTAssertEqual(presentation.subtitle, "No sessions left today")
        XCTAssertEqual(presentation.primaryButtonTitle, "Done for today")
    }

    func testRepairPresentationShowsTheRepairCopy() {
        let presentation = ShieldPresentation.repair

        XCTAssertEqual(presentation.subtitle, "Open Pause to repair this app")
        XCTAssertEqual(presentation.primaryButtonTitle, "Done for today")
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
