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

    func testAuxiliaryWindowsUseIntentionalButtonPolicies() {
        let app = XCUIApplication()
        launchDocument(in: app)

        app.activate()
        app.windows.firstMatch.click()
        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = window(named: "MDViewer+ Settings", in: app)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        XCTAssertLessThan(settingsWindow.frame.height, 500)
        XCTAssertFalse(
            windowButton(matching: "mini", in: settingsWindow).isEnabled
        )
        XCTAssertFalse(
            windowButton(matching: "zoom", in: settingsWindow).isEnabled
        )

        app.typeKey("w", modifierFlags: .command)
        let helpMenu = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 5))
        helpMenu.click()
        let helpItem = helpMenu.menus.menuItems["MDViewer+ Help"]
        XCTAssertTrue(helpItem.waitForExistence(timeout: 5))
        helpItem.click()

        let helpWindow = window(named: "Help", in: app)
        XCTAssertTrue(helpWindow.waitForExistence(timeout: 5))
        let minimizeButton = windowButton(matching: "mini", in: helpWindow)
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(minimizeButton.isEnabled)
        XCTAssertFalse(windowButton(matching: "zoom", in: helpWindow).isEnabled)
        XCTAssertTrue(
            helpWindow.staticTexts[
                "Native, offline Markdown editing and preview."
            ].exists
        )
        XCTAssertFalse(helpWindow.staticTexts["MDViewer+ Help"].exists)
    }

    func testFolderNavigatorHasOneStableToolbarControlWithHelp() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        let documentWindow = window(named: "source.md", in: app)

        XCTAssertTrue(
            waitForCount(
                1,
                in: allSidebarToolbarControls(in: documentWindow),
                timeout: 5
            )
        )
        var controls = sidebarToolbarControls(in: documentWindow)
        XCTAssertEqual(controls.count, 1)
        let initialControl = controls.firstMatch
        let initialFrame = initialControl.frame
        XCTAssertEqual(initialControl.label, "Folder Navigator")

        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.descendants(matching: .any)["folderNavigator"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            waitForCount(
                1,
                in: allSidebarToolbarControls(in: documentWindow),
                timeout: 5
            )
        )
        controls = sidebarToolbarControls(in: documentWindow)
        XCTAssertEqual(controls.count, 1)
        XCTAssertEqual(
            controls.firstMatch.frame.minX,
            initialFrame.minX,
            accuracy: 2
        )

        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertFalse(
            app.descendants(matching: .any)["folderNavigator"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertEqual(sidebarToolbarControls(in: documentWindow).count, 1)
    }

    func testFolderNavigatorLongFilenameHasExactExtensionAndHelp() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        authorizeNavigatorRoot(fixture, in: app)

        let filename = navigatorLongFilename
        let row = navigatorRow(filename, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.hasSuffix(filename))
        XCTAssertTrue(row.label.hasSuffix(".markdown"))
        row.hover()

        let helpTag = app.descendants(matching: .helpTag).firstMatch
        XCTAssertTrue(helpTag.waitForExistence(timeout: 3))
    }

    func testFolderNavigatorSelectionDoesNotMoveCurrentDocumentMarker() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        authorizeNavigatorRoot(fixture, in: app)

        let sourceRow = navigatorRow("source.md", in: app)
        let nestedRow = navigatorRow("nested", in: app)
        let currentMarker = sourceRow.descendants(matching: .image)[
            "Current document"
        ]
        XCTAssertTrue(currentMarker.waitForExistence(timeout: 5))

        nestedRow.click()

        XCTAssertTrue(waitForSelection(in: nestedRow, timeout: 5))
        XCTAssertFalse(sourceRow.isSelected)
        XCTAssertTrue(currentMarker.exists)
        XCTAssertFalse(
            nestedRow.descendants(matching: .image)["Current document"].exists
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

        target.click()
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

    func testPreviewFindReportsCurrentTotalAndNoMatches() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try Data("# Alpha\n\nalpha alpha".utf8).write(
            to: fixture.appendingPathComponent("source.md")
        )

        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        app.typeKey("f", modifierFlags: .command)

        let field = app.descendants(matching: .any)["previewFindField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("alpha")
        field.typeKey(.return, modifierFlags: [])

        let status = app.descendants(matching: .any)["previewFindStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("1 of 3 matches", in: status, timeout: 5)
        )

        let next = app.buttons["Next Match"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
        XCTAssertTrue(
            waitForValue("2 of 3 matches", in: status, timeout: 5)
        )

        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("absent")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("No matches", in: status, timeout: 5))
    }

    func testQuickOpenAdaptsToWholeResultRows() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)

        app.typeKey("k", modifierFlags: .command)
        let search = app.descendants(matching: .any)["quickOpenSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let results = app.descendants(matching: .any)["quickOpenResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        let initialHeight = results.frame.height
        XCTAssertEqual(initialHeight, 48, accuracy: 4)

        search.typeText("source")
        XCTAssertTrue(
            waitForHeight(
                24,
                in: results,
                accuracy: 4,
                timeout: 5
            )
        )
        XCTAssertLessThan(results.frame.height, initialHeight)
    }

    func testOutlineUsesWholeRowsAndExcludesFrontmatter() throws {
        let fixture = try makeNavigatorFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let markdown = """
        ---
        title: Hidden metadata
        ---
        \((1...12).map { "# Heading \($0)" }.joined(separator: "\n\n"))
        """
        try Data(markdown.utf8).write(
            to: fixture.appendingPathComponent("source.md")
        )
        let app = XCUIApplication()
        launchFile(fixture.appendingPathComponent("source.md"), in: app)
        XCTAssertTrue(
            app.staticTexts["Heading 1"].waitForExistence(timeout: 5)
        )

        app.typeKey("o", modifierFlags: [.command, .shift])
        let results = app.descendants(matching: .any)["outlineResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertEqual(results.frame.height, 240, accuracy: 4)
        XCTAssertTrue(
            app.staticTexts["12 headings"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(results.staticTexts["Hidden metadata"].exists)
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
        let expand = app.buttons["Expand nested"]
        if !expand.waitForExistence(timeout: 3) {
            let openFolder = app.buttons.matching(
                NSPredicate(
                    format: "label == %@ OR label == %@",
                    "Open Folder",
                    "Open Folder…"
                )
            ).firstMatch
            XCTAssertTrue(openFolder.waitForExistence(timeout: 5))
            openFolder.click()
        }
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

    private func sidebarToolbarControls(
        in window: XCUIElement
    ) -> XCUIElementQuery {
        window.buttons.matching(
            identifier: "folderNavigatorToolbarButton"
        )
    }

    private func allSidebarToolbarControls(
        in window: XCUIElement
    ) -> XCUIElementQuery {
        window.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "sidebar",
                "folder navigator"
            )
        )
    }

    private func windowButton(
        matching name: String,
        in window: XCUIElement
    ) -> XCUIElement {
        window.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
                name,
                name
            )
        ).firstMatch
    }

    private func window(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.windows.matching(
            NSPredicate(
                format: "label == %@ OR title == %@",
                title,
                title
            )
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
        try Data("# Long Filename".utf8).write(
            to: root.appendingPathComponent(navigatorLongFilename)
        )
        try Data("# Destination Content".utf8).write(
            to: root.appendingPathComponent("nested/target.md")
        )
        return root
    }

    private var navigatorLongFilename: String {
        "a-very-long-markdown-filename-that-keeps-its-extension.markdown"
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

    private func waitForValue(
        _ value: String,
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.value as? String == value { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return element.value as? String == value
    }

    private func waitForHeight(
        _ height: CGFloat,
        in element: XCUIElement,
        accuracy: CGFloat,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if abs(element.frame.height - height) <= accuracy { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return abs(element.frame.height - height) <= accuracy
    }

    private func waitForSelection(
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.isSelected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return element.isSelected
    }

    private func waitForCount(
        _ count: Int,
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if query.count == count { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return query.count == count
    }
}
