import SwiftUI

enum MarkdownFormatCommand: Equatable {
    case bold
    case italic
    case link
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

        CommandGroup(after: .newItem) {
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

        CommandGroup(after: .textEditing) {
            Button("Toggle Edit Mode") {
                actions?.toggleEditMode()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(actions == nil)
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
            .keyboardShortcut("k", modifiers: .command)
            .disabled(actions?.canFormat != true)
        }
    }
}
