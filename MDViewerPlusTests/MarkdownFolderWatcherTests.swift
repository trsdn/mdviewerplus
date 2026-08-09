import XCTest
@testable import MDViewerPlus

@MainActor
final class MarkdownFolderWatcherTests: XCTestCase {
    func testNativeWatcherDebouncesFolderChangesAndStops() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        let changed = expectation(description: "Folder change observed")
        changed.expectedFulfillmentCount = 1
        let watcher = MarkdownFolderWatcher(debounce: .milliseconds(80))
        XCTAssertTrue(
            watcher.start(watching: folder) {
                changed.fulfill()
            }
        )

        try "one".write(
            to: folder.appendingPathComponent("one.md"),
            atomically: true,
            encoding: .utf8
        )
        try "two".write(
            to: folder.appendingPathComponent("two.md"),
            atomically: true,
            encoding: .utf8
        )

        await fulfillment(of: [changed], timeout: 3)
        watcher.stop()
        XCTAssertNil(watcher.watchedFolder)
    }
}
