import XCTest
@testable import MDViewerPlus

final class MarkdownSiblingNavigatorTests: XCTestCase {
    private var folderURL: URL!

    override func setUpWithError() throws {
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folderURL)
    }

    func testFiltersExtensionsHiddenFilesAndDirectories() throws {
        try createFile("Alpha.MD")
        try createFile("bravo.markdown")
        try createFile("charlie.MDOWN")
        try createFile("delta.mKd")
        try createFile("ignored.txt")
        try createFile(".hidden.md")
        try FileManager.default.createDirectory(
            at: folderURL.appendingPathComponent("folder.md"),
            withIntermediateDirectories: false
        )

        let siblings = try MarkdownSiblingNavigator.siblings(
            of: folderURL.appendingPathComponent("bravo.markdown"),
            in: folderURL
        )

        XCTAssertEqual(siblings.previous?.lastPathComponent, "Alpha.MD")
        XCTAssertEqual(siblings.next?.lastPathComponent, "charlie.MDOWN")
    }

    func testSortsFilenamesCaseInsensitively() throws {
        try createFile("alpha.md")
        try createFile("Bravo.md")
        try createFile("charlie.md")

        let siblings = try MarkdownSiblingNavigator.siblings(
            of: folderURL.appendingPathComponent("Bravo.md"),
            in: folderURL
        )

        XCTAssertEqual(siblings.previous?.lastPathComponent, "alpha.md")
        XCTAssertEqual(siblings.next?.lastPathComponent, "charlie.md")
    }

    func testBoundariesDoNotWrap() throws {
        try createFile("a.md")
        try createFile("b.md")

        let first = try MarkdownSiblingNavigator.siblings(
            of: folderURL.appendingPathComponent("a.md"),
            in: folderURL
        )
        let last = try MarkdownSiblingNavigator.siblings(
            of: folderURL.appendingPathComponent("b.md"),
            in: folderURL
        )

        XCTAssertNil(first.previous)
        XCTAssertEqual(first.next?.lastPathComponent, "b.md")
        XCTAssertEqual(last.previous?.lastPathComponent, "a.md")
        XCTAssertNil(last.next)
        XCTAssertNil(
            try MarkdownSiblingNavigator.destination(
                from: folderURL.appendingPathComponent("a.md"),
                in: folderURL,
                direction: .previous
            )
        )
        XCTAssertNil(
            try MarkdownSiblingNavigator.destination(
                from: folderURL.appendingPathComponent("b.md"),
                in: folderURL,
                direction: .next
            )
        )
    }

    func testMissingCurrentFileThrows() throws {
        try createFile("other.md")

        XCTAssertThrowsError(
            try MarkdownSiblingNavigator.siblings(
                of: folderURL.appendingPathComponent("missing.md"),
                in: folderURL
            )
        ) { error in
            XCTAssertEqual(
                error as? MarkdownSiblingNavigationError,
                .currentFileNotFound
            )
        }
    }

    func testEnumerationErrorIsPropagated() {
        let missingFolderFile = folderURL
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("document.md")

        XCTAssertThrowsError(
            try MarkdownSiblingNavigator.siblings(
                of: missingFolderFile,
                in: missingFolderFile.deletingLastPathComponent()
            )
        ) { error in
            XCTAssertNotNil(error as? CocoaError)
        }
    }

    func testOrderingUsesStableCaseFoldAndBinaryTieBreak() {
        let names = ["alpha.md", "i.md", "ALPHA.md", "I.md"]
        let ordered = names
            .map { URL(fileURLWithPath: "/tmp").appendingPathComponent($0) }
            .sorted(by: MarkdownSiblingNavigator.filenamePrecedes)
            .map(\.lastPathComponent)

        XCTAssertEqual(ordered, ["ALPHA.md", "alpha.md", "I.md", "i.md"])
    }

    func testCanonicalizesDocumentFolderAndReturnedURLs() throws {
        try createFile("a.md")
        try createFile("b.md")
        let nested = folderURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: false
        )
        let nonCanonicalDocument = URL(
            fileURLWithPath: nested.path + "/../b.md"
        )

        let siblings = try MarkdownSiblingNavigator.siblings(
            of: nonCanonicalDocument,
            in: nested.appendingPathComponent("..", isDirectory: true)
        )

        XCTAssertEqual(
            siblings.previous,
            folderURL.appendingPathComponent("a.md").standardizedFileURL
        )
        XCTAssertNil(siblings.next)
        XCTAssertFalse(siblings.previous?.path.contains("/../") == true)
    }

    func testReenumerationDiscoversAddedAndRemovedBoundaryFiles() throws {
        try createFile("a.md")
        try createFile("b.md")
        let currentURL = folderURL.appendingPathComponent("b.md")

        let initial = try MarkdownSiblingNavigator.siblings(
            of: currentURL,
            in: folderURL
        )
        XCTAssertEqual(initial.previous?.lastPathComponent, "a.md")
        XCTAssertNil(initial.next)

        try createFile("c.md")
        try FileManager.default.removeItem(
            at: folderURL.appendingPathComponent("a.md")
        )

        let refreshed = try MarkdownSiblingNavigator.siblings(
            of: currentURL,
            in: folderURL
        )
        XCTAssertNil(refreshed.previous)
        XCTAssertEqual(refreshed.next?.lastPathComponent, "c.md")
    }

    private func createFile(_ name: String) throws {
        try Data("# Test".utf8).write(to: folderURL.appendingPathComponent(name))
    }
}

