import AppKit
import SwiftUI

final class MDViewerPlusAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            WorkspaceRegistry.shared.open(urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        !flag
    }
}

@main
struct MDViewerPlusApp: App {
    @NSApplicationDelegateAdaptor(MDViewerPlusAppDelegate.self)
    private var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("lightThemeID") private var lightThemeID: String =
        ThemeRegistry.defaultLightThemeID.rawValue
    @AppStorage("darkThemeID") private var darkThemeID: String =
        ThemeRegistry.defaultDarkThemeID.rawValue

    var body: some Scene {
        WindowGroup {
            WorkspaceView(
                appearanceMode: AppearanceMode(rawValue: appearanceMode) ?? .system,
                lightThemeID: lightThemeID,
                darkThemeID: darkThemeID
            )
            .frame(minWidth: 640, minHeight: 420)
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
        .windowResizability(.contentSize)

        Window("About MDViewer+", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Help", id: "help") {
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
