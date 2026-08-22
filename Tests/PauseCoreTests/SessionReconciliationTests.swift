import Foundation
@testable import PauseCore
import XCTest

final class SessionReconciliationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testUnexpiredActiveSessionStaysOpen() {
        XCTAssertEqual(reconciliation(for: runtime(state: .active, expiresIn: 60), now: now), .keepOpen)
    }

    func testUnexpiredProvisionalSessionActivatesDuringRecovery() {
        XCTAssertEqual(
            reconciliation(for: runtime(state: .provisional, expiresIn: 60), now: now),
            .activateProvisional
        )
    }

    func testExpiredActiveSessionExpires() {
        XCTAssertEqual(reconciliation(for: runtime(state: .active, expiresIn: 0), now: now), .expire)
    }

    func testExpiredProvisionalSessionExpiresWithoutChangingItsCharge() {
        let charged = runtime(state: .provisional, expiresIn: -1)

        XCTAssertEqual(reconciliation(for: charged, now: now), .expire)
        XCTAssertEqual(charged.sessionsStarted, 2)
    }

    func testNoOpenSessionRequiresNoRuntimeChange() {
        let runtime = RuleRuntime(logicalDay: CalendarDay(date: now, calendar: .current), sessionsStarted: 2)

        XCTAssertEqual(reconciliation(for: runtime, now: now), .noSession)
    }

    private func runtime(state: OpenSessionState, expiresIn offset: TimeInterval) -> RuleRuntime {
        RuleRuntime(
            logicalDay: CalendarDay(date: now, calendar: .current),
            sessionsStarted: 2,
            openSession: OpenSession(
                activityName: "session.2acf6cb8-46e2-4498-8153-a45be2bf282f",
                expiresAt: now.addingTimeInterval(offset),
                state: state
            )
        )
    }
}
