import Foundation
import XCTest

final class RuleRemovalCoordinatorTests: XCTestCase {
    private let ruleID = UUID(uuidString: "77E8662F-875F-4D9E-B1BB-CFCA0AD999B8")!

    func testPrecommitFailureRestoresRuntimeWithoutStoppingMonitoring() {
        var events: [String] = []
        var stagedRuleIDs = Set<UUID>()

        XCTAssertThrowsError(
            try RuleRemovalCoordinator().remove(
                ruleIDs: [ruleID],
                stageRuntime: { ruleID in
                    events.append("stage")
                    stagedRuleIDs.insert(ruleID)
                    return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
                },
                restoreRuntime: { stage in
                    events.append("restore-runtime")
                    stagedRuleIDs.remove(stage.ruleID)
                },
                finalizeRuntime: { _ in events.append("finalize-runtime") },
                unshield: { _ in
                    events.append("unshield")
                    throw TestError.precommit
                },
                restoreShields: { _ in events.append("restore-shields") },
                commitConfiguration: { events.append("commit") },
                stopMonitoring: { _ in events.append("stop-monitoring") }
            )
        ) { error in
            let failure = error as? RuleRemovalFailure
            XCTAssertEqual(failure?.primaryError as? TestError, .precommit)
            XCTAssertEqual(failure?.repairErrors.count, 0)
        }

        XCTAssertTrue(stagedRuleIDs.isEmpty)
        XCTAssertEqual(events, ["stage", "unshield", "restore-runtime", "restore-shields"])
    }

    func testConfigurationFailureRestoresRuntimeAndShieldWithoutStoppingMonitoring() {
        var events: [String] = []
        var runtimeIsStaged = false
        var shieldIsRemoved = false

        XCTAssertThrowsError(
            try RuleRemovalCoordinator().remove(
                ruleIDs: [ruleID],
                stageRuntime: { ruleID in
                    events.append("stage")
                    runtimeIsStaged = true
                    return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
                },
                restoreRuntime: { _ in
                    events.append("restore-runtime")
                    runtimeIsStaged = false
                },
                finalizeRuntime: { _ in events.append("finalize-runtime") },
                unshield: { _ in
                    events.append("unshield")
                    shieldIsRemoved = true
                },
                restoreShields: { _ in
                    events.append("restore-shields")
                    shieldIsRemoved = false
                },
                commitConfiguration: {
                    events.append("commit")
                    throw TestError.configuration
                },
                stopMonitoring: { _ in events.append("stop-monitoring") }
            )
        ) { error in
            let failure = error as? RuleRemovalFailure
            XCTAssertEqual(failure?.primaryError as? TestError, .configuration)
            XCTAssertEqual(failure?.repairErrors.count, 0)
        }

        XCTAssertFalse(runtimeIsStaged)
        XCTAssertFalse(shieldIsRemoved)
        XCTAssertEqual(
            events,
            ["stage", "unshield", "commit", "restore-runtime", "restore-shields"]
        )
    }

    func testSuccessCommitsBeforeStoppingMonitoringAndFinalizingRuntime() throws {
        var events: [String] = []

        let outcome = try RuleRemovalCoordinator().remove(
            ruleIDs: [ruleID],
            stageRuntime: { ruleID in
                events.append("stage")
                return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
            },
            restoreRuntime: { _ in events.append("restore-runtime") },
            finalizeRuntime: { _ in events.append("finalize-runtime") },
            unshield: { _ in events.append("unshield") },
            restoreShields: { _ in events.append("restore-shields") },
            commitConfiguration: { events.append("commit") },
            clearFailedGrantBlock: { _ in events.append("clear-marker") },
            stopMonitoring: { _ in events.append("stop-monitoring") }
        )

        XCTAssertTrue(outcome.cleanupErrors.isEmpty)
        XCTAssertEqual(
            events,
            ["stage", "unshield", "commit", "clear-marker", "stop-monitoring", "finalize-runtime"]
        )
    }

