import XCTest
@testable import PauseCore

final class SmokeTests: XCTestCase {
    func testSharedAppGroupIdentifier() {
        XCTAssertEqual(SharedIdentifiers.appGroup, "group.com.koubalabs.pause")
    }
}
