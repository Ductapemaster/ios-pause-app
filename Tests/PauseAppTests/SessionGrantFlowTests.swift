import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class SessionGrantFlowTests: XCTestCase {
    private let ruleID = UUID(uuidString: "2acf6cb8-46e2-4498-8153-a45be2bf282f")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testUseSessionRunsRealPersistenceAndShowsManualReturnOnlyAfterGrant() async throws {
        let harness = try makeHarness(route: nil, automaticRoute: false, launchSucceeds: false)
        harness.model.sceneDidBecomeActive(now: now)
        guard case .pause = harness.model.entryRoute else {
            return XCTFail("Expected a pause before the grant")
        }

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))

        guard case let .manualReturn(content) = harness.model.entryRoute else {
            return XCTFail("Expected manual return after the grant became active")
        }
        XCTAssertEqual(content.ruleID, ruleID)
        XCTAssertEqual(content.expiresAt, now.addingTimeInterval(5 * 60 + 1))
        XCTAssertEqual(harness.shield.operations, ["unshield"])
        let runtime = try XCTUnwrap(RuntimeRepository(directoryURL: harness.directory).load(ruleID: ruleID))
        XCTAssertEqual(runtime.sessionsStarted, 1)
        XCTAssertEqual(runtime.openSession?.state, .active)
    }

    func testInstagramRouteSuccessChargesExactlyOneSessionAndReturnsToConfiguration() async throws {
        let harness = try makeHarness(route: .instagram, automaticRoute: true, launchSucceeds: true)
        harness.model.sceneDidBecomeActive(now: now)

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))

        guard case .configuration = harness.model.entryRoute else {
            return XCTFail("Successful automatic return should finish the Pause flow")
        }
        XCTAssertEqual(harness.launcher.openCount, 1)
        let runtime = try XCTUnwrap(RuntimeRepository(directoryURL: harness.directory).load(ruleID: ruleID))
        XCTAssertEqual(runtime.sessionsStarted, 1)
        XCTAssertEqual(runtime.openSession?.state, .active)
    }

    func testExplicitLaunchFailureRollsBackStopsReconcilesAndChargesNothing() async throws {
        let harness = try makeHarness(route: .instagram, automaticRoute: true, launchSucceeds: false)
        harness.model.sceneDidBecomeActive(now: now)

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))

        guard case .configuration = harness.model.entryRoute else {
            return XCTFail("A failed handoff should finish at configuration with a visible error")
        }
        XCTAssertEqual(harness.scheduler.stopCount, 1)
        XCTAssertEqual(harness.shield.operations, ["unshield", "shield"])
        XCTAssertNotNil(harness.model.presentedError)
        let runtime = try XCTUnwrap(RuntimeRepository(directoryURL: harness.directory).load(ruleID: ruleID))
        XCTAssertEqual(runtime.sessionsStarted, 0)
        XCTAssertNil(runtime.openSession)
    }

    func testAppLaunchRouterOffersOnlyInstagramAndUsesExactPublicURL() async throws {
        let instagramID = ruleID
        let otherID = UUID(uuidString: "d7636097-103c-45ad-a6aa-f4f7b85f8681")!
        var openedURL: URL?
        let router = AppLaunchRouter(
            routes: [instagramID: .instagram],
            openURL: { url in
                openedURL = url
                return true
            }
        )

        XCTAssertTrue(router.hasAutomaticRoute(ruleID: instagramID))
        XCTAssertFalse(router.hasAutomaticRoute(ruleID: otherID))
        let openedInstagram = await router.open(ruleID: instagramID)
        XCTAssertTrue(openedInstagram)
        XCTAssertEqual(openedURL, URL(string: "instagram://"))
        let openedOther = await router.open(ruleID: otherID)
        XCTAssertFalse(openedOther)
    }

    func testDuplicateRequestAndSceneReactivationDoNotRestartSuspendedLaunch() async throws {
        let launcher = SuspendedLauncher()
        let harness = try makeHarness(
            route: .instagram,
            automaticRoute: true,
            launchSucceeds: true,
            launcherOverride: launcher
        )
        harness.model.sceneDidBecomeActive(now: now)

        let firstGrant = Task {
            await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))
        }
        await launcher.waitUntilOpenStarts()

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))
        harness.model.sceneDidBecomeInactive()
        harness.model.sceneDidBecomeActive(now: now.addingTimeInterval(2))

        XCTAssertEqual(harness.scheduler.registerCount, 1)
        XCTAssertEqual(launcher.openCount, 1)
        XCTAssertTrue(harness.model.isGrantRequested)
        guard case .pause = harness.model.entryRoute else {
            return XCTFail("The suspended grant must remain the active flow")
        }

        launcher.resume(result: true)
        await firstGrant.value
        XCTAssertEqual(harness.scheduler.registerCount, 1)
        guard case .configuration = harness.model.entryRoute else {
            return XCTFail("The original grant should finish once")
        }
    }

    func testRepairFailureAlertReportsUnknownChargeAndShieldState() async throws {
        let runtime = FailingRollbackRuntime()
        let scheduler = AppFakeScheduler()
        scheduler.stopError = AppGrantTestError.stop
        let shield = AppFakeShield()
        shield.failedGrantShieldError = AppGrantTestError.forceShield
        let harness = try makeHarness(
            route: .instagram,
            automaticRoute: true,
            launchSucceeds: false,
            schedulerOverride: scheduler,
            shieldOverride: shield,
            runtimePersistence: runtime
        )
        harness.model.sceneDidBecomeActive(now: now)

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))

        let message = try XCTUnwrap(harness.model.presentedError?.message)
        XCTAssertTrue(message.contains("couldn't confirm whether the session was charged"))
        XCTAssertTrue(message.contains("couldn't confirm whether the app was blocked"))
        XCTAssertTrue(message.contains("roll back session state"))
        XCTAssertFalse(message.contains("stop expiry monitoring"))
        XCTAssertTrue(message.contains("block the app again"))
        XCTAssertFalse(message.contains("session was not charged, and the app remains blocked"))
    }

    func testFailedGrantAlertReportsImmediateBlockWithUnknownDurability() async throws {
        let runtime = FailingRollbackRuntime()
        let shield = AppFakeShield()
        shield.failedGrantShieldOutcome = .immediateOnly(AppGrantTestError.markerPersistence)
        let harness = try makeHarness(
            route: .instagram,
            automaticRoute: true,
            launchSucceeds: false,
            shieldOverride: shield,
            runtimePersistence: runtime
        )
        harness.model.sceneDidBecomeActive(now: now)

        await harness.model.requestSessionGrant(now: now.addingTimeInterval(1))

        let message = try XCTUnwrap(harness.model.presentedError?.message)
        XCTAssertTrue(message.contains("blocked now"))
        XCTAssertTrue(message.contains("future reconciliation"))
        XCTAssertTrue(message.contains("save the failed-session block"))
        XCTAssertFalse(message.contains("couldn't confirm whether the app was blocked"))
    }

    private func makeHarness(
        route: LaunchRoute?,
        automaticRoute: Bool,
        launchSucceeds: Bool,
        launcherOverride: (any TargetLaunching)? = nil,
        schedulerOverride: AppFakeScheduler? = nil,
        shieldOverride: AppFakeShield? = nil,
        runtimePersistence: (any RuntimePersisting)? = nil
    ) throws -> AppGrantHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-task-seven-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let tokenData = Data(ruleID.uuidString.utf8).base64EncodedString()
        let token = try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(tokenData)\"}".utf8)
        )
        let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: try GlobalSettings(pauseSeconds: 1),
                    rules: [rule],
                    targets: [
                        RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: route)
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: ruleID
        )

        let scheduler = schedulerOverride ?? AppFakeScheduler()
        let shield = shieldOverride ?? AppFakeShield()
        let launcher = AppFakeLauncher(
            automaticRoute: automaticRoute,
            launchSucceeds: launchSucceeds
        )
        let model = AppModel(
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {},
            entryActivationProvider: { activationDate in
                PauseActivationResolution(
                    payload: .pause(
                        PauseEntryContext(
                            details: PauseEntryDetails(
                                ruleID: self.ruleID,
                                sessionNumber: 1,
                                sessionsPerDay: 3,
                                lengthMinutes: 5,
                                pauseSeconds: 1
                            ),
                            applicationToken: token,
                            countdown: try PauseCountdown(
                                ruleID: self.ruleID,
                                seconds: 1,
                                now: activationDate
                            )
                        )
                    ),
                    performMaintenance: false
                )
            },
            sessionScheduler: scheduler,
            sessionRuntimePersistence: runtimePersistence,
            sessionShieldController: shield,
            targetLauncher: launcherOverride ?? launcher
        )
        return AppGrantHarness(
            directory: directory,
            model: model,
            scheduler: scheduler,
            shield: shield,
            launcher: launcher
        )
    }
}

