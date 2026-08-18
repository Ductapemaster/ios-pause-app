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
