import SwiftUI

enum MarkdownFormatCommand: Equatable {
    case bold
    case italic
    case link
}

enum FindCommand: Equatable {
    case show
    case next
    case previous
    case dismiss
}

struct FindCommandRequest: Equatable {
    let id = UUID()
    let command: FindCommand
}

struct PreviewFindRequest: Equatable {
    let id = UUID()
    let query: String
    let backwards: Bool
    let clear: Bool

    init(query: String, backwards: Bool = false, clear: Bool = false) {
        self.query = query
        self.backwards = backwards
        self.clear = clear
    }
}

struct PreviewOutlineRequest: Equatable {
    let id = UUID()
    let slug: String
}

struct EditorOutlineRequest: Equatable {
    let id = UUID()
    let location: Int
}

struct EditorCommandRequest: Equatable {
    let id = UUID()
    let command: MarkdownFormatCommand
}

struct DocumentCommandActions {
    let canReload: Bool
    let canFormat: Bool
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let canPrepareNavigation: Bool
    let canQuickOpen: Bool
    let canShowOutline: Bool
    let canDismissFind: Bool
    let canToggleFolderNavigator: Bool
    let canChooseFolderNavigatorRoot: Bool
    let canRevealInFolderNavigator: Bool
    let canSave: Bool
    let canCloseTab: Bool
    let navigationPreparationTitle: String
    let reload: () -> Void
    let navigatePrevious: () -> Void
    let navigateNext: () -> Void
    let prepareNavigation: () -> Void
    let toggleEditMode: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let zoomReset: () -> Void
    let printDocument: () -> Void
    let find: (FindCommand) -> Void
    let quickOpen: () -> Void
    let showOutline: () -> Void
    let toggleFolderNavigator: () -> Void
    let chooseFolderNavigatorRoot: () -> Void
    let revealInFolderNavigator: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Void
    let openFile: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let format: (MarkdownFormatCommand) -> Void
}

private struct DocumentCommandActionsKey: FocusedValueKey {
    typealias Value = DocumentCommandActions
}

extension FocusedValues {
    var documentCommandActions: DocumentCommandActions? {
        get { self[DocumentCommandActionsKey.self] }
        set { self[DocumentCommandActionsKey.self] = newValue }
    }
}

struct DocumentCommands: Commands {
    @FocusedValue(\.documentCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                actions?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                actions?.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions == nil)

            Button("Save As…") {
                actions?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandGroup(after: .newItem) {
            Button("New Tab") {
                actions?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions == nil)

            Button("Open…") {
                actions?.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions == nil)

            Button("Close Tab") {
                actions?.closeTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(actions?.canCloseTab != true)

            Divider()

            Button("Open Folder…") {
                actions?.chooseFolderNavigatorRoot()
            }
            .disabled(actions?.canChooseFolderNavigatorRoot != true)

            Divider()

            Button(
                actions?.navigationPreparationTitle
                    ?? "Enable Sibling Navigation…"
            ) {
                actions?.prepareNavigation()
            }
            .disabled(actions?.canPrepareNavigation != true)

            Button("Previous Markdown File") {
                actions?.navigatePrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(actions?.canNavigatePrevious != true)

            Button("Next Markdown File") {
                actions?.navigateNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(actions?.canNavigateNext != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Folder Navigator") {
                actions?.toggleFolderNavigator()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(actions?.canToggleFolderNavigator != true)

            Divider()

            Button("Reload") {
                actions?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions?.canReload != true)

            Divider()

            Button("Zoom In") {
                actions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(actions == nil)

            Button("Zoom Out") {
                actions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(actions == nil)

            Button("Actual Size") {
                actions?.zoomReset()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                actions?.find(.show)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)

            Button("Find Next") {
                actions?.find(.next)
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(actions == nil)

            Button("Find Previous") {
                actions?.find(.previous)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("Dismiss Find") {
                actions?.find(.dismiss)
            }
            .keyboardShortcut(.cancelAction)
            .disabled(actions?.canDismissFind != true)

            Divider()

            Button("Toggle Edit Mode") {
                actions?.toggleEditMode()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandMenu("Navigate") {
            Button("Reveal Current Document in Folder Navigator") {
                actions?.revealInFolderNavigator()
            }
            .disabled(actions?.canRevealInFolderNavigator != true)

            Divider()

            Button("Quick Open…") {
                actions?.quickOpen()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(actions?.canQuickOpen != true)

            Button("Document Outline…") {
                actions?.showOutline()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions?.canShowOutline != true)
        }

        CommandMenu("Format") {
            Button("Bold") {
                actions?.format(.bold)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(actions?.canFormat != true)

            Button("Italic") {
                actions?.format(.italic)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(actions?.canFormat != true)

            Button("Link") {
                actions?.format(.link)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(actions?.canFormat != true)
        }
    }
}
