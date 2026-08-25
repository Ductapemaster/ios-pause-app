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

    func testAUnitDroppingCoverageLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(from: try unit(), to: nil))
    }

    func testAUnitGainingCoverageDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(from: nil, to: try unit()))
    }

    func testAUnitAbsentThroughoutDoesNotLoosen() {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: nil as ConfigurationComparison.RuleUnit?,
            to: nil as ConfigurationComparison.RuleUnit?
        ))
    }

    func testAUnitRaisingItsAllowanceLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(sessionsPerDay: 3),
            to: try unit(sessionsPerDay: 5)
        ))
    }

    func testAUnitLoweringItsAllowanceDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try unit(sessionsPerDay: 5),
            to: try unit(sessionsPerDay: 3)
        ))
    }

    func testAUnitLengtheningItsSessionLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(sessionLengthMinutes: 5),
            to: try unit(sessionLengthMinutes: 10)
        ))
    }

    func testAUnitShorteningItsSessionDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try unit(sessionLengthMinutes: 10),
            to: try unit(sessionLengthMinutes: 5)
        ))
    }

    func testAUnitRepointedAtAnotherApplicationLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(seed: "instagram"),
            to: try unit(seed: "threads")
        ))
    }

    func testShorteningThePauseLoosensTheSettingsUnit() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 10),
            to: try GlobalSettings(pauseSeconds: 5)
        ))
    }

    func testLengtheningThePauseDoesNotLoosenTheSettingsUnit() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 5),
            to: try GlobalSettings(pauseSeconds: 10)
        ))
    }

    func testUnitsAreKeyedByRuleIdentity() throws {
        let units = ConfigurationComparison.units(of: try twoRuleDocument())

        XCTAssertEqual(Set(units.keys), [ruleID, otherRuleID])
        XCTAssertEqual(units[ruleID]?.rule.id, ruleID)
        XCTAssertEqual(units[ruleID]?.target.ruleID, ruleID)
    }

    // MARK: - Helpers

    private func unit(
        sessionsPerDay: Int = 3,
        sessionLengthMinutes: Int = 5,
        seed: String = "instagram"
    ) throws -> ConfigurationComparison.RuleUnit {
        ConfigurationComparison.RuleUnit(
            rule: try AppRule(
                id: ruleID,
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            ),
            target: RuleTarget(
                ruleID: ruleID,
                applicationToken: try token(seed: seed),
                launchRoute: nil
            )
        )
    }

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

    func testShorteningTheCooldownLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 5),
            to: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 2)
        ))
    }

    func testSwitchingTheCooldownOffLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 5),
            to: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 0)
        ))
    }

    func testLengtheningTheCooldownDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 2),
            to: try GlobalSettings(pauseSeconds: 10, cooldownMinutes: 5)
        ))
    }
}
