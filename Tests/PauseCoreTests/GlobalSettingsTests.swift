import PauseCore
import XCTest

final class GlobalSettingsTests: XCTestCase {
    func testResetMinuteDefaultsToMidnight() throws {
        let settings = try GlobalSettings(pauseSeconds: 10)

        XCTAssertEqual(settings.resetMinuteOfDay, 0)
    }

    func testResetMinuteAcceptsEveryQuarterHourPosition() throws {
        for minute in stride(from: 0, through: 1425, by: 15) {
            let settings = try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: minute)
            XCTAssertEqual(settings.resetMinuteOfDay, minute)
        }
    }

    func testResetMinuteRejectsAPositionOffTheQuarterHourGrid() {
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 7)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
    }

    func testResetMinuteRejectsAPositionOutsideTheDay() {
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 1440)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: -15)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
    }

    /// Settings written by the current build carry no reset minute. Decoding one
    /// must read back as midnight rather than failing, which is the whole of the
    /// compatibility story for this change.
    func testDecodingSettingsWrittenBeforeTheResetExistedReadsAsMidnight() throws {
        let legacy = Data("{\"pauseSeconds\":10}".utf8)

        let settings = try JSONDecoder().decode(GlobalSettings.self, from: legacy)

        XCTAssertEqual(settings.pauseSeconds, 10)
        XCTAssertEqual(settings.resetMinuteOfDay, 0)
    }

    func testEncodedSettingsRoundTrip() throws {
        let settings = try GlobalSettings(pauseSeconds: 30, resetMinuteOfDay: 375)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }
}
