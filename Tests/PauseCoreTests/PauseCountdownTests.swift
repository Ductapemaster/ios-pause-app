import XCTest
@testable import PauseCore

final class PauseCountdownTests: XCTestCase {
    private let ruleID = UUID(uuidString: "42a50b5f-6a9d-4a65-b5db-25af5bb6607c")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testCreationStartsWithTheFullConfiguredDuration() throws {
        let countdown = try PauseCountdown(ruleID: ruleID, seconds: 10, now: now)

        XCTAssertEqual(countdown.remainingSeconds(at: now), 10)
        XCTAssertEqual(countdown.endsAt, now.addingTimeInterval(10))
    }

    func testRemainingTimeRoundsUpBeforeCompletion() throws {
        let countdown = try PauseCountdown(ruleID: ruleID, seconds: 10, now: now)

        XCTAssertEqual(countdown.remainingSeconds(at: now.addingTimeInterval(9.01)), 1)
    }

    func testCompletionOccursOnlyAtOrAfterTheEndDate() throws {
        let countdown = try PauseCountdown(ruleID: ruleID, seconds: 10, now: now)

        XCTAssertFalse(countdown.isComplete(at: now.addingTimeInterval(9.999)))
        XCTAssertTrue(countdown.isComplete(at: now.addingTimeInterval(10)))
        XCTAssertTrue(countdown.isComplete(at: now.addingTimeInterval(11)))
    }

    func testRejectsNonpositiveDurations() {
        XCTAssertThrowsError(try PauseCountdown(ruleID: ruleID, seconds: 0, now: now)) {
            XCTAssertEqual($0 as? PauseCountdownError, .nonpositiveDuration)
        }
        XCTAssertThrowsError(try PauseCountdown(ruleID: ruleID, seconds: -1, now: now)) {
            XCTAssertEqual($0 as? PauseCountdownError, .nonpositiveDuration)
        }
    }

    func testNewCountdownAfterAbandonmentRestartsAtTheFullDuration() throws {
        let abandoned = try PauseCountdown(ruleID: ruleID, seconds: 10, now: now)
        let restartedAt = now.addingTimeInterval(4)
        let restarted = try PauseCountdown(ruleID: ruleID, seconds: 10, now: restartedAt)

        XCTAssertEqual(abandoned.remainingSeconds(at: restartedAt), 6)
        XCTAssertEqual(restarted.remainingSeconds(at: restartedAt), 10)
        XCTAssertEqual(restarted.startedAt, restartedAt)
    }
}

final class PauseEntryRouterTests: XCTestCase {
    private let ruleID = UUID(uuidString: "d659f0b5-4a4f-4f9d-b1c5-ec85c848b590")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testNormalLaunchRoutesToConfiguration() {
        XCTAssertEqual(PauseEntryRouter.route(input: .noIntent, now: now), .configuration)
    }

    func testStaleIntentRoutesToRepairWithoutStartingPause() {
        let input = PauseEntryInput.intent(
            createdAt: now.addingTimeInterval(-30.001),
            resolution: allowedResolution
        )

        XCTAssertEqual(PauseEntryRouter.route(input: input, now: now), .repair)
    }

    func testUnresolvedIntentRoutesToRepair() {
        let input = PauseEntryInput.intent(createdAt: now, resolution: .invalid)

        XCTAssertEqual(PauseEntryRouter.route(input: input, now: now), .repair)
    }

    func testAllowedIntentRoutesToPauseWithGrantDetails() {
        let input = PauseEntryInput.intent(createdAt: now.addingTimeInterval(-30), resolution: allowedResolution)

        XCTAssertEqual(
            PauseEntryRouter.route(input: input, now: now),
            .pause(
                PauseEntryDetails(
                    ruleID: ruleID,
                    sessionNumber: 2,
                    sessionsPerDay: 3,
                    lengthMinutes: 5,
                    pauseSeconds: 10
                )
            )
        )
    }

    func testRefusedIntentRoutesToTheRefusalReason() {
        let reason = RefusalReason.dailyAllowanceExhausted(limit: 3)
        let input = PauseEntryInput.intent(
            createdAt: now,
            resolution: .resolved(
                ruleID: ruleID,
                sessionsPerDay: 3,
                pauseSeconds: 10,
                decision: .refused(reason)
            )
        )

        XCTAssertEqual(PauseEntryRouter.route(input: input, now: now), .refused(reason))
    }

