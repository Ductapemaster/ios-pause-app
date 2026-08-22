import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationSaveRouterTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testATighteningEditAppliesImmediately() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a"], sessionsPerDay: ["a": 5]),
            pending: nil
        )
        let candidate = try document(seeds: ["a"], sessionsPerDay: ["a": 3])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testALooseningEditIsScheduledForTheNextLogicalDay() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a"], sessionsPerDay: ["a": 3]),
            pending: nil
        )
        let candidate = try document(seeds: ["a"], sessionsPerDay: ["a": 5])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, existing.effective)
        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.pending?.startDay, LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar))
    }

    func testATighteningEditClearsAScheduledChange() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a"], sessionsPerDay: ["a": 3]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"], sessionsPerDay: ["a": 5]),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a"], sessionsPerDay: ["a": 2])

        let result = try ConfigurationSaveRouter.route(
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
            effective: try document(seeds: ["a"], sessionsPerDay: ["a": 3]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"], sessionsPerDay: ["a": 5]),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a"], sessionsPerDay: ["a": 8])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.effective, existing.effective)
    }

    func testAnAddedAppIsCoveredTodayWhileADroppedOneWaits() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        // The picker's candidate: "b" dropped, "c" added, "a" retained.
        let candidate = try document(seeds: ["a", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
        XCTAssertEqual(seeds(of: result.pending?.document), ["a", "c"])
        XCTAssertEqual(result.pending?.startDay, LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar))
    }

    func testAScheduledRemovalSurvivesASaveAboutAnotherApp() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"]),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        // Adding "c" says nothing about "b", whose removal is already scheduled.
        let candidate = try document(seeds: ["a", "b", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
        XCTAssertEqual(seeds(of: result.pending?.document), ["a", "c"])
    }

    func testAScheduledAllowanceSurvivesASaveAboutAnotherApp() throws {
        let scheduled = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 5])
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: scheduled,
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a", "b", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 3)
        XCTAssertEqual(sessionsPerDay(of: result.pending?.document, seed: "a"), 5)
        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
    }

    func testASaveAboutAnAppReplacesWhatWasScheduledForIt() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a", "b"], sessionsPerDay: ["a": 5]),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 4])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 3)
        XCTAssertEqual(sessionsPerDay(of: result.pending?.document, seed: "a"), 4)
    }

    func testASaveThatDefersNothingLeavesTheCandidateAsEffective() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 2])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testASettingsLooseningWaitsWhileAnAppChangeApplies() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 2], pauseSeconds: 5)

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 2)
        XCTAssertEqual(result.effective.settings.pauseSeconds, 10)
        XCTAssertEqual(result.pending?.document.settings.pauseSeconds, 5)
    }

    /// A file written before the router judged per app can hold an addition
    /// that is waiting, because the old router deferred a mixed picker save
    /// whole. The added app is named by neither the in-force document nor a
    /// candidate built from it, so walking only those two would drop it.
    func testAnAppLeftWaitingByTheOldWholeEditRuleIsCoveredRatherThanDropped() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a"]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a", "c"]),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.effective), ["a", "c"])
        XCTAssertNil(result.pending)
    }

    /// A save that moves the reset re-stamps the start day of whatever is still
    /// deferred, and the label is read back through the reset the save just put
    /// in force. Stamping it in the pre-save frame lets a loosening — here an app
    /// leaving Pause — land the moment it is saved.
    func testMovingTheResetEarlierDoesNotLandADeferredLooseningAtOnce() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"], resetMinuteOfDay: 10 * 60),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"], resetMinuteOfDay: 10 * 60),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 10 * 60, calendar: calendar)
            )
        )
        // What the settings screen builds: the rules in force, with a new reset.
        let candidate = try document(seeds: ["a", "b"], resetMinuteOfDay: 0)

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.inForce(at: now(), calendar: calendar)), ["a", "b"])
        XCTAssertEqual(
            result.pending?.startDay,
            LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
        )
    }

    /// The mirror: moving the reset later must not push a deferred change past
    /// the next reset the new setting names.
    func testMovingTheResetLaterStartsADeferredChangeAtTheNextResetItNames() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"], resetMinuteOfDay: 0),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"], resetMinuteOfDay: 0),
                startDay: LogicalDay.next(after: now(), resetMinuteOfDay: 0, calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a", "b"], resetMinuteOfDay: 10 * 60)

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(
            result.pending?.startDay,
            LogicalDay.next(after: now(), resetMinuteOfDay: 10 * 60, calendar: calendar)
        )
    }

    // MARK: - Helpers

    private let ruleIDs = [
        "a": UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!,
        "b": UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!,
        "c": UUID(uuidString: "cccccccc-0000-0000-0000-000000000003")!,
    ]

    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
    }

    /// Each app keeps one rule id across every document a test builds, which is
    /// what pairs its unit between them.
    private func document(
        seeds: [String],
        sessionsPerDay: [String: Int] = [:],
        pauseSeconds: Int = 10,
        resetMinuteOfDay: Int = 0
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(
                pauseSeconds: pauseSeconds,
                resetMinuteOfDay: resetMinuteOfDay
            ),
            rules: try seeds.map { seed in
                try AppRule(
                    id: ruleIDs[seed]!,
                    sessionsPerDay: sessionsPerDay[seed] ?? 3,
                    sessionLengthMinutes: 5
                )
            },
            targets: try seeds.map { seed in
                RuleTarget(
                    ruleID: ruleIDs[seed]!,
                    applicationToken: try token(seed: seed),
                    launchRoute: nil
                )
            }
        )
    }

    private func seeds(of document: ConfigurationDocument?) -> [String]? {
        document?.targets.compactMap { target in
            ruleIDs.first { $0.value == target.ruleID }?.key
        }
    }

    private func sessionsPerDay(of document: ConfigurationDocument?, seed: String) -> Int? {
        document?.rules.first { $0.id == ruleIDs[seed] }?.sessionsPerDay
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
