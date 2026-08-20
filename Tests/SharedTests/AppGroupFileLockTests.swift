import Darwin
import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class AppGroupFileLockTests: XCTestCase {
    /// `standardizedFileURL` drops a leading `/private` from a path only once that
    /// path exists, so the lock file has one spelling before it is created and
    /// another afterwards. A lock built before the first acquisition and a lock
    /// built after it must still reach the same state: two states over one file
    /// means the second `flock(LOCK_EX)` waits on a lock this process already
    /// holds, which no one will ever release.
    ///
    /// `flock` is faked here so a regression reports two acquisitions instead of
    /// blocking the suite forever, but `open` is real so the lock file genuinely
    /// appears on disk between the two constructions.
    func testLockBuiltAfterTheLockFileExistsSharesStateWithOneBuiltBefore() throws {
        let directory = try privateRootedTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent(SharedIdentifiers.stateLockFilename)
        let systemCalls = NonBlockingSystemCalls()

        let early = AppGroupFileLock(
            directoryURL: directory,
            systemCalls: systemCalls.dependencies
        )
        let spellingBeforeCreation = lockURL.standardizedFileURL.path
        try early.withLock {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
        XCTAssertNotEqual(
            spellingBeforeCreation,
            lockURL.standardizedFileURL.path,
            "This directory no longer reproduces the path spelling change the test exists to cover."
        )

        let late = AppGroupFileLock(
            directoryURL: directory,
            systemCalls: systemCalls.dependencies
        )
        systemCalls.resetExclusiveAcquisitions()
        try late.withLock {
            try early.withLock {}
        }

        XCTAssertEqual(systemCalls.exclusiveAcquisitions, 1)
    }

    func testIndependentInstancesSerializeAndNestedAccessDoesNotDeadlock() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AppGroupFileLock(directoryURL: directory)
        let second = AppGroupFileLock(directoryURL: directory)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let secondFinished = expectation(description: "second lock finishes")
        let state = LockedEvents()

        DispatchQueue.global().async {
            try? first.withLock {
                state.append("first-enter")
                try first.withLock { state.append("nested") }
                entered.signal()
                release.wait()
                state.append("first-exit")
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            try? second.withLock { state.append("second") }
            secondFinished.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(state.values, ["first-enter", "nested"])
        release.signal()
        wait(for: [secondFinished], timeout: 2)
        XCTAssertEqual(state.values, ["first-enter", "nested", "first-exit", "second"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(SharedIdentifiers.stateLockFilename).path
        ))
    }

    func testDelayedExpiryCannotOverwriteSessionReservedByIndependentRepository() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let expiryRepository = RuntimeRepository(directoryURL: directory)
        let grantRepository = RuntimeRepository(directoryURL: directory)
        try expiryRepository.save(
            RuleRuntime(
                logicalDay: CalendarDay(date: now, calendar: .current),
                sessionsStarted: 1,
                openSession: OpenSession(
                    activityName: "session.old",
                    expiresAt: now.addingTimeInterval(-1),
                    state: .active
                )
            ),
            ruleID: ruleID
        )
        let expiryRead = DispatchSemaphore(value: 0)
        let releaseExpiry = DispatchSemaphore(value: 0)
        let expiryFinished = expectation(description: "expiry finished")
        let grantFinished = expectation(description: "grant finished")
        let expiryLock = AppGroupFileLock(directoryURL: directory)

        DispatchQueue.global().async {
            try? expiryLock.withLock {
                guard var staleRuntime = try expiryRepository.load(ruleID: ruleID) else { return }
                expiryRead.signal()
                releaseExpiry.wait()
                staleRuntime.clearExpiredSession(at: now)
                try expiryRepository.save(staleRuntime, ruleID: ruleID)
            }
            expiryFinished.fulfill()
        }
        XCTAssertEqual(expiryRead.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            _ = try? grantRepository.update(ruleID: ruleID) { runtime in
                try runtime.reserve(
                    activityName: "session.new",
                    expiresAt: now.addingTimeInterval(300)
                )
            }
            grantFinished.fulfill()
        }

        releaseExpiry.signal()
        wait(for: [expiryFinished, grantFinished], timeout: 2)
        let final = try XCTUnwrap(expiryRepository.load(ruleID: ruleID))
        XCTAssertEqual(final.sessionsStarted, 2)
        XCTAssertEqual(final.openSession?.activityName, "session.new")
    }

    func testStaleShieldSnapshotCannotApplyAfterMarkerAndShieldTransaction() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID()
        let reconciliationLock = AppGroupFileLock(directoryURL: directory)
        let targetedLock = AppGroupFileLock(directoryURL: directory)
        let markers = FailedGrantBlockFileStore(directoryURL: directory)
        let shields = LockedStringSet()
        let snapshotReady = DispatchSemaphore(value: 0)
        let releaseSnapshot = DispatchSemaphore(value: 0)
        let reconciliationFinished = expectation(description: "reconciliation finished")
        let targetedFinished = expectation(description: "targeted shield finished")

        DispatchQueue.global().async {
            try? reconciliationLock.withLock {
                let staleSnapshot = Set<String>()
                snapshotReady.signal()
                releaseSnapshot.wait()
                shields.replace(with: staleSnapshot)
            }
            reconciliationFinished.fulfill()
        }
        XCTAssertEqual(snapshotReady.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            try? targetedLock.withLock {
                try markers.add(ruleID: ruleID)
                shields.insert("selected")
            }
            targetedFinished.fulfill()
        }

        releaseSnapshot.signal()
        wait(for: [reconciliationFinished, targetedFinished], timeout: 2)
        XCTAssertEqual(shields.values, ["selected"])
        XCTAssertTrue(try markers.contains(ruleID: ruleID))
    }

    func testIndependentServiceAndRepositorySerializeExpiryThroughFinalShieldApply() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let token = try applicationToken(for: ruleID)
        try ConfigurationStore(directoryURL: directory).save(
            ConfigurationDocument(
                settings: .phaseOneDefault,
                rules: [try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
                targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
            )
        )
        let repository = RuntimeRepository(directoryURL: directory)
        try repository.save(
            RuleRuntime(
                logicalDay: CalendarDay(date: now, calendar: .current),
                sessionsStarted: 1,
                openSession: OpenSession(
                    activityName: SessionActivityName.sessionActivityName(for: ruleID),
                    expiresAt: now.addingTimeInterval(-1),
                    state: .active
                )
            ),
            ruleID: ruleID
        )
        let applyStarted = DispatchSemaphore(value: 0)
        let releaseApply = DispatchSemaphore(value: 0)
        let serviceFinished = expectation(description: "service finished")
        let grantFinished = expectation(description: "grant finished")

        DispatchQueue.global().async {
            let reconciler = ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in
                    applyStarted.signal()
                    releaseApply.wait()
                },
                failedGrantBlockIDs: { [] },
                stateLock: AppGroupFileLock(directoryURL: directory)
            )
            let service = SessionReconciliationService(
                directoryURL: directory,
                shieldReconciler: reconciler,
                stopMonitoring: { _ in }
            )
            _ = service.reconcile(now: now, trigger: .intervalDidEnd(ruleID: ruleID))
            serviceFinished.fulfill()
        }
        XCTAssertEqual(applyStarted.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            let grantRepository = RuntimeRepository(directoryURL: directory)
            _ = try? grantRepository.update(ruleID: ruleID) { runtime in
                try runtime.reserve(
                    activityName: "session.after-expiry",
                    expiresAt: now.addingTimeInterval(300)
                )
            }
            grantFinished.fulfill()
        }

        releaseApply.signal()
        wait(for: [serviceFinished, grantFinished], timeout: 2)
        let final = try XCTUnwrap(repository.load(ruleID: ruleID))
        XCTAssertEqual(final.sessionsStarted, 2)
        XCTAssertEqual(final.openSession?.activityName, "session.after-expiry")
    }

    /// A directory under `/private`, which the process temporary directory is not.
    /// Only a `/private`-rooted path changes spelling once its contents exist.
    private func privateRootedTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pause-file-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-file-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func applicationToken(for ruleID: UUID) throws -> ApplicationToken {
        let encoded = Data(ruleID.uuidString.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(encoded)\"}".utf8)
        )
    }
}

/// Real `open` and `close` so the lock file appears on disk, with `flock` counted
/// and stubbed out so a test that would otherwise deadlock reports instead of hanging.
private final class NonBlockingSystemCalls: @unchecked Sendable {
    private let counterLock = NSLock()
    private var storedExclusiveAcquisitions = 0

    var exclusiveAcquisitions: Int {
        counterLock.withLock { storedExclusiveAcquisitions }
    }

    func resetExclusiveAcquisitions() {
        counterLock.withLock { storedExclusiveAcquisitions = 0 }
    }

    var dependencies: AppGroupFileLockSystemCalls {
        AppGroupFileLockSystemCalls(
            openFile: { path, flags, mode in Darwin.open(path, flags, mode) },
            flockFile: { [self] _, operation in
                if operation == LOCK_EX {
                    counterLock.withLock { storedExclusiveAcquisitions += 1 }
                }
                return 0
            },
            closeFile: { descriptor in Darwin.close(descriptor) }
        )
    }
}

private final class LockedStringSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func replace(with values: Set<String>) {
        lock.lock()
        storage = values
        lock.unlock()
    }

    func insert(_ value: String) {
        lock.lock()
        storage.insert(value)
        lock.unlock()
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
