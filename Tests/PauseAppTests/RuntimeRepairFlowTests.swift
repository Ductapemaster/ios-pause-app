import FamilyControls
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

@MainActor
final class RuntimeRepairFlowTests: XCTestCase {
    private let selectedRuleID = UUID(uuidString: "2acf6cb8-46e2-4498-8153-a45be2bf282f")!
    private let otherRuleID = UUID(uuidString: "d7636097-103c-45ad-a6aa-f4f7b85f8681")!
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

    func testSuccessfulRuleRemovalClearsOnlyRemovedMarkerAfterConfigurationCommit() throws {
        let harness = try makeHarness(corruptSelectedRuntime: false)
        let markers = FailedGrantBlockStore(directoryURL: harness.directory)
        try markers.add(ruleID: selectedRuleID)
        try markers.add(ruleID: otherRuleID)

        try harness.model.removeRule(id: selectedRuleID)

        XCTAssertFalse(try markers.contains(ruleID: selectedRuleID))
        XCTAssertTrue(try markers.contains(ruleID: otherRuleID))
        let saved = try XCTUnwrap(ConfigurationStore(directoryURL: harness.directory).load())
        XCTAssertFalse(saved.rules.contains(where: { $0.id == selectedRuleID }))
        XCTAssertTrue(saved.rules.contains(where: { $0.id == otherRuleID }))
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
            ConfigurationDocument(
                settings: .phaseOneDefault,
                rules: rules,
                targets: [
                    RuleTarget(ruleID: selectedRuleID, applicationToken: selectedToken, launchRoute: nil),
                    RuleTarget(ruleID: otherRuleID, applicationToken: otherToken, launchRoute: nil),
                    RuleTarget(ruleID: untouchedRuleID, applicationToken: untouchedToken, launchRoute: nil),
                ]
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
