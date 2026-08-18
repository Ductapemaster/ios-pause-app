import XCTest
@testable import PauseCore

final class SelectionChangeTests: XCTestCase {
    func testNewSelectionIsAdded() {
        let change = selectionChange(existing: Set([1]), selected: Set([1, 2]))

        XCTAssertEqual(change.added, Set([2]))
        XCTAssertEqual(change.retained, Set([1]))
        XCTAssertEqual(change.removed, Set<Int>())
    }

    func testExistingSelectionIsRetained() {
        let change = selectionChange(existing: Set([1, 2]), selected: Set([2, 3]))

        XCTAssertEqual(change.retained, Set([2]))
    }

    func testDeselectedValueIsRemoved() {
        let change = selectionChange(existing: Set([1, 2]), selected: Set([2]))

        XCTAssertEqual(change.removed, Set([1]))
        XCTAssertEqual(change.added, Set<Int>())
    }

    func testUnchangedSelectionHasNoAdditionsOrRemovals() {
        let change = selectionChange(existing: Set([1, 2]), selected: Set([1, 2]))

        XCTAssertEqual(change.added, Set<Int>())
        XCTAssertEqual(change.retained, Set([1, 2]))
        XCTAssertEqual(change.removed, Set<Int>())
    }
}
