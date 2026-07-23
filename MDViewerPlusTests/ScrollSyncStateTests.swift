import XCTest
@testable import MDViewerPlus

final class ScrollSyncStateTests: XCTestCase {
    func testReturningToPriorEditorFractionAfterPreviewScrollCreatesNewCommand() {
        var state = ScrollSyncState()

        let first = state.command(forEditorFraction: 0.25)
        XCTAssertNotNil(first)
        XCTAssertFalse(
            state.shouldAcceptPreviewScroll(generation: first?.generation)
        )

        XCTAssertTrue(state.shouldAcceptPreviewScroll(generation: nil))

        let returned = state.command(forEditorFraction: 0.25)
        XCTAssertNotNil(returned)
        XCTAssertNotEqual(returned?.generation, first?.generation)
    }

    func testRepeatedEditorFractionIsCoalesced() {
        var state = ScrollSyncState()

        XCTAssertNotNil(state.command(forEditorFraction: 0.5))
        XCTAssertNil(state.command(forEditorFraction: 0.5005))
        XCTAssertNotNil(state.command(forEditorFraction: 0.51))
    }

    func testProgrammaticScrollEventsAreIgnoredRegardlessOfGenerationAge() {
        var state = ScrollSyncState()

        let first = state.command(forEditorFraction: 0.2)
        let second = state.command(forEditorFraction: 0.8)

        XCTAssertFalse(
            state.shouldAcceptPreviewScroll(generation: first?.generation)
        )
        XCTAssertFalse(
            state.shouldAcceptPreviewScroll(generation: second?.generation)
        )
    }

    func testForcedRestoreAlwaysCreatesCommand() {
        var state = ScrollSyncState()

        XCTAssertNotNil(state.command(forEditorFraction: 0.4))
        XCTAssertNotNil(
            state.command(forEditorFraction: 0.4, force: true)
        )
    }
}