@MainActor
private struct AppGrantHarness {
    let directory: URL
    let model: AppModel
    let scheduler: AppFakeScheduler
    let shield: AppFakeShield
    let launcher: AppFakeLauncher
}

@MainActor
private final class AppFakeScheduler: SessionScheduling {
    private(set) var registerCount = 0
    private(set) var stopCount = 0
    var stopError: Error?

    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        registerCount += 1
        return SessionActivityName.sessionActivityName(for: ruleID)
    }

    func stop(activityName: String) throws {
        stopCount += 1
        if let stopError { throw stopError }
    }
}

@MainActor
private final class AppFakeShield: ShieldControlling {
    private(set) var operations: [String] = []
    var shieldError: Error?
    var failedGrantShieldError: Error?
    var failedGrantShieldOutcome: ForceShieldOutcome = .durable

    func unshield(ruleID: UUID) throws { operations.append("unshield") }
    func shield(ruleID: UUID) throws {
        operations.append("shield")
        if let shieldError { throw shieldError }
    }

    func forceShieldForFailedGrant(ruleID: UUID) throws -> ForceShieldOutcome {
        operations.append("force-failed-grant-shield")
        if let failedGrantShieldError { throw failedGrantShieldError }
        return failedGrantShieldOutcome
    }
}

@MainActor
private final class AppFakeLauncher: TargetLaunching {
    let automaticRoute: Bool
    let launchSucceeds: Bool
    private(set) var openCount = 0

