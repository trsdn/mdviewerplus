import XCTest
import AppKit
@testable import MDViewerPlus

final class ViewModeTests: XCTestCase {
    func testViewModeCyclesThroughAllModes() {
        XCTAssertEqual(ViewMode.view.next, .split)
        XCTAssertEqual(ViewMode.split.next, .edit)
        XCTAssertEqual(ViewMode.edit.next, .view)
    }

    @MainActor
    func testEditorUsesAutoHidingOverlayVerticalScrollerOnly() {
        let scrollView = NSScrollView()
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.horizontalScrollElasticity = .automatic

        MarkdownEditorView.configureScrollerBehavior(scrollView)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(scrollView.horizontalScrollElasticity, .none)
    }

    @MainActor
    func testSearchFieldErrorStateUsesSystemRedAndAccessibilityHelp() {
        let field = NSSearchField()

        NativeSearchField.applyErrorAppearance(true, to: field)

        XCTAssertEqual(field.textColor, .systemRed)
        XCTAssertEqual(field.layer?.borderWidth, 1)
        XCTAssertEqual(field.accessibilityHelp(), "No matches")

        NativeSearchField.applyErrorAppearance(false, to: field)

        XCTAssertEqual(field.textColor, .controlTextColor)
        XCTAssertEqual(field.layer?.borderWidth, 0)
        XCTAssertNil(field.accessibilityHelp())
    }
}
