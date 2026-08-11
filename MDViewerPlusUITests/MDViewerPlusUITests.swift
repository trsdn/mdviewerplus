import XCTest

final class MDViewerPlusUITests: XCTestCase {
    func testLaunchShowsDocumentWindow() {
        let app = XCUIApplication()
        launchDocument(in: app)
    }

    func testToggleEditModeAffectsOnlyFrontWindow() {
        let app = XCUIApplication()
        launchDocument(in: app)

        toggleEditMode(in: app)
        let initialEditor = app.windows.firstMatch.descendants(matching: .any)["markdownEditor"]
        XCTAssertTrue(initialEditor.waitForExistence(timeout: 5))
        initialEditor.click()
        initialEditor.typeText("first document")
        toggleEditMode(in: app)
        toggleEditMode(in: app)

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()
        let newItem = fileMenu.menus.menuItems["New"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5))
        newItem.click()
        guard app.windows.element(boundBy: 1).waitForExistence(timeout: 5) else {
            return XCTFail("A second document window did not open")
        }

        let windows = app.windows.allElementsBoundByIndex
        XCTAssertEqual(windows.count, 2)

        let frontWindow = windows[0]
        let otherWindow = windows[1]
        frontWindow.click()
        toggleEditMode(in: app)

        XCTAssertTrue(
            frontWindow.descendants(matching: .any)["markdownEditor"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(otherWindow.descendants(matching: .any)["markdownEditor"].exists)
    }

    func testThemeShortcutPreservesSplitModeAndUnsavedText() {
        let app = XCUIApplication()
        launchDocument(in: app)
        toggleEditMode(in: app)

        let editor = app.descendants(matching: .any)["markdownEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("unsaved theme text")

        app.typeKey("2", modifierFlags: [.command, .shift])

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("unsaved theme text") == true)
        XCTAssertTrue(
            app.descendants(matching: .any)["markdownPreview"]
                .waitForExistence(timeout: 5)
        )
    }

    func testSiblingCommandsArePresentAndDisabledForNewDocument() {
        let app = XCUIApplication()
        launchDocument(in: app)

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()

        let enable = fileMenu.menus.menuItems["Enable Sibling Navigation…"]
        let previous = fileMenu.menus.menuItems["Previous Markdown File"]
        let next = fileMenu.menus.menuItems["Next Markdown File"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(enable.isEnabled)
        XCTAssertFalse(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
    }

    func testFolderNavigatorCommandsArePresentAndCollapsedForNewDocument() {
        let app = XCUIApplication()
        launchDocument(in: app)

        XCTAssertFalse(app.descendants(matching: .any)["folderNavigator"].exists)

        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        viewMenu.click()
        let toggle = viewMenu.menus.menuItems["Folder Navigator"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.isEnabled)

        app.typeKey(.escape, modifierFlags: [])
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        XCTAssertTrue(
            fileMenu.menus.menuItems["Open Folder…"].waitForExistence(timeout: 5)
        )
    }

    func testFolderNavigatorAcceptanceFlowForCleanSource() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        authorizeNavigatorRoot(fixture, in: app)

        let navigator = app.descendants(matching: .any)["folderNavigator"]
        XCTAssertTrue(navigator.waitForExistence(timeout: 5))
        let expand = app.buttons["Expand nested"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.click()

        let target = navigatorElement("target.md", in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.doubleClick()
        XCTAssertTrue(waitForWindowCount(1, in: app))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Current document"].waitForExistence(timeout: 5))

        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertFalse(navigator.waitForExistence(timeout: 1))
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(navigator.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Current document"].waitForExistence(timeout: 5))
    }

    func testFolderNavigatorKeepsEditedSourceAndOpensDestination() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        authorizeNavigatorRoot(fixture, in: app)

        app.buttons["Expand nested"].click()
        toggleEditMode(in: app)
        let sourceWindow = window(named: "source.md", in: app)
        let sourceEditor = sourceWindow.descendants(matching: .any)[
            "markdownEditor"
        ]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 5))
        sourceEditor.click()
        sourceEditor.typeText("\nunsaved source edit")

        let targetRow = navigatorRow("nested--target.md", in: app)
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5))
        targetRow.click()
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitForWindowCount(2, in: app))
        let destinationWindow = window(named: "target.md", in: app)
        XCTAssertTrue(sourceWindow.exists)
        XCTAssertTrue(destinationWindow.waitForExistence(timeout: 8))
        XCTAssertTrue(
            (sourceEditor.value as? String)?.contains("unsaved source edit")
                == true
        )