final class DocumentOpeningPolicyTests: XCTestCase {
    func testSuccessfulOpenClosesCleanSource() {
        XCTAssertEqual(
            DocumentOpeningPolicy.sourceDisposition(
                openSucceeded: true,
                hasUnsavedChanges: false
            ),
            .close
        )
    }

    func testSuccessfulOpenKeepsEditedSource() {
        XCTAssertEqual(
            DocumentOpeningPolicy.sourceDisposition(
                openSucceeded: true,
                hasUnsavedChanges: true
            ),
            .keepOpen
        )
    }

    func testFailedOpenAlwaysKeepsSource() {
        XCTAssertEqual(
            DocumentOpeningPolicy.sourceDisposition(
                openSucceeded: false,
                hasUnsavedChanges: false
            ),
            .keepOpen
        )
        XCTAssertEqual(
            DocumentOpeningPolicy.sourceDisposition(
                openSucceeded: false,
                hasUnsavedChanges: true
            ),
            .keepOpen
        )
    }

    @MainActor
    func testSuccessfulOpenClosesSourceThatIsStillUnedited() {
        let window = NavigationWindowStub(isDocumentEdited: false)

        DocumentOpeningPolicy.handleSuccessfulOpen(sourceWindow: window)

        XCTAssertEqual(window.closeCount, 1)
    }

    @MainActor
    func testSuccessfulOpenKeepsSourceThatIsEditedAtCompletion() {
        let window = NavigationWindowStub(isDocumentEdited: true)

        DocumentOpeningPolicy.handleSuccessfulOpen(sourceWindow: window)

        XCTAssertEqual(window.closeCount, 0)
    }
}

final class SiblingNavigationTargetPolicyTests: XCTestCase {
    func testOpenFailureClearsPreviouslyEnabledTargets() {
        let targets = MarkdownSiblingFiles(
            previous: URL(fileURLWithPath: "/tmp/previous.md"),
            next: URL(fileURLWithPath: "/tmp/failed.md")
        )

        let result = SiblingNavigationTargetPolicy.afterOpenFailure(
            currentTargets: targets
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertNil(result.previous)
        XCTAssertNil(result.next)
    }
}

final class SiblingNavigationFreshnessPolicyTests: XCTestCase {
    func testPreparationCommandChangesFromEnableToRefreshAfterAuthorization() {
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.preparationCommandTitle(
                hasFolderAccess: false
            ),
            "Enable Sibling Navigation…"
        )
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.preparationCommandTitle(
                hasFolderAccess: true
            ),
            "Refresh Sibling Navigation"
        )
    }

    func testReloadWithAuthorizationReenumeratesSilently() {
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.action(
                for: .reload,
                hasFolderAccess: true
            ),
            .enumerateSilently
        )
    }

    func testReloadWithoutOrAfterDeniedAuthorizationClearsSilently() {
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.action(
                for: .reload,
                hasFolderAccess: false
            ),
            .clearSilently
        )
        XCTAssertFalse(SiblingNavigationFreshnessAction.clearSilently.reportsErrors)
    }

    func testOnlyExplicitPreparationRequestsOrReportsAuthorizationErrors() {
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.action(
                for: .explicitPreparation,
                hasFolderAccess: false
            ),
            .requestAuthorization
        )
        XCTAssertEqual(
            SiblingNavigationFreshnessPolicy.action(
                for: .explicitPreparation,
                hasFolderAccess: true
            ),
            .enumerateReportingErrors
        )
        XCTAssertTrue(
            SiblingNavigationFreshnessAction.enumerateReportingErrors.reportsErrors
        )
    }
}

final class SecurityScopedLeaseLifetimeTests: XCTestCase {
    func testLeaseRemainsAliveThroughoutAsyncOperation() async {
        weak var weakLease: LeaseLifetimeProbe?
        var lease: LeaseLifetimeProbe? = LeaseLifetimeProbe()
        weakLease = lease

        await SecurityScopedLeaseLifetime.retaining(lease!) {
            lease = nil
            await Task.yield()
            XCTAssertNotNil(weakLease)
        }

        XCTAssertNil(weakLease)
    }
}

private final class LeaseLifetimeProbe {}

private final class NavigationWindowStub: NavigationSourceWindow {
    let isDocumentEdited: Bool
    private(set) var closeCount = 0

    init(isDocumentEdited: Bool) {
        self.isDocumentEdited = isDocumentEdited
    }

    func closeAfterSuccessfulNavigation() {
        closeCount += 1
    }
}

final class FolderAccessAuthorizationPolicyTests: XCTestCase {
    func testDocumentPreflightNeverRequestsAccessWithoutRestoredLease() {
        XCTAssertEqual(
            FolderAccessAuthorizationPolicy.decision(
                for: .documentPreflight,
                hasRestoredAccess: false
            ),
            .unavailable
        )
    }

    func testDocumentPreflightUsesRestoredLease() {
        XCTAssertEqual(
            FolderAccessAuthorizationPolicy.decision(
                for: .documentPreflight,
                hasRestoredAccess: true
            ),
            .useRestoredAccess
        )
    }

    func testExplicitNavigationMayRequestAccess() {
        XCTAssertEqual(
            FolderAccessAuthorizationPolicy.decision(
                for: .explicitNavigation,
                hasRestoredAccess: false
            ),
            .requestAccess
        )
    }

    func testDeniedAccessLeavesNavigationUnavailable() {
        XCTAssertFalse(
            FolderAccessAuthorizationPolicy.navigationAvailable(
                afterAccessWasGranted: false
            )
        )
    }
}
