import Darwin
import Foundation
import ManagedSettings
import PauseCore
import XCTest

/// The shield's primary button carries a different promise in each state: it
/// starts a session when one is available, and otherwise reads "Done for
/// today", which is a dismissal. These tests pin what each state answers, and
/// in particular that a failure to decide never borrows the refusal's answer.
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

    /// The repair shield shows the same "Close" button, so an app the
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

    /// A lock timeout says nothing about whether a session is available, so it
    /// must not borrow the refusal's answer and close the app the user asked for.
    func testALockTimeoutLeavesTheShieldUpInsteadOfClosingTheApp() throws {
        let now = date(year: 2026, month: 8, day: 22, hour: 23)
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()
        try seed(
            directoryURL: directoryURL,
            token: token,
            sessionsPerDay: 4,
            sessionsStarted: 1,
            now: now
        )
        var reported: [String] = []

        let outcome = ShieldPrimaryAction(
            directoryURL: directoryURL,
            intentStore: ShieldIntentStore(defaults: try defaults()),
            stateLock: AppGroupFileLock(
                directoryURL: directoryURL,
                systemCalls: ContendedSystemCalls().dependencies
            )
        ).resolve(
            applicationToken: token,
            now: now,
            calendar: calendar,
            errorSink: { reported.append($0) }
        )

        XCTAssertEqual(outcome, .keepShield)
        XCTAssertEqual(reported.count, 1, "the failure is reported, not silent")
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

/// A lock nobody ever releases, on an injected clock so the wait costs the suite
/// nothing. `AppGroupFileLockTests` owns the general form of this stub; this is
/// the one case the shield's decision needs.
private final class ContendedSystemCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0

    var dependencies: AppGroupFileLockSystemCalls {
        AppGroupFileLockSystemCalls(
            openFile: { path, flags, mode in Darwin.open(path, flags, mode) },
            flockFile: { _, operation in
                guard operation & LOCK_UN == 0 else { return 0 }
                errno = EWOULDBLOCK
                return -1
            },
            closeFile: { descriptor in Darwin.close(descriptor) },
            now: { [self] in lock.withLock { elapsed } },
            sleepFor: { [self] interval in lock.withLock { elapsed += interval } }
        )
    }
}
