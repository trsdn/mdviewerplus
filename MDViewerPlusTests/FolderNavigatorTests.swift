import XCTest
import AppKit
import CoreServices
@testable import MDViewerPlus

final class FolderNavigatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testContractConstantsAndExtensionAuthority() {
        XCTAssertEqual(
            MarkdownFileCatalog.supportedExtensions,
            ["md", "markdown", "mdown", "mkd"]
        )
        let limits = FolderNavigatorLimits.standard
        XCTAssertEqual(limits.maximumDepth, 12)
        XCTAssertEqual(limits.maximumChildren, 500)
        XCTAssertEqual(limits.maximumLoadedNodes, 5_000)
        XCTAssertEqual(limits.debounceMilliseconds, 250)
        XCTAssertEqual(limits.maximumPayloadBytes, 1_048_576)
        XCTAssertEqual(FolderNavigatorMetrics.defaultWidth, 240)
        XCTAssertEqual(FolderNavigatorMetrics.minimumWidth, 180)
        XCTAssertEqual(FolderNavigatorMetrics.maximumWidth, 420)
        XCTAssertEqual(FolderNavigatorMetrics.shortcut, "Cmd+Shift+B")
        XCTAssertEqual(RecursiveFolderNavigatorWatcher.defaultLatency, 0.25)
    }

    func testDirectChildrenFilterAndStableDirectoryFirstOrdering() throws {
        try directory("zeta")
        try directory("Alpha")
        for name in [
            "alpha.md", "b.markdown", "c.MDOWN", "d.mKd",
            "ignored.txt", ".hidden.md"
        ] {
            try file(name)
        }
        try directory("nested")
        try file("nested/not-direct.md")

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )

        XCTAssertEqual(result.nodes.map(\.name), [
            "Alpha", "nested", "zeta",
            "alpha.md", "b.markdown", "c.MDOWN", "d.mKd"
        ])
        XCTAssertEqual(result.nodes.prefix(3).map(\.kind), [
            .directory, .directory, .directory
        ])
        XCTAssertFalse(result.nodes.contains { $0.name == "not-direct.md" })
    }

    func testEmptyDirectoryAndLazyNestedEnumeration() throws {
        try directory("empty")
        try directory("guide")
        try file("guide/page.md")

        let rootChildren = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )
        XCTAssertFalse(rootChildren.nodes.contains { $0.name == "page.md" })

        let empty = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "empty",
            depth: 1
        )
        XCTAssertTrue(empty.nodes.isEmpty)
    }

    func testHiddenPackagesUnsupportedFilesAndSymlinksAreExcluded() throws {
        try directory(".secret")
        try file(".secret/page.md")
        try directory("Archive.app")
        try file("Archive.app/page.md")
        try file("plain.txt")
        try file("target.md")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.md"),
            withDestinationURL: root.appendingPathComponent("target.md")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-folder"),
            withDestinationURL: root
        )

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )
        XCTAssertEqual(result.nodes.map(\.name), ["target.md"])
    }

    func testChildAndDepthBoundsAreExplicit() throws {
        for index in 0..<501 {
            try file(String(format: "%03d.md", index))
        }

        func testEnumerationRetainsAtMostTheCandidateLimit() throws {
            for index in 0..<40 {
                try file(String(format: "%03d.md", 100 - index))
            }
            let limits = FolderNavigatorLimits(
                maximumChildren: 7,
                maximumLoadedNodes: 100
            )
            var observedCounts: [Int] = []
            let result = try FolderNavigatorTreeBuilder.children(
                rootURL: root,
                relativeDirectory: "",
                depth: 0,
                limits: limits,
                candidateCountObserver: { observedCounts.append($0) }
            )

            XCTAssertEqual(result.nodes.count, 7)
            XCTAssertEqual(observedCounts.max(), 7)
            XCTAssertTrue(result.isTruncated)
        }
        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )
        XCTAssertEqual(result.nodes.count, 500)
        XCTAssertTrue(result.isTruncated)
        XCTAssertTrue(result.nodes.last?.isTruncated == true)

        XCTAssertThrowsError(
            try FolderNavigatorTreeBuilder.children(
                rootURL: root,
                relativeDirectory: "",
                depth: 12
            )
        ) {
            XCTAssertEqual($0 as? FolderNavigatorError, .depthLimit)
        }

        let path = (1...11).map { "level\($0)" }.joined(separator: "/")
        try directory("\(path)/last")
        let deepestAllowed = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: path,
            depth: 11
        )
        XCTAssertEqual(deepestAllowed.nodes.single?.depth, 12)
        XCTAssertFalse(deepestAllowed.nodes.single?.isExpandable ?? true)
        XCTAssertTrue(deepestAllowed.nodes.allSatisfy { $0.depth <= 12 })
    }

    func testTraversalAbsoluteEncodedSeparatorAndDepthMismatchAreRejected() {
        for path in ["../outside", "/tmp", "a//b", "a%2Fb", "a\\b"] {
            XCTAssertThrowsError(
                try FolderNavigatorTreeBuilder.children(
                    rootURL: root,
                    relativeDirectory: path,
                    depth: path.isEmpty ? 0 : 1
                )
            )
        }
        XCTAssertThrowsError(
            try FolderNavigatorTreeBuilder.children(
                rootURL: root,
                relativeDirectory: "",
                depth: 1
            )
        )
    }

    func testResolvedFileIsConfinedAndRejectsSymlink() throws {
        try file("safe.md")
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try Data("# Outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.md"),
            withDestinationURL: outside
        )

        XCTAssertEqual(
            try FolderNavigatorTreeBuilder.resolvedMarkdownFile(
                rootURL: root,
                relativePath: "safe.md"
            ),
            root.appendingPathComponent("safe.md")
        )
        XCTAssertThrowsError(
            try FolderNavigatorTreeBuilder.resolvedMarkdownFile(
                rootURL: root,
                relativePath: "escape.md"
            )
        ) {
            XCTAssertEqual($0 as? FolderNavigatorError, .symbolicLink)
        }
    }

    func testResolvedFileRejectsDotHiddenAndResourceHiddenComponents() throws {
        try file(".private/secret.md")
        try directory("hidden")
        try file("hidden/secret.md")
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        var hiddenURL = root.appendingPathComponent("hidden")
        try hiddenURL.setResourceValues(hiddenValues)

        for relativePath in [".private/secret.md", "hidden/secret.md"] {
            XCTAssertThrowsError(
                try FolderNavigatorTreeBuilder.resolvedMarkdownFile(
                    rootURL: root,
                    relativePath: relativePath
                )
            ) {
                XCTAssertEqual($0 as? FolderNavigatorError, .accessDenied)
            }
        }
    }

    func testResolvedFileRejectsPackageComponents() throws {
        try directory("Archive.app")
        try file("Archive.app/inside.md")

        XCTAssertThrowsError(
            try FolderNavigatorTreeBuilder.resolvedMarkdownFile(
                rootURL: root,
                relativePath: "Archive.app/inside.md"
            )
        ) {
            XCTAssertEqual($0 as? FolderNavigatorError, .accessDenied)
        }
    }

    func testComponentWiseAncestorAndMostSpecificSelection() {
        let docs = URL(fileURLWithPath: "/tmp/vault/docs", isDirectory: true)
        let privateDocs = URL(
            fileURLWithPath: "/tmp/vault/docs-private/file.md"
        )
        XCTAssertFalse(FolderNavigatorPath.isContained(privateDocs, by: docs))

        let destination = URL(
            fileURLWithPath: "/tmp/vault/docs/guide/page.md"
        )
        XCTAssertEqual(
            FolderNavigatorPath.mostSpecificAncestor(
                of: destination,
                among: [
                    URL(fileURLWithPath: "/tmp/vault"),
                    docs,
                    URL(fileURLWithPath: "/tmp/other")
                ]
            ),
            docs
        )
    }

    func testFilesystemRefreshTargetsOnlyLoadedDirectories() {
        let loaded: Set<String> = ["", "guide", "guide/chapter"]
        let affected = FolderNavigatorRefreshPolicy.loadedDirectories(
            affectedBy: [
                root.appendingPathComponent("guide/chapter/new.md"),
                root.appendingPathComponent("unopened/deep/new.md"),
                root.deletingLastPathComponent().appendingPathComponent("outside.md")
            ],
            rootURL: root,
            loadedRelativeDirectories: loaded,
            pathExists: {
                $0 == self.root || $0.path.hasSuffix("/guide/chapter")
            }
        )
        XCTAssertEqual(affected, ["guide/chapter"])
    }

    func testWatcherGenerationRejectsQueuedOldStreamEvents() {
        XCTAssertTrue(
            RecursiveFolderNavigatorWatcher.shouldDeliver(
                producingGeneration: 4,
                currentGeneration: 4
            )
        )
        XCTAssertFalse(
            RecursiveFolderNavigatorWatcher.shouldDeliver(
                producingGeneration: 3,
                currentGeneration: 4
            )
        )
    }

    func testWatcherDroppedFlagsRequireFullRefresh() {
        for flag in [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped
        ] {
            XCTAssertTrue(
                RecursiveFolderNavigatorWatcher.requiresFullRefresh(
                    flags: FSEventStreamEventFlags(flag)
                )
            )
        }
        XCTAssertFalse(
            RecursiveFolderNavigatorWatcher.requiresFullRefresh(
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified
                )
            )
        )
    }

    func testDeletedLoadedDirectoryRefreshesOnlyItsParent() {
        let loaded: Set<String> = ["", "guide", "guide/chapter"]
        let deleted = root.appendingPathComponent("guide")
        let affected = FolderNavigatorRefreshPolicy.loadedDirectories(
            affectedBy: [deleted],
            rootURL: root,
            loadedRelativeDirectories: loaded,
            pathExists: { $0 == self.root }
        )

        XCTAssertEqual(affected, [""])
    }

    func testSpacePolicyDoesNotTreatPrintableKeysAsActivation() {
        XCTAssertTrue(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.shouldActivate(
                keyCode: 49,
                modifiers: []
            )
        )
        XCTAssertFalse(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.shouldActivate(
                keyCode: 0,
                modifiers: []
            )
        )
        XCTAssertFalse(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.shouldActivate(
                keyCode: 49,
                modifiers: .command
            )
        )
    }

    func testNavigatorRowsUseFixedColumnsAndIndentationGrid() {
        let metrics = FolderNavigatorSidebar.NavigatorRowMetrics.self
        XCTAssertEqual(metrics.indentationStep, 14)
        XCTAssertEqual(metrics.indentationWidth(for: 0), 0)
        XCTAssertEqual(metrics.indentationWidth(for: 3), 42)
        XCTAssertEqual(metrics.disclosureWidth, 12)
        XCTAssertEqual(metrics.iconWidth, 16)
        XCTAssertEqual(metrics.currentIndicatorWidth, 10)
        XCTAssertEqual(metrics.columnSpacing, 4)
    }

    func testNavigatorSelectionAndCurrentDocumentAreIndependent() {
        let selected = FolderNavigatorSidebar.rowState(
            relativePath: "selected.markdown",
            selectedRelativePath: "selected.markdown",
            currentRelativePath: "current.md"
        )
        let current = FolderNavigatorSidebar.rowState(
            relativePath: "current.md",
            selectedRelativePath: "selected.markdown",
            currentRelativePath: "current.md"
        )

        XCTAssertEqual(
            selected,
            .init(isSelected: true, isCurrentDocument: false)
        )
        XCTAssertEqual(
            current,
            .init(isSelected: false, isCurrentDocument: true)
        )
    }

    func testSpaceFocusPolicyIsLimitedToTreeAndExcludesButtons() {
        let table = NSTableView()
        let rowContent = NSView()
        table.addSubview(rowContent)
        XCTAssertTrue(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.isTreeFocused(
                rowContent
            )
        )

        let rowButton = NSButton()
        table.addSubview(rowButton)
        XCTAssertFalse(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.isTreeFocused(
                rowButton
            )
        )
        XCTAssertFalse(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.isTreeFocused(
                NSButton()
            )
        )
        XCTAssertFalse(
            FolderNavigatorSidebar.NavigatorSpaceKeyPolicy.isTreeFocused(
                NSView()
            )
        )
    }

    @MainActor
    func testFileRefreshQueuesWhileDirectoryIsLoading() async throws {
        try file("changed.md")
        await assertRefreshQueuesWhileLoading(
            paths: [root.appendingPathComponent("changed.md")],
            requiresFullRefresh: false
        )
    }

    @MainActor
    func testDroppedRefreshQueuesWhileDirectoryIsLoading() async {
        await assertRefreshQueuesWhileLoading(
            paths: [],
            requiresFullRefresh: true
        )
    }

    @MainActor
    private func assertRefreshQueuesWhileLoading(
        paths: [URL],
        requiresFullRefresh: Bool
    ) async {
        let started = expectation(description: "Initial enumeration started")
        let loader = BlockingFolderNavigatorLoader(started: started)
        let state = FolderNavigatorState(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            childrenLoader: {
                try loader.load(
                    rootURL: $0,
                    relativeDirectory: $1,
                    depth: $2,
                    limits: $3
                )
            }
        )
        let setup = Task {
            await state.setRoot(
                FolderAccessLease(testingRootURL: root),
                documentURL: root.appendingPathComponent("page.md")
            )
        }
        await fulfillment(of: [started], timeout: 5)

        await state.handleFilesystemChanges(
            paths: paths,
            requiresFullRefresh: requiresFullRefresh
        )
        loader.releaseInitialLoad()
        await setup.value

        XCTAssertEqual(loader.invocationCount, 2)
        XCTAssertEqual(
            state.childrenByDirectory[""]?.nodes.map(\.name),
            ["refreshed.md"]
        )
        XCTAssertTrue(state.loadingDirectories.isEmpty)
        state.reset()
    }

    @MainActor
    func testNodeLimitEarlyReturnClearsLoadingDirectory() async {
        try? file("page.md")
        let state = FolderNavigatorState(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            limits: FolderNavigatorLimits(maximumLoadedNodes: 0)
        )
        await state.setRoot(
            FolderAccessLease(testingRootURL: root),
            documentURL: root.appendingPathComponent("page.md")
        )

        XCTAssertTrue(state.loadingDirectories.isEmpty)
        XCTAssertEqual(
            state.statusMessage,
            FolderNavigatorError.nodeLimit.localizedDescription
        )
        state.reset()
    }

    @MainActor
    func testDeletedExpandedDirectoryRemovesLoadedSubtreeWithoutAccessError() async throws {
        try directory("guide/chapter")
        try file("guide/chapter/page.md")
        let state = FolderNavigatorState(
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await state.setRoot(
            FolderAccessLease(testingRootURL: root),
            documentURL: root.appendingPathComponent("guide/chapter/page.md"),
            expanded: ["guide", "guide/chapter"]
        )
        XCTAssertNotNil(state.childrenByDirectory["guide"])
        XCTAssertNotNil(state.childrenByDirectory["guide/chapter"])

        let deleted = root.appendingPathComponent("guide")
        try FileManager.default.removeItem(at: deleted)
        await state.handleFilesystemChanges(
            paths: [deleted],
            requiresFullRefresh: false
        )

        XCTAssertNil(state.childrenByDirectory["guide"])
        XCTAssertNil(state.childrenByDirectory["guide/chapter"])
        XCTAssertFalse(state.expandedRelativePaths.contains("guide"))
        XCTAssertNotEqual(
            state.statusMessage,
            FolderNavigatorError.accessDenied.localizedDescription
        )
        state.reset()
    }

    @MainActor
    func testDroppedEventRefreshesEveryStillLoadedDirectory() async throws {
        try directory("guide")
        try file("guide/old.md")
        let state = FolderNavigatorState(
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await state.setRoot(
            FolderAccessLease(testingRootURL: root),
            documentURL: root.appendingPathComponent("guide/old.md"),
            expanded: ["guide"]
        )

        try file("root-new.md")
        try file("guide/guide-new.md")
        await state.handleFilesystemChanges(
            paths: [],
            requiresFullRefresh: true
        )

        XCTAssertTrue(
            state.childrenByDirectory[""]?.nodes.contains {
                $0.relativePath == "root-new.md"
            } == true
        )
        XCTAssertTrue(
            state.childrenByDirectory["guide"]?.nodes.contains {
                $0.relativePath == "guide/guide-new.md"
            } == true
        )
        state.reset()
    }

    func testHomeAndEndSelectVisibleTreeBoundaries() {
        let paths = ["first", "middle", "last"]
        XCTAssertEqual(
            FolderNavigatorKeyboardSelection.boundaryPath(paths, first: true),
            "first"
        )
        XCTAssertEqual(
            FolderNavigatorKeyboardSelection.boundaryPath(paths, first: false),
            "last"
        )
    }

    @MainActor
    func testEditedNavigatorSourceStaysOpenWhileContextIsConsumed() {
        let store = FolderNavigatorContextStore()
        let destination = root.appendingPathComponent("nested/target.md")
        let context = FolderNavigatorPendingContext(
            rootURL: root,
            isVisible: true,
            expandedRelativePaths: ["nested"],
            selectedRelativePath: "nested/target.md",
            width: 240
        )
        store.store(context, for: destination)
        let window = FolderNavigatorEditedWindowStub()

        DocumentOpeningPolicy.handleSuccessfulOpen(sourceWindow: window)

        XCTAssertEqual(window.closeCount, 0)
        XCTAssertEqual(store.consume(for: destination), context)
    }

    @MainActor
    func testPendingContextIsConsumedOnceWithoutLease() {
        let destination = root.appendingPathComponent("page.md")
        let context = FolderNavigatorPendingContext(
            rootURL: root,
            isVisible: true,
            expandedRelativePaths: ["guide"],
            selectedRelativePath: "guide/page.md",
            width: 300
        )
        FolderNavigatorContextStore.shared.store(context, for: destination)
        XCTAssertEqual(
            FolderNavigatorContextStore.shared.consume(for: destination),
            context
        )
        XCTAssertNil(
            FolderNavigatorContextStore.shared.consume(for: destination)
        )
    }

    @MainActor
    func testPendingContextSurvivesOldDelayAndExpiresSafely() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let store = FolderNavigatorContextStore(
            expirationInterval: 10,
            maximumEntries: 2,
            now: { currentDate }
        )
        let context = FolderNavigatorPendingContext(
            rootURL: root,
            isVisible: true,
            expandedRelativePaths: [],
            selectedRelativePath: nil,
            width: 240
        )
        let first = root.appendingPathComponent("first.md")
        store.store(context, for: first)

        currentDate.addTimeInterval(2)
        XCTAssertEqual(store.consume(for: first), context)

        let expired = root.appendingPathComponent("expired.md")
        store.store(context, for: expired)
        currentDate.addTimeInterval(11)
        XCTAssertNil(store.consume(for: expired))
        XCTAssertEqual(store.pendingCount, 0)
    }

    @MainActor
    func testPendingContextPrunesOldestEntryAtCapacity() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 2_000)
        let store = FolderNavigatorContextStore(
            expirationInterval: 60,
            maximumEntries: 2,
            now: { currentDate }
        )
        let context = FolderNavigatorPendingContext(
            rootURL: root,
            isVisible: true,
            expandedRelativePaths: [],
            selectedRelativePath: nil,
            width: 240
        )
        let destinations = (0..<3).map {
            root.appendingPathComponent("\($0).md")
        }
        for destination in destinations {
            store.store(context, for: destination)
            currentDate.addTimeInterval(1)
        }

        XCTAssertEqual(store.pendingCount, 2)
        XCTAssertNil(store.consume(for: destinations[0]))
        XCTAssertEqual(store.consume(for: destinations[1]), context)
        XCTAssertEqual(store.consume(for: destinations[2]), context)
    }

    private func directory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relativePath),
            withIntermediateDirectories: true
        )
    }

    private func file(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("# Test".utf8).write(to: url)
    }

}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}

