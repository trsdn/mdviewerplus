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

    func testQuickOpenDuplicateBasenamesUseOnlyDisplayPathForContext() {
        let items = [
            QuickOpenItem(
                url: URL(fileURLWithPath: "/documents/guides/README.md"),
                displayRelativePath: "guides/README.md"
            ),
            QuickOpenItem(
                url: URL(fileURLWithPath: "/documents/reference/readme.md"),
                displayRelativePath: "reference/readme.md"
            ),
            QuickOpenItem(
                url: URL(fileURLWithPath: "/documents/notes.md"),
                displayRelativePath: "notes.md"
            ),
        ]
        let duplicates = QuickOpenMatcher.duplicateBasenames(in: items)

        XCTAssertTrue(
            QuickOpenMatcher.hasDuplicateBasename(
                items[0],
                duplicateBasenames: duplicates
            )
        )
        XCTAssertTrue(
            QuickOpenMatcher.hasDuplicateBasename(
                items[1],
                duplicateBasenames: duplicates
            )
        )
        XCTAssertFalse(
            QuickOpenMatcher.hasDuplicateBasename(
                items[2],
                duplicateBasenames: duplicates
            )
        )
        XCTAssertEqual(items.map(\.displayParentPath), [
            "guides", "reference", ".",
        ])
        XCTAssertTrue(
            QuickOpenMatcher.filter(items, query: "reference").isEmpty
        )
    }

    func testQuickOpenCatalogRemainsDirectChildOnly() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = projectRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Direct".utf8).write(
            to: root.appendingPathComponent("direct.md")
        )
        try Data("# Nested".utf8).write(
            to: nested.appendingPathComponent("nested.md")
        )

        XCTAssertEqual(
            try MarkdownFileCatalog.files(in: root).map(\.lastPathComponent),
            ["direct.md"]
        )
    }

    func testNavigationPanelSizingUsesWholeRowsAndWindowClamp() {
        XCTAssertEqual(
            NavigationPanelSizing.quickOpenHeight(
                resultCount: 0,
                presentingHeight: 800
            ),
            128
        )
        XCTAssertEqual(
            NavigationPanelSizing.quickOpenHeight(
                resultCount: 99,
                presentingHeight: 800
            ),
            296
        )
        XCTAssertEqual(
            NavigationPanelSizing.outlineHeight(
                entryCount: 99,
                presentingHeight: 800
            ),
            344
        )

        let clamped = NavigationPanelSizing.quickOpenHeight(
            resultCount: 99,
            presentingHeight: 400
        )
        XCTAssertEqual(clamped, 224)
        XCTAssertLessThanOrEqual(clamped, 400 * 0.6)
        XCTAssertEqual(
            NavigationPanelSizing.rowViewportHeight(for: clamped)
                .truncatingRemainder(
                    dividingBy: NavigationPanelSizing.rowHeight
                ),
            0
        )
    }

    func testPreviewFindIndexResetsAndWrapsAfterSuccessfulFinds() {
        var state = PreviewFindIndexState()
        state.begin(query: "alpha")

        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 3,
                backwards: false
            ),
            PreviewFindResult(
                matchFound: true,
                currentIndex: 1,
                totalCount: 3
            )
        )
        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 3,
                backwards: false
            ).currentIndex,
            2
        )
        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 3,
                backwards: false
            ).currentIndex,
            3
        )
        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 3,
                backwards: false
            ).currentIndex,
            1
        )
        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 3,
                backwards: true
            ).currentIndex,
            3
        )
        XCTAssertEqual(
            state.result(
                matchFound: false,
                totalCount: 3,
                backwards: false
            ).currentIndex,
            3
        )

        state.begin(query: "beta")
        XCTAssertEqual(
            state.result(
                matchFound: true,
                totalCount: 2,
                backwards: false
            ).currentIndex,
            1
        )
        XCTAssertEqual(
            state.result(
                matchFound: false,
                totalCount: 0,
                backwards: false
            ),
            .empty
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

    func testFrontmatterSplitPreservesLineEndingsAndUTF16Offset() throws {
        let markdown = "---\r\ntitle: 😀\r\ntags:\r\n  - one\r\n---\r\n# Body\r\n"
        let split = try XCTUnwrap(MarkdownFrontmatter.split(markdown))

        XCTAssertEqual(split.source, "title: 😀\r\ntags:\r\n  - one\r\n")
        XCTAssertEqual(split.body, "# Body\r\n")
        XCTAssertEqual(
            split.bodyUTF16Offset,
            (markdown as NSString).range(of: "# Body").location
        )
    }

    func testFrontmatterSplitRequiresExactCompleteDelimiters() {
        XCTAssertNil(MarkdownFrontmatter.split("Before\n---\ntitle: no\n---\n"))
        XCTAssertNil(MarkdownFrontmatter.split("--- \ntitle: no\n---\n"))
        XCTAssertNil(MarkdownFrontmatter.split("---\ntitle: incomplete\n"))
        XCTAssertNil(MarkdownFrontmatter.split("---\ntitle: no\n...\nBody"))
        XCTAssertNil(MarkdownFrontmatter.split("---\ntitle: no\n--- trailing\nBody"))
    }

    func testOutlineExcludesFrontmatterAndRestoresSourceLocations() {
        let markdown = """
        ---
        # Hidden heading
        hidden setext
        =============
        ---
        😀 preface
        # Visible heading
        Visible setext
        --------------
        """
        let entries = DocumentOutlineParser.parse(markdown)

        XCTAssertEqual(entries.map(\.title), ["Visible heading", "Visible setext"])
        XCTAssertEqual(
            entries.map(\.sourceLocation),
            [
                (markdown as NSString).range(of: "# Visible heading").location,
                (markdown as NSString).range(of: "Visible setext").location,
            ]
        )
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
