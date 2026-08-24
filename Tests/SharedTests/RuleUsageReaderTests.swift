import Foundation
import PauseCore
import XCTest

/// The reader consults `rules` alone, so these documents carry no targets.
/// Adding one would mean fabricating an `ApplicationToken` and would test
/// nothing the reader reads.
final class RuleUsageReaderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testReportsTheStoredCountForTheCurrentAllowanceDay() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 2
                )
            ])
        )

        let used = reader.sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertEqual(used[ruleID], 2)
    }

    func testAnUntouchedRuleReadsAsNoneUsed() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 0
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: now, calendar: calendar)[ruleID], 0)
    }

    func testAnExhaustedRuleReadsAsItsLimit() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 3, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: now, calendar: calendar)[ruleID], 3)
    }

    /// The stored count rolls over lazily, so a record left from an earlier day
    /// still carries that day's number. Reading it raw is the defect this reader
    /// exists to avoid.
    func testACountLeftFromAnEarlierDayReadsAsNoneUsed() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let today = date(year: 2026, month: 8, day: 21, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(spentAt, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 4
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: today, calendar: calendar)[ruleID], 0)
    }

    /// The feature's central behaviour, and the shape of the defect the
    /// configurable-reset effort shipped: with the reset away from midnight, the
    /// civil date turning over must not renew the count.
    func testTheCountSurvivesMidnightWhenTheResetIsLater() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterMidnight = date(year: 2026, month: 8, day: 21, hour: 2)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterMidnight, calendar: calendar)[ruleID], 3)
    }

    func testTheCountRenewsOnceTheConfiguredResetHasPassed() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterReset = date(year: 2026, month: 8, day: 21, hour: 7)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterReset, calendar: calendar)[ruleID], 0)
    }

    func testARuleWhoseRuntimeIsMissingCarriesNoCount() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)

        let used = RuleUsageReader(runtimeReader: StubRuntimeReader())
            .sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertNil(used[ruleID])
    }

    func testARuleWhoseRuntimeCannotBeReadCarriesNoCount() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)

        let used = RuleUsageReader(
            runtimeReader: StubRuntimeReader(unreadableRuleIDs: [ruleID])
        ).sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertNil(used[ruleID])
    }

    /// The reset that decides the allowance day is the effective document's. A
    /// pending document carrying a different reset must not move the boundary
    /// that the count is charged against.
    func testTheEffectiveResetDecidesTheDayNotThePendingOne() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterMidnight = date(year: 2026, month: 8, day: 21, hour: 2)
        let effective = try document(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let scheduled = try document(ruleID: ruleID, sessionsPerDay: 8, resetMinuteOfDay: 0)
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(date: afterMidnight, calendar: calendar)
            )
        )
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterMidnight, calendar: calendar)[ruleID], 3)
    }

    private func document(
        ruleID: UUID,
        sessionsPerDay: Int,
        resetMinuteOfDay: Int
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: resetMinuteOfDay),
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: []
        )
    }

    private func file(
        ruleID: UUID,
        sessionsPerDay: Int,
        resetMinuteOfDay: Int
    ) throws -> ConfigurationFile {
        ConfigurationFile(
            effective: try document(
                ruleID: ruleID,
                sessionsPerDay: sessionsPerDay,
                resetMinuteOfDay: resetMinuteOfDay
            ),
            pending: nil
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

private struct StubRuntimeReader: RuntimeReading {
    var runtimes: [UUID: RuleRuntime] = [:]
    var unreadableRuleIDs: Set<UUID> = []

    func load(ruleID: UUID) throws -> RuleRuntime? {
        if unreadableRuleIDs.contains(ruleID) {
            throw StubError.unreadable
        }
        return runtimes[ruleID]
    }

    enum StubError: Error {
        case unreadable
    }
}
