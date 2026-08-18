import FamilyControls
import Foundation
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class AppModelFlowTests: XCTestCase {
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
        XCTAssertNotNil(try ConfigurationStore(directoryURL: directory).load())
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
            ConfigurationDocument(settings: .phaseOneDefault, rules: [], targets: [])
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.updatePauseSeconds(17)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 17)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).load()?.settings.pauseSeconds,
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

    private func writeEmptyConfiguration(to directory: URL) throws {
        try ConfigurationStore(directoryURL: directory).save(
            ConfigurationDocument(settings: .phaseOneDefault, rules: [], targets: [])
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
