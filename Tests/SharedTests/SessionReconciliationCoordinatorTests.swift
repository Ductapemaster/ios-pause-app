import Foundation
import PauseCore
import XCTest

@MainActor
final class SessionReconciliationCoordinatorTests: XCTestCase {
    private let ruleID = UUID(uuidString: "2acf6cb8-46e2-4498-8153-a45be2bf282f")!
    private let otherRuleID = UUID(uuidString: "d7636097-103c-45ad-a6aa-f4f7b85f8681")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testActivationPromotesUnmarkedUnexpiredProvisionalSessionBeforeShieldReconciliation() {
        var runtime = makeRuntime(ruleID: ruleID, state: .provisional, expiresIn: 60)
        var events: [String] = []
        let result = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .appActivation,
            loadRuntime: { _ in runtime },
            saveRuntime: { saved, _ in runtime = saved; events.append("save") },
            clearFailedGrantBlock: { _ in events.append("clear") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(runtime.openSession?.state, .active)
        XCTAssertEqual(events, ["save", "shield"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testActivationLeavesMarkedUnexpiredProvisionalSessionBlockedAndUnchanged() {
        let original = makeRuntime(ruleID: ruleID, state: .provisional, expiresIn: 60)
        var saved: RuleRuntime?
        var cleared: [UUID] = []
        let result = coordinator(markers: [ruleID]).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .appActivation,
            loadRuntime: { _ in original },
            saveRuntime: { runtime, _ in saved = runtime },
            clearFailedGrantBlock: { cleared.append($0) },
            applyShields: {}
        )

        XCTAssertNil(saved)
        XCTAssertEqual(cleared, [])
        XCTAssertEqual(result.repairRuleIDs, [ruleID])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMarkedExpiredSessionPersistsClearBeforeMarkerClearAndFullReconcile() {
        var events: [String] = []
        let result = coordinator(markers: [ruleID]).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalDidEnd(ruleID: ruleID),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .provisional, expiresIn: -1) },
            saveRuntime: { runtime, _ in
                XCTAssertNil(runtime.openSession)
                XCTAssertEqual(runtime.sessionsStarted, 1)
                events.append("save")
            },
            clearFailedGrantBlock: { _ in events.append("clear") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "clear", "shield"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMarkedExpirySaveFailureDoesNotClearMarkerButStillReconcilesFailBlocked() {
        var events: [String] = []
        let result = coordinator(markers: [ruleID]).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalDidEnd(ruleID: ruleID),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .provisional, expiresIn: -1) },
            saveRuntime: { _, _ in events.append("save"); throw TestError.save },
            clearFailedGrantBlock: { _ in events.append("clear") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "shield"])
        XCTAssertEqual(result.repairRuleIDs, [ruleID])
        XCTAssertEqual(result.issues.map(\.operation), [.saveRuntime])
    }

    func testMarkedExpiryClearFailureIsRetainedAndReconcileStillRuns() {
        var events: [String] = []
        let result = coordinator(markers: [ruleID]).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalDidEnd(ruleID: ruleID),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .provisional, expiresIn: -1) },
            saveRuntime: { _, _ in events.append("save") },
            clearFailedGrantBlock: { _ in events.append("clear"); throw TestError.clear },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "clear", "shield"])
        XCTAssertEqual(result.repairRuleIDs, [ruleID])
        XCTAssertEqual(result.issues.map(\.operation), [.clearFailedGrantBlock])
    }

    func testEarlyEndCallbackChangesNothingAndDoesNotStopMonitoring() {
        var events: [String] = []
        let result = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalWillEndWarning(ruleID: ruleID, activityName: "session.rule"),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .active, expiresIn: 60) },
            saveRuntime: { _, _ in events.append("save") },
            clearFailedGrantBlock: { _ in events.append("clear") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, [])
        XCTAssertNil(result.pendingStopActivityName)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testEarlyCallbackDoesNotPromoteProvisionalSessionOrMutateShields() {
        var saved: RuleRuntime?
        var shieldCount = 0
        _ = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalDidEnd(ruleID: ruleID),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .provisional, expiresIn: 60) },
            saveRuntime: { saved = $0; _ = $1 },
            clearFailedGrantBlock: { _ in }, applyShields: { shieldCount += 1 }
        )

        XCTAssertNil(saved)
        XCTAssertEqual(shieldCount, 0)
    }

    func testWarningReportsOnlyTheNamedActivityToStopAfterExpiredRuntimeAndShieldArePersisted() {
        var events: [String] = []
        let result = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalWillEndWarning(ruleID: ruleID, activityName: "session.selected"),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .active, expiresIn: -1) },
            saveRuntime: { _, _ in events.append("save") },
            clearFailedGrantBlock: { _ in },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "shield"])
        XCTAssertEqual(result.pendingStopActivityName, "session.selected")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testWarningDoesNotStopWhenShieldReconciliationFails() {
        var events: [String] = []
        let result = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalWillEndWarning(ruleID: ruleID, activityName: "session.selected"),
            loadRuntime: { _ in self.makeRuntime(ruleID: self.ruleID, state: .active, expiresIn: -1) },
            saveRuntime: { _, _ in events.append("save") }, clearFailedGrantBlock: { _ in },
            applyShields: { events.append("shield"); throw TestError.shield }
        )

        XCTAssertEqual(events, ["save", "shield"])
        XCTAssertNil(result.pendingStopActivityName)
        XCTAssertEqual(result.issues.map(\.operation), [.applyShields])
    }

    func testDuplicateCallbackWithNoOpenSessionDoesNotChangeCountAndRepairsShield() {
        let runtime = RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 1)
        var saved: RuleRuntime?
        var shieldCount = 0
        _ = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID], now: now, trigger: .intervalDidEnd(ruleID: ruleID),
            loadRuntime: { _ in runtime }, saveRuntime: { saved = $0; _ = $1 },
            clearFailedGrantBlock: { _ in }, applyShields: { shieldCount += 1 }
        )

        XCTAssertNil(saved)
        XCTAssertEqual(runtime.sessionsStarted, 1)
        XCTAssertEqual(shieldCount, 1)
    }

    func testMissingAndCorruptRuntimesAreBothReportedWhileFullReconcileStillRuns() {
        var shieldCount = 0
        let result = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID, otherRuleID], now: now, trigger: .appActivation,
            loadRuntime: { id in
                if id == self.ruleID { return nil }
                throw TestError.load
            },
            saveRuntime: { _, _ in }, clearFailedGrantBlock: { _ in },
            applyShields: { shieldCount += 1 }
        )

        XCTAssertEqual(result.repairRuleIDs, [ruleID, otherRuleID])
        XCTAssertEqual(result.issues.map(\.operation), [.loadRuntime, .loadRuntime])
        XCTAssertEqual(shieldCount, 1)
    }

    func testActivationExpiresActiveAndProvisionalSessionsWithoutReducingCounts() {
        var saved: [UUID: RuleRuntime] = [:]
        let runtimes = [
            ruleID: makeRuntime(ruleID: ruleID, state: .active, expiresIn: -1),
            otherRuleID: makeRuntime(ruleID: otherRuleID, state: .provisional, expiresIn: -1),
        ]
        _ = coordinator(markers: []).reconcile(
            ruleIDs: [ruleID, otherRuleID], now: now, trigger: .appActivation,
            loadRuntime: { runtimes[$0] }, saveRuntime: { saved[$1] = $0 },
            clearFailedGrantBlock: { _ in }, applyShields: {}
        )

        XCTAssertNil(saved[ruleID]?.openSession)
        XCTAssertNil(saved[otherRuleID]?.openSession)
        XCTAssertEqual(saved[ruleID]?.sessionsStarted, 1)
        XCTAssertEqual(saved[otherRuleID]?.sessionsStarted, 1)
    }

    func testRuntimeResetSavesZeroBeforeClearingOnlySelectedMarkerThenReconciles() {
        var events: [String] = []
        let result = coordinator(markers: [ruleID, otherRuleID]).resetRuntime(
            ruleID: ruleID,
            logicalDay: CalendarDay(date: now, calendar: .current),
            saveRuntime: { runtime, id in
                XCTAssertEqual(id, self.ruleID)
                XCTAssertEqual(runtime.sessionsStarted, 0)
                XCTAssertNil(runtime.openSession)
                events.append("save")
            },
            clearFailedGrantBlock: { id in events.append("clear:\(id.uuidString)") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "clear:\(ruleID.uuidString)", "shield"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testRuntimeResetFailureNeverClearsMarker() {
        var events: [String] = []
        let result = coordinator(markers: [ruleID]).resetRuntime(
            ruleID: ruleID, logicalDay: CalendarDay(date: now, calendar: .current),
            saveRuntime: { _, _ in events.append("save"); throw TestError.save },
            clearFailedGrantBlock: { _ in events.append("clear") },
            applyShields: { events.append("shield") }
        )

        XCTAssertEqual(events, ["save", "shield"])
        XCTAssertEqual(result.repairRuleIDs, [ruleID])
    }

    func testRuntimeResetClearAndReconcileFailuresAreBothVisible() {
        let result = coordinator(markers: [ruleID]).resetRuntime(
            ruleID: ruleID, logicalDay: CalendarDay(date: now, calendar: .current),
            saveRuntime: { _, _ in },
            clearFailedGrantBlock: { _ in throw TestError.clear },
            applyShields: { throw TestError.shield }
        )

        XCTAssertEqual(result.repairRuleIDs, [ruleID])
        XCTAssertEqual(result.issues.map(\.operation), [.clearFailedGrantBlock, .applyShields])
    }

    private func coordinator(markers: Set<UUID>) -> SessionReconciliationCoordinator {
        SessionReconciliationCoordinator(loadFailedGrantBlocks: { markers })
    }

    private func makeRuntime(
        ruleID: UUID,
        state: OpenSessionState,
        expiresIn offset: TimeInterval
    ) -> RuleRuntime {
        RuleRuntime(
            logicalDay: CalendarDay(date: now, calendar: .current),
            sessionsStarted: 1,
            openSession: OpenSession(
                activityName: SessionActivityName.sessionActivityName(for: ruleID),
                expiresAt: now.addingTimeInterval(offset),
                state: state
            )
        )
    }
}

private enum TestError: Error {
    case load
    case save
    case clear
    case shield
}
