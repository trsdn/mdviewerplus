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
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
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
}
