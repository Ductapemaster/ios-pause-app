import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationSaveRouterTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let ruleID = UUID()

    func testATighteningEditAppliesImmediately() throws {
        let existing = ConfigurationFile(effective: try document(sessionsPerDay: 5), pending: nil)
        let candidate = try document(sessionsPerDay: 3)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testALooseningEditIsScheduledForTheNextLogicalDay() throws {
        let existing = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)
        let candidate = try document(sessionsPerDay: 5)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, existing.effective)
        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.pending?.startDay, LogicalDay.next(after: now(), calendar: calendar))
    }

    func testATighteningEditClearsAScheduledChange() throws {
        let existing = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(sessionsPerDay: 2)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testASecondLooseningEditReplacesTheFirstRatherThanQueueing() throws {
        let existing = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(sessionsPerDay: 8)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.effective, existing.effective)
    }

    // MARK: - Helpers

    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
    }

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
