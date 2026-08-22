import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

final class ScheduledChangeWordingTests: XCTestCase {
    private let instagram = UUID(uuidString: "3f7c1d20-6b8a-4f19-8e42-0a5c9d1b7e63")!
    private let reddit = UUID(uuidString: "9c2f8a41-5d3e-4b07-9f16-2e8b4a0c6d95")!
    private let youTube = UUID(uuidString: "1b4e7f92-8c05-4a63-b2d1-7f39c5a08e64")!

    // MARK: - What one document does to another

    func testDroppingAnAppReadsAsARemoval() throws {
        let before = try document(rules: [(instagram, 3, 5), (reddit, 2, 10)])
        let after = try document(rules: [(reddit, 2, 10)])

        XCTAssertEqual(
            ScheduledChangeWording.changes(from: before, to: after),
            [.removal(try token(seed: "instagram"))]
        )
    }

    func testAddingAnAppReadsAsAnAddition() throws {
        let before = try document(rules: [(instagram, 3, 5)])
        let after = try document(rules: [(instagram, 3, 5), (reddit, 2, 10)])

        XCTAssertEqual(
            ScheduledChangeWording.changes(from: before, to: after),
            [.addition(try token(seed: "reddit"))]
        )
    }

    func testAnAllowanceNamesOnlyTheFieldThatMoved() throws {
        let before = try document(rules: [(instagram, 3, 5)])
        let after = try document(rules: [(instagram, 5, 5)])

        XCTAssertEqual(
            ScheduledChangeWording.changes(from: before, to: after),
            [
                .allowance(
                    try token(seed: "instagram"),
                    sessionsPerDay: 5,
                    sessionLengthMinutes: nil
                )
            ]
        )
    }

    func testAPauseDurationChangeIsItsOwnChange() throws {
        let before = try document(rules: [(instagram, 3, 5)], pauseSeconds: 30)
        let after = try document(rules: [(instagram, 3, 5)], pauseSeconds: 20)

        XCTAssertEqual(
            ScheduledChangeWording.changes(from: before, to: after),
            [.pauseDuration(seconds: 20)]
        )
    }

    func testAnIdenticalDocumentChangesNothing() throws {
        let document = try document(rules: [(instagram, 3, 5)])

        XCTAssertEqual(ScheduledChangeWording.changes(from: document, to: document), [])
    }

    func testARemovalIsReadBeforeAnAddition() throws {
        let before = try document(rules: [(instagram, 3, 5)])
        let after = try document(rules: [(reddit, 2, 10)])

        XCTAssertEqual(
            ScheduledChangeWording.changes(from: before, to: after),
            [.removal(try token(seed: "instagram")), .addition(try token(seed: "reddit"))]
        )
    }

    // MARK: - The sentence

    func testARemovalNamesTheAppAndTheDay() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [.removal(try token(seed: "instagram"))],
                starting: "tomorrow"
            ),
            .aboutApp(try token(seed: "instagram"), predicate: "is being removed tomorrow.")
        )
    }

    func testAnAdditionNamesTheApp() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [.addition(try token(seed: "reddit"))],
                starting: "on Aug 22"
            ),
            .aboutApp(try token(seed: "reddit"), predicate: "is being added on Aug 22.")
        )
    }

    func testAnAllowanceReadsAsSessionsWhenOnlyTheCountMoved() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [
                    .allowance(
                        try token(seed: "instagram"),
                        sessionsPerDay: 5,
                        sessionLengthMinutes: nil
                    )
                ],
                starting: "tomorrow"
            ),
            .aboutApp(
                try token(seed: "instagram"),
                predicate: "changes to 5 sessions tomorrow."
            )
        )
    }

    func testAnAllowanceReadsAsMinutesWhenOnlyTheLengthMoved() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [
                    .allowance(
                        try token(seed: "instagram"),
                        sessionsPerDay: nil,
                        sessionLengthMinutes: 20
                    )
                ],
                starting: "tomorrow"
            ),
            .aboutApp(
                try token(seed: "instagram"),
                predicate: "changes to 20-minute sessions tomorrow."
            )
        )
    }

    func testAnAllowanceReadsBothFieldsWhenBothMoved() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [
                    .allowance(
                        try token(seed: "instagram"),
                        sessionsPerDay: 1,
                        sessionLengthMinutes: 1
                    )
                ],
                starting: "tomorrow"
            ),
            .aboutApp(
                try token(seed: "instagram"),
                predicate: "changes to 1 session of 1 minute tomorrow."
            )
        )
    }

    func testThePauseDurationNeedsNoApp() {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [.pauseDuration(seconds: 20)],
                starting: "tomorrow"
            ),
            .plain("The pause changes to 20 seconds tomorrow.")
        )
    }

    func testTwoChangesNameTheFirstAndCountTheOther() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [
                    .removal(try token(seed: "instagram")),
                    .pauseDuration(seconds: 20)
                ],
                starting: "tomorrow"
            ),
            .aboutApp(
                try token(seed: "instagram"),
                predicate: "is being removed, and 1 other change starts tomorrow."
            )
        )
    }

    func testFourChangesStayOneSentence() throws {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(
                for: [
                    .removal(try token(seed: "instagram")),
                    .addition(try token(seed: "reddit")),
                    .allowance(
                        try token(seed: "youtube"),
                        sessionsPerDay: 4,
                        sessionLengthMinutes: nil
                    ),
                    .pauseDuration(seconds: 20)
                ],
                starting: "tomorrow"
            ),
            .aboutApp(
                try token(seed: "instagram"),
                predicate: "is being removed, and 3 other changes start tomorrow."
            )
        )
    }

    func testNoNamedChangeFallsBackToTheBareNotice() {
        XCTAssertEqual(
            ScheduledChangeWording.sentence(for: [], starting: "at the next reset"),
            .plain("A change to your rules starts at the next reset.")
        )
    }

    // MARK: - Fixtures

    private func document(
        rules: [(UUID, Int, Int)],
        pauseSeconds: Int = 30
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: pauseSeconds),
            rules: try rules.map { ruleID, sessionsPerDay, sessionLengthMinutes in
                try AppRule(
                    id: ruleID,
                    sessionsPerDay: sessionsPerDay,
                    sessionLengthMinutes: sessionLengthMinutes
                )
            },
            targets: try rules.map { ruleID, _, _ in
                RuleTarget(
                    ruleID: ruleID,
                    applicationToken: try token(seed: seed(for: ruleID)),
                    launchRoute: nil
                )
            }
        )
    }

    private func seed(for ruleID: UUID) -> String {
        switch ruleID {
        case instagram: "instagram"
        case reddit: "reddit"
        default: "youtube"
        }
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
