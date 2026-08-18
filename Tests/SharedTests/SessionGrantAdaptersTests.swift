import Foundation
import ManagedSettings
import PauseCore
import XCTest

@MainActor
final class SessionGrantAdaptersTests: XCTestCase {
    func testReserveRollsOverAndReplacesExpiredSession() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RuntimeRepository(directoryURL: directory)
        let ruleID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        try repository.save(
            RuleRuntime(
                logicalDay: CalendarDay(date: yesterday, calendar: .current),
                sessionsStarted: 3,
                openSession: OpenSession(
                    activityName: "session.expired",
                    expiresAt: now.addingTimeInterval(-1),
                    state: .active
                )
            ),
            ruleID: ruleID
        )
        let adapter = RepositoryRuntimePersistence(repository: repository, now: now)
        let expiresAt = now.addingTimeInterval(5 * 60)

        try adapter.reserve(ruleID: ruleID, activityName: "session.new", expiresAt: expiresAt)

        let runtime = try XCTUnwrap(repository.load(ruleID: ruleID))
        XCTAssertEqual(runtime.logicalDay, CalendarDay(date: now, calendar: .current))
        XCTAssertEqual(runtime.sessionsStarted, 1)
        XCTAssertEqual(
            runtime.openSession,
            OpenSession(activityName: "session.new", expiresAt: expiresAt, state: .provisional)
        )
    }

    func testForceShieldOverridesProvisionalRuntimeAndTouchesOnlySelectedToken() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RuntimeRepository(directoryURL: directory)
        let selectedID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let otherID = UUID(uuidString: "d16fdfd3-8764-437c-994b-adc70ae406d3")!
        let selectedToken = try token(seed: "selected")
        let otherToken = try token(seed: "other")
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        for ruleID in [selectedID, otherID] {
            try repository.save(
                RuleRuntime(
                    logicalDay: CalendarDay(date: now, calendar: .current),
                    sessionsStarted: 1,
                    openSession: OpenSession(
                        activityName: SessionActivityName.sessionActivityName(for: ruleID),
                        expiresAt: now.addingTimeInterval(5 * 60),
                        state: .provisional
                    )
                ),
                ruleID: ruleID
            )
        }
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [
                AppRule(id: selectedID, sessionsPerDay: 3, sessionLengthMinutes: 5),
                AppRule(id: otherID, sessionsPerDay: 3, sessionLengthMinutes: 5),
            ],
            targets: [
                RuleTarget(ruleID: selectedID, applicationToken: selectedToken, launchRoute: nil),
                RuleTarget(ruleID: otherID, applicationToken: otherToken, launchRoute: nil),
            ]
        )
        var appliedApplications: Set<ApplicationToken>?
        let reconciler = ShieldReconciler(
            currentApplications: { appliedApplications },
            applyApplications: { appliedApplications = $0 }
        )
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            runtimeRepository: repository,
            reconciler: reconciler,
            now: now
        )

        try adapter.forceShield(ruleID: selectedID)

        XCTAssertEqual(appliedApplications, [selectedToken])
        XCTAssertFalse(appliedApplications?.contains(otherToken) == true)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-adapter-tests-\(UUID().uuidString)", isDirectory: true)
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
}
