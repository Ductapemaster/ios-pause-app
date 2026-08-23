import FamilyControls
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class AppModelFlowTests: XCTestCase {
    private let ruleID = UUID(uuidString: "3f7c1d20-6b8a-4f19-8e42-0a5c9d1b7e63")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testUnsafeRootPrecedesAuthorizationAndCannotDismissIntoConfiguration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .denied)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: true)

        XCTAssertEqual(model.rootRoute, .configurationRepair)
        model.returnToConfiguration()
        XCTAssertEqual(model.rootRoute, .configurationRepair)
    }

    func testUnsafePickerMutationPerformsNoPersistenceCleanupOrReconciliation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtimeURL = directory.appendingPathComponent("runtime-existing.json")
        let originalRuntime = Data("do-not-delete".utf8)
        try originalRuntime.write(to: runtimeURL)
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: true)

        XCTAssertThrowsError(try model.applyPickerSelection())
        XCTAssertEqual(try Data(contentsOf: runtimeURL), originalRuntime)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("configuration.json").path
        ))
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
        XCTAssertEqual(model.configurationLoadState, .missing)
    }

    func testFailedConfigurationCannotBePromotedByPickerSave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent("configuration.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: configurationURL)
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        XCTAssertThrowsError(try model.applyPickerSelection())
        XCTAssertEqual(model.configurationLoadState, .failed)
        XCTAssertEqual(try Data(contentsOf: configurationURL), corruptData)
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testFreshMissingPickerSaveCreatesKnownGoodConfiguration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.applyPickerSelection()

        XCTAssertEqual(model.configurationLoadState, .knownGood)
        XCTAssertNotNil(try ConfigurationStore(directoryURL: directory).loadFile())
    }

    func testFailedFreshPickerSavePreservesMissingStateAndPartialRuntime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        let partialRuntimeURL = directory.appendingPathComponent("runtime-partial.json")
        let partialRuntime = Data("keep-for-retry".utf8)
        try partialRuntime.write(to: partialRuntimeURL)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("configuration.json"),
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try model.applyPickerSelection())

        XCTAssertEqual(model.configurationLoadState, .missing)
        XCTAssertEqual(try Data(contentsOf: partialRuntimeURL), partialRuntime)
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testKnownGoodTaskFourMutationsRemainWired() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [],
                    targets: []
                ),
                pending: nil
            )
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.updatePauseSeconds(17)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 17)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).loadFile()?.effective.settings.pauseSeconds,
            17
        )
    }

    func testRootRoutingUsesProductionSafetyPrecedence() throws {
        let unsafeDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: unsafeDirectory) }
        let unsafe = makeModel(
            directory: unsafeDirectory,
            probe: FlowProbe(status: .denied),
            hasProtectedState: true
        )
        XCTAssertEqual(unsafe.rootRoute, .configurationRepair)

        let authorizationDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: authorizationDirectory) }
        let authorization = makeModel(
            directory: authorizationDirectory,
            probe: FlowProbe(status: .denied),
            hasProtectedState: false
        )
        XCTAssertEqual(authorization.rootRoute, .authorization)

        let configurationDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: configurationDirectory) }
        let configuration = makeModel(
            directory: configurationDirectory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        XCTAssertEqual(configuration.rootRoute, .authorizedContent)
    }

    func testAuthorizationCompletionWhileInactiveDefersIntentUntilRealActiveEntry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        probe.authorizationRequest = { probe.status = .approved }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidLeaveForeground()

        await model.requestAuthorization()
        XCTAssertEqual(probe.intentConsumptionCount, 0)
        XCTAssertNil(probe.startedCountdown)

        let activeAt = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: activeAt)
        XCTAssertEqual(probe.intentConsumptionCount, 1)
        XCTAssertEqual(probe.startedCountdown?.startedAt, activeAt)
        XCTAssertEqual(probe.startedCountdown?.remainingSeconds(at: activeAt), 10)
    }

    func testAuthorizationCompletionWhileActiveRerunsActivationExactlyOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        probe.authorizationRequest = { probe.status = .approved }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidBecomeActive(now: Date(timeIntervalSince1970: 1_750_000_000))

        await model.requestAuthorization()

        XCTAssertEqual(probe.intentConsumptionCount, 1)
        guard let countdown = probe.startedCountdown else {
            return XCTFail("Authorization completion should start one active-scene attempt")
        }
        XCTAssertEqual(countdown.remainingSeconds(at: countdown.startedAt), 10)
    }

    func testActiveCallbackWinningAuthorizationRaceDoesNotConsumeTwice() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let probe = FlowProbe(status: .denied)
        let gate = AuthorizationGate()
        probe.authorizationRequest = { await gate.wait() }
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.sceneDidLeaveForeground()

        let request = Task { await model.requestAuthorization() }
        await Task.yield()
        probe.status = .approved
        let activeAt = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: activeAt)
        gate.resume()
        await request.value

        XCTAssertEqual(probe.intentConsumptionCount, 1)
        XCTAssertEqual(probe.startedCountdown?.startedAt, activeAt)
        XCTAssertEqual(probe.startedCountdown?.remainingSeconds(at: activeAt), 10)
    }

    /// `updateRule` persists through `persist(_:now:)`, which refreshes the
    /// published usage itself rather than waiting for the next activation -
    /// the rule editor never leaves and re-enters the scene around a save.
    func testSavingARuleEditPublishesTheCurrentChargeWithoutARefreshTrigger() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: .current),
                sessionsStarted: 2
            ),
            ruleID: ruleID
        )
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        XCTAssertNil(model.sessionsUsedByRule[ruleID])

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)

        XCTAssertEqual(
            model.sessionsUsedByRule[ruleID],
            2,
            "a save must publish the current charge, since nothing else refreshes it before the next activation"
        )
    }

    func testRaisingAnAllowanceLeavesTodaysRuleInPlace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(
            id: ruleID,
            sessionsPerDay: 5,
            sessionLengthMinutes: 5,
            now: now
        )

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))
    }

    func testLoweringAnAllowanceAppliesAtOnceAndClearsASchedule() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        try model.updateRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5, now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 2)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testCancellingAScheduledChangeLeavesTodaysRuleInForce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        model.cancelScheduledChange(now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertNil(model.pendingChangeStartDay)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).loadFile()?.pending,
            nil
        )
    }

    func testShorteningThePauseWaitsWhileLengtheningItAppliesAtOnce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updatePauseSeconds(5, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 10)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testRemovingAnAppLeavesItsRuntimeUntilTheChangeTakesEffect() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let runtimeURL = directory.appendingPathComponent(
            "runtime-\(ruleID.uuidString.lowercased()).json"
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.removeRule(id: ruleID, now: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeURL.path))
        XCTAssertEqual(model.configuration.targets.count, 1)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }

    func testDroppingAnAppFromThePickerKeepsItSelectedUntilTheRemovalLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(model.pickerSelection.applicationTokens, [try token(seed: "instagram")])
        XCTAssertEqual(model.configuration.rules.map(\.id), [ruleID])
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))
    }

    func testTheRemovalTakesTheAppAndItsSelectionWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertTrue(model.configuration.rules.isEmpty)
        XCTAssertTrue(model.pickerSelection.applicationTokens.isEmpty)
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testAPickerSaveThatAddsAndDropsCoversTheAddedAppToday() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // One trip through the picker: Instagram dropped, Threads added.
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(
            Set(model.configuration.targets.map(\.applicationToken)),
            [try token(seed: "instagram"), try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))
        XCTAssertTrue(model.lastSaveDeferredPart)
    }

    func testAPickerSaveThatAddsAndDropsStillReconcilesShields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]

        try model.applyPickerSelection(now: now)

        // The addition is in force today, so it needs its shield now even
        // though the drop in the same save waits for the reset.
        XCTAssertEqual(probe.reconciliationCount, 1)
    }

    func testCancellingAMixedSaveDropsTheRemovalAndKeepsTheAddedApp() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]
        try model.applyPickerSelection(now: now)

        model.cancelScheduledChange(now: now)

        XCTAssertEqual(
            Set(model.configuration.targets.map(\.applicationToken)),
            [try token(seed: "instagram"), try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
        XCTAssertNil(model.presentedError)
        // The cancellation is durable, not just in memory.
        let stored = try ConfigurationStore(directoryURL: directory).loadFile()
        XCTAssertNil(stored?.pending)
        XCTAssertEqual(
            Set(stored?.effective.targets.map(\.applicationToken) ?? []),
            [try token(seed: "instagram"), try token(seed: "threads")]
        )
    }

    func testAnAddedAppTakesTheChosenAllowance() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        let added = try token(seed: "threads")
        model.pickerSelection.applicationTokens = [added]

        try model.applyPickerSelection(
            newAppAllowances: [added: AppRule.Allowance(sessionsPerDay: 7, sessionLengthMinutes: 45)],
            now: now
        )

        XCTAssertEqual(model.configuration.rules.count, 1)
        XCTAssertEqual(model.configuration.rules.first?.sessionsPerDay, 7)
        XCTAssertEqual(model.configuration.rules.first?.sessionLengthMinutes, 45)
    }

    func testAnAddedAppWithoutAChosenAllowanceTakesTheDefault() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(model.configuration.rules.first?.sessionsPerDay, AppRuleLimits.defaultSessionsPerDay)
        XCTAssertEqual(
            model.configuration.rules.first?.sessionLengthMinutes,
            AppRuleLimits.defaultSessionLengthMinutes
        )
    }

    func testAnOutOfRangeAllowanceIsRefusedBeforeAnyRuntimeIsWritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        let added = try token(seed: "threads")
        model.pickerSelection.applicationTokens = [added]

        XCTAssertThrowsError(
            try model.applyPickerSelection(
                newAppAllowances: [added: AppRule.Allowance(sessionsPerDay: 21, sessionLengthMinutes: 5)],
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? AppModelError, .invalidSessionsPerDay)
        }
        XCTAssertThrowsError(
            try model.applyPickerSelection(
                newAppAllowances: [added: AppRule.Allowance(sessionsPerDay: 3, sessionLengthMinutes: 121)],
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? AppModelError, .invalidSessionLength)
        }

        XCTAssertTrue(model.configuration.rules.isEmpty)
        XCTAssertEqual(try runtimeFileNames(in: directory), [])
    }

    func testTheAddedAppSurvivesTheDropWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertEqual(
            model.configuration.targets.map(\.applicationToken),
            [try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testATighteningSaveDefersNothingOfItsOwnWhileAChangeIsScheduled() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // Schedule Instagram's removal, then lengthen the pause — a tightening
        // that says nothing about Instagram.
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)
        XCTAssertTrue(model.lastSaveDeferredPart)

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertFalse(model.lastSaveDeferredPart)
        // The removal is still scheduled; only this save deferred nothing.
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current))
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
    }

    func testSettingTheResetTimePersistsItAndKeepsThePauseDuration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)
        let pauseBefore = model.configuration.settings.pauseSeconds

        try model.setResetMinuteOfDay(6 * 60, now: now)

        XCTAssertEqual(model.configuration.settings.resetMinuteOfDay, 6 * 60)
        XCTAssertEqual(model.configuration.settings.pauseSeconds, pauseBefore)
    }

    /// The pause-duration setter rebuilds the whole settings value, so a reset
    /// time already chosen must survive an unrelated edit to the countdown.
    func testEditingThePauseDurationKeepsTheResetTime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)
        try model.setResetMinuteOfDay(9 * 60 + 45, now: now)

        try model.updatePauseSeconds(30, now: now)

        XCTAssertEqual(model.configuration.settings.resetMinuteOfDay, 9 * 60 + 45)
        XCTAssertEqual(model.configuration.settings.pauseSeconds, 30)
    }

    func testAResetTimeOffTheQuarterHourGridIsRefused() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)

        XCTAssertThrowsError(try model.setResetMinuteOfDay(7, now: now)) { error in
            XCTAssertEqual(error as? AppModelError, .invalidResetMinuteOfDay)
        }
    }

    /// The entry decision, on the path the shield actually takes: a tap resolved
    /// after civil midnight but before a 06:00 reset must still be refused, since
    /// the allowance it would spend belongs to the day still running.
    func testEntryIsRefusedAfterMidnightWhileTheAllowanceDayStillRuns() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let spentAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 2))!
        let applicationToken = try token(seed: "instagram")
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
                    rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: applicationToken,
                            launchRoute: nil
                        )
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(
                    spentAt,
                    resetMinuteOfDay: 6 * 60,
                    calendar: calendar
                ),
                sessionsStarted: 3
            ),
            ruleID: ruleID
        )
        let suiteName = "pause-allowance-day-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        try ShieldIntentStore(defaults: defaults).write(
            ShieldIntent(applicationToken: applicationToken, createdAt: afterMidnight)
        )
        let model = AppModel(
            shieldReconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in },
                failedGrantBlockIDs: { [] }
            ),
            shieldIntentStore: ShieldIntentStore(defaults: defaults),
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {}
        )

        model.sceneDidBecomeActive(now: afterMidnight)

        guard case let .refused(content) = model.entryRoute else {
            return XCTFail("A spent allowance day must refuse entry, not open the pause")
        }
        XCTAssertEqual(content.title, "No sessions left today")
    }

    /// The list reads this snapshot, so activation must populate it with the
    /// count resolved against the allowance day — not the civil date, and not
    /// whatever the record happened to carry on disk.
    func testActivationPublishesTheCountResolvedAgainstTheAllowanceDay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let spentAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 2))!
        let applicationToken = try token(seed: "instagram")
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
                    rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: applicationToken,
                            launchRoute: nil
                        )
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(
                    spentAt,
                    resetMinuteOfDay: 6 * 60,
                    calendar: calendar
                ),
                sessionsStarted: 3
            ),
            ruleID: ruleID
        )
        let suiteName = "pause-allowance-day-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        try ShieldIntentStore(defaults: defaults).write(
            ShieldIntent(applicationToken: applicationToken, createdAt: afterMidnight)
        )
        let model = AppModel(
            shieldReconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in },
                failedGrantBlockIDs: { [] }
            ),
            shieldIntentStore: ShieldIntentStore(defaults: defaults),
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {}
        )

        model.sceneDidBecomeActive(now: afterMidnight)

        XCTAssertEqual(
            model.sessionsUsedByRule[ruleID],
            3,
            "midnight passing must not renew the count when the reset is later"
        )
    }

    /// The second activation is the ordinary re-foreground: once one activation
    /// has been handled for the current foreground streak, the activation
    /// coordinator returns `.unchanged` immediately, before it would run cleanup,
    /// reconciliation, or consume an intent again. If `refreshUsage` sat after the
    /// `switch outcome` instead of before it, that early return would skip it, and
    /// the published count would freeze at the first activation's answer for as
    /// long as the app stayed foregrounded - the most common case there is.
    func testTheCountRefreshesOnEveryForegroundNotJustTheFirst() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let spentAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 2))!
        let afterReset = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 7))!
        let applicationToken = try token(seed: "instagram")
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
                    rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: applicationToken,
                            launchRoute: nil
                        )
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(
                    spentAt,
                    resetMinuteOfDay: 6 * 60,
                    calendar: calendar
                ),
                sessionsStarted: 3
            ),
            ruleID: ruleID
        )
        let suiteName = "pause-allowance-day-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        try ShieldIntentStore(defaults: defaults).write(
            ShieldIntent(applicationToken: applicationToken, createdAt: afterMidnight)
        )
        let model = AppModel(
            shieldReconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: { _ in },
                failedGrantBlockIDs: { [] }
            ),
            shieldIntentStore: ShieldIntentStore(defaults: defaults),
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {}
        )

        model.sceneDidBecomeActive(now: afterMidnight)
        XCTAssertEqual(
            model.sessionsUsedByRule[ruleID],
            3,
            "the first activation must publish what the allowance day has charged"
        )

        model.sceneDidBecomeActive(now: afterReset)
        XCTAssertEqual(
            model.sessionsUsedByRule[ruleID],
            0,
            "an ordinary re-foreground past the reset must still refresh the count, even though the activation coordinator reports .unchanged"
        )
    }

    private func makeModel(
        directory: URL,
        probe: FlowProbe,
        hasProtectedState: Bool
    ) -> AppModel {
        AppModel(
            storageDirectoryURL: directory,
            authorizationStatusProvider: { probe.status },
            authorizationRequester: { try await probe.requestAuthorization() },
            entryActivationProvider: { now in
                probe.intentConsumptionCount += 1
                probe.startedCountdown = try PauseCountdown(
                    ruleID: UUID(uuidString: "b7ee38c9-cfed-4fbc-aa35-df716b5001ab")!,
                    seconds: 10,
                    now: now
                )
                return PauseActivationResolution(
                    payload: .configuration,
                    performMaintenance: false
                )
            },
            protectedStateDetector: { _ in hasProtectedState },
            cleanupOverride: { probe.cleanupCount += 1 },
            reconciliationOverride: { probe.reconciliationCount += 1 }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedOneRule(in directory: URL, sessionsPerDay: Int) throws {
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [
                        AppRule(
                            id: ruleID,
                            sessionsPerDay: sessionsPerDay,
                            sessionLengthMinutes: 5
                        )
                    ],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: try token(seed: "instagram"),
                            launchRoute: nil
                        )
                    ]
                ),
                pending: nil
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: .current), sessionsStarted: 0),
            ruleID: ruleID
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }

    private func runtimeFileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("runtime-") }
            .sorted()
    }

    private func writeEmptyConfiguration(to directory: URL) throws {
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [],
                    targets: []
                ),
                pending: nil
            )
        )
    }
}

@MainActor
private final class FlowProbe {
    var status: AuthorizationStatus
    var authorizationRequest: () async throws -> Void = {}
    var intentConsumptionCount = 0
    var startedCountdown: PauseCountdown?
    var cleanupCount = 0
    var reconciliationCount = 0

    init(status: AuthorizationStatus) {
        self.status = status
    }

    func requestAuthorization() async throws {
        try await authorizationRequest()
    }
}

@MainActor
private final class AuthorizationGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
