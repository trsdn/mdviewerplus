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

    func testSemanticPaletteColorsDriveSyntaxTokens() {
        let palette = ThemeRegistry.palette(id: ThemeID.sepia.rawValue, category: .light)
        let storage = NSTextStorage(
            string: "# Heading\n[Link](url)\n`code`\n> quote\nplain"
        )
        MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            palette: palette.syntax
        ).highlight(storage)

        assertColor(
            palette.colors.link.nsColor,
            in: storage,
            at: (storage.string as NSString).range(of: "Heading").location
        )
        let codeLocation = (storage.string as NSString).range(of: "code").location
        assertColor(
            palette.colors.codeForeground.nsColor,
            in: storage,
            at: codeLocation
        )
        assertColor(
            palette.colors.codeBackground.nsColor,
            key: .backgroundColor,
            in: storage,
            at: codeLocation
        )
        assertColor(
            palette.colors.blockquoteForeground.nsColor,
            in: storage,
            at: (storage.string as NSString).range(of: "quote").location
        )
        assertColor(
            palette.colors.foreground.nsColor,
            in: storage,
            at: (storage.string as NSString).range(of: "plain").location
        )
    }

    private func makeHighlighter() -> MarkdownSyntaxHighlighter {
        let palette = ThemeRegistry.palette(
            id: ThemeID.githubLight.rawValue,
            category: .light
        )
        return MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            palette: palette.syntax
        )
    }

    private func assertColor(
        _ expected: NSColor,
        key: NSAttributedString.Key = .foregroundColor,
        in storage: NSTextStorage,
        at location: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = storage.attribute(key, at: location, effectiveRange: nil) as? NSColor
        XCTAssertTrue(actual?.isEqual(expected) == true, file: file, line: line)
    }
}