        destinationWindow.click()
        toggleEditMode(in: app)
        let destinationEditor = destinationWindow.descendants(matching: .any)[
            "markdownEditor"
        ]
        XCTAssertTrue(destinationEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (destinationEditor.value as? String)?
                .contains("Destination Content") == true
        )
        XCTAssertTrue(sourceWindow.exists)
        XCTAssertTrue(
            (sourceEditor.value as? String)?.contains("unsaved source edit")
                == true
        )
    }

    func testFolderNavigatorHomeEndReturnAndSpaceKeys() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        authorizeNavigatorRoot(fixture, in: app)

        let sourceRow = navigatorRow("source.md", in: app)
        let nestedRow = navigatorRow("nested", in: app)
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 5))
        sourceRow.click()

        app.typeKey(.home, modifierFlags: [])
        XCTAssertTrue(nestedRow.isSelected)
        app.typeKey(" ", modifierFlags: [])

        let targetRow = navigatorRow("nested--target.md", in: app)
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5))
        targetRow.click()
        app.typeKey(.end, modifierFlags: [])
        XCTAssertTrue(sourceRow.isSelected)

        targetRow.click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(window(named: "target.md", in: app).waitForExistence(timeout: 8))
    }

    private func toggleEditMode(in app: XCUIApplication) {
        let editMenu = app.menuBars.menuBarItems["Edit"]
        XCTAssertTrue(editMenu.waitForExistence(timeout: 5))
        editMenu.click()

        let toggleItem = editMenu.menus.menuItems["Toggle Edit Mode"]
        XCTAssertTrue(toggleItem.waitForExistence(timeout: 5))
        XCTAssertTrue(toggleItem.isEnabled)
        toggleItem.click()
    }

    private func launchDocument(in app: XCUIApplication) {
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-folderNavigatorVisible", "NO"
        ]
        app.launch()

        let newDocumentButton = app.buttons["NewDocumentButton"]
        if newDocumentButton.waitForExistence(timeout: 3) {
            newDocumentButton.click()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["markdownPreview"]
                .waitForExistence(timeout: 5)
        )
    }

    private func launchFile(_ fileURL: URL, in app: XCUIApplication) {
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-folderNavigatorVisible", "NO"
        ]
        app.launchEnvironment["MDVIEWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MDVIEWER_UI_TEST_DOCUMENT"] = fileURL.path
        app.launchEnvironment["MDVIEWER_UI_TEST_FOLDER"] =
            fileURL.deletingLastPathComponent().path
        app.launch()
        let newDocument = app.buttons["NewDocumentButton"]
        if newDocument.waitForExistence(timeout: 3) {
            newDocument.click()
        }
        XCTAssertTrue(
            window(named: fileURL.lastPathComponent, in: app)
                .waitForExistence(timeout: 8)
        )
    }

    private func authorizeNavigatorRoot(_ rootURL: URL, in app: XCUIApplication) {
        app.typeKey("b", modifierFlags: [.command, .shift])
        let navigator = app.descendants(matching: .any)["folderNavigator"]
        XCTAssertTrue(navigator.waitForExistence(timeout: 5))
        let openFolder = app.buttons["Open Folder…"]
        XCTAssertTrue(openFolder.waitForExistence(timeout: 5))
        openFolder.click()
        XCTAssertTrue(app.buttons["Expand nested"].waitForExistence(timeout: 8))
    }

    private func navigatorElement(
        _ name: String,
        kind: String = "Markdown file",
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "\(kind), \(name)")
        ).firstMatch
    }

    private func navigatorRow(
        _ relativePathIdentifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[
            "folderNavigatorRow-\(relativePathIdentifier)"
        ]
    }

    private func window(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.windows.matching(
            NSPredicate(format: "label == %@", title)
        ).firstMatch
    }

    private func makeNavigatorFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("# Source".utf8).write(
            to: root.appendingPathComponent("source.md")
        )
        try Data("# Destination Content".utf8).write(
            to: root.appendingPathComponent("nested/target.md")
        )
        return root
    }

    private func waitForWindowCount(
        _ count: Int,
        in app: XCUIApplication
    ) -> Bool {
        waitForWindowCount(in: app) { $0 == count }
    }

    private func waitForWindowCount(
        in app: XCUIApplication,
        predicate: (Int) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if predicate(app.windows.count) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return predicate(app.windows.count)
    }
}
