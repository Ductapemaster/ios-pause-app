import Foundation
import PauseCore
import XCTest

final class PickerTitleTests: XCTestCase {
    func testNoSelectionAsksTheUserToChoose() {
        XCTAssertEqual(PickerTitle.text(forSelectedAppCount: 0), "Choose apps")
    }

    func testOneSelectedAppReadsAsSingular() {
        XCTAssertEqual(PickerTitle.text(forSelectedAppCount: 1), "1 app selected")
    }

    func testSeveralSelectedAppsReadAsPlural() {
        XCTAssertEqual(PickerTitle.text(forSelectedAppCount: 3), "3 apps selected")
    }

    func testNegativeCountFallsBackToTheEmptyPrompt() {
        XCTAssertEqual(PickerTitle.text(forSelectedAppCount: -1), "Choose apps")
    }
}
