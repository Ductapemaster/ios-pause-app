import Foundation
import ManagedSettings
import PauseCore
import XCTest

@MainActor
final class FailedGrantBlockStoreTests: XCTestCase {
    func testMarkerPersistsAcrossStoreInstances() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ruleID = UUID(uuidString: "11e3ccb8-823c-4867-9be7-9028947e64ae")!

        try FailedGrantBlockStore(directoryURL: directory).add(ruleID: ruleID)

        let reloaded = FailedGrantBlockStore(directoryURL: directory)
        XCTAssertEqual(try reloaded.load(), [ruleID])
        XCTAssertTrue(try reloaded.contains(ruleID: ruleID))

        try reloaded.clear(ruleID: ruleID)

        XCTAssertFalse(try FailedGrantBlockStore(directoryURL: directory).contains(ruleID: ruleID))
    }

    func testMalformedMarkerMakesOrdinaryReconciliationFailBlocked() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(SharedIdentifiers.failedGrantBlocksFilename)
        )
        let selectedID = UUID(uuidString: "11e3ccb8-823c-4867-9be7-9028947e64ae")!
        let selectedToken = try token(seed: "selected")
        let configuration = try configuration(ruleID: selectedID, token: selectedToken)
        var applied: Set<ApplicationToken>?
        let reconciler = ShieldReconciler(
            currentApplications: { applied },
            applyApplications: { applied = $0 },
            failedGrantBlockIDs: { try FailedGrantBlockStore(directoryURL: directory).load() }
        )

        XCTAssertThrowsError(
            try reconciler.reconcile(
                configuration: configuration,
                runtimeRepository: RuntimeRepository(directoryURL: directory),
                now: Date()
            )
        ) {
            XCTAssertEqual($0 as? ShieldReconciliationError, .unreadableFailedGrantBlocks)
        }
        XCTAssertEqual(applied, [selectedToken])
    }

    private func configuration(ruleID: UUID, token: ApplicationToken) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-failed-grant-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
