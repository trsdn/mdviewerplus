import SwiftUI

extension Notification.Name {
    static let reloadDocument = Notification.Name("reloadDocument")
}

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@main
struct MDViewerApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(
                document: file.document,
                fileURL: file.fileURL,
                appearanceMode: AppearanceMode(rawValue: appearanceMode) ?? .system,
                zoomLevel: zoomLevel
            )
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadDocument, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    zoomLevel = min(zoomLevel + 0.1, 3.0)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    zoomLevel = max(zoomLevel - 0.1, 0.5)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    zoomLevel = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)

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
    }

    private func shortcut(for mode: AppearanceMode) -> KeyboardShortcut {
        switch mode {
        case .system: return KeyboardShortcut("0", modifiers: [.command, .shift])
        case .light: return KeyboardShortcut("1", modifiers: [.command, .shift])
        case .dark: return KeyboardShortcut("2", modifiers: [.command, .shift])
        }
    }
}
