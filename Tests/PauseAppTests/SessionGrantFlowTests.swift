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
        XCTAssertEqual(harness.shield.operations, ["unshield", "reconcile"])
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

    private func makeHarness(
        route: LaunchRoute?,
        automaticRoute: Bool,
        launchSucceeds: Bool
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
            ConfigurationDocument(
                settings: try GlobalSettings(pauseSeconds: 1),
                rules: [rule],
                targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: route)]
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: ruleID
        )

        let scheduler = AppFakeScheduler()
        let shield = AppFakeShield()
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
            sessionShieldController: shield,
            targetLauncher: launcher
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

private final class AppFakeScheduler: SessionScheduling, @unchecked Sendable {
    private(set) var stopCount = 0

    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        SessionActivityName.sessionActivityName(for: ruleID)
    }

    func stop(activityName: String) throws {
        stopCount += 1
    }
}

private final class AppFakeShield: ShieldControlling, @unchecked Sendable {
    private(set) var operations: [String] = []

    func unshield(ruleID: UUID) throws { operations.append("unshield") }
    func reconcile() throws { operations.append("reconcile") }
}

private final class AppFakeLauncher: TargetLaunching, @unchecked Sendable {
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
