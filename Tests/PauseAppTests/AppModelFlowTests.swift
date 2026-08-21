import FamilyControls
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class AppModelFlowTests: XCTestCase {
    private let ruleID = UUID(uuidString: "3f7c1d20-6b8a-4f19-8e42-0a5c9d1b7e63")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testUnsafeRootPrecedesAuthorizationAndCannotDismissIntoConfiguration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .denied)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: true)

        XCTAssertEqual(model.rootRoute, .configurationRepair)
        model.returnToConfiguration()
        XCTAssertEqual(model.rootRoute, .configurationRepair)
    }

    func testUnsafePickerMutationPerformsNoPersistenceCleanupOrReconciliation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtimeURL = directory.appendingPathComponent("runtime-existing.json")
        let originalRuntime = Data("do-not-delete".utf8)
        try originalRuntime.write(to: runtimeURL)
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: true)

        XCTAssertThrowsError(try model.applyPickerSelection())
        XCTAssertEqual(try Data(contentsOf: runtimeURL), originalRuntime)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("configuration.json").path
        ))
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
        XCTAssertEqual(model.configurationLoadState, .missing)
    }

    func testFailedConfigurationCannotBePromotedByPickerSave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent("configuration.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: configurationURL)
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        XCTAssertThrowsError(try model.applyPickerSelection())
        XCTAssertEqual(model.configurationLoadState, .failed)
        XCTAssertEqual(try Data(contentsOf: configurationURL), corruptData)
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testFreshMissingPickerSaveCreatesKnownGoodConfiguration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.applyPickerSelection()

        XCTAssertEqual(model.configurationLoadState, .knownGood)
        XCTAssertNotNil(try ConfigurationStore(directoryURL: directory).loadFile())
    }

    func testFailedFreshPickerSavePreservesMissingStateAndPartialRuntime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        let partialRuntimeURL = directory.appendingPathComponent("runtime-partial.json")
        let partialRuntime = Data("keep-for-retry".utf8)
        try partialRuntime.write(to: partialRuntimeURL)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("configuration.json"),
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try model.applyPickerSelection())

        XCTAssertEqual(model.configurationLoadState, .missing)
        XCTAssertEqual(try Data(contentsOf: partialRuntimeURL), partialRuntime)
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testKnownGoodTaskFourMutationsRemainWired() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [],
                    targets: []
                ),
                pending: nil
            )
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.updatePauseSeconds(17)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 17)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).loadFile()?.effective.settings.pauseSeconds,
            17
        )
    }

    func testRootRoutingUsesProductionSafetyPrecedence() throws {
        let unsafeDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: unsafeDirectory) }
        let unsafe = makeModel(
            directory: unsafeDirectory,
            probe: FlowProbe(status: .denied),
            hasProtectedState: true
        )
        XCTAssertEqual(unsafe.rootRoute, .configurationRepair)

        let authorizationDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: authorizationDirectory) }
        let authorization = makeModel(
            directory: authorizationDirectory,
            probe: FlowProbe(status: .denied),
            hasProtectedState: false
        )
        XCTAssertEqual(authorization.rootRoute, .authorization)

        let configurationDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: configurationDirectory) }
        let configuration = makeModel(
            directory: configurationDirectory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        XCTAssertEqual(configuration.rootRoute, .authorizedContent)
    }

    func testAuthorizationCompletionWhileInactiveDefersIntentUntilRealActiveEntry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        probe.authorizationRequest = { probe.status = .approved }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidBecomeInactive()

        await model.requestAuthorization()
        XCTAssertEqual(probe.intentConsumptionCount, 0)
        XCTAssertNil(probe.startedCountdown)

        let activeAt = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: activeAt)
        XCTAssertEqual(probe.intentConsumptionCount, 1)
        XCTAssertEqual(probe.startedCountdown?.startedAt, activeAt)
        XCTAssertEqual(probe.startedCountdown?.remainingSeconds(at: activeAt), 10)
    }

    func testAuthorizationCompletionWhileActiveRerunsActivationExactlyOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        probe.authorizationRequest = { probe.status = .approved }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidBecomeActive(now: Date(timeIntervalSince1970: 1_750_000_000))

        await model.requestAuthorization()

        XCTAssertEqual(probe.intentConsumptionCount, 1)
        guard let countdown = probe.startedCountdown else {
            return XCTFail("Authorization completion should start one active-scene attempt")
        }
        XCTAssertEqual(countdown.remainingSeconds(at: countdown.startedAt), 10)
    }

    func testActiveCallbackWinningAuthorizationRaceDoesNotConsumeTwice() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        let gate = AuthorizationGate()
        probe.authorizationRequest = { await gate.wait() }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidBecomeInactive()

        let request = Task { await model.requestAuthorization() }
        await Task.yield()
        probe.status = .approved
        let activeAt = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: activeAt)
        gate.resume()
        await request.value

        XCTAssertEqual(probe.intentConsumptionCount, 1)
        XCTAssertEqual(probe.startedCountdown?.startedAt, activeAt)
        XCTAssertEqual(probe.startedCountdown?.remainingSeconds(at: activeAt), 10)
    }

    func testRaisingAnAllowanceLeavesTodaysRuleInPlace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(
            id: ruleID,
            sessionsPerDay: 5,
            sessionLengthMinutes: 5,
            now: now
        )

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
    }

    func testLoweringAnAllowanceAppliesAtOnceAndClearsASchedule() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        try model.updateRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5, now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 2)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testCancellingAScheduledChangeLeavesTodaysRuleInForce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        model.cancelScheduledChange(now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertNil(model.pendingChangeStartDay)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).loadFile()?.pending,
            nil
        )
    }

    func testShorteningThePauseWaitsWhileLengtheningItAppliesAtOnce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updatePauseSeconds(5, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 10)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testRemovingAnAppLeavesItsRuntimeUntilTheChangeTakesEffect() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let runtimeURL = directory.appendingPathComponent(
            "runtime-\(ruleID.uuidString.lowercased()).json"
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.removeRule(id: ruleID, now: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeURL.path))
        XCTAssertEqual(model.configuration.targets.count, 1)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testDroppingAnAppFromThePickerKeepsItSelectedUntilTheRemovalLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(model.pickerSelection.applicationTokens, [try token(seed: "instagram")])
        XCTAssertEqual(model.configuration.rules.map(\.id), [ruleID])
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
    }

    func testTheRemovalTakesTheAppAndItsSelectionWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertTrue(model.configuration.rules.isEmpty)
        XCTAssertTrue(model.pickerSelection.applicationTokens.isEmpty)
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testAPickerSaveThatAddsAndDropsCoversTheAddedAppToday() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // One trip through the picker: Instagram dropped, Threads added.
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(
            Set(model.configuration.targets.map(\.applicationToken)),
            [try token(seed: "instagram"), try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertTrue(model.lastSaveDeferredPart)
    }

    func testTheAddedAppSurvivesTheDropWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertEqual(
            model.configuration.targets.map(\.applicationToken),
            [try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testATighteningSaveDefersNothingOfItsOwnWhileAChangeIsScheduled() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // Schedule Instagram's removal, then lengthen the pause — a tightening
        // that says nothing about Instagram.
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)
        XCTAssertTrue(model.lastSaveDeferredPart)

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertFalse(model.lastSaveDeferredPart)
        // The removal is still scheduled; only this save deferred nothing.
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
    }

    private func makeModel(
        directory: URL,
        probe: FlowProbe,
        hasProtectedState: Bool
    ) -> AppModel {
        AppModel(
            storageDirectoryURL: directory,
            authorizationStatusProvider: { probe.status },
            authorizationRequester: { try await probe.requestAuthorization() },
            entryActivationProvider: { now in
                probe.intentConsumptionCount += 1
                probe.startedCountdown = try PauseCountdown(
                    ruleID: UUID(uuidString: "b7ee38c9-cfed-4fbc-aa35-df716b5001ab")!,
                    seconds: 10,
                    now: now
                )
                return PauseActivationResolution(
                    payload: .configuration,
                    performMaintenance: false
                )
            },
            protectedStateDetector: { _ in hasProtectedState },
            cleanupOverride: { probe.cleanupCount += 1 },
            reconciliationOverride: { probe.reconciliationCount += 1 }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedOneRule(in directory: URL, sessionsPerDay: Int) throws {
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [
                        AppRule(
                            id: ruleID,
                            sessionsPerDay: sessionsPerDay,
                            sessionLengthMinutes: 5
                        )
                    ],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: try token(seed: "instagram"),
                            launchRoute: nil
                        )
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(logicalDay: LogicalDay.containing(now), sessionsStarted: 0),
            ruleID: ruleID
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }

    private func writeEmptyConfiguration(to directory: URL) throws {
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [],
                    targets: []
                ),
                pending: nil
            )
        )
    }
}

@MainActor
private final class FlowProbe {
    var status: AuthorizationStatus
    var authorizationRequest: () async throws -> Void = {}
    var intentConsumptionCount = 0
    var startedCountdown: PauseCountdown?
    var cleanupCount = 0
    var reconciliationCount = 0

    init(status: AuthorizationStatus) {
        self.status = status
    }

    func requestAuthorization() async throws {
        try await authorizationRequest()
    }
}

@MainActor
private final class AuthorizationGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
