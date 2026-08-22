import Foundation
import ManagedSettings
import PauseCore
import XCTest

@MainActor
final class SessionReconciliationServiceTests: XCTestCase {
    private let ruleID = UUID(uuidString: "6f1a0e1c-1f3e-4a2b-9c0d-2b7f5a8e4d31")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let calendar = Calendar.current

    func testReconciliationUsesThePendingConfigurationOnceItsStartDayArrives() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.containing(now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .appActivation)

        XCTAssertEqual(applied, [])
    }

    func testReconciliationKeepsTheEffectiveConfigurationBeforeTheStartDay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.next(after: now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .appActivation)

        XCTAssertEqual(applied, [try token(seed: "instagram")])
    }

    func testTheResetReleasesAnApplicationWhoseRemovalHasLanded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.containing(now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .dailyReset)

        XCTAssertEqual(applied, [])
    }

    func testTheResetKeepsShieldingAnApplicationWhoseRemovalHasNotLanded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.next(after: now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .dailyReset)

        XCTAssertEqual(applied, [try token(seed: "instagram")])
    }

    // MARK: - Helpers

    /// One rule in force, and a pending document that removes it.
    private func seedRemovalPending(in directory: URL, startDay: CalendarDay) throws {
        let effective = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [
                RuleTarget(
                    ruleID: ruleID,
                    applicationToken: try token(seed: "instagram"),
                    launchRoute: nil
                )
            ]
        )
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: effective,
                pending: PendingConfiguration(
                    document: try ConfigurationDocument(
                        settings: .phaseOneDefault,
                        rules: [],
                        targets: []
                    ),
                    startDay: startDay
                )
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, calendar: calendar),
                sessionsStarted: 0
            ),
            ruleID: ruleID
        )
    }

    /// The shield set is never written to disk and `ManagedSettingsStore` is out
    /// of reach in the simulator, so the injected apply closure is where a test
    /// reads what the reconcile decided.
    private func makeService(
        directory: URL,
        applyApplications: @escaping (Set<ApplicationToken>) -> Void
    ) -> SessionReconciliationService {
        SessionReconciliationService(
            directoryURL: directory,
            shieldReconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: applyApplications,
                failedGrantBlockIDs: { [] },
                stateLock: AppGroupFileLock(directoryURL: directory)
            ),
            stopMonitoring: { _ in }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-reconciliation-service-tests-\(UUID().uuidString)", isDirectory: true)
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
