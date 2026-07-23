import XCTest
@testable import MDViewerPlus

final class MarkdownResourceResolverTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    func testResolvesFileInsideAuthorizedRoot() throws {
        let images = rootURL.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let image = images.appendingPathComponent("photo.png")
        try Data([0]).write(to: image)

        let result = try MarkdownResourceResolver.resolve(
            try XCTUnwrap(
                URL(string: "mdviewerplus-resource://document/images/photo.png")
            ),
            under: rootURL
        )

        XCTAssertEqual(result, image.resolvingSymlinksInPath())
    }

    func testRejectsEncodedTraversal() throws {
        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(
                try XCTUnwrap(
                    URL(string: "mdviewerplus-resource://document/%2E%2E/secret.png")
                ),
                under: rootURL
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, .traversal)
        }
    }

    func testRejectsSymlinkEscape() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secret = outside.appendingPathComponent("secret.png")
        try Data([0]).write(to: secret)
        let link = rootURL.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(
                try XCTUnwrap(
                    URL(string: "mdviewerplus-resource://document/linked.png")
                ),
                under: rootURL
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, .outsideAuthorizedRoot)
        }
    }

    func testRejectsWrongSchemeAndHost() throws {
        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(
                try XCTUnwrap(URL(string: "https://document/image.png")),
                under: rootURL
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, .invalidScheme)
        }

        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(
                try XCTUnwrap(
                    URL(string: "mdviewerplus-resource://elsewhere/image.png")
                ),
                under: rootURL
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, .invalidHost)
        }
    }
}
