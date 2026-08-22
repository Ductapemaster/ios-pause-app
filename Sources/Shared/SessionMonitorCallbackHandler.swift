import Foundation
import PauseCore

public enum DailyResetActivityName {
    public static let value = "daily-reset"
}

public struct SessionMonitorCallbackHandler {
    private let reconcile: (SessionReconciliationTrigger, Date) -> Void

    public init(reconcile: @escaping (SessionReconciliationTrigger, Date) -> Void) {
        self.reconcile = reconcile
    }

    /// Only the daily reset is acted on here. A session's own interval begins at
    /// the instant it is granted, so this callback also arrives immediately on
    /// every grant, carrying that session's name — which makes the name, not the
    /// arrival, the thing worth reading.
    public func intervalDidStart(activityName: String, now: Date) {
        guard SessionActivityName.ruleID(fromSessionActivityName: activityName) == nil else {
            return
        }
        reconcile(.dailyReset, now)
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

    public func intervalDidStart(activityName: String, now: Date) {
        handle(activityName: activityName, now: now, warning: false, didStart: true)
    }

    public func intervalDidEnd(activityName: String, now: Date) {
        handle(activityName: activityName, now: now, warning: false)
    }

    public func intervalWillEndWarning(activityName: String, now: Date) {
        handle(activityName: activityName, now: now, warning: true)
    }

    private func handle(
        activityName: String,
        now: Date,
        warning: Bool,
        didStart: Bool = false
    ) {
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
            if didStart {
                handler.intervalDidStart(activityName: activityName, now: now)
            } else if warning {
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
