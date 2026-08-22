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

    /// The reset time lives in the configuration and choosing the configuration
    /// needs the day, so the effective document's reset is what defines the day.
    /// A pending document's own reset must not reach back and move the boundary
    /// that decides whether it is in force yet.
    func testTheEffectiveResetDefinesTheDayThatSelectsThePending() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        let instant = formatter.date(from: "2026-03-10T05:00:00Z")!

        let effective = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let scheduled = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 20, resetMinuteOfDay: 0),
            rules: [],
            targets: []
        )
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(
                    date: formatter.date(from: "2026-03-10T12:00:00Z")!,
                    calendar: utc
                )
            )
        )

        // 05:00 with a 06:00 reset is still 2026-03-09, so a change starting on
        // 2026-03-10 has not arrived.
        XCTAssertEqual(file.inForce(at: instant, calendar: utc), effective)
        XCTAssertEqual(
            file.logicalDay(at: instant, calendar: utc),
            CalendarDay(date: formatter.date(from: "2026-03-09T12:00:00Z")!, calendar: utc)
        )
    }

    func testThePendingArrivesOnceTheEffectiveResetHasPassed() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!

        let effective = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let scheduled = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 20, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(
                    date: formatter.date(from: "2026-03-10T12:00:00Z")!,
                    calendar: utc
                )
            )
        )

        let afterReset = formatter.date(from: "2026-03-10T06:00:00Z")!
        XCTAssertEqual(file.inForce(at: afterReset, calendar: utc), scheduled)
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
