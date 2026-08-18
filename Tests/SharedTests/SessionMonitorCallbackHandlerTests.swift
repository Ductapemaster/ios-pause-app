import Foundation
import PauseCore
import XCTest

final class SessionMonitorCallbackHandlerTests: XCTestCase {
    private let ruleID = UUID(uuidString: "2acf6cb8-46e2-4498-8153-a45be2bf282f")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testEndCallbackParsesRuleAndRunsSynchronousReconciliation() {
        var received: SessionReconciliationTrigger?
        let handler = SessionMonitorCallbackHandler { trigger, date in
            XCTAssertEqual(date, self.now)
            received = trigger
        }

        handler.intervalDidEnd(
            activityName: SessionActivityName.sessionActivityName(for: ruleID),
            now: now
        )

        XCTAssertEqual(received, .intervalDidEnd(ruleID: ruleID))
    }

    func testWarningCallbackCarriesExactNamedActivity() {
        let name = SessionActivityName.sessionActivityName(for: ruleID)
        var received: SessionReconciliationTrigger?
        let handler = SessionMonitorCallbackHandler { trigger, _ in received = trigger }

        handler.intervalWillEndWarning(activityName: name, now: now)

        XCTAssertEqual(received, .intervalWillEndWarning(ruleID: ruleID, activityName: name))
    }

    func testMalformedActivityDoesNotRunReconciliation() {
        var count = 0
        let handler = SessionMonitorCallbackHandler { _, _ in count += 1 }

        handler.intervalDidEnd(activityName: "not-a-session", now: now)
        handler.intervalWillEndWarning(activityName: "session.invalid", now: now)

        XCTAssertEqual(count, 0)
    }
}
