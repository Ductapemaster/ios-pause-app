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

    func testFailedGrantForceShieldOverridesProvisionalRuntimeAndTouchesOnlySelectedToken() throws {
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
        let blockStore = FailedGrantBlockStore(directoryURL: directory)
        let reconciler = ShieldReconciler(
            currentApplications: { appliedApplications },
            applyApplications: { appliedApplications = $0 },
            failedGrantBlockIDs: { try blockStore.load() }
        )
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: reconciler,
            failedGrantBlockStore: blockStore
        )

        let outcome = try adapter.forceShieldForFailedGrant(ruleID: selectedID)

        XCTAssertTrue(outcome.isDurable)
        XCTAssertEqual(appliedApplications, [selectedToken])
        XCTAssertFalse(appliedApplications?.contains(otherToken) == true)

        let reloadedBlockStore = FailedGrantBlockStore(directoryURL: directory)
        XCTAssertTrue(try reloadedBlockStore.contains(ruleID: selectedID))
        var reconciledApplications: Set<ApplicationToken>?
        let newReconciler = ShieldReconciler(
            currentApplications: { reconciledApplications },
            applyApplications: { reconciledApplications = $0 },
            failedGrantBlockIDs: { try reloadedBlockStore.load() }
        )

        try newReconciler.reconcile(
            configuration: configuration,
            runtimeRepository: RuntimeRepository(directoryURL: directory),
            now: now
        )

        XCTAssertEqual(reconciledApplications, [selectedToken])
        XCTAssertFalse(reconciledApplications?.contains(otherToken) == true)
    }

    func testFailedGrantForceShieldDoesNotInspectUnrelatedUnreadableRuntime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selectedID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let otherID = UUID(uuidString: "d16fdfd3-8764-437c-994b-adc70ae406d3")!
        let selectedToken = try token(seed: "selected")
        let otherToken = try token(seed: "other")
        let configuration = try twoRuleConfiguration(
            selectedID: selectedID,
            selectedToken: selectedToken,
            otherID: otherID,
            otherToken: otherToken
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("runtime-\(otherID.uuidString.lowercased()).json")
        )
        var appliedApplications: Set<ApplicationToken>? = [otherToken]
        let blockStore = FailedGrantBlockStore(directoryURL: directory)
        let reconciler = ShieldReconciler(
            currentApplications: { appliedApplications },
            applyApplications: { appliedApplications = $0 },
            failedGrantBlockIDs: { try blockStore.load() }
        )
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: reconciler,
            failedGrantBlockStore: blockStore
        )

        let outcome = try adapter.forceShieldForFailedGrant(ruleID: selectedID)

        XCTAssertTrue(outcome.isDurable)
        XCTAssertEqual(appliedApplications, [selectedToken, otherToken])
    }

    func testFailedGrantForceShieldPersistsBeforeApplyingImmediateBlock() throws {
        let selectedID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let selectedToken = try token(seed: "selected")
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: selectedID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: selectedID, applicationToken: selectedToken, launchRoute: nil)]
        )
        let log = AdapterOperationLog()
        let blockStore = OrderedBlockStore(log: log)
        let reconciler = ShieldReconciler(
            currentApplications: { [] },
            applyApplications: { _ in log.append("apply-shield") },
            failedGrantBlockIDs: { [] }
        )
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: reconciler,
            failedGrantBlockStore: blockStore
        )

        let outcome = try adapter.forceShieldForFailedGrant(ruleID: selectedID)

        XCTAssertTrue(outcome.isDurable)
        XCTAssertEqual(log.values, ["persist-marker", "apply-shield"])
    }

    func testFailedGrantMarkerPersistenceFailureStillAppliesShieldInOrder() throws {
        let ruleID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token(seed: "selected"), launchRoute: nil)]
        )
        let log = AdapterOperationLog()
        let blockStore = OrderedBlockStore(log: log)
        blockStore.addError = AdapterTestError.persistence
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in log.append("apply-shield") },
                failedGrantBlockIDs: { [] }
            ),
            failedGrantBlockStore: blockStore
        )

        let outcome = try adapter.forceShieldForFailedGrant(ruleID: ruleID)

        XCTAssertFalse(outcome.isDurable)
        XCTAssertEqual(outcome.persistenceError as? AdapterTestError, .persistence)
        XCTAssertEqual(log.values, ["persist-marker", "apply-shield"])
    }

    func testFailedGrantForceShieldResolvesTargetBeforePersistingMarker() throws {
        let knownID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let missingID = UUID(uuidString: "d16fdfd3-8764-437c-994b-adc70ae406d3")!
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: knownID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: knownID, applicationToken: token(seed: "known"), launchRoute: nil)]
        )
        let log = AdapterOperationLog()
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in log.append("apply-shield") },
                failedGrantBlockIDs: { [] }
            ),
            failedGrantBlockStore: OrderedBlockStore(log: log)
        )

        XCTAssertThrowsError(try adapter.forceShieldForFailedGrant(ruleID: missingID))
        XCTAssertEqual(log.values, [])
    }

    func testFailedGrantForceShieldAppliesImmediateBlockWhenDurableMarkerCannotBeStored() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent(SharedIdentifiers.failedGrantBlocksFilename)
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)
        let ruleID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let selectedToken = try token(seed: "selected")
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: selectedToken, launchRoute: nil)]
        )
        var appliedApplications: Set<ApplicationToken>?
        let blockStore = FailedGrantBlockStore(directoryURL: directory)
        let reconciler = ShieldReconciler(
            currentApplications: { appliedApplications },
            applyApplications: { appliedApplications = $0 },
            failedGrantBlockIDs: { try blockStore.load() }
        )
        let adapter = ConfigurationShieldController(
            configuration: configuration,
            reconciler: reconciler,
            failedGrantBlockStore: blockStore
        )

        let outcome = try adapter.forceShieldForFailedGrant(ruleID: ruleID)

        XCTAssertFalse(outcome.isDurable)
        XCTAssertNotNil(outcome.persistenceError)
        XCTAssertEqual(appliedApplications, [selectedToken])
    }

    func testSuccessfulRollbackUsesImmediateShieldWithoutMarkerAndLaterSessionCanReconcileOpen() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let selectedToken = try token(seed: "selected")
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: selectedToken, launchRoute: .instagram)]
        )
        let repository = RuntimeRepository(directoryURL: directory)
        try repository.save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: ruleID
        )
        let blockStore = FailedGrantBlockStore(directoryURL: directory)
        var appliedApplications: Set<ApplicationToken>?
        let controller = ConfigurationShieldController(
            configuration: configuration,
            reconciler: ShieldReconciler(
                currentApplications: { appliedApplications },
                applyApplications: { appliedApplications = $0 },
                failedGrantBlockIDs: { try blockStore.load() }
            ),
            failedGrantBlockStore: blockStore
        )
        let coordinator = SessionGrantCoordinator(
            scheduler: AdapterScheduler(),
            runtime: RepositoryRuntimePersistence(repository: repository, now: now),
            shield: controller,
            launcher: AdapterFailingLauncher()
        )

        do {
            _ = try await coordinator.grant(
                rule: configuration.rules[0],
                now: now
            )
            XCTFail("Expected launch failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.chargeState, .notCharged)
            XCTAssertEqual(failure.shieldState, .blocked)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }

        XCTAssertFalse(try blockStore.contains(ruleID: ruleID))
        XCTAssertEqual(appliedApplications, [selectedToken])
        try repository.save(
            RuleRuntime(
                logicalDay: CalendarDay(date: now, calendar: .current),
                sessionsStarted: 1,
                openSession: OpenSession(
                    activityName: SessionActivityName.sessionActivityName(for: ruleID),
                    expiresAt: now.addingTimeInterval(5 * 60),
                    state: .active
                )
            ),
            ruleID: ruleID
        )
        var restartedApplications: Set<ApplicationToken>? = [selectedToken]
        let restartedReconciler = ShieldReconciler(
            currentApplications: { restartedApplications },
            applyApplications: { restartedApplications = $0 },
            failedGrantBlockIDs: { try FailedGrantBlockStore(directoryURL: directory).load() }
        )

        try restartedReconciler.reconcile(
            configuration: configuration,
            runtimeRepository: RuntimeRepository(directoryURL: directory),
            now: now
        )

        XCTAssertEqual(restartedApplications, [])
    }

    func testRollbackFailurePersistsMarkerShieldsImmediatelyAndRetainsMonitoring() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID(uuidString: "d8aa967e-10a8-4a9d-a4ab-e49aaf19fa9a")!
        let selectedToken = try token(seed: "selected")
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let configuration = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: selectedToken, launchRoute: .instagram)]
        )
        let repository = RuntimeRepository(directoryURL: directory)
        try repository.save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: ruleID
        )
        let blockStore = FailedGrantBlockStore(directoryURL: directory)
        var appliedApplications: Set<ApplicationToken>?
        let controller = ConfigurationShieldController(
            configuration: configuration,
            reconciler: ShieldReconciler(
                currentApplications: { appliedApplications },
                applyApplications: { appliedApplications = $0 },
                failedGrantBlockIDs: { try blockStore.load() }
            ),
            failedGrantBlockStore: blockStore
        )
        let scheduler = AdapterScheduler()
        let coordinator = SessionGrantCoordinator(
            scheduler: scheduler,
            runtime: AdapterRollbackFailingRuntime(
                underlying: RepositoryRuntimePersistence(repository: repository, now: now)
            ),
            shield: controller,
            launcher: AdapterFailingLauncher()
        )

        do {
            _ = try await coordinator.grant(rule: configuration.rules[0], now: now)
            XCTFail("Expected launch failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.chargeState, .unknown)
            XCTAssertEqual(failure.shieldState, .blocked)
            XCTAssertEqual(failure.repairErrors.map(\.step), [.rollBackRuntime])
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }

        XCTAssertTrue(try blockStore.contains(ruleID: ruleID))
        XCTAssertEqual(appliedApplications, [selectedToken])
        XCTAssertEqual(scheduler.stopCount, 0)
        XCTAssertEqual(try repository.load(ruleID: ruleID)?.openSession?.state, .provisional)
    }

    private func twoRuleConfiguration(
        selectedID: UUID,
        selectedToken: ApplicationToken,
        otherID: UUID,
        otherToken: ApplicationToken
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
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

@MainActor
private final class AdapterOperationLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

@MainActor
private final class OrderedBlockStore: FailedGrantBlockStoring {
    let log: AdapterOperationLog
    var addError: Error?

    init(log: AdapterOperationLog) {
        self.log = log
    }

    func load() throws -> Set<UUID> { [] }
    func add(ruleID: UUID) throws {
        log.append("persist-marker")
        if let addError { throw addError }
    }
    func clear(ruleID: UUID) throws {}
    func contains(ruleID: UUID) throws -> Bool { false }
}

private enum AdapterTestError: Error, Equatable {
    case persistence
    case rollback
}

@MainActor
private final class AdapterScheduler: SessionScheduling {
    private(set) var stopCount = 0

    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        SessionActivityName.sessionActivityName(for: ruleID)
    }

    func stop(activityName: String) throws { stopCount += 1 }
}

@MainActor
private final class AdapterRollbackFailingRuntime: RuntimePersisting {
    private let underlying: any RuntimePersisting

    init(underlying: any RuntimePersisting) {
        self.underlying = underlying
    }

    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws {
        try underlying.reserve(ruleID: ruleID, activityName: activityName, expiresAt: expiresAt)
    }

    func activate(ruleID: UUID) throws {
        try underlying.activate(ruleID: ruleID)
    }

    func rollBack(ruleID: UUID) throws {
        throw AdapterTestError.rollback
    }
}

@MainActor
private final class AdapterFailingLauncher: TargetLaunching {
    func hasAutomaticRoute(ruleID: UUID) -> Bool { true }
    func open(ruleID: UUID) async -> Bool { false }
}
