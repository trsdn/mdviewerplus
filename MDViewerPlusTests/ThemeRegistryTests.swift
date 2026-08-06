import SwiftUI
import XCTest
@testable import MDViewerPlus

final class ThemeRegistryTests: XCTestCase {
    private let tokenNames = [
        "background", "foreground", "border", "codeBackground",
        "codeForeground", "link", "blockquoteForeground",
        "blockquoteBorder", "horizontalRule", "selectionBackground",
        "selectionForeground", "caret", "activeLine", "gutterBackground",
        "gutterForeground", "splitter", "splitterHover", "searchMatch",
        "searchMatchSelected",
    ]

    func testRegistryExactlyMatchesTrustedPaletteContract() {
        let expected: [(ThemeID, String, ThemeCategory, [String])] = [
            (.githubLight, "GitHub Light", .light, ["#ffffff", "#24292f", "#d0d7de", "#f6f8fa", "#24292f", "#0969da", "#656d76", "#d0d7de", "#d8dee4", "#b6d7ff", "#24292f", "#24292f", "#f6f8fa", "#ffffff", "#656d76", "#d0d7de", "#0969da", "#fff8c5", "#b6d7ff"]),
            (.solarizedLight, "Solarized Light", .light, ["#fdf6e3", "#586e75", "#93a1a1", "#eee8d5", "#566c73", "#006da8", "#586e75", "#93a1a1", "#93a1a1", "#d9e2cc", "#3f555d", "#586e75", "#eee8d5", "#fdf6e3", "#586e75", "#93a1a1", "#006da8", "#e8d7a4", "#b8d7e8"]),
            (.sepia, "Sepia", .light, ["#f4ecd8", "#3e3629", "#d4c4a8", "#e8dcc0", "#3e3629", "#765200", "#6b5d4f", "#d4c4a8", "#cbbfa3", "#d9c59e", "#2f281e", "#3e3629", "#eee3c9", "#f4ecd8", "#6b5d4f", "#d4c4a8", "#765200", "#ead38f", "#d9c59e"]),
            (.githubDark, "GitHub Dark", .dark, ["#0d1117", "#e6edf3", "#30363d", "#161b22", "#e6edf3", "#58a6ff", "#8b949e", "#30363d", "#21262d", "#264f78", "#ffffff", "#e6edf3", "#161b22", "#0d1117", "#8b949e", "#30363d", "#58a6ff", "#4d3e00", "#264f78"]),
            (.solarizedDark, "Solarized Dark", .dark, ["#002b36", "#839496", "#073642", "#073642", "#93a1a1", "#3aaed8", "#839496", "#073642", "#073642", "#075b70", "#eee8d5", "#93a1a1", "#073642", "#002b36", "#839496", "#073642", "#3aaed8", "#5b4b00", "#075b70"]),
            (.dracula, "Dracula", .dark, ["#282a36", "#f8f8f2", "#44475a", "#44475a", "#f8f8f2", "#bd93f9", "#a8adc0", "#44475a", "#44475a", "#44475a", "#f8f8f2", "#f8f8f2", "#343746", "#282a36", "#a8adc0", "#44475a", "#ff79c6", "#6d5a00", "#44475a"]),
            (.monokai, "Monokai", .dark, ["#272822", "#f8f8f2", "#49483e", "#3e3d32", "#f8f8f2", "#66d9ef", "#a8a590", "#49483e", "#49483e", "#49483e", "#f8f8f2", "#f8f8f2", "#3e3d32", "#272822", "#a8a590", "#49483e", "#a6e22e", "#756e00", "#49483e"]),
            (.nord, "Nord", .dark, ["#2e3440", "#eceff4", "#4c566a", "#3b4252", "#e5e9f0", "#88c0d0", "#d8dee9", "#4c566a", "#4c566a", "#434c5e", "#eceff4", "#eceff4", "#3b4252", "#2e3440", "#81a1c1", "#4c566a", "#88c0d0", "#5e5a2f", "#434c5e"]),
        ]

        XCTAssertEqual(ThemeRegistry.palettes.count, expected.count)
        for (palette, row) in zip(ThemeRegistry.palettes, expected) {
            XCTAssertEqual(palette.id, row.0)
            XCTAssertEqual(palette.name, row.1)
            XCTAssertEqual(palette.category, row.2)
            XCTAssertEqual(
                palette.colors.webValues,
                Dictionary(uniqueKeysWithValues: zip(tokenNames, row.3))
            )
        }
    }

