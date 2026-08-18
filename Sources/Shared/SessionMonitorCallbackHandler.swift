import Foundation
import PauseCore

public struct SessionMonitorCallbackHandler {
    private let reconcile: (SessionReconciliationTrigger, Date) -> Void

    public init(reconcile: @escaping (SessionReconciliationTrigger, Date) -> Void) {
        self.reconcile = reconcile
    }

    public func intervalDidEnd(activityName: String, now: Date) {
        guard let ruleID = SessionActivityName.ruleID(fromSessionActivityName: activityName) else {
            return
        }
        reconcile(.intervalDidEnd(ruleID: ruleID), now)
    }

    public func intervalWillEndWarning(activityName: String, now: Date) {
        guard let ruleID = SessionActivityName.ruleID(fromSessionActivityName: activityName) else {
            return
        }
        reconcile(
            .intervalWillEndWarning(ruleID: ruleID, activityName: activityName),
            now
        )
    }
}
