import Foundation
import PauseCore
import XCTest

final class SessionGrantCoordinatorTests: XCTestCase {
    private let ruleID = UUID(uuidString: "bb6aa453-a819-4bc9-9f72-a40a78a6cc71")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testRegistersThenReservesThenUnshieldsBeforeOpeningAndActivating() async throws {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: true)

        let result = try await harness.coordinator.grant(rule: rule, now: now)

        XCTAssertEqual(result, .openedAutomatically(expiresAt: expiresAt))
        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "activate"]
        )
    }

    func testSchedulingFailureLeavesRuntimeAndShieldUntouched() async {
        let harness = Harness(ruleID: ruleID)
        harness.scheduler.registerError = TestError.scheduling

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(harness.log.values, ["register"])
        XCTAssertFalse(harness.runtime.isReserved)
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testReservationFailureStopsScheduleAndLeavesShieldIntact() async {
        let harness = Harness(ruleID: ruleID)
        harness.runtime.reserveError = TestError.reservation

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(harness.log.values, ["register", "reserve", "stop"])
        XCTAssertFalse(harness.runtime.isReserved)
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testUnshieldFailureRollsBackStopsAndReconciles() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "rollback", "stop", "reconcile"]
        )
        XCTAssertFalse(harness.runtime.isReserved)
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testExplicitRouteFailureRollsBackStopsAndReshieldsWithoutCharging() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: false)

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "rollback", "stop", "reconcile"]
        )
        XCTAssertFalse(harness.runtime.isReserved)
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testNoAutomaticRouteActivatesAndReturnsManualInstructions() async throws {
        let harness = Harness(ruleID: ruleID, automaticRoute: false)

        let result = try await harness.coordinator.grant(rule: rule, now: now)

        XCTAssertEqual(result, .readyForManualReturn(expiresAt: expiresAt))
        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "activate"]
        )
        XCTAssertTrue(harness.runtime.isActive)
        XCTAssertFalse(harness.shield.isShielded)
    }

    func testActivationPersistenceFailureAfterSuccessfulLaunchLeavesProvisionalCharged() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: true)
        harness.runtime.activateError = TestError.activation

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "activate"]
        )
        XCTAssertTrue(harness.runtime.isReserved)
        XCTAssertFalse(harness.runtime.isActive)
        XCTAssertFalse(harness.shield.isShielded)
    }

    func testRepairFailuresAreAllAttemptedAndRetainedWithPrimaryFailure() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: false)
        harness.runtime.rollbackError = TestError.rollback
        harness.scheduler.stopError = TestError.stop
        harness.shield.reconcileError = TestError.reconcile

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected the failed launch to throw")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.primaryError as? SessionGrantError, .automaticLaunchFailed)
            XCTAssertEqual(failure.repairErrors.count, 3)
            XCTAssertEqual(failure.repairErrors[0] as? TestError, .rollback)
            XCTAssertEqual(failure.repairErrors[1] as? TestError, .stop)
            XCTAssertEqual(failure.repairErrors[2] as? TestError, .reconcile)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "rollback", "stop", "reconcile"]
        )
    }

    private var rule: AppRule {
        try! AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
    }

    private var expiresAt: Date {
        now.addingTimeInterval(5 * 60)
    }
}

private enum TestError: Error, Equatable {
    case scheduling
    case reservation
    case unshield
    case activation
    case rollback
    case stop
    case reconcile
}

private final class OperationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class FakeScheduler: SessionScheduling, @unchecked Sendable {
    let log: OperationLog
    var registerError: Error?
    var stopError: Error?

    init(log: OperationLog) { self.log = log }

    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        log.append("register")
        if let registerError { throw registerError }
        return SessionActivityName.sessionActivityName(for: ruleID)
    }

    func stop(activityName: String) throws {
        log.append("stop")
        if let stopError { throw stopError }
    }
}

private final class FakeRuntime: RuntimePersisting, @unchecked Sendable {
    let log: OperationLog
    var reserveError: Error?
    var activateError: Error?
    var rollbackError: Error?
    var isReserved = false
    var isActive = false

    init(log: OperationLog) { self.log = log }

    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws {
        log.append("reserve")
        if let reserveError { throw reserveError }
        isReserved = true
    }

    func activate(ruleID: UUID) throws {
        log.append("activate")
        if let activateError { throw activateError }
        isActive = true
    }

    func rollBack(ruleID: UUID) throws {
        log.append("rollback")
        if let rollbackError { throw rollbackError }
        isReserved = false
        isActive = false
    }
}

private final class FakeShield: ShieldControlling, @unchecked Sendable {
    let log: OperationLog
    var unshieldError: Error?
    var reconcileError: Error?
    var isShielded = true

    init(log: OperationLog) { self.log = log }

    func unshield(ruleID: UUID) throws {
        log.append("unshield")
        if let unshieldError { throw unshieldError }
        isShielded = false
    }

    func reconcile() throws {
        log.append("reconcile")
        if let reconcileError { throw reconcileError }
        isShielded = true
    }
}

private final class FakeLauncher: TargetLaunching, @unchecked Sendable {
    let log: OperationLog
    let automaticRoute: Bool
    let launchSucceeds: Bool

    init(log: OperationLog, automaticRoute: Bool, launchSucceeds: Bool) {
        self.log = log
        self.automaticRoute = automaticRoute
        self.launchSucceeds = launchSucceeds
    }

    func hasAutomaticRoute(ruleID: UUID) -> Bool {
        log.append("has-route")
        return automaticRoute
    }

    func open(ruleID: UUID) async -> Bool {
        log.append("open")
        return launchSucceeds
    }
}

private struct Harness {
    let log = OperationLog()
    let scheduler: FakeScheduler
    let runtime: FakeRuntime
    let shield: FakeShield
    let launcher: FakeLauncher
    let coordinator: SessionGrantCoordinator

    init(ruleID: UUID, automaticRoute: Bool = false, launchSucceeds: Bool = false) {
        scheduler = FakeScheduler(log: log)
        runtime = FakeRuntime(log: log)
        shield = FakeShield(log: log)
        launcher = FakeLauncher(
            log: log,
            automaticRoute: automaticRoute,
            launchSucceeds: launchSucceeds
        )
        coordinator = SessionGrantCoordinator(
            scheduler: scheduler,
            runtime: runtime,
            shield: shield,
            launcher: launcher
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
