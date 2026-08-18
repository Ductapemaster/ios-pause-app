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

    func testSynchronousRunnerWorksOnMainAndBackgroundContextsWithoutDeadlock() {
        let mainEvents = MonitorEvents()
        let mainRunner = SessionMonitorReconciliationRunner(
            makeReconcile: { { trigger, _ in
                mainEvents.append(String(describing: trigger))
                return SessionReconciliationResult()
            } },
            errorSink: { mainEvents.append($0) }
        )
        mainRunner.intervalDidEnd(
            activityName: SessionActivityName.sessionActivityName(for: ruleID),
            now: now
        )

        let backgroundFinished = expectation(description: "background callback returned")
        let backgroundEvents = MonitorEvents()
        let backgroundRuleID = ruleID
        let backgroundNow = now
        DispatchQueue.global().async {
            let runner = SessionMonitorReconciliationRunner(
                makeReconcile: { { trigger, _ in
                    backgroundEvents.append(String(describing: trigger))
                    return SessionReconciliationResult()
                } },
                errorSink: { backgroundEvents.append($0) }
            )
            runner.intervalWillEndWarning(
                activityName: SessionActivityName.sessionActivityName(for: backgroundRuleID),
                now: backgroundNow
            )
            backgroundFinished.fulfill()
        }

        wait(for: [backgroundFinished], timeout: 2)
        XCTAssertEqual(mainEvents.values.count, 1)
        XCTAssertEqual(backgroundEvents.values.count, 1)
    }

    func testRunnerSendsConstructionAndReconciliationFailuresToInjectedSink() {
        let constructionEvents = MonitorEvents()
        SessionMonitorReconciliationRunner(
            makeReconcile: { throw MonitorTestError.construction },
            errorSink: { constructionEvents.append($0) }
        ).intervalDidEnd(
            activityName: SessionActivityName.sessionActivityName(for: ruleID),
            now: now
        )

        let reconciliationEvents = MonitorEvents()
        SessionMonitorReconciliationRunner(
            makeReconcile: { { _, _ in
                SessionReconciliationResult(
                    repairRuleIDs: [self.ruleID],
                    issues: [
                        SessionReconciliationIssue(
                            ruleID: self.ruleID,
                            operation: .saveRuntime,
                            underlyingError: MonitorTestError.reconciliation
                        )
                    ]
                )
            } },
            errorSink: { reconciliationEvents.append($0) }
        ).intervalWillEndWarning(
            activityName: SessionActivityName.sessionActivityName(for: ruleID),
            now: now
        )

        XCTAssertTrue(constructionEvents.values.joined().contains("construction"))
        XCTAssertTrue(reconciliationEvents.values.joined().contains("save repaired session data"))
        XCTAssertTrue(reconciliationEvents.values.joined().contains(ruleID.uuidString))
    }
}

private enum MonitorTestError: LocalizedError {
    case construction
    case reconciliation

    var errorDescription: String? {
        switch self {
        case .construction: "construction failure"
        case .reconciliation: "reconciliation failure"
        }
    }
}

private final class MonitorEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
