import Darwin
import Foundation
import PauseCore
import XCTest

@MainActor
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

    func testPreparationLockCoversRegistrationReservationAndUnshieldButNotExternalLaunch() async throws {
        let log = OperationLog()
        let lock = RecordingGrantLock(log: log)
        let harness = Harness(
            ruleID: ruleID,
            automaticRoute: true,
            launchSucceeds: true,
            log: log,
            lock: lock
        )

        _ = try await harness.coordinator.grant(rule: rule, now: now)

        XCTAssertEqual(
            log.values,
            [
                "lock-enter", "register", "reserve", "unshield", "lock-exit",
                "has-route", "open", "activate",
            ]
        )
    }

    func testPreparationFailureRepairsRemainInsideThePreparationLock() async {
        let log = OperationLog()
        let lock = RecordingGrantLock(log: log)
        let harness = Harness(ruleID: ruleID, log: log, lock: lock)
        harness.shield.unshieldError = TestError.unshield

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            log.values,
            [
                "lock-enter", "register", "reserve", "unshield", "rollback", "stop", "shield",
                "lock-exit",
            ]
        )
    }

    func testPreparationLockFailureReportsUnchargedBlockedStateWithoutStartingPreparation() async {
        let log = OperationLog()
        let harness = Harness(
            ruleID: ruleID,
            log: log,
            lock: FailingGrantLock(failOnEntry: 1)
        )

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected the lock failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.primaryError as? TestError, .lock)
            XCTAssertEqual(failure.chargeState, .notCharged)
            XCTAssertEqual(failure.shieldState, .blocked)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }
        XCTAssertTrue(log.values.isEmpty)
    }

    func testRepairLockFailureIsRetainedWithoutClaimingRollbackOrReshield() async {
        let harness = Harness(
            ruleID: ruleID,
            automaticRoute: true,
            launchSucceeds: false,
            lock: FailingGrantLock(failOnEntry: 2)
        )

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(failure?.repairErrors.map(\.step), [.acquireStateLock])
        XCTAssertEqual(failure?.repairErrors.first?.underlyingError as? TestError, .lock)
        XCTAssertEqual(failure?.chargeState, .charged)
        XCTAssertEqual(failure?.shieldState, .unblocked)
    }

    func testReleaseFailureAfterSuccessfulPreparationDoesNotBecomeAnUnchargedFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let systemCalls = ReleaseFailingSystemCalls()
        let harness = Harness(
            ruleID: ruleID,
            automaticRoute: false,
            lock: AppGroupFileLock(
                directoryURL: directory,
                systemCalls: systemCalls.dependencies
            )
        )

        let result = try await harness.coordinator.grant(rule: rule, now: now)

        XCTAssertEqual(result, .readyForManualReturn(expiresAt: expiresAt))
        XCTAssertEqual(systemCalls.unlockAttempts, 1)
        XCTAssertEqual(systemCalls.closeAttempts, 1)
    }

    func testReleaseFailureAfterSuccessfulRepairDoesNotUndoTheRepairedStateReport() async {
        let directory: URL
        do {
            directory = try temporaryDirectory()
        } catch {
            return XCTFail("Could not create lock directory: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        let systemCalls = ReleaseFailingSystemCalls()
        let harness = Harness(
            ruleID: ruleID,
            automaticRoute: true,
            launchSucceeds: false,
            lock: AppGroupFileLock(
                directoryURL: directory,
                systemCalls: systemCalls.dependencies
            )
        )

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(failure?.repairErrors.map(\.step), [])
        XCTAssertEqual(failure?.chargeState, .notCharged)
        XCTAssertEqual(failure?.shieldState, .blocked)
        XCTAssertEqual(systemCalls.unlockAttempts, 2)
        XCTAssertEqual(systemCalls.closeAttempts, 2)
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

    func testReservationAndStopFailuresRetainPrimaryAndRepairError() async {
        let harness = Harness(ruleID: ruleID)
        harness.runtime.reserveError = TestError.reservation
        harness.scheduler.stopError = TestError.stop

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected reservation failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.primaryError as? TestError, .reservation)
            XCTAssertEqual(failure.repairErrors.map(\.step), [.stopMonitoring])
            XCTAssertEqual(failure.repairErrors[0].underlyingError as? TestError, .stop)
            XCTAssertEqual(failure.chargeState, .notCharged)
            XCTAssertEqual(failure.shieldState, .blocked)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }
    }

    func testUnshieldFailureRollsBackStopsAndReconciles() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "rollback", "stop", "shield"]
        )
        XCTAssertFalse(harness.runtime.isReserved)
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testExplicitRouteFailureRollsBackStopsAndReshieldsWithoutCharging() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: false)

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.grant(rule: rule, now: now))

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "rollback", "stop", "shield"]
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

    func testActivationPersistenceFailureForManualReturnLeavesProvisionalCharged() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: false)
        harness.runtime.activateError = TestError.activation

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected activation persistence failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.chargeState, .charged)
            XCTAssertEqual(failure.shieldState, .unblocked)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }
        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "activate"]
        )
    }

    func testSubsecondGrantCeilsExpiryBeforeSchedulingPersistenceAndResult() async throws {
        let subsecondNow = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
        let harness = Harness(ruleID: ruleID, automaticRoute: false)

        let result = try await harness.coordinator.grant(rule: rule, now: subsecondNow)

        let expected = Date(timeIntervalSinceReferenceDate: 800_000_301)
        XCTAssertEqual(harness.scheduler.registeredExpiresAt, expected)
        XCTAssertEqual(harness.runtime.reservedExpiresAt, expected)
        XCTAssertEqual(result, .readyForManualReturn(expiresAt: expected))
    }

    func testUnshieldFailureRetainsEveryRepairFailureAndUnknownResultingState() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield
        harness.runtime.rollbackError = TestError.rollback
        harness.scheduler.stopError = TestError.stop
        harness.shield.failedGrantShieldError = TestError.reconcile

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected unshield failure")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.primaryError as? TestError, .unshield)
            XCTAssertEqual(
                failure.repairErrors.map(\.step),
                [.rollBackRuntime, .forceShield]
            )
            XCTAssertEqual(failure.chargeState, .unknown)
            XCTAssertEqual(failure.shieldState, .unknown)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }
    }

    func testUnshieldFailureWithRollbackFailureStillForceShieldsSelectedRule() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield
        harness.runtime.rollbackError = TestError.rollback

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(failure?.repairErrors.map(\.step), [.rollBackRuntime])
        XCTAssertEqual(failure?.chargeState, .unknown)
        XCTAssertEqual(failure?.shieldState, .blocked)
        XCTAssertEqual(Array(harness.log.values.suffix(2)), ["rollback", "force-failed-grant-shield"])
        XCTAssertFalse(harness.log.values.contains("stop"))
        XCTAssertTrue(harness.shield.isShielded)
    }

    func testImmediateOnlyForceShieldReportsUnknownDurability() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield
        harness.runtime.rollbackError = TestError.rollback
        harness.shield.failedGrantShieldOutcome = .immediateOnly(TestError.markerPersistence)

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(
            failure?.repairErrors.map(\.step),
            [.rollBackRuntime, .persistFailedGrantBlock]
        )
        XCTAssertEqual(
            failure?.repairErrors.last?.underlyingError as? TestError,
            .markerPersistence
        )
        XCTAssertEqual(failure?.chargeState, .unknown)
        XCTAssertEqual(failure?.shieldState, .blockedDurabilityUnknown)
        XCTAssertFalse(harness.log.values.contains("stop"))
        XCTAssertTrue(
            failure?.localizedDescription.contains("blocked now") == true
        )
        XCTAssertTrue(
            failure?.localizedDescription.contains("future reconciliation") == true
        )
    }

    func testUnshieldFailureWithStopFailureReportsCleanupButRemainsRolledBackAndBlocked() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield
        harness.scheduler.stopError = TestError.stop

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(failure?.repairErrors.map(\.step), [.stopMonitoring])
        XCTAssertEqual(failure?.chargeState, .notCharged)
        XCTAssertEqual(failure?.shieldState, .blocked)
    }

    func testUnshieldFailureWithForceShieldFailureDoesNotClaimAppIsBlocked() async {
        let harness = Harness(ruleID: ruleID)
        harness.shield.unshieldError = TestError.unshield
        harness.shield.shieldError = TestError.reconcile

        let failure = await capturedFailure(from: harness)

        XCTAssertEqual(failure?.repairErrors.map(\.step), [.forceShield])
        XCTAssertEqual(failure?.chargeState, .notCharged)
        XCTAssertEqual(failure?.shieldState, .unknown)
        XCTAssertTrue(failure?.localizedDescription.contains("couldn't confirm whether the app was blocked") == true)
    }

    func testRepairFailuresAreAllAttemptedAndRetainedWithPrimaryFailure() async {
        let harness = Harness(ruleID: ruleID, automaticRoute: true, launchSucceeds: false)
        harness.runtime.rollbackError = TestError.rollback
        harness.shield.failedGrantShieldError = TestError.reconcile

        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected the failed launch to throw")
        } catch let failure as SessionGrantFailure {
            XCTAssertEqual(failure.primaryError as? SessionGrantError, .automaticLaunchFailed)
            XCTAssertEqual(failure.repairErrors.count, 2)
            XCTAssertEqual(failure.repairErrors.map(\.step), [.rollBackRuntime, .forceShield])
            XCTAssertEqual(failure.repairErrors[0].underlyingError as? TestError, .rollback)
            XCTAssertEqual(failure.repairErrors[1].underlyingError as? TestError, .reconcile)
            XCTAssertEqual(failure.chargeState, .unknown)
            XCTAssertEqual(failure.shieldState, .unknown)
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
        }

        XCTAssertEqual(
            harness.log.values,
            ["register", "reserve", "unshield", "has-route", "open", "rollback", "force-failed-grant-shield"]
        )
    }

    private var rule: AppRule {
        try! AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
    }

    private var expiresAt: Date {
        now.addingTimeInterval(5 * 60)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-grant-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func capturedFailure(from harness: Harness) async -> SessionGrantFailure? {
        do {
            _ = try await harness.coordinator.grant(rule: rule, now: now)
            XCTFail("Expected grant failure")
            return nil
        } catch let failure as SessionGrantFailure {
            return failure
        } catch {
            XCTFail("Expected SessionGrantFailure, got \(error)")
            return nil
        }
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
    case markerPersistence
    case lock
}

@MainActor
private final class OperationLog {
    private var storage: [String] = []

    var values: [String] {
        storage
    }

    func append(_ value: String) {
        storage.append(value)
    }
}

@MainActor
private final class RecordingGrantLock: SessionGrantLocking {
    private let log: OperationLog

    init(log: OperationLog) {
        self.log = log
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        log.append("lock-enter")
        defer { log.append("lock-exit") }
        return try operation()
    }
}

@MainActor
private final class FailingGrantLock: SessionGrantLocking {
    private let failOnEntry: Int
    private var entryCount = 0

    init(failOnEntry: Int) {
        self.failOnEntry = failOnEntry
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        entryCount += 1
        if entryCount == failOnEntry { throw TestError.lock }
        return try operation()
    }
}

private final class ReleaseFailingSystemCalls: @unchecked Sendable {
    private let counterLock = NSLock()
    private var storedUnlockAttempts = 0
    private var storedCloseAttempts = 0

    var unlockAttempts: Int {
        counterLock.withLock { storedUnlockAttempts }
    }

    var closeAttempts: Int {
        counterLock.withLock { storedCloseAttempts }
    }

    var dependencies: AppGroupFileLockSystemCalls {
        AppGroupFileLockSystemCalls(
            openFile: { path, flags, mode in Darwin.open(path, flags, mode) },
            flockFile: { [self] descriptor, operation in
                if operation == LOCK_UN {
                    counterLock.withLock { storedUnlockAttempts += 1 }
                    errno = EIO
                    return -1
                }
                return flock(descriptor, operation)
            },
            closeFile: { [self] descriptor in
                counterLock.withLock { storedCloseAttempts += 1 }
                return Darwin.close(descriptor)
            }
        )
    }
}

@MainActor
private final class FakeScheduler: SessionScheduling {
    let log: OperationLog
    var registerError: Error?
    var stopError: Error?
    var registeredExpiresAt: Date?

    init(log: OperationLog) { self.log = log }

    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        log.append("register")
        if let registerError { throw registerError }
        registeredExpiresAt = expiresAt
        return SessionActivityName.sessionActivityName(for: ruleID)
    }

    func stop(activityName: String) throws {
        log.append("stop")
        if let stopError { throw stopError }
    }
}

