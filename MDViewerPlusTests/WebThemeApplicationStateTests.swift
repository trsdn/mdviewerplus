import XCTest
@testable import MDViewerPlus

final class WebThemeApplicationStateTests: XCTestCase {
    func testRapidReversalAppliesLatestDesiredPaletteAfterInFlightTheme() throws {
        let github = palette(.githubLight, category: .light)
        let sepia = palette(.sepia, category: .light)
        let state = WebThemeApplicationState(desiredPalette: github)

        let initial = try XCTUnwrap(state.pageDidBecomeReady())
        XCTAssertEqual(initial.palette.id, .githubLight)
        XCTAssertNil(state.complete(generation: initial.generation, succeeded: true).next)

        let toSepia = try XCTUnwrap(state.request(sepia))
        XCTAssertNil(state.request(github))
        XCTAssertEqual(state.desiredPalette.id, .githubLight)
        XCTAssertEqual(state.inFlightPaletteID, .sepia)

        let reversal = try XCTUnwrap(
            state.complete(generation: toSepia.generation, succeeded: true).next
        )
        XCTAssertEqual(reversal.palette.id, .githubLight)
        XCTAssertNil(state.complete(generation: reversal.generation, succeeded: true).next)
        XCTAssertEqual(state.successfullyAppliedPaletteID, .githubLight)
        XCTAssertEqual(state.desiredPalette.id, .githubLight)
    }

    func testFailureRetriesDesiredPaletteAndOnlyMarksSuccessfulApply() throws {
        let nord = palette(.nord, category: .dark)
        let state = WebThemeApplicationState(desiredPalette: nord)

        let first = try XCTUnwrap(state.pageDidBecomeReady())
        let retry = try XCTUnwrap(
            state.complete(generation: first.generation, succeeded: false).next
        )

        XCTAssertNil(state.successfullyAppliedPaletteID)
        XCTAssertEqual(retry.palette.id, .nord)
        XCTAssertNil(state.complete(generation: retry.generation, succeeded: true).next)
        XCTAssertEqual(state.successfullyAppliedPaletteID, .nord)
    }

    func testLaterCoordinatorUpdateRetriesAfterTwoFailures() throws {
        let dracula = palette(.dracula, category: .dark)
        let state = WebThemeApplicationState(desiredPalette: dracula)

        let first = try XCTUnwrap(state.pageDidBecomeReady())
        let automaticRetry = try XCTUnwrap(
            state.complete(generation: first.generation, succeeded: false).next
        )
        XCTAssertNil(
            state.complete(
                generation: automaticRetry.generation,
                succeeded: false
            ).next
        )
        XCTAssertNil(state.successfullyAppliedPaletteID)

        let updateRetry = try XCTUnwrap(state.request(dracula))
        XCTAssertEqual(updateRetry.palette.id, .dracula)
    }

    private func palette(
        _ id: ThemeID,
        category: ThemeCategory
    ) -> ThemePalette {
        ThemeRegistry.palette(id: id.rawValue, category: category)
    }
}