    func testMarkerClearFailureIsPostcommitCleanupAndDoesNotRestoreRemovedState() throws {
        var events: [String] = []

        let outcome = try RuleRemovalCoordinator().remove(
            ruleIDs: [ruleID],
            stageRuntime: { id in
                events.append("stage")
                return StagedRuntimeRemoval(ruleID: id, wasPresent: true)
            },
            restoreRuntime: { _ in events.append("restore-runtime") },
            finalizeRuntime: { _ in events.append("finalize-runtime") },
            unshield: { _ in events.append("unshield") },
            restoreShields: { _ in events.append("restore-shields") },
            commitConfiguration: { events.append("commit") },
            clearFailedGrantBlock: { id in
                XCTAssertEqual(id, self.ruleID)
                events.append("clear-marker")
                throw TestError.markerClear
            },
            stopMonitoring: { _ in events.append("stop-monitoring") }
        )

        XCTAssertEqual(
            events,
            ["stage", "unshield", "commit", "clear-marker", "stop-monitoring", "finalize-runtime"]
        )
        XCTAssertEqual(outcome.cleanupErrors.compactMap { $0 as? TestError }, [.markerClear])
        XCTAssertFalse(events.contains("restore-runtime"))
        XCTAssertFalse(events.contains("restore-shields"))
    }

    func testFailurePreservesPrimaryAndEveryRepairFailure() {
        XCTAssertThrowsError(
            try RuleRemovalCoordinator().remove(
                ruleIDs: [ruleID],
                stageRuntime: { ruleID in
                    StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
                },
                restoreRuntime: { _ in throw TestError.runtimeRestore },
                finalizeRuntime: { _ in },
                unshield: { _ in throw TestError.precommit },
                restoreShields: { _ in throw TestError.shieldRestore },
                commitConfiguration: {},
                stopMonitoring: { _ in }
            )
        ) { error in
            guard let failure = error as? RuleRemovalFailure else {
                return XCTFail("Expected RuleRemovalFailure, got \(error)")
            }
            XCTAssertEqual(failure.primaryError as? TestError, .precommit)
            XCTAssertEqual(
                failure.repairErrors.compactMap { $0 as? TestError },
                [.runtimeRestore, .shieldRestore]
            )
            XCTAssertEqual(
                failure.localizedDescription,
                "The app removal failed (precommit failed). Repair also failed: runtime restore failed; shield restore failed."
            )
        }
    }

    func testAdditionalRepairErrorsAppendWithoutReplacingExistingFailures() {
        let original = RuleRemovalFailure(
            primaryError: TestError.precommit,
            repairErrors: [TestError.runtimeRestore]
        )

        let combined = original.addingRepairErrors([TestError.shieldRestore])

        XCTAssertEqual(combined.primaryError as? TestError, .precommit)
        XCTAssertEqual(
            combined.repairErrors.compactMap { $0 as? TestError },
            [.runtimeRestore, .shieldRestore]
        )
    }

    func testFailedRuntimeRestoreForcesTheAffectedRuleToStayShielded() {
        var forcedShieldRuleIDs = Set<UUID>()

        XCTAssertThrowsError(
            try RuleRemovalCoordinator().remove(
                ruleIDs: [ruleID],
                stageRuntime: { ruleID in
                    StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
                },
                restoreRuntime: { _ in throw TestError.runtimeRestore },
                finalizeRuntime: { _ in },
                unshield: { _ in throw TestError.precommit },
                restoreShields: { forcedShieldRuleIDs = $0 },
                commitConfiguration: {},
                stopMonitoring: { _ in }
            )
        )

        XCTAssertEqual(forcedShieldRuleIDs, [ruleID])
    }

    private enum TestError: LocalizedError, Equatable {
        case precommit
        case configuration
        case runtimeRestore
        case shieldRestore
        case markerClear

        var errorDescription: String? {
            switch self {
            case .precommit: "precommit failed"
            case .configuration: "configuration failed"
            case .runtimeRestore: "runtime restore failed"
            case .shieldRestore: "shield restore failed"
            case .markerClear: "marker clear failed"
            }
        }
    }
}