@MainActor
private final class FakeRuntime: RuntimePersisting {
    let log: OperationLog
    var reserveError: Error?
    var activateError: Error?
    var rollbackError: Error?
    var isReserved = false
    var isActive = false
    var reservedExpiresAt: Date?

    init(log: OperationLog) { self.log = log }

    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws {
        log.append("reserve")
        if let reserveError { throw reserveError }
        isReserved = true
        reservedExpiresAt = expiresAt
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

@MainActor
private final class FakeShield: ShieldControlling {
    let log: OperationLog
    var unshieldError: Error?
    var shieldError: Error?
    var failedGrantShieldError: Error?
    var failedGrantShieldOutcome: ForceShieldOutcome = .durable
    var isShielded = true

    init(log: OperationLog) { self.log = log }

    func unshield(ruleID: UUID) throws {
        log.append("unshield")
        if let unshieldError { throw unshieldError }
        isShielded = false
    }

    func shield(ruleID: UUID) throws {
        log.append("shield")
        if let shieldError { throw shieldError }
        isShielded = true
    }

    func forceShieldForFailedGrant(ruleID: UUID) throws -> ForceShieldOutcome {
        log.append("force-failed-grant-shield")
        if let failedGrantShieldError { throw failedGrantShieldError }
        isShielded = true
        return failedGrantShieldOutcome
    }
}

@MainActor
private final class FakeLauncher: TargetLaunching {
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

@MainActor
private struct Harness {
    let log: OperationLog
    let scheduler: FakeScheduler
    let runtime: FakeRuntime
    let shield: FakeShield
    let launcher: FakeLauncher
    let coordinator: SessionGrantCoordinator

    init(
        ruleID: UUID,
        automaticRoute: Bool = false,
        launchSucceeds: Bool = false,
        log: OperationLog = OperationLog(),
        lock: (any SessionGrantLocking)? = nil
    ) {
        self.log = log
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
            launcher: launcher,
            lock: lock
        )
    }
}

@MainActor
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
