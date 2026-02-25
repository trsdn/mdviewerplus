import SwiftUI

extension Notification.Name {
    static let reloadDocument = Notification.Name("reloadDocument")
    static let toggleEditMode = Notification.Name("toggleEditMode")
    static let formatBold = Notification.Name("formatBold")
    static let formatItalic = Notification.Name("formatItalic")
    static let formatLink = Notification.Name("formatLink")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let printDocument = Notification.Name("printDocument")
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
struct MDViewerPlusApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(
                document: file.$document,
                fileURL: file.fileURL,
                appearanceMode: AppearanceMode(rawValue: appearanceMode) ?? .system
            )
        }
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadDocument, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
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

            CommandGroup(after: .textEditing) {
                Button("Toggle Edit Mode") {
                    NotificationCenter.default.post(name: .toggleEditMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandMenu("Format") {
                Button("Bold") {
                    NotificationCenter.default.post(name: .formatBold, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NotificationCenter.default.post(name: .formatItalic, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Link") {
                    NotificationCenter.default.post(name: .formatLink, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
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
