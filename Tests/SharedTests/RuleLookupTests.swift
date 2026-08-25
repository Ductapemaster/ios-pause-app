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
            settings: try GlobalSettings(pauseSeconds: 10),
            logicalDay: CalendarDay(date: now, calendar: calendar),
            now: now
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
            settings: try GlobalSettings(pauseSeconds: 10),
            logicalDay: CalendarDay(date: now, calendar: calendar),
            now: now
        )

        XCTAssertEqual(evaluation.runtime, runtime)
        XCTAssertEqual(evaluation.decision, .refused(.sessionAlreadyOpen(until: expiry)))
    }

    func testAllowedPresentationCountsTheSessionsStillAvailable() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .allowed(sessionNumber: 2, lengthMinutes: 5)
        )

        XCTAssertEqual(presentation.subtitle, "3 sessions left today")
        XCTAssertEqual(presentation.primaryButtonTitle, "Take a breath")
    }

    func testAllowedPresentationSaysSessionOnceOneRemains() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .allowed(sessionNumber: 4, lengthMinutes: 5)
        )

        XCTAssertEqual(presentation.subtitle, "1 session left today")
        XCTAssertEqual(presentation.primaryButtonTitle, "Take a breath")
    }

    func testExhaustedPresentationShowsTheRefusalCopy() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .refused(.dailyAllowanceExhausted(limit: 4))
        )

        XCTAssertEqual(presentation.subtitle, "That's all for today.")
        XCTAssertEqual(presentation.primaryButtonTitle, "Close")
    }

    /// The subtitle carries the instruction; the button says only what pressing
    /// it does, so the screen no longer names an action its button cannot take.
    func testRepairPresentationShowsTheRepairCopy() {
        let presentation = ShieldPresentation.repair

        XCTAssertEqual(presentation.subtitle, "Pause can't check this app. Open Pause to fix it.")
        XCTAssertEqual(presentation.primaryButtonTitle, "Close")
    }

    /// An allowed shield offers two different answers — start the session, or
    /// leave without starting one — so it needs both buttons.
    func testTheAllowedPresentationKeepsAWayOutBesideThePause() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)

        let presentation = ShieldPresentation(
            rule: rule,
            decision: .allowed(sessionNumber: 1, lengthMinutes: 5)
        )

        XCTAssertEqual(presentation.secondaryButtonTitle, "Not now")
    }

    /// Every refusal shows one button. Both buttons closed the app, so the
    /// second only restated the first.
    func testEveryRefusalShowsASingleCloseButton() throws {
        let rule = try AppRule(sessionsPerDay: 4, sessionLengthMinutes: 5)
        let presentations = [
            ShieldPresentation(rule: rule, decision: .refused(.dailyAllowanceExhausted(limit: 4))),
            ShieldPresentation(rule: rule, decision: .refused(.sessionAlreadyOpen(until: Date()))),
            ShieldPresentation.repair,
        ]

        for presentation in presentations {
            XCTAssertEqual(presentation.primaryButtonTitle, "Close")
            XCTAssertNil(presentation.secondaryButtonTitle)
        }
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
