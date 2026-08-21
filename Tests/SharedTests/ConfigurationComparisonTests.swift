import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationComparisonTests: XCTestCase {
    private let ruleID = UUID()
    private let otherRuleID = UUID()

    func testRaisingTheDailyAllowanceLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try document(sessionsPerDay: 5)
        ))
    }

    func testLoweringTheDailyAllowanceDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 5),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testLengtheningASessionLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionLengthMinutes: 5),
            to: try document(sessionLengthMinutes: 10)
        ))
    }

    func testShorteningASessionDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionLengthMinutes: 10),
            to: try document(sessionLengthMinutes: 5)
        ))
    }

    func testShorteningThePauseLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(pauseSeconds: 10),
            to: try document(pauseSeconds: 5)
        ))
    }

    func testLengtheningThePauseDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(pauseSeconds: 5),
            to: try document(pauseSeconds: 10)
        ))
    }

    func testRemovingATargetLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try twoRuleDocument(),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testAddingATargetDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try twoRuleDocument()
        ))
    }

    func testPointingARuleAtAnotherApplicationLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3, seed: "instagram"),
            to: try document(sessionsPerDay: 3, seed: "threads")
        ))
    }

    func testAnUnchangedDocumentDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testAnEditThatBothLoosensAndTightensLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3, sessionLengthMinutes: 10),
            to: try document(sessionsPerDay: 5, sessionLengthMinutes: 5)
        ))
    }

    // MARK: - Helpers

    private func document(
        sessionsPerDay: Int = 3,
        sessionLengthMinutes: Int = 5,
        pauseSeconds: Int = 10,
        seed: String = "instagram"
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: pauseSeconds),
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: sessionLengthMinutes)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: seed), launchRoute: nil)]
        )
    }

    private func twoRuleDocument() throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [
                AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
                AppRule(id: otherRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
            ],
            targets: [
                RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "instagram"), launchRoute: nil),
                RuleTarget(ruleID: otherRuleID, applicationToken: try token(seed: "threads"), launchRoute: nil),
            ]
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
