import XCTest
@testable import MDViewerPlus

final class InternalMarkdownLinkResolverTests: XCTestCase {
    private var root: URL!
    private var document: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        document = root.appendingPathComponent("current.md")
        try "# Current".write(to: document, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testResolvesSupportedRelativeFileAndFragment() throws {
        let target = root.appendingPathComponent("next.markdown")
        try "# Target".write(to: target, atomically: true, encoding: .utf8)

        let result = try InternalMarkdownLinkResolver.resolve(
            rawLink: "next.markdown#target-heading",
            documentURL: document,
            authorizedRoot: root
        )

        XCTAssertEqual(result.fileURL, target.resolvingSymlinksInPath())
        XCTAssertEqual(result.fragment, "target-heading")
    }

    func testRejectsTraversalQueriesUnsupportedTypesAndSymlinkEscape() throws {
        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "../outside.md",
                documentURL: document,
                authorizedRoot: root
            )
        )
        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "next.md?download=1",
                documentURL: document,
                authorizedRoot: root
            )
        )
        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "image.png",
                documentURL: document,
                authorizedRoot: root
            )
        )

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideFile = outside.appendingPathComponent("outside.md")
        try "outside".write(
            to: outsideFile,
            atomically: true,
            encoding: .utf8
        )
        let link = root.appendingPathComponent("escape.md")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outsideFile
        )
        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "escape.md",
                documentURL: document,
                authorizedRoot: root
            )
        ) {
            XCTAssertEqual(
                $0 as? InternalMarkdownLinkError,
                .outsideAuthorizedRoot
            )
        }
    }
}
