import Foundation
import ManagedSettings
import PauseCore
import XCTest

/// The shield configuration extension runs under a sandbox profile that refuses
/// every write, including creating the state lock file. These tests pin the two
/// properties that follow: the read path resolves a presentation, and it does so
/// without ever asking for the lock.
final class ShieldStateReaderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testResolvesThePresentationWithoutCreatingALockFile() throws {
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()

        try seed(
            directoryURL: directoryURL,
            ruleID: ruleID,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 1,
            now: now
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: now, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "3 sessions left today")
        XCTAssertEqual(presentation.primaryButtonTitle, "Take a breath")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryURL.appendingPathComponent(SharedIdentifiers.stateLockFilename).path
            ),
            "the shield read path must not create the lock file"
        )
    }

    func testReportsTheExhaustedPresentationOnceTheDayIsSpent() throws {
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()

        try seed(
            directoryURL: directoryURL,
            ruleID: ruleID,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 4,
            now: now
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: now, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "That's all for today.")
        XCTAssertEqual(presentation.primaryButtonTitle, "Close")
    }

    func testThrowsWhenNoConfigurationHasBeenWritten() throws {
        let directoryURL = try temporaryDirectory()
        let token = try token(seed: "instagram")

        XCTAssertThrowsError(
            try ShieldStateReader(directoryURL: directoryURL)
                .presentation(for: token, now: Date(), calendar: calendar)
        ) { error in
            XCTAssertEqual(error as? RuleLookupError, .targetNotFound)
        }
    }

    func testThePendingConfigurationAppliesOnceItsStartDayArrives() throws {
        let now = date(year: 2026, month: 8, day: 21, hour: 9)
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()

        let effective = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        let scheduled = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 6, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        try AtomicJSONFile<ConfigurationFile>(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        ).save(
            ConfigurationFile(
                effective: effective,
                pending: PendingConfiguration(
                    document: scheduled,
                    startDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar)
                )
            )
        )
        try AtomicJSONFile<RuleRuntime>(
            url: directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
        ).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                sessionsStarted: 1,
                openSession: nil
            )
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: now, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "5 sessions left today")
    }

    /// The feature's central behaviour: with the reset away from midnight, the
    /// civil date turning over must not renew the allowance. The count has to
    /// ride to the configured reset, because that is the instant the shield's
    /// wait is measured against.
    func testTheSessionCountSurvivesMidnightWhenTheResetIsLater() throws {
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterMidnight = date(year: 2026, month: 8, day: 21, hour: 2)

        try seed(
            directoryURL: directoryURL,
            ruleID: ruleID,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 4,
            resetMinuteOfDay: 6 * 60,
            spentAt: spentAt
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: afterMidnight, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "That's all for today.")
    }

    func testTheSessionCountRenewsAtTheConfiguredReset() throws {
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterTheReset = date(year: 2026, month: 8, day: 21, hour: 7)

        try seed(
            directoryURL: directoryURL,
            ruleID: ruleID,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 4,
            resetMinuteOfDay: 6 * 60,
            spentAt: spentAt
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: afterTheReset, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "4 sessions left today")
    }

    // MARK: - Helpers

    /// Writes the files the app would have written, without taking the lock, so
    /// the lock-file assertion measures only what the reader did.
    private func seed(
        directoryURL: URL,
        ruleID: UUID,
        token: ApplicationToken,
        sessionsPerDay: Int,
        sessionsStarted: Int,
        now: Date
    ) throws {
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        try AtomicJSONFile<ConfigurationDocument>(
            url: directoryURL.appendingPathComponent("configuration.json")
        ).save(configuration)

        let runtime = RuleRuntime(
            logicalDay: CalendarDay(date: now, calendar: calendar),
            sessionsStarted: sessionsStarted,
            openSession: nil
        )
        try AtomicJSONFile<RuleRuntime>(
            url: directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
        ).save(runtime)
    }

    /// The same, for a reset away from midnight: the file carries the reset and
    /// the runtime is charged to the allowance day the sessions were spent in.
    private func seed(
        directoryURL: URL,
        ruleID: UUID,
        token: ApplicationToken,
        sessionsPerDay: Int,
        sessionsStarted: Int,
        resetMinuteOfDay: Int,
        spentAt: Date
    ) throws {
        let configuration = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: resetMinuteOfDay),
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        try AtomicJSONFile<ConfigurationFile>(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        ).save(ConfigurationFile(effective: configuration, pending: nil))

        try AtomicJSONFile<RuleRuntime>(
            url: directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
        ).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(
                    spentAt,
                    resetMinuteOfDay: resetMinuteOfDay,
                    calendar: calendar
                ),
                sessionsStarted: sessionsStarted,
                openSession: nil
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-shield-reader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
