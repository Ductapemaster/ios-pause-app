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

public struct SessionMonitorReconciliationRunner {
    public typealias Reconcile = (
        SessionReconciliationTrigger,
        Date
    ) -> SessionReconciliationResult

    private let makeReconcile: () throws -> Reconcile
    private let errorSink: (String) -> Void

    public init(
        makeReconcile: @escaping () throws -> Reconcile,
        errorSink: @escaping (String) -> Void
    ) {
        self.makeReconcile = makeReconcile
        self.errorSink = errorSink
    }

    public func intervalDidEnd(activityName: String, now: Date) {
        handle(activityName: activityName, now: now, warning: false)
    }

    public func intervalWillEndWarning(activityName: String, now: Date) {
        handle(activityName: activityName, now: now, warning: true)
    }

    private func handle(activityName: String, now: Date, warning: Bool) {
        do {
            let reconcile = try makeReconcile()
            let handler = SessionMonitorCallbackHandler { trigger, date in
                let result = reconcile(trigger, date)
                for issue in result.issues {
                    let rule = issue.ruleID?.uuidString ?? trigger.selectedRuleID?.uuidString ?? "unknown"
                    errorSink(
                        "Monitor reconciliation failed for activity \(activityName), rule \(rule): \(issue.localizedDescription)"
                    )
                }
            }
            if warning {
                handler.intervalWillEndWarning(activityName: activityName, now: now)
            } else {
                handler.intervalDidEnd(activityName: activityName, now: now)
            }
        } catch {
            errorSink(
                "Monitor reconciliation could not start for activity \(activityName): \(error.localizedDescription)"
            )
        }
    }
}
