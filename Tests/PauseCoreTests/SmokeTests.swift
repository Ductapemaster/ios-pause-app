import XCTest
@testable import PauseCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(PauseCore.version, 1)
    }

    func testSessionActivityNameRoundTripsRuleID() {
        let ruleID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!

        XCTAssertEqual(
            SessionActivityName.sessionActivityName(for: ruleID),
            "session.550e8400-e29b-41d4-a716-446655440000"
        )
        XCTAssertEqual(
            SessionActivityName.ruleID(
                fromSessionActivityName: "session.550e8400-e29b-41d4-a716-446655440000"
            ),
            ruleID
        )
    }

    func testSessionActivityNameRejectsNamesOutsideTheSessionNamespace() {
        XCTAssertNil(SessionActivityName.ruleID(fromSessionActivityName: "rule.550e8400-e29b-41d4-a716-446655440000"))
    }
}