    init(automaticRoute: Bool, launchSucceeds: Bool) {
        self.automaticRoute = automaticRoute
        self.launchSucceeds = launchSucceeds
    }

    func hasAutomaticRoute(ruleID: UUID) -> Bool { automaticRoute }

    func open(ruleID: UUID) async -> Bool {
        openCount += 1
        return launchSucceeds
    }
}

@MainActor
private final class SuspendedLauncher: TargetLaunching {
    private(set) var openCount = 0
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<Bool, Never>?

    func hasAutomaticRoute(ruleID: UUID) -> Bool { true }

    func open(ruleID: UUID) async -> Bool {
        openCount += 1
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilOpenStarts() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume(result: Bool) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

@MainActor
private final class FailingRollbackRuntime: RuntimePersisting {
    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws {}
    func activate(ruleID: UUID) throws {}
    func rollBack(ruleID: UUID) throws { throw AppGrantTestError.rollback }
}

private enum AppGrantTestError: LocalizedError {
    case rollback
    case stop
    case forceShield
    case markerPersistence

    var errorDescription: String? {
        switch self {
        case .rollback: "runtime rollback failed"
        case .stop: "monitor stop failed"
        case .forceShield: "forced shield failed"
        case .markerPersistence: "marker persistence failed"
        }
    }
}
