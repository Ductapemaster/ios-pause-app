@testable import PauseCore
import XCTest

final class RuntimeRepositoryTests: XCTestCase {
    private var directoryURL: URL!
    private var repository: RuntimeRepository!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        repository = RuntimeRepository(directoryURL: directoryURL)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        repository = nil
        directoryURL = nil
    }

    func testRuntimeFilesAreStoredSeparatelyByRuleID() throws {
        let firstID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let secondID = UUID(uuidString: "00F7635F-BA5B-4B8B-9CC8-D68B9E6A8DD7")!
        let first = runtime(sessionsStarted: 1)
        let second = runtime(sessionsStarted: 2)

        try repository.save(first, ruleID: firstID)
        try repository.save(second, ruleID: secondID)

        XCTAssertEqual(try repository.load(ruleID: firstID), first)
        XCTAssertEqual(try repository.load(ruleID: secondID), second)
    }

    func testDeletingOneRuntimeDoesNotAffectAnother() throws {
        let firstID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let secondID = UUID(uuidString: "00F7635F-BA5B-4B8B-9CC8-D68B9E6A8DD7")!
        let first = runtime(sessionsStarted: 1)
        let second = runtime(sessionsStarted: 2)
        try repository.save(first, ruleID: firstID)
        try repository.save(second, ruleID: secondID)

        try repository.delete(ruleID: firstID)

        XCTAssertNil(try repository.load(ruleID: firstID))
        XCTAssertEqual(try repository.load(ruleID: secondID), second)
    }

    func testStagedRemovalCanRestoreTheOriginalRuntimeFile() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let original = runtime(sessionsStarted: 2)
        try repository.save(original, ruleID: ruleID)

        let stage = try repository.stageRemoval(ruleID: ruleID)

        XCTAssertTrue(stage.wasPresent)
        XCTAssertNil(try repository.load(ruleID: ruleID))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).count, 1)

        try repository.restoreRemoval(stage)

        XCTAssertEqual(try repository.load(ruleID: ruleID), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).count, 1)
    }

    func testFinalizingStagedRemovalDeletesTheStagedRuntime() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        try repository.save(runtime(sessionsStarted: 2), ruleID: ruleID)
        let stage = try repository.stageRemoval(ruleID: ruleID)

        try repository.finalizeRemoval(stage)

        XCTAssertNil(try repository.load(ruleID: ruleID))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).isEmpty)
    }

    func testFailedRestoreLeavesTheStagedRuntimeAvailableForRetry() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let original = runtime(sessionsStarted: 2)
        let unexpectedReplacement = runtime(sessionsStarted: 9)
        try repository.save(original, ruleID: ruleID)
        let stage = try repository.stageRemoval(ruleID: ruleID)
        try repository.save(unexpectedReplacement, ruleID: ruleID)

        XCTAssertThrowsError(try repository.restoreRemoval(stage)) { error in
            XCTAssertEqual(error as? PersistenceError, .runtimeRestoreDestinationExists(ruleID))
        }
        XCTAssertEqual(try repository.load(ruleID: ruleID), unexpectedReplacement)

        try repository.delete(ruleID: ruleID)
        try repository.restoreRemoval(stage)

        XCTAssertEqual(try repository.load(ruleID: ruleID), original)
    }

    func testStageRemovalRejectsCanonicalLookingDirectory() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let runtimeDirectoryURL = directoryURL.appendingPathComponent(
            "runtime-\(ruleID.uuidString.lowercased()).json",
            isDirectory: true
        )
        let sentinelURL = runtimeDirectoryURL.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: false
        )
        try Data("leave me".utf8).write(to: sentinelURL)

        XCTAssertThrowsError(try repository.stageRemoval(ruleID: ruleID)) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidRuntimeFile(ruleID))
        }
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("leave me".utf8))
    }

    func testDeleteOrphanedRuntimesRemovesOnlyRulesOutsideKeepSet() throws {
        let retainedID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let orphanedID = UUID(uuidString: "00F7635F-BA5B-4B8B-9CC8-D68B9E6A8DD7")!
        let retained = runtime(sessionsStarted: 1)
        try repository.save(retained, ruleID: retainedID)
        try repository.save(runtime(sessionsStarted: 2), ruleID: orphanedID)

        try repository.deleteOrphanedRuntimes(keeping: [retainedID])

        XCTAssertEqual(try repository.load(ruleID: retainedID), retained)
        XCTAssertNil(try repository.load(ruleID: orphanedID))
    }

    func testDeleteOrphanedRuntimesIgnoresNoncanonicalFiles() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let uppercaseRuntimeURL = directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString).json")
        let unrelatedURL = directoryURL.appendingPathComponent("configuration.json")
        let contents = Data("leave me".utf8)
        try contents.write(to: uppercaseRuntimeURL)
        try contents.write(to: unrelatedURL)

        try repository.deleteOrphanedRuntimes(keeping: [])

        XCTAssertEqual(try Data(contentsOf: uppercaseRuntimeURL), contents)
        XCTAssertEqual(try Data(contentsOf: unrelatedURL), contents)
    }

    func testDeleteOrphanedRuntimesRetriesAfterDeletionFailure() throws {
        let orphanedID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let orphaned = runtime(sessionsStarted: 1)
        try repository.save(orphaned, ruleID: orphanedID)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directoryURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
        }

        XCTAssertThrowsError(try repository.deleteOrphanedRuntimes(keeping: []))
        XCTAssertEqual(try repository.load(ruleID: orphanedID), orphaned)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        try repository.deleteOrphanedRuntimes(keeping: [])

        XCTAssertNil(try repository.load(ruleID: orphanedID))
    }

    func testDeleteOrphanedRuntimesIgnoresCanonicalLookingDirectory() throws {
        let directoryID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let runtimeDirectoryURL = directoryURL.appendingPathComponent(
            "runtime-\(directoryID.uuidString.lowercased()).json",
            isDirectory: true
        )
        let sentinelURL = runtimeDirectoryURL.appendingPathComponent("sentinel")
        let sentinel = Data("leave me".utf8)
        try FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: false
        )
        try sentinel.write(to: sentinelURL)

        try repository.deleteOrphanedRuntimes(keeping: [])

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectoryURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinel)
    }

    func testUpdatePersistsCompleteMutation() throws {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        try repository.save(runtime(sessionsStarted: 1), ruleID: ruleID)

        let updated = try repository.update(ruleID: ruleID) { runtime in
            runtime.sessionsStarted = 2
            try runtime.reserve(
                activityName: "session.77e8662f-875f-4d9e-b1bb-cfca0ad999b8",
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
        }

        XCTAssertEqual(updated.sessionsStarted, 3)
        XCTAssertEqual(try repository.load(ruleID: ruleID), updated)
    }

    func testUpdateThrowingMutationLeavesPreviousRuntime() throws {
        enum MutationError: Error { case rejected }

        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!
        let original = runtime(sessionsStarted: 1)
        try repository.save(original, ruleID: ruleID)

        XCTAssertThrowsError(try repository.update(ruleID: ruleID) { runtime in
            runtime.sessionsStarted = 99
            throw MutationError.rejected
        })

        XCTAssertEqual(try repository.load(ruleID: ruleID), original)
    }

    func testUpdateMissingRuntimeThrowsMissingRuntime() {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!

        XCTAssertThrowsError(try repository.update(ruleID: ruleID) { _ in }) { error in
            XCTAssertEqual(error as? PersistenceError, .missingRuntime(ruleID))
        }
    }

    func testSessionActivityNameParserAcceptsOnlyFixedSessionUUIDForm() {
        let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!

        XCTAssertEqual(
            SessionActivityName.ruleID(fromSessionActivityName: "session.77e8662f-875f-4d9e-b1bb-cfca0ad999b8"),
            ruleID
        )
        XCTAssertNil(SessionActivityName.ruleID(fromSessionActivityName: "session.77E8662F-875F-4D9E-B1BB-CFCA0AD999B8"))
        XCTAssertNil(SessionActivityName.ruleID(fromSessionActivityName: "session.{77e8662f-875f-4d9e-b1bb-cfca0ad999b8}"))
        XCTAssertNil(SessionActivityName.ruleID(fromSessionActivityName: "other.77e8662f-875f-4d9e-b1bb-cfca0ad999b8"))
    }

    private func runtime(sessionsStarted: Int) -> RuleRuntime {
        RuleRuntime(
            logicalDay: CalendarDay(
                date: Date(timeIntervalSince1970: 1_771_465_600),
                calendar: Self.utcGregorian
            ),
            sessionsStarted: sessionsStarted
        )
    }

    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
