import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationFileTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTheEffectiveDocumentAppliesWhenNothingIsPending() throws {
        let file = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)

        XCTAssertEqual(file.inForce(on: day(2026, 8, 20)).rules[0].sessionsPerDay, 3)
    }

    func testTheEffectiveDocumentAppliesBeforeTheStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 8, 20)).rules[0].sessionsPerDay, 3)
    }

    func testThePendingDocumentAppliesOnItsStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 8, 21)).rules[0].sessionsPerDay, 5)
    }

    func testThePendingDocumentStillAppliesAfterItsStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 9, 1)).rules[0].sessionsPerDay, 5)
    }

    // MARK: - Helpers

    private let ruleID = UUID()

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
        CalendarDay(
            date: calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!,
            calendar: calendar
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