    func testOpenSessionRefusalRoutesToItsReason() {
        let until = now.addingTimeInterval(300)
        let reason = RefusalReason.sessionAlreadyOpen(until: until)
        let input = PauseEntryInput.intent(
            createdAt: now,
            resolution: .resolved(
                ruleID: ruleID,
                sessionsPerDay: 3,
                pauseSeconds: 10,
                decision: .refused(reason)
            )
        )

        XCTAssertEqual(PauseEntryRouter.route(input: input, now: now), .refused(reason))
    }

    func testFutureDatedIntentRoutesToRepair() {
        let input = PauseEntryInput.intent(
            createdAt: now.addingTimeInterval(0.001),
            resolution: allowedResolution
        )

        XCTAssertEqual(PauseEntryRouter.route(input: input, now: now), .repair)
    }

    private var allowedResolution: PauseEntryResolution {
        .resolved(
            ruleID: ruleID,
            sessionsPerDay: 3,
            pauseSeconds: 10,
            decision: .allowed(sessionNumber: 2, lengthMinutes: 5)
        )
    }
}

final class ForegroundPauseStateTests: XCTestCase {
    func testSceneInactivityAbandonsAnUnfinishedCountdown() {
        XCTAssertEqual(
            ForegroundPauseState.countingDown.transitioned(for: .sceneBecameInactive),
            .configuration
        )
    }

    func testSceneInactivityDoesNotRollBackAStartedGrant() {
        XCTAssertEqual(
            ForegroundPauseState.grantStarted.transitioned(for: .sceneBecameInactive),
            .grantStarted
        )
    }
}

final class PauseActivationCoordinatorTests: XCTestCase {
    private enum TestError: Error {
        case missingRuntime
        case unreadableRuntime
    }

    func testMissingConfigurationWithPendingIntentRepairsWithoutMaintenance() {
        var coordinator = PauseActivationCoordinator(configurationState: .missing)
        var cleanupCount = 0
        var reconciliationCount = 0
        var resolutionCount = 0

        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: { 1 },
            resolveIntent: { _ in
                resolutionCount += 1
                return PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: { cleanupCount += 1 },
            reconcile: { reconciliationCount += 1 }
        )

        XCTAssertEqual(outcome, .repair)
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(reconciliationCount, 0)
        XCTAssertEqual(resolutionCount, 0)
    }

    func testMissingConfigurationWithExistingProtectedStateRepairsWithoutAnIntent() {
        var coordinator = PauseActivationCoordinator(
            configurationState: .missing,
            hasProtectedState: true
        )
        var cleanupCount = 0
        var reconciliationCount = 0

        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: { nil as Int? },
            resolveIntent: { _ in
                XCTFail("Unsafe configuration must not resolve an intent")
                return PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: { cleanupCount += 1 },
            reconcile: { reconciliationCount += 1 }
        )

        XCTAssertEqual(outcome, .repair)
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(reconciliationCount, 0)
    }

    func testFailedConfigurationWithPendingIntentRepairsWithoutMaintenance() {
        var coordinator = PauseActivationCoordinator(configurationState: .failed)
        var cleanupCount = 0
        var reconciliationCount = 0

        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: { 1 },
            resolveIntent: { _ in
                XCTFail("Unsafe configuration must not resolve an intent")
                return PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: { cleanupCount += 1 },
            reconcile: { reconciliationCount += 1 }
        )

        XCTAssertEqual(outcome, .repair)
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(reconciliationCount, 0)
    }

    func testDuplicateActivationDoesNotConsumeASecondIntent() {
        var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
        var consumed = 0

        func activate() -> PauseActivationOutcome<String> {
            coordinator.activate(
                isAuthorized: true,
                consumeIntent: {
                    consumed += 1
                    return 1
                },
                resolveIntent: { _ in
                    PauseActivationResolution(payload: "pause", performMaintenance: true)
                },
                cleanup: {},
                reconcile: {}
            )
        }

        XCTAssertEqual(activate(), .resolved("pause"))
        XCTAssertEqual(activate(), .unchanged)
        XCTAssertEqual(consumed, 1)
    }

    func testReactivationAfterInterruptedCountdownReturnsToConfigurationWithoutANewIntent() {
        var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
        var intents = [1]

        func activate() -> PauseActivationOutcome<String> {
            coordinator.activate(
                isAuthorized: true,
                consumeIntent: { intents.isEmpty ? nil : intents.removeFirst() },
                resolveIntent: { _ in
                    PauseActivationResolution(payload: "pause", performMaintenance: true)
                },
                cleanup: {},
                reconcile: {}
            )
        }

        XCTAssertEqual(activate(), .resolved("pause"))
        coordinator.countdownDidStart()
        coordinator.sceneDidBecomeInactive()
        XCTAssertEqual(coordinator.foregroundState, .configuration)
        XCTAssertEqual(activate(), .configuration)
    }

