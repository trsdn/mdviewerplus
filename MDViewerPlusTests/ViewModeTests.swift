import XCTest
@testable import MDViewerPlus

final class ViewModeTests: XCTestCase {
    func testViewModeCyclesThroughAllModes() {
        XCTAssertEqual(ViewMode.view.next, .split)
        XCTAssertEqual(ViewMode.split.next, .edit)
        XCTAssertEqual(ViewMode.edit.next, .view)
    }
}
