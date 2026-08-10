import SwiftUI

@main
struct MDViewerPlusApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("lightThemeID") private var lightThemeID: String =
        ThemeRegistry.defaultLightThemeID.rawValue
    @AppStorage("darkThemeID") private var darkThemeID: String =
        ThemeRegistry.defaultDarkThemeID.rawValue

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(
                document: file.$document,
                fileURL: file.fileURL,
                appearanceMode: AppearanceMode(rawValue: appearanceMode) ?? .system,
                lightThemeID: lightThemeID,
                darkThemeID: darkThemeID
            )
        }
        .commands {
            DocumentCommands()
            SupportCommands()

            CommandGroup(after: .toolbar) {
                Divider()
                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            appearanceMode = mode.rawValue
                        } label: {
                            if appearanceMode == mode.rawValue {
                                Text("\(mode.label)")
                            } else {
                                Text(mode.label)
                            }
                        }
                        .keyboardShortcut(shortcut(for: mode))
                    }
                }
            }
        }

        Settings {
            ThemeSettingsView()
        }

        Window("About MDViewer+", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("MDViewer+ Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }

    private func shortcut(for mode: AppearanceMode) -> KeyboardShortcut {
        switch mode {
        case .system: return KeyboardShortcut("0", modifiers: [.command, .shift])
        case .light: return KeyboardShortcut("1", modifiers: [.command, .shift])
        case .dark: return KeyboardShortcut("2", modifiers: [.command, .shift])
        }
    }
}
