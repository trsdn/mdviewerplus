import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeCategory: String, CaseIterable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var appearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}

enum ThemeID: String, CaseIterable, Identifiable {
    case githubLight = "github-light"
    case solarizedLight = "solarized-light"
    case sepia
    case githubDark = "github-dark"
    case solarizedDark = "solarized-dark"
    case dracula
    case monokai
    case nord

    var id: String { rawValue }
}

struct ThemeColor: Equatable, Hashable {
    let hex: String

    init(_ hex: String) {
        precondition(
            hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
            "Theme colors must be six-digit hexadecimal values"
        )
        self.hex = hex.lowercased()
    }

    var nsColor: NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

struct ThemeColors: Equatable {
    let background: ThemeColor
    let foreground: ThemeColor
    let border: ThemeColor
    let codeBackground: ThemeColor
    let codeForeground: ThemeColor
    let link: ThemeColor
    let blockquoteForeground: ThemeColor
    let blockquoteBorder: ThemeColor
    let horizontalRule: ThemeColor
    let selectionBackground: ThemeColor
    let selectionForeground: ThemeColor
    let caret: ThemeColor
    let activeLine: ThemeColor
    let gutterBackground: ThemeColor
    let gutterForeground: ThemeColor
    let splitter: ThemeColor
    let splitterHover: ThemeColor
    let searchMatch: ThemeColor
    let searchMatchSelected: ThemeColor

    var webValues: [String: String] {
        [
            "background": background.hex,
            "foreground": foreground.hex,
            "border": border.hex,
            "codeBackground": codeBackground.hex,
            "codeForeground": codeForeground.hex,
            "link": link.hex,
            "blockquoteForeground": blockquoteForeground.hex,
            "blockquoteBorder": blockquoteBorder.hex,
            "horizontalRule": horizontalRule.hex,
            "selectionBackground": selectionBackground.hex,
            "selectionForeground": selectionForeground.hex,
            "caret": caret.hex,
            "activeLine": activeLine.hex,
            "gutterBackground": gutterBackground.hex,
            "gutterForeground": gutterForeground.hex,
            "splitter": splitter.hex,
            "splitterHover": splitterHover.hex,
            "searchMatch": searchMatch.hex,
            "searchMatchSelected": searchMatchSelected.hex,
        ]
    }
}

struct MarkdownSyntaxPalette: Equatable {
    let text: ThemeColor
    let accent: ThemeColor
    let code: ThemeColor
    let codeBackground: ThemeColor
    let muted: ThemeColor
}

struct ThemePalette: Identifiable, Equatable {
    let id: ThemeID
    let name: String
    let category: ThemeCategory
    let colors: ThemeColors

    var syntax: MarkdownSyntaxPalette {
        MarkdownSyntaxPalette(
            text: colors.foreground,
            accent: colors.link,
            code: colors.codeForeground,
            codeBackground: colors.codeBackground,
            muted: colors.blockquoteForeground
        )
    }

    var webTheme: [String: Any] {
        var values: [String: Any] = colors.webValues
        values["category"] = category.rawValue
        return values
    }
}

enum ThemeRegistry {
    static let defaultLightThemeID = ThemeID.githubLight
    static let defaultDarkThemeID = ThemeID.githubDark

