import XCTest
@testable import MDViewerPlus

final class ReloadPolicyTests: XCTestCase {
    func testUnchangedTextDoesNothing() {
        XCTAssertEqual(
            ReloadPolicy.decide(
                currentText: "same",
                diskText: "same",
                hasUnsavedChanges: true
            ),
            .unchanged
        )
    }

    func testCleanDocumentAppliesChangedDiskText() {
        XCTAssertEqual(
            ReloadPolicy.decide(
                currentText: "old",
                diskText: "new",
                hasUnsavedChanges: false
            ),
            .apply("new")
        )
    }

    func testEditedDocumentRequiresConfirmation() {
        XCTAssertEqual(
            ReloadPolicy.decide(
                currentText: "local edit",
                diskText: "disk edit",
                hasUnsavedChanges: true
            ),
            .confirm("disk edit")
        )
    }
}
