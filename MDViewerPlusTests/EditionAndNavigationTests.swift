import XCTest
@testable import MDViewerPlus

final class EditionAndNavigationTests: XCTestCase {
    func testCapabilityModelIsMutuallyExclusive() {
        let capabilities = EditionCapabilities.current
        XCTAssertNotEqual(capabilities.prism, capabilities.broadHighlighting)
        XCTAssertEqual(
            capabilities.edition == .full,
            capabilities.frontmatter && capabilities.mermaid
        )
    }

    func testSupportMetadataIsStableAndSecure() {
        XCTAssertEqual(AppSupport.copyright, "Copyright © 2026 Torsten Mahr")
        XCTAssertEqual(
            AppSupport.websiteURL.absoluteString,
            "https://trsdn.github.io/mdviewerplus/"
        )
        XCTAssertEqual(
            AppSupport.sourceURL.absoluteString,
            "https://github.com/trsdn/mdviewerplus"
        )
        XCTAssertEqual(
            AppSupport.issueURL.absoluteString,
            "https://github.com/trsdn/mdviewerplus/issues/new"
        )
        XCTAssertEqual(AppSupport.websiteURL.scheme, "https")
        XCTAssertEqual(AppSupport.sourceURL.scheme, "https")
        XCTAssertEqual(AppSupport.issueURL.scheme, "https")
    }

    func testQuickOpenMatchingIsDeterministic() {
        let items = [
            "Reference.md", "README.md", "release-notes.md", "guide.markdown"
        ].map {
            QuickOpenItem(url: URL(fileURLWithPath: "/documents/\($0)"))
        }

        XCTAssertEqual(
            QuickOpenMatcher.filter(items, query: "read").map(\.name),
            ["README.md", "release-notes.md"]
        )
        XCTAssertEqual(
            QuickOpenMatcher.filter(items, query: "rnts").map(\.name),
            ["release-notes.md"]
        )
    }

    func testOutlineParsesATXSetextDuplicatesUnicodeAndFences() {
        let markdown = """
        # Hello World
        ## Hello World
        Über view
        =========
        ```
        # Not a heading
        ```
        """
        let entries = DocumentOutlineParser.parse(markdown)

        XCTAssertEqual(entries.map(\.title), [
            "Hello World", "Hello World", "Über view"
        ])
        XCTAssertEqual(entries.map(\.slug), [
            "hello-world", "hello-world-1", "über-view"
        ])
        XCTAssertEqual(entries.map(\.level), [1, 2, 1])
        XCTAssertTrue(entries.allSatisfy { $0.sourceLocation != nil })
    }

    func testModulePathValidationRejectsTraversal() {
        XCTAssertTrue(
            MarkdownModuleResolver.isSafeRelativePath(
                "mermaid/chunks/flowDiagram.mjs"
            )
        )
        XCTAssertFalse(
            MarkdownModuleResolver.isSafeRelativePath("../outside.mjs")
        )
        XCTAssertFalse(
            MarkdownModuleResolver.isSafeRelativePath("folder\\module.mjs")
        )
    }

    func testModuleResolverMatchesEditionBoundary() throws {
        let url = try XCTUnwrap(
            URL(
                string: "\(MarkdownModuleResolver.baseURL.absoluteString)js-yaml.esm.min.mjs"
            )
        )
        if EditionCapabilities.current.edition == .full {
            let module = try MarkdownModuleResolver.resolve(url)
            XCTAssertTrue(module.fileURL.lastPathComponent.hasSuffix(".mjs"))
            XCTAssertGreaterThan(module.byteCount, 0)
        } else {
            XCTAssertThrowsError(try MarkdownModuleResolver.resolve(url)) {
                XCTAssertEqual($0 as? MarkdownModuleError, .unavailable)
            }
        }
    }
}