    static let palettes: [ThemePalette] = [
        ThemePalette(
            id: .githubLight,
            name: "GitHub Light",
            category: .light,
            colors: ThemeColors(
                background: ThemeColor("#ffffff"),
                foreground: ThemeColor("#24292f"),
                border: ThemeColor("#d0d7de"),
                codeBackground: ThemeColor("#f6f8fa"),
                codeForeground: ThemeColor("#24292f"),
                link: ThemeColor("#0969da"),
                blockquoteForeground: ThemeColor("#656d76"),
                blockquoteBorder: ThemeColor("#d0d7de"),
                horizontalRule: ThemeColor("#d8dee4"),
                selectionBackground: ThemeColor("#b6d7ff"),
                selectionForeground: ThemeColor("#24292f"),
                caret: ThemeColor("#24292f"),
                activeLine: ThemeColor("#f6f8fa"),
                gutterBackground: ThemeColor("#ffffff"),
                gutterForeground: ThemeColor("#656d76"),
                splitter: ThemeColor("#d0d7de"),
                splitterHover: ThemeColor("#0969da"),
                searchMatch: ThemeColor("#fff8c5"),
                searchMatchSelected: ThemeColor("#b6d7ff")
            )
        ),
        ThemePalette(
            id: .solarizedLight,
            name: "Solarized Light",
            category: .light,
            colors: ThemeColors(
                background: ThemeColor("#fdf6e3"),
                foreground: ThemeColor("#586e75"),
                border: ThemeColor("#93a1a1"),
                codeBackground: ThemeColor("#eee8d5"),
                codeForeground: ThemeColor("#566c73"),
                link: ThemeColor("#006da8"),
                blockquoteForeground: ThemeColor("#586e75"),
                blockquoteBorder: ThemeColor("#93a1a1"),
                horizontalRule: ThemeColor("#93a1a1"),
                selectionBackground: ThemeColor("#d9e2cc"),
                selectionForeground: ThemeColor("#3f555d"),
                caret: ThemeColor("#586e75"),
                activeLine: ThemeColor("#eee8d5"),
                gutterBackground: ThemeColor("#fdf6e3"),
                gutterForeground: ThemeColor("#586e75"),
                splitter: ThemeColor("#93a1a1"),
                splitterHover: ThemeColor("#006da8"),
                searchMatch: ThemeColor("#e8d7a4"),
                searchMatchSelected: ThemeColor("#b8d7e8")
            )
        ),
        ThemePalette(
            id: .sepia,
            name: "Sepia",
            category: .light,
            colors: ThemeColors(
                background: ThemeColor("#f4ecd8"),
                foreground: ThemeColor("#3e3629"),
                border: ThemeColor("#d4c4a8"),
                codeBackground: ThemeColor("#e8dcc0"),
                codeForeground: ThemeColor("#3e3629"),
                link: ThemeColor("#765200"),
                blockquoteForeground: ThemeColor("#6b5d4f"),
                blockquoteBorder: ThemeColor("#d4c4a8"),
                horizontalRule: ThemeColor("#cbbfa3"),
                selectionBackground: ThemeColor("#d9c59e"),
                selectionForeground: ThemeColor("#2f281e"),
                caret: ThemeColor("#3e3629"),
                activeLine: ThemeColor("#eee3c9"),
                gutterBackground: ThemeColor("#f4ecd8"),
                gutterForeground: ThemeColor("#6b5d4f"),
                splitter: ThemeColor("#d4c4a8"),
                splitterHover: ThemeColor("#765200"),
                searchMatch: ThemeColor("#ead38f"),
                searchMatchSelected: ThemeColor("#d9c59e")
            )
        ),
        ThemePalette(
            id: .githubDark,
            name: "GitHub Dark",
            category: .dark,
            colors: ThemeColors(
                background: ThemeColor("#0d1117"),
                foreground: ThemeColor("#e6edf3"),
                border: ThemeColor("#30363d"),
                codeBackground: ThemeColor("#161b22"),
                codeForeground: ThemeColor("#e6edf3"),
                link: ThemeColor("#58a6ff"),
                blockquoteForeground: ThemeColor("#8b949e"),
                blockquoteBorder: ThemeColor("#30363d"),
                horizontalRule: ThemeColor("#21262d"),
                selectionBackground: ThemeColor("#264f78"),
                selectionForeground: ThemeColor("#ffffff"),
                caret: ThemeColor("#e6edf3"),
                activeLine: ThemeColor("#161b22"),
                gutterBackground: ThemeColor("#0d1117"),
                gutterForeground: ThemeColor("#8b949e"),
                splitter: ThemeColor("#30363d"),
                splitterHover: ThemeColor("#58a6ff"),
                searchMatch: ThemeColor("#4d3e00"),
                searchMatchSelected: ThemeColor("#264f78")
            )
        ),
        ThemePalette(
            id: .solarizedDark,
            name: "Solarized Dark",
            category: .dark,
            colors: ThemeColors(
                background: ThemeColor("#002b36"),
                foreground: ThemeColor("#839496"),
                border: ThemeColor("#073642"),
                codeBackground: ThemeColor("#073642"),
                codeForeground: ThemeColor("#93a1a1"),
                link: ThemeColor("#3aaed8"),
                blockquoteForeground: ThemeColor("#839496"),
                blockquoteBorder: ThemeColor("#073642"),
                horizontalRule: ThemeColor("#073642"),
                selectionBackground: ThemeColor("#075b70"),
                selectionForeground: ThemeColor("#eee8d5"),
                caret: ThemeColor("#93a1a1"),
                activeLine: ThemeColor("#073642"),
                gutterBackground: ThemeColor("#002b36"),
                gutterForeground: ThemeColor("#839496"),
                splitter: ThemeColor("#073642"),
                splitterHover: ThemeColor("#3aaed8"),
                searchMatch: ThemeColor("#5b4b00"),
                searchMatchSelected: ThemeColor("#075b70")
            )
        ),
        ThemePalette(
            id: .dracula,
            name: "Dracula",
            category: .dark,
            colors: ThemeColors(
                background: ThemeColor("#282a36"),
                foreground: ThemeColor("#f8f8f2"),
                border: ThemeColor("#44475a"),
                codeBackground: ThemeColor("#44475a"),
                codeForeground: ThemeColor("#f8f8f2"),
                link: ThemeColor("#bd93f9"),
                blockquoteForeground: ThemeColor("#a8adc0"),
                blockquoteBorder: ThemeColor("#44475a"),
                horizontalRule: ThemeColor("#44475a"),
                selectionBackground: ThemeColor("#44475a"),
                selectionForeground: ThemeColor("#f8f8f2"),
                caret: ThemeColor("#f8f8f2"),
                activeLine: ThemeColor("#343746"),
                gutterBackground: ThemeColor("#282a36"),
                gutterForeground: ThemeColor("#a8adc0"),
                splitter: ThemeColor("#44475a"),
                splitterHover: ThemeColor("#ff79c6"),
                searchMatch: ThemeColor("#6d5a00"),
                searchMatchSelected: ThemeColor("#44475a")
            )
        ),
        ThemePalette(
            id: .monokai,
            name: "Monokai",
            category: .dark,
            colors: ThemeColors(
                background: ThemeColor("#272822"),
                foreground: ThemeColor("#f8f8f2"),
                border: ThemeColor("#49483e"),
                codeBackground: ThemeColor("#3e3d32"),
                codeForeground: ThemeColor("#f8f8f2"),
                link: ThemeColor("#66d9ef"),
                blockquoteForeground: ThemeColor("#a8a590"),
                blockquoteBorder: ThemeColor("#49483e"),
                horizontalRule: ThemeColor("#49483e"),
                selectionBackground: ThemeColor("#49483e"),
                selectionForeground: ThemeColor("#f8f8f2"),
                caret: ThemeColor("#f8f8f2"),
                activeLine: ThemeColor("#3e3d32"),
                gutterBackground: ThemeColor("#272822"),
                gutterForeground: ThemeColor("#a8a590"),
                splitter: ThemeColor("#49483e"),
                splitterHover: ThemeColor("#a6e22e"),
                searchMatch: ThemeColor("#756e00"),
                searchMatchSelected: ThemeColor("#49483e")
            )
        ),
        ThemePalette(
            id: .nord,
            name: "Nord",
            category: .dark,
            colors: ThemeColors(
                background: ThemeColor("#2e3440"),
                foreground: ThemeColor("#eceff4"),
                border: ThemeColor("#4c566a"),
                codeBackground: ThemeColor("#3b4252"),
                codeForeground: ThemeColor("#e5e9f0"),
                link: ThemeColor("#88c0d0"),
                blockquoteForeground: ThemeColor("#d8dee9"),
                blockquoteBorder: ThemeColor("#4c566a"),
                horizontalRule: ThemeColor("#4c566a"),
                selectionBackground: ThemeColor("#434c5e"),
                selectionForeground: ThemeColor("#eceff4"),
                caret: ThemeColor("#eceff4"),
                activeLine: ThemeColor("#3b4252"),
                gutterBackground: ThemeColor("#2e3440"),
                gutterForeground: ThemeColor("#81a1c1"),
                splitter: ThemeColor("#4c566a"),
                splitterHover: ThemeColor("#88c0d0"),
                searchMatch: ThemeColor("#5e5a2f"),
                searchMatchSelected: ThemeColor("#434c5e")
            )
        ),
    ]

    static let lightPalettes = palettes.filter { $0.category == .light }
    static let darkPalettes = palettes.filter { $0.category == .dark }

    static func palette(id: String, category: ThemeCategory) -> ThemePalette {
        if let palette = palettes.first(
            where: { $0.id.rawValue == id && $0.category == category }
        ) {
            return palette
        }

        let fallback = category == .light ? defaultLightThemeID : defaultDarkThemeID
        return palettes.first { $0.id == fallback }!
    }

    static func resolve(
        appearanceMode: AppearanceMode,
        lightThemeID: String,
        darkThemeID: String,
        systemColorScheme: ColorScheme
    ) -> ThemePalette {
        let category: ThemeCategory
        switch appearanceMode {
        case .system:
            category = ThemeCategory(colorScheme: systemColorScheme)
        case .light:
            category = .light
        case .dark:
            category = .dark
        }

        return palette(
            id: category == .light ? lightThemeID : darkThemeID,
            category: category
        )
    }
}