private final class FolderNavigatorEditedWindowStub: NavigationSourceWindow {
    var isDocumentEdited: Bool { true }
    private(set) var closeCount = 0

    func closeAfterSuccessfulNavigation() {
        closeCount += 1
    }
}

private final class BlockingFolderNavigatorLoader: @unchecked Sendable {
    private let started: XCTestExpectation
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0

    init(started: XCTestExpectation) {
        self.started = started
    }

    var invocationCount: Int {
        lock.withLock { count }
    }

    func releaseInitialLoad() {
        release.signal()
    }

    func load(
        rootURL: URL,
        relativeDirectory: String,
        depth: Int,
        limits: FolderNavigatorLimits
    ) throws -> FolderNavigatorChildren {
        let invocation = lock.withLock {
            count += 1
            return count
        }
        if invocation == 1 {
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
        }
        let name = invocation == 1 ? "initial.md" : "refreshed.md"
        return FolderNavigatorChildren(
            relativeDirectory: relativeDirectory,
            nodes: [
                FolderNavigatorNode(
                    id: "\(rootURL.path)#\(name)",
                    name: name,
                    relativePath: name,
                    kind: .file,
                    depth: depth + 1,
                    isExpandable: false,
                    isTruncated: false
                )
            ],
            isTruncated: false
        )
    }
}
