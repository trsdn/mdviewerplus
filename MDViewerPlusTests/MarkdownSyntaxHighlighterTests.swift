import AppKit
import XCTest
@testable import MDViewerPlus

final class MarkdownSyntaxHighlighterTests: XCTestCase {
    private let sentinel = NSAttributedString.Key("testSentinel")

    func testOrdinaryEditPreservesAttributesOutsideEditedLine() {
        let storage = NSTextStorage(string: "# Heading\nplain text\nlast line")
        let highlighter = makeHighlighter()
        highlighter.highlight(storage)
        storage.addAttribute(
            sentinel,
            value: true,
            range: NSRange(location: 0, length: 1)
        )

        let plainRange = (storage.string as NSString).range(of: "plain")
        highlighter.highlight(storage, editedRange: plainRange)

        XCTAssertNotNil(storage.attribute(sentinel, at: 0, effectiveRange: nil))
    }

    func testEditInsideFenceRehighlightsWholeFencedBlock() {
        let storage = NSTextStorage(string: "```\ncode\n```\nafter")
        let highlighter = makeHighlighter()
        highlighter.highlight(storage)
        storage.addAttribute(
            sentinel,
            value: true,
            range: NSRange(location: 0, length: 1)
        )

        let codeRange = (storage.string as NSString).range(of: "code")
        highlighter.highlight(storage, editedRange: codeRange)

        XCTAssertNil(storage.attribute(sentinel, at: 0, effectiveRange: nil))
    }

    func testFenceEditCanInvalidateThroughEndOfDocument() {
        let storage = NSTextStorage(string: "```\ncode\n```\nafter")
        let highlighter = makeHighlighter()
        highlighter.highlight(storage)
        let lastLocation = storage.length - 1
        storage.addAttribute(
            sentinel,
            value: true,
            range: NSRange(location: lastLocation, length: 1)
        )

        highlighter.highlight(
            storage,
            editedRange: NSRange(location: 0, length: 3),
            rehighlightToEnd: true
        )

        XCTAssertNil(
            storage.attribute(sentinel, at: lastLocation, effectiveRange: nil)
        )
    }

    private func makeHighlighter() -> MarkdownSyntaxHighlighter {
        MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            isDark: false
        )
    }
}
