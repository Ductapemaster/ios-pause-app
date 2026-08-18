import DeviceActivity
import Foundation

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
        let work = {
            MainActor.assumeIsolated {
                guard let service = try? SessionReconciliationService() else { return }
                let handler = SessionMonitorCallbackHandler { trigger, now in
                    _ = service.reconcile(now: now, trigger: trigger)
                }
                if warning {
                    handler.intervalWillEndWarning(activityName: activityName, now: Date())
                } else {
                    handler.intervalDidEnd(activityName: activityName, now: Date())
                }
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
