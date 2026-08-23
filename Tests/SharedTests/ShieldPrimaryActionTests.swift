import Foundation
import ManagedSettings
import PauseCore
import XCTest

/// The shield's primary button carries a different promise in each state: it
/// starts a session when one is available, and otherwise reads "Done for
/// today", which is a dismissal. These tests pin the property the button
/// depends on — every press resolves to an action, so no state leaves it dead.
final class ShieldPrimaryActionTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDismissesOnceTheDailyAllowanceIsSpent() throws {
        let now = date(year: 2026, month: 8, day: 22, hour: 23)
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        try seed(
            directoryURL: directoryURL,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 4,
            now: now
        )

        let outcome = ShieldPrimaryAction(
            directoryURL: directoryURL,
            intentStore: ShieldIntentStore(defaults: try defaults())
        ).resolve(applicationToken: token, now: now, calendar: calendar)

        XCTAssertEqual(outcome, .dismiss)
    }

    func testDismissesWhileASessionIsAlreadyOpen() throws {
        let now = date(year: 2026, month: 8, day: 22, hour: 23)
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        try seed(
            directoryURL: directoryURL,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 1,
            now: now,
            openSession: OpenSession(
                activityName: "session",
                expiresAt: now.addingTimeInterval(300),
                state: .active
            )
        )

        let outcome = ShieldPrimaryAction(
            directoryURL: directoryURL,
            intentStore: ShieldIntentStore(defaults: try defaults())
        ).resolve(applicationToken: token, now: now, calendar: calendar)

        XCTAssertEqual(outcome, .dismiss)
    }

    /// The repair shield shows the same "Done for today" button, so an app the
    /// configuration cannot resolve must dismiss rather than swallow the press.
    func testDismissesWhenTheAppCannotBeResolved() throws {
        let directoryURL = try temporaryDirectory()
        let token = try token(seed: "instagram")
        var reported: [String] = []

        let outcome = ShieldPrimaryAction(
            directoryURL: directoryURL,
            intentStore: ShieldIntentStore(defaults: try defaults())
        ).resolve(
            applicationToken: token,
            now: Date(),
            calendar: calendar,
            errorSink: { reported.append($0) }
        )

        XCTAssertEqual(outcome, .dismiss)
        XCTAssertEqual(reported.count, 1, "the refusal is reported, not silent")
    }

    func testOpensPauseAndRecordsTheIntentWhenASessionIsAvailable() throws {
        let now = date(year: 2026, month: 8, day: 22, hour: 23)
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        let store = ShieldIntentStore(defaults: try defaults())
        try seed(
            directoryURL: directoryURL,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 1,
            now: now
        )

        let outcome = ShieldPrimaryAction(directoryURL: directoryURL, intentStore: store)
            .resolve(applicationToken: token, now: now, calendar: calendar)

        XCTAssertEqual(outcome, .openPause)
        XCTAssertEqual(try store.consume()?.applicationToken, token)
    }

    // MARK: - Helpers

    private func seed(
        directoryURL: URL,
        token: ApplicationToken,
        sessionsPerDay: Int,
        sessionsStarted: Int,
        now: Date,
        openSession: OpenSession? = nil
    ) throws {
        let ruleID = UUID()
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
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
                logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                sessionsStarted: sessionsStarted,
                openSession: openSession
            )
        )
    }

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "pause-shield-action-tests-\(UUID().uuidString)"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-shield-action-tests-\(UUID().uuidString)", isDirectory: true)
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
