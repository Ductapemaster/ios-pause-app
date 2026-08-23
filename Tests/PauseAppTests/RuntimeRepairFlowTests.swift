import FamilyControls
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class RuntimeRepairFlowTests: XCTestCase {
    private let selectedRuleID = UUID(uuidString: "2acf6cb8-46e2-4498-8153-a45be2bf282f")!
    private let otherRuleID = UUID(uuidString: "1d636097-103c-45ad-a6aa-f4f7b85f8681")!
    private let untouchedRuleID = UUID(uuidString: "4daec47c-1fed-4354-a604-808e237a99f5")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testActivationShowsAffectedAppleTokenAndOneRuntimeResetActionForCorruptState() throws {
        let harness = try makeHarness(corruptSelectedRuntime: true)

        harness.model.sceneDidBecomeActive(now: now)

        guard case let .repair(content) = harness.model.entryRoute else {
            return XCTFail("Unreadable runtime should route to visible repair")
        }
        XCTAssertEqual(content.applicationToken, harness.selectedToken)
        XCTAssertEqual(content.runtimeResetRuleID, selectedRuleID)
        XCTAssertTrue(content.message.contains("remains blocked") || content.message.contains("kept this app blocked"))
        XCTAssertNotNil(harness.model.presentedError)
    }

    func testShieldIntentWithCorruptRuntimeShowsTheAffectedAppleToken() throws {
        let harness = try makeHarness(corruptSelectedRuntime: true)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        try repository.save(
            runtime(ruleID: untouchedRuleID, state: .active, expiresIn: -60),
            ruleID: untouchedRuleID
        )
        try ShieldIntentStore(defaults: harness.defaults).write(
            ShieldIntent(applicationToken: harness.selectedToken, createdAt: now)
        )

        harness.model.sceneDidBecomeActive(now: now)

        guard case let .repair(content) = harness.model.entryRoute else {
            return XCTFail("Corrupt intent runtime should route to selected-app repair")
        }
        XCTAssertEqual(content.applicationToken, harness.selectedToken)
        XCTAssertEqual(content.runtimeResetRuleID, selectedRuleID)
        XCTAssertNil(try repository.load(ruleID: untouchedRuleID)?.openSession)
    }

    func testSelectedCorruptIntentRepairIsNotReplacedByUnrelatedCorruptRuntimeRepair() throws {
        let harness = try makeHarness(corruptSelectedRuntime: true)
        try Data("also-not-json".utf8).write(
            to: runtimeURL(ruleID: otherRuleID, directory: harness.directory)
        )
        try ShieldIntentStore(defaults: harness.defaults).write(
            ShieldIntent(applicationToken: harness.selectedToken, createdAt: now)
        )

        harness.model.sceneDidBecomeActive(now: now)

        guard case let .repair(content) = harness.model.entryRoute else {
            return XCTFail("The repair route for the opened shield intent must remain visible")
        }
        XCTAssertEqual(content.applicationToken, harness.selectedToken)
        XCTAssertEqual(content.runtimeResetRuleID, selectedRuleID)
    }

    func testUnrelatedCorruptRuntimeOverridesSelectedPauseWithFailBlockedRepair() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let otherToken = try token(for: otherRuleID)
        try Data("not-json".utf8).write(
            to: runtimeURL(ruleID: otherRuleID, directory: harness.directory)
        )
        try ShieldIntentStore(defaults: harness.defaults).write(
            ShieldIntent(applicationToken: harness.selectedToken, createdAt: now)
        )

        harness.model.sceneDidBecomeActive(now: now)

        guard case let .repair(content) = harness.model.entryRoute else {
            return XCTFail("Unreadable unrelated state must keep the activation fail-blocked")
        }
        XCTAssertEqual(content.applicationToken, otherToken)
        XCTAssertEqual(content.runtimeResetRuleID, otherRuleID)
    }

    func testMismatchedIntentKeepsRepairRouteAndRecoversUnrelatedProvisionalSession() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        try repository.save(
            runtime(ruleID: otherRuleID, state: .provisional, expiresIn: 60),
            ruleID: otherRuleID
        )
        let unknownToken = try token(
            for: UUID(uuidString: "79138656-b105-4c14-996f-909251fa1c90")!
        )
        try ShieldIntentStore(defaults: harness.defaults).write(
            ShieldIntent(applicationToken: unknownToken, createdAt: now)
        )

        harness.model.sceneDidBecomeActive(now: now)

        guard case .repair = harness.model.entryRoute else {
            return XCTFail("The mismatched intent repair route must be preserved")
        }
        XCTAssertEqual(try repository.load(ruleID: otherRuleID)?.openSession?.state, .active)
    }

    func testActivationPromotesOrdinaryProvisionalButNotMarkedProvisional() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        try repository.save(
            runtime(ruleID: selectedRuleID, state: .provisional, expiresIn: 60),
            ruleID: selectedRuleID
        )
        try repository.save(
            runtime(ruleID: otherRuleID, state: .provisional, expiresIn: 60),
            ruleID: otherRuleID
        )
        try FailedGrantBlockStore(directoryURL: harness.directory).add(ruleID: otherRuleID)

        harness.model.sceneDidBecomeActive(now: now)

        XCTAssertEqual(try repository.load(ruleID: selectedRuleID)?.openSession?.state, .active)
        XCTAssertEqual(try repository.load(ruleID: otherRuleID)?.openSession?.state, .provisional)
        XCTAssertNil(harness.model.presentedError)
        guard case let .repair(content) = harness.model.entryRoute else {
            return XCTFail("A durably blocked failed grant needs the selected runtime reset action")
        }
        XCTAssertEqual(content.runtimeResetRuleID, otherRuleID)
    }

    func testSafeActivationPrunesOnlyFailedGrantMarkersOutsideCurrentConfiguration() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        try repository.save(
            runtime(ruleID: otherRuleID, state: .provisional, expiresIn: 60),
            ruleID: otherRuleID
        )
        let orphanRuleID = UUID(uuidString: "05f629e6-cb5d-4dc3-a693-1bb5d6d80913")!
        let markers = FailedGrantBlockStore(directoryURL: harness.directory)
        try markers.add(ruleID: orphanRuleID)
        try markers.add(ruleID: otherRuleID)

        harness.model.sceneDidBecomeActive(now: now)

        XCTAssertFalse(try markers.contains(ruleID: orphanRuleID))
        XCTAssertTrue(try markers.contains(ruleID: otherRuleID))
    }

    func testUnsafeConfigurationDoesNotPruneFailedGrantMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-unsafe-marker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let markerRuleID = UUID(uuidString: "05f629e6-cb5d-4dc3-a693-1bb5d6d80913")!
        let markers = FailedGrantBlockStore(directoryURL: directory)
        try markers.add(ruleID: markerRuleID)
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("configuration.json")
        )
        let defaultsName = "pause-unsafe-marker-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        let model = AppModel(
            shieldIntentStore: ShieldIntentStore(defaults: defaults),
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {}
        )

        model.sceneDidBecomeActive(now: now)

        XCTAssertTrue(try markers.contains(ruleID: markerRuleID))
    }

    func testConfirmedRuntimeResetTouchesOnlySelectedFileAndClearsOnlySelectedMarker() throws {
        let harness = try makeHarness(corruptSelectedRuntime: true)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        let otherRuntime = runtime(ruleID: otherRuleID, state: .active, expiresIn: -60)
        let untouchedRuntime = runtime(ruleID: untouchedRuleID, state: .active, expiresIn: -60)
        try repository.save(otherRuntime, ruleID: otherRuleID)
        try repository.save(untouchedRuntime, ruleID: untouchedRuleID)
        let markers = FailedGrantBlockStore(directoryURL: harness.directory)
        try markers.add(ruleID: selectedRuleID)
        try markers.add(ruleID: otherRuleID)
        harness.model.resetRuntime(ruleID: selectedRuleID, now: now)

        let reset = try XCTUnwrap(repository.load(ruleID: selectedRuleID))
        XCTAssertEqual(reset.logicalDay, CalendarDay(date: now, calendar: .current))
        XCTAssertEqual(reset.sessionsStarted, 0)
        XCTAssertNil(reset.openSession)
        XCTAssertEqual(try repository.load(ruleID: otherRuleID), otherRuntime)
        XCTAssertEqual(try repository.load(ruleID: untouchedRuleID), untouchedRuntime)
        XCTAssertFalse(try markers.contains(ruleID: selectedRuleID))
        XCTAssertTrue(try markers.contains(ruleID: otherRuleID))
        guard case .configuration = harness.model.entryRoute else {
            return XCTFail("Successful confirmed reset should return to the app list")
        }
    }

    /// `resetRuntime` writes `sessionsStarted: 0` and routes straight back to
    /// the rules list; without its own refresh, the published count would
    /// still be whatever the last activation or grant resolved.
    func testAResetPublishesTheClearedCountInsteadOfLeavingThePreResetCountOnScreen() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let repository = RuntimeRepository(directoryURL: harness.directory)
        try repository.save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 3),
            ruleID: selectedRuleID
        )
        harness.model.sceneDidBecomeActive(now: now)
        XCTAssertEqual(harness.model.sessionsUsedByRule[selectedRuleID], 3)

        harness.model.resetRuntime(ruleID: selectedRuleID, now: now)

        XCTAssertEqual(
            harness.model.sessionsUsedByRule[selectedRuleID],
            0,
            "a reset must publish the cleared count instead of leaving the pre-reset count on screen"
        )
    }

    func testRuleRemovalSchedulesTheChangeAndKeepsEveryMarkerUntilItLands() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let markers = FailedGrantBlockStore(directoryURL: harness.directory)
        try markers.add(ruleID: selectedRuleID)
        try markers.add(ruleID: otherRuleID)

        try harness.model.removeRule(id: selectedRuleID, now: now)

        // Removing an app loosens the rules, so it is scheduled for the next
        // reset. Until then the rule is in force, so its failed-grant block
        // stays; the orphan cleanup clears it once the removal has landed.
        XCTAssertTrue(try markers.contains(ruleID: selectedRuleID))
        XCTAssertTrue(try markers.contains(ruleID: otherRuleID))
        let file = try XCTUnwrap(ConfigurationStore(directoryURL: harness.directory).loadFile())
        XCTAssertTrue(file.effective.rules.contains(where: { $0.id == selectedRuleID }))
        XCTAssertEqual(
            file.pending?.startDay,
            LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current)
        )
        let scheduled = try XCTUnwrap(file.pending?.document)
        XCTAssertFalse(scheduled.rules.contains(where: { $0.id == selectedRuleID }))
        XCTAssertTrue(scheduled.rules.contains(where: { $0.id == otherRuleID }))
    }

    private func makeHarness(corruptSelectedRuntime: Bool) throws -> RuntimeRepairHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-runtime-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let selectedToken = try token(for: selectedRuleID)
        let otherToken = try token(for: otherRuleID)
        let untouchedToken = try token(for: untouchedRuleID)
        let rules = [
            try AppRule(id: selectedRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
            try AppRule(id: otherRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
            try AppRule(id: untouchedRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
        ]
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: rules,
                    targets: [
                        RuleTarget(ruleID: selectedRuleID, applicationToken: selectedToken, launchRoute: nil),
                        RuleTarget(ruleID: otherRuleID, applicationToken: otherToken, launchRoute: nil),
                        RuleTarget(ruleID: untouchedRuleID, applicationToken: untouchedToken, launchRoute: nil),
                    ]
                ),
                pending: nil
            )
        )
        let repository = RuntimeRepository(directoryURL: directory)
        if corruptSelectedRuntime {
            try Data("not-json".utf8).write(
                to: directory.appendingPathComponent("runtime-\(selectedRuleID.uuidString.lowercased()).json")
            )
        } else {
            try repository.save(
                RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
                ruleID: selectedRuleID
            )
        }
        try repository.save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: otherRuleID
        )
        try repository.save(
            RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 0),
            ruleID: untouchedRuleID
        )

        let markers = FailedGrantBlockStore(directoryURL: directory)
        let reconciler = ShieldReconciler(
            currentApplications: { [] },
            applyApplications: { _ in },
            failedGrantBlockIDs: markers.load
        )
        let suiteName = "pause-runtime-repair-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            shieldReconciler: reconciler,
            shieldIntentStore: ShieldIntentStore(defaults: defaults),
            storageDirectoryURL: directory,
            authorizationStatusProvider: { .approved },
            authorizationRequester: {}
        )
        return RuntimeRepairHarness(
            directory: directory,
            model: model,
            selectedToken: selectedToken,
            defaults: defaults
        )
    }

    private func token(for ruleID: UUID) throws -> ApplicationToken {
        let encoded = Data(ruleID.uuidString.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(encoded)\"}".utf8)
        )
    }

    private func runtimeURL(ruleID: UUID, directory: URL) -> URL {
        directory.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
    }

    private func runtime(
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

@MainActor
private struct RuntimeRepairHarness {
    let directory: URL
    let model: AppModel
    let selectedToken: ApplicationToken
    let defaults: UserDefaults
}
