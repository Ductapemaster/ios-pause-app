import DeviceActivity
import Foundation
import OSLog

final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {}

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        handle(activityName: activity.rawValue, warning: false)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        handle(activityName: activity.rawValue, warning: true)
    }

    private func handle(activityName: String, warning: Bool) {
        let logger = Logger(subsystem: "com.koubalabs.pause.monitor", category: "reconciliation")
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
        if warning {
            runner.intervalWillEndWarning(activityName: activityName, now: Date())
        } else {
            runner.intervalDidEnd(activityName: activityName, now: Date())
        }
    }
}