    func testUnreadableRuntimeRepairsWithoutRuntimeOrShieldMutation() {
        for error in [TestError.missingRuntime, TestError.unreadableRuntime] {
            var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
            var cleanupCount = 0
            var reconciliationCount = 0

            let outcome: PauseActivationOutcome<String> = coordinator.activate(
                isAuthorized: true,
                consumeIntent: { 1 },
                resolveIntent: { _ in
                    throw error
                },
                cleanup: { cleanupCount += 1 },
                reconcile: { reconciliationCount += 1 }
            )

            XCTAssertEqual(outcome, .repair)
            XCTAssertEqual(cleanupCount, 0)
            XCTAssertEqual(reconciliationCount, 0)
        }
    }

    func testBothRefusalReasonsTraverseTheActivationWorkflow() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let ruleID = UUID(uuidString: "2c29cf48-6747-47e3-b9ad-d848630f3178")!
        let reasons: [RefusalReason] = [
            .dailyAllowanceExhausted(limit: 3),
            .sessionAlreadyOpen(until: now.addingTimeInterval(300))
        ]

        for reason in reasons {
            var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
            let outcome: PauseActivationOutcome<PauseEntryRoute> = coordinator.activate(
                isAuthorized: true,
                consumeIntent: { now },
                resolveIntent: { createdAt in
                    let route = PauseEntryRouter.route(
                        input: .intent(
                            createdAt: createdAt,
                            resolution: .resolved(
                                ruleID: ruleID,
                                sessionsPerDay: 3,
                                pauseSeconds: 10,
                                decision: .refused(reason)
                            )
                        ),
                        now: now
                    )
                    return PauseActivationResolution(payload: route, performMaintenance: true)
                },
                cleanup: {},
                reconcile: {}
            )

            XCTAssertEqual(outcome, .resolved(.refused(reason)))
        }
    }

    func testIntentResolutionPrecedesDestructiveMaintenance() {
        var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
        var events: [String] = []

        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: {
                events.append("consume")
                return 1
            },
            resolveIntent: { _ in
                events.append("resolve")
                return PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: { events.append("cleanup") },
            reconcile: { events.append("reconcile") }
        )

        XCTAssertEqual(outcome, .resolved("pause"))
        XCTAssertEqual(events, ["consume", "resolve", "cleanup", "reconcile"])
    }

    func testGrantStartedSurvivesInactivityWithoutReconsumingIntent() {
        var coordinator = PauseActivationCoordinator(configurationState: .knownGood)
        coordinator.grantDidStart()
        coordinator.sceneDidBecomeInactive()
        var consumed = 0

        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: {
                consumed += 1
                return 1
            },
            resolveIntent: { _ in
                PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: {},
            reconcile: {}
        )

        XCTAssertEqual(coordinator.foregroundState, .grantStarted)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(consumed, 0)
    }

    func testSuccessfulReloadEnablesMaintenanceAndLaterFailureDisablesIt() {
        var coordinator = PauseActivationCoordinator(configurationState: .missing)
        coordinator.configurationBecameKnownGood()
        XCTAssertEqual(coordinator.configurationState, .knownGood)

        coordinator.configurationLoadFailed()
        XCTAssertEqual(coordinator.configurationState, .failed)

        var maintenanceCount = 0
        let outcome: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: { nil as Int? },
            resolveIntent: { _ in
                PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: { maintenanceCount += 1 },
            reconcile: { maintenanceCount += 1 }
        )
        XCTAssertEqual(outcome, .repair)
        XCTAssertEqual(maintenanceCount, 0)
    }

    func testUnsafeConfigurationCannotDismissOrMutateThroughAppFlowPolicy() {
        let unsafeCoordinators = [
            PauseActivationCoordinator(configurationState: .failed),
            PauseActivationCoordinator(configurationState: .missing, hasProtectedState: true)
        ]

        for coordinator in unsafeCoordinators {
            XCTAssertTrue(coordinator.requiresConfigurationRepair)
            XCTAssertFalse(coordinator.canDismissConfigurationRepair)
            XCTAssertFalse(coordinator.allowsConfigurationMutation(.pickerSelection))
            XCTAssertFalse(coordinator.allowsConfigurationMutation(.ruleEdit))
            XCTAssertFalse(coordinator.allowsConfigurationMutation(.globalSettingsEdit))
            XCTAssertFalse(coordinator.allowsConfigurationMutation(.ruleRemoval))
        }
    }

    func testUnsafeConfigurationPrecedesAuthorizationAndCannotBeBypassedWhenAuthorizationChanges() {
        var coordinator = PauseActivationCoordinator(configurationState: .failed)
        var cleanupCount = 0
        var reconciliationCount = 0

        func activate(isAuthorized: Bool) -> PauseActivationOutcome<String> {
            coordinator.activate(
                isAuthorized: isAuthorized,
                consumeIntent: { nil as Int? },
                resolveIntent: { _ in
                    PauseActivationResolution(payload: "pause", performMaintenance: true)
                },
                cleanup: { cleanupCount += 1 },
                reconcile: { reconciliationCount += 1 }
            )
        }

        XCTAssertEqual(activate(isAuthorized: false), .repair)
        coordinator.authorizationDidChange()
        XCTAssertEqual(activate(isAuthorized: true), .repair)
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(reconciliationCount, 0)
    }

    func testFreshMissingConfigurationRemainsEditableAcrossAuthorizationChange() {
        var coordinator = PauseActivationCoordinator(configurationState: .missing)

        XCTAssertFalse(coordinator.requiresConfigurationRepair)
        XCTAssertTrue(coordinator.canDismissConfigurationRepair)
        XCTAssertTrue(coordinator.allowsConfigurationMutation(.pickerSelection))
        XCTAssertFalse(coordinator.allowsConfigurationMutation(.ruleEdit))

        let unauthorized: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: false,
            consumeIntent: { nil as Int? },
            resolveIntent: { _ in
                PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: {},
            reconcile: {}
        )
        XCTAssertEqual(unauthorized, .configuration)

        coordinator.authorizationDidChange()
        let authorized: PauseActivationOutcome<String> = coordinator.activate(
            isAuthorized: true,
            consumeIntent: { nil as Int? },
            resolveIntent: { _ in
                PauseActivationResolution(payload: "pause", performMaintenance: true)
            },
            cleanup: {},
            reconcile: {}
        )
        XCTAssertEqual(authorized, .configuration)
    }

    func testPickerSaveOnlyLegitimizesFreshMissingStateAfterSuccess() {
        var fresh = PauseActivationCoordinator(configurationState: .missing)
        fresh.configurationSaveCompleted(successfully: false)
        XCTAssertEqual(fresh.configurationState, .missing)
        XCTAssertTrue(fresh.allowsConfigurationMutation(.pickerSelection))
        XCTAssertFalse(fresh.allowsConfigurationMutation(.ruleEdit))

        fresh.configurationSaveCompleted(successfully: true)
        XCTAssertEqual(fresh.configurationState, .knownGood)
        XCTAssertTrue(fresh.allowsConfigurationMutation(.ruleEdit))
        XCTAssertTrue(fresh.allowsConfigurationMutation(.globalSettingsEdit))
        XCTAssertTrue(fresh.allowsConfigurationMutation(.ruleRemoval))

        var protected = PauseActivationCoordinator(
            configurationState: .missing,
            hasProtectedState: true
        )
        protected.configurationSaveCompleted(successfully: false)
        XCTAssertEqual(protected.configurationState, .missing)
        XCTAssertTrue(protected.requiresConfigurationRepair)
        XCTAssertFalse(protected.allowsConfigurationMutation(.pickerSelection))

        var failed = PauseActivationCoordinator(configurationState: .failed)
        failed.configurationSaveCompleted(successfully: false)
        XCTAssertEqual(failed.configurationState, .failed)
        XCTAssertFalse(failed.allowsConfigurationMutation(.pickerSelection))
    }

    func testKnownGoodConfigurationAllowsExistingTaskFourMutations() {
        let coordinator = PauseActivationCoordinator(configurationState: .knownGood)

        XCTAssertTrue(coordinator.allowsConfigurationMutation(.pickerSelection))
        XCTAssertTrue(coordinator.allowsConfigurationMutation(.ruleEdit))
        XCTAssertTrue(coordinator.allowsConfigurationMutation(.globalSettingsEdit))
        XCTAssertTrue(coordinator.allowsConfigurationMutation(.ruleRemoval))
    }
}
