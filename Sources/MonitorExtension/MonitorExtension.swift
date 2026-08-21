import DeviceActivity
import Foundation
import OSLog

final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        handle(activityName: activity.rawValue, callback: "intervalDidStart", warning: false, didStart: true)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        handle(activityName: activity.rawValue, callback: "intervalDidEnd", warning: false)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        handle(activityName: activity.rawValue, callback: "intervalWillEndWarning", warning: true)
    }

    private func handle(
        activityName: String,
        callback: String,
        warning: Bool,
        didStart: Bool = false
    ) {
        let logger = Logger(subsystem: "com.koubalabs.pause.monitor", category: "reconciliation")

        // Notice, not info: only notice and above are written to the log data
        // store, and a sysdiagnose archive is the only way these lines are read
        // back. An entry that never reaches the archive is indistinguishable
        // from an extension that never launched.
        logger.notice("Monitor callback \(callback, privacy: .public) for activity \(activityName, privacy: .public)")
        logger.notice("Monitor sandbox probe: \(AppGroupSandboxProbe.run().summary, privacy: .public)")

        let runner = SessionMonitorReconciliationRunner(
            makeReconcile: {
                let service = try SessionReconciliationService()
                return { trigger, now in
                    service.reconcile(now: now, trigger: trigger)
                }
            },
            errorSink: { message in
                logger.error("\(message, privacy: .public)")
            }
        )
        if didStart {
            runner.intervalDidStart(activityName: activityName, now: Date())
        } else if warning {
            runner.intervalWillEndWarning(activityName: activityName, now: Date())
        } else {
            runner.intervalDidEnd(activityName: activityName, now: Date())
        }
        logger.notice("Monitor callback \(callback, privacy: .public) returned for activity \(activityName, privacy: .public)")
    }
}
