import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

final class ScheduledChangeWordingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testAChangeStartingTheNextAllowanceDayReadsAsTomorrow() throws {
        let file = try fileWithReset(minuteOfDay: 0)

        XCTAssertEqual(
            ScheduledChangeWording.phrase(
                for: file.nextLogicalDay(after: now, calendar: calendar),
                in: file,
                now: now
            ),
            "tomorrow"
        )
    }

    func testARaisedSessionCountIsNamedWithoutTheLengthThatDidNotMove() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .allowance(sessionsPerDay: 4, sessionLengthMinutes: nil),
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Changes to 4 sessions tomorrow."
        )
    }

    func testBothAllowanceFieldsMovingAreNamedTogether() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .allowance(sessionsPerDay: 1, sessionLengthMinutes: 16),
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Changes to 1 session of 16 minutes tomorrow."
        )
    }

    func testARemovalSaysTheAppIsShieldedUntilItGoes() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .removal,
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Leaves Pause tomorrow. Until then it is shielded as normal."
        )
    }

    func testAShorterPauseIsNamedInSeconds() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingSettingsChange(
            pauseSeconds: 1,
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.settingsDescription(of: change, in: file, now: now),
            "The pause changes to 1 second tomorrow."
        )
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func fileWithReset(minuteOfDay: Int) throws -> ConfigurationFile {
        ConfigurationFile(
            effective: try ConfigurationDocument(
                settings: try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: minuteOfDay),
                rules: [],
                targets: []
            ),
            pending: nil
        )
    }
}