    func testCategoryFilteringAndDefaults() {
        XCTAssertEqual(
            ThemeRegistry.lightPalettes.map(\.id),
            [.githubLight, .solarizedLight, .sepia]
        )
        XCTAssertEqual(
            ThemeRegistry.darkPalettes.map(\.id),
            [.githubDark, .solarizedDark, .dracula, .monokai, .nord]
        )
        XCTAssertEqual(ThemeRegistry.defaultLightThemeID, .githubLight)
        XCTAssertEqual(ThemeRegistry.defaultDarkThemeID, .githubDark)
        XCTAssertEqual(
            AppearanceMode.allCases.map(\.rawValue),
            ["system", "light", "dark"]
        )
    }

    func testResolutionUsesModeAndReactiveSystemColorScheme() {
        let light = ThemeRegistry.resolve(
            appearanceMode: .system,
            lightThemeID: ThemeID.sepia.rawValue,
            darkThemeID: ThemeID.nord.rawValue,
            systemColorScheme: .light
        )
        let dark = ThemeRegistry.resolve(
            appearanceMode: .system,
            lightThemeID: ThemeID.sepia.rawValue,
            darkThemeID: ThemeID.nord.rawValue,
            systemColorScheme: .dark
        )

        XCTAssertEqual(light.id, .sepia)
        XCTAssertEqual(dark.id, .nord)
        XCTAssertEqual(
            ThemeRegistry.resolve(
                appearanceMode: .light,
                lightThemeID: ThemeID.solarizedLight.rawValue,
                darkThemeID: ThemeID.dracula.rawValue,
                systemColorScheme: .dark
            ).id,
            .solarizedLight
        )
        XCTAssertEqual(
            ThemeRegistry.resolve(
                appearanceMode: .dark,
                lightThemeID: ThemeID.sepia.rawValue,
                darkThemeID: ThemeID.dracula.rawValue,
                systemColorScheme: .light
            ).id,
            .dracula
        )
    }

    func testInvalidObsoleteAndWrongCategoryIDsFallBackWithoutMutation() {
        let obsolete = "old-sepia-mode"
        XCTAssertEqual(
            ThemeRegistry.palette(id: obsolete, category: .light).id,
            .githubLight
        )
        XCTAssertEqual(
            ThemeRegistry.palette(id: ThemeID.sepia.rawValue, category: .dark).id,
            .githubDark
        )
        XCTAssertEqual(obsolete, "old-sepia-mode")
    }

    func testSyntaxPaletteMapsSemanticTokens() {
        let sepia = ThemeRegistry.palette(id: ThemeID.sepia.rawValue, category: .light)
        XCTAssertEqual(sepia.syntax.text, sepia.colors.foreground)
        XCTAssertEqual(sepia.syntax.accent, sepia.colors.link)
        XCTAssertEqual(sepia.syntax.code, sepia.colors.codeForeground)
        XCTAssertEqual(sepia.syntax.codeBackground, sepia.colors.codeBackground)
        XCTAssertEqual(sepia.syntax.muted, sepia.colors.blockquoteForeground)
    }

    func testTextColorPairsMeetWCAGAAContrast() {
        for palette in ThemeRegistry.palettes {
            let colors = palette.colors
            assertContrast(
                colors.foreground, against: colors.background,
                token: "foreground", palette: palette
            )
            assertContrast(
                colors.link, against: colors.background,
                token: "link", palette: palette
            )
            assertContrast(
                colors.blockquoteForeground, against: colors.background,
                token: "blockquote/muted", palette: palette
            )
            assertContrast(
                colors.codeForeground, against: colors.codeBackground,
                token: "code", palette: palette
            )
            assertContrast(
                colors.gutterForeground, against: colors.gutterBackground,
                token: "gutter", palette: palette
            )
            assertContrast(
                colors.selectionForeground, against: colors.selectionBackground,
                token: "selection", palette: palette
            )
            assertContrast(
                colors.selectionForeground, against: colors.searchMatch,
                token: "search match", palette: palette
            )
            assertContrast(
                colors.selectionForeground, against: colors.searchMatchSelected,
                token: "selected search match", palette: palette
            )
        }
    }

    private func assertContrast(
        _ foreground: ThemeColor,
        against background: ThemeColor,
        token: String,
        palette: ThemePalette,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio,
            4.5,
            "\(palette.id.rawValue) \(token) contrast was \(ratio):1",
            file: file,
            line: line
        )
    }

    private func contrastRatio(_ first: ThemeColor, _ second: ThemeColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: ThemeColor) -> Double {
        let hex = color.hex.dropFirst()
        let channels = stride(from: 0, to: 6, by: 2).map { offset -> Double in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return Double(UInt8(hex[start..<end], radix: 16) ?? 0) / 255
        }
        let linear = channels.map { channel in
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
