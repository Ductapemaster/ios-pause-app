import DeviceActivity
import Foundation
import XCTest

final class DailyResetSchedulerTests: XCTestCase {
    func testTheScheduleBeginsAtTheConfiguredReset() throws {
        var registered: DeviceActivitySchedule?
        let scheduler = DailyResetScheduler(startMonitoring: { _, schedule in
            registered = schedule
        })

        try scheduler.register(resetMinuteOfDay: 6 * 60 + 30)

        XCTAssertEqual(registered?.intervalStart.hour, 6)
        XCTAssertEqual(registered?.intervalStart.minute, 30)
        XCTAssertTrue(registered?.repeats == true)
    }

    func testMidnightRegistersTheScheduleItAlwaysDid() throws {
        var registered: DeviceActivitySchedule?
        let scheduler = DailyResetScheduler(startMonitoring: { _, schedule in
            registered = schedule
        })

        try scheduler.register(resetMinuteOfDay: 0)

        XCTAssertEqual(registered?.intervalStart.hour, 0)
        XCTAssertEqual(registered?.intervalStart.minute, 0)
    }

    func testTheRegisteredActivityIsTheDailyResetByName() throws {
        var name: DeviceActivityName?
        let scheduler = DailyResetScheduler(startMonitoring: { activityName, _ in
            name = activityName
        })

        try scheduler.register(resetMinuteOfDay: 0)

        XCTAssertEqual(name?.rawValue, DailyResetActivityName.value)
    }
}
