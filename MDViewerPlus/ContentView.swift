import SwiftUI

enum ViewMode {
    case view, split, edit

    var next: ViewMode {
        switch self {
        case .view: return .split
        case .split: return .edit
        case .edit: return .view
        }
    }
}

enum ActivePane {
    case editor, preview
}

enum ScrollSource {
    case editor, preview
}

private enum ZoomAction {
    case zoomIn
    case zoomOut
    case zoomReset
}

enum ReloadDecision: Equatable {
    case unchanged
    case apply(String)
    case confirm(String)
}

struct ReloadPolicy {
    static func decide(
        currentText: String,
        diskText: String,
        hasUnsavedChanges: Bool
    ) -> ReloadDecision {
        guard currentText != diskText else { return .unchanged }
        return hasUnsavedChanges ? .confirm(diskText) : .apply(diskText)
    }
}

private enum DocumentAlert: Identifiable {
    case confirmReload(String)
    case error(title: String, message: String)

    var id: Int {
        switch self {
        case .confirmReload: return 0
        case .error: return 1
        }
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14.0
    @State private var viewMode: ViewMode = .view
    @State private var activePane: ActivePane = .preview
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollSource: ScrollSource = .editor
    @State private var editorCommandRequest: EditorCommandRequest?
    @State private var documentAlert: DocumentAlert?
    @State private var folderAccess: FolderAccessLease?
    @State private var relativeResourcesRequested = false
    @State private var resourceAccessDeclined = false
    @State private var isRequestingResourceAccess = false
    @State private var resourceAccessGeneration = 0
    @State private var pendingRelativeLink: URL?
    @StateObject private var windowState = DocumentWindowState()
    @StateObject private var printController = MarkdownPrintController()

    var body: some View {
        Group {
            switch viewMode {
            case .view:
                MarkdownWebView(
                    text: document.text,
                    fileURL: fileURL,
                    appearanceMode: appearanceMode,
                    zoomLevel: zoomLevel,
                    resourceRoot: folderAccess?.rootURL,
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    onFocus: { activePane = .preview },
                    onError: showRenderError,
                    onRelativeResources: handleRelativeResources,
                    onOpenRelativeLink: openRelativeLink
                )
            case .split:
                HSplitView {
                    MarkdownEditorView(
                        text: $document.text,
                        appearanceMode: appearanceMode,
                        fontSize: CGFloat(editorFontSize),
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        commandRequest: editorCommandRequest,
                        onFocus: { activePane = .editor }
                    )
                    .frame(minWidth: 200)
                    MarkdownWebView(
                        text: document.text,
                        fileURL: fileURL,
                        appearanceMode: appearanceMode,
                        zoomLevel: zoomLevel,
                        resourceRoot: folderAccess?.rootURL,
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        onFocus: { activePane = .preview },
                        onError: showRenderError,
                        onRelativeResources: handleRelativeResources,
                        onOpenRelativeLink: openRelativeLink
                    )
                    .frame(minWidth: 200)
                }
            case .edit:
                MarkdownEditorView(
                    text: $document.text,
                    appearanceMode: appearanceMode,
                    fontSize: CGFloat(editorFontSize),
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    commandRequest: editorCommandRequest,
                    onFocus: { activePane = .editor }
                )
            }
        }
        .background(DocumentWindowAccessor(state: windowState))
        .overlay(alignment: .topTrailing) {
            resourceAccessNotice
        }
        .focusedSceneValue(\.documentCommandActions, commandActions)
        .task(id: fileURL) {
            resetFolderAccess()
        }
        .alert(item: $documentAlert) { alert in
            switch alert {
            case .confirmReload(let diskText):
                return Alert(
                    title: Text("Reload Document?"),
                    message: Text("Reloading will discard unsaved changes in this document."),
                    primaryButton: .destructive(Text("Reload")) {
                        document.text = diskText
                    },
                    secondaryButton: .cancel()
                )
            case .error(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var commandActions: DocumentCommandActions {
        DocumentCommandActions(
            canReload: fileURL != nil,
            canFormat: canFormat,
            reload: reload,
            toggleEditMode: toggleEditMode,
            zoomIn: { handleZoom(.zoomIn) },
            zoomOut: { handleZoom(.zoomOut) },
            zoomReset: { handleZoom(.zoomReset) },
            printDocument: printCurrentDocument,
            format: requestFormat
        )
    }

    private var canFormat: Bool {
        switch viewMode {
        case .view:
            return false
        case .edit:
            return true
        case .split:
            return activePane == .editor
        }
    }

    @ViewBuilder
    private var resourceAccessNotice: some View {
        if relativeResourcesRequested, folderAccess == nil {
            HStack(spacing: 8) {
                Text(
                    fileURL == nil
                        ? "Save this document to load relative resources."
                        : "Folder access is required for relative resources."
                )
                .font(.caption)

                if fileURL != nil {
                    Button(resourceAccessDeclined ? "Grant Access" : "Choose Folder") {
                        resourceAccessDeclined = false
                        requestFolderAccess()
                    }
                    .disabled(isRequestingResourceAccess)
                }
            }
            .padding(8)
            .background(.regularMaterial)
            .cornerRadius(6)
            .padding(8)
        }
    }

    private var zoomTarget: ActivePane {
        switch viewMode {
        case .view: return .preview
        case .edit: return .editor
        case .split: return activePane
        }
    }

    private func handleZoom(_ action: ZoomAction) {
        switch zoomTarget {
        case .preview:
            switch action {
            case .zoomIn: zoomLevel = min(zoomLevel + 0.1, 3.0)
            case .zoomOut: zoomLevel = max(zoomLevel - 0.1, 0.5)
            case .zoomReset: zoomLevel = 1.0
            }
        case .editor:
            switch action {
            case .zoomIn: editorFontSize = min(editorFontSize + 1, 72)
            case .zoomOut: editorFontSize = max(editorFontSize - 1, 8)
            case .zoomReset: editorFontSize = 14.0
            }
        }
    }

    private func toggleEditMode() {
        viewMode = viewMode.next
        switch viewMode {
        case .view: activePane = .preview
        case .edit: activePane = .editor
        case .split: break
        }
    }

    private func requestFormat(_ command: MarkdownFormatCommand) {
        guard canFormat else { return }
        editorCommandRequest = EditorCommandRequest(command: command)
    }

    private func reload() {
        guard let url = fileURL else { return }

        do {
            let diskText = try String(contentsOf: url, encoding: .utf8)
            switch ReloadPolicy.decide(
                currentText: document.text,
                diskText: diskText,
                hasUnsavedChanges: windowState.window?.isDocumentEdited == true
            ) {
            case .unchanged:
                break
            case .apply(let text):
                document.text = text
            case .confirm(let text):
                documentAlert = .confirmReload(text)
            }
        } catch {
            documentAlert = .error(
                title: "Couldn’t Reload Document",
                message: error.localizedDescription
            )
        }
    }

    private func showRenderError(_ message: String) {
        documentAlert = .error(
            title: "Couldn’t Render Document",
            message: message
        )
    }

    private func printCurrentDocument() {
        printController.print(
            markdown: document.text,
            resourceRoot: folderAccess?.rootURL
        ) { message in
            documentAlert = .error(
                title: "Couldn’t Print Document",
                message: message
            )
        }
    }

    private func handleRelativeResources(_ resources: [String]) {
        guard !resources.isEmpty else { return }
        relativeResourcesRequested = true

        guard folderAccess == nil,
              fileURL != nil,
              !resourceAccessDeclined else { return }
        requestFolderAccess()
    }

    private func restoreFolderAccess() {
        guard let fileURL else { return }

        do {
            folderAccess = try FolderAccessStore.shared.restoredAccess(for: fileURL)
        } catch {
            showResourceError(error)
        }
    }

    private func resetFolderAccess() {
        resourceAccessGeneration += 1
        folderAccess = nil
        relativeResourcesRequested = false
        resourceAccessDeclined = false
        isRequestingResourceAccess = false
        pendingRelativeLink = nil
        restoreFolderAccess()
    }

    private func requestFolderAccess() {
        guard !isRequestingResourceAccess, let fileURL else { return }
        isRequestingResourceAccess = true
        let generation = resourceAccessGeneration

        Task { @MainActor in
            do {
                let access = try await FolderAccessStore.shared.requestAccess(
                    for: fileURL,
                    attachedTo: windowState.window
                )
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                folderAccess = access
                resourceAccessDeclined = access == nil
                if let rootURL = access?.rootURL {
                    openPendingRelativeLink(under: rootURL)
                }
            } catch {
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                resourceAccessDeclined = true
                showResourceError(error)
            }
            if generation == resourceAccessGeneration {
                isRequestingResourceAccess = false
            }
        }
    }

    private func openRelativeLink(_ url: URL) {
        relativeResourcesRequested = true
        pendingRelativeLink = url

        if let rootURL = folderAccess?.rootURL {
            openPendingRelativeLink(under: rootURL)
        } else if fileURL != nil, !resourceAccessDeclined {
            requestFolderAccess()
        }
    }

    private func openPendingRelativeLink(under rootURL: URL) {
        guard let pendingRelativeLink else { return }

        do {
            let fileURL = try MarkdownResourceResolver.resolve(
                pendingRelativeLink,
                under: rootURL
            )
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            guard NSWorkspace.shared.open(fileURL) else {
                throw CocoaError(.fileReadUnknown)
            }
            self.pendingRelativeLink = nil
        } catch {
            showResourceError(error)
        }
    }

    private func showResourceError(_ error: Error) {
        documentAlert = .error(
            title: "Couldn’t Access Relative Resource",
            message: error.localizedDescription
        )
    }
}

private final class DocumentWindowState: ObservableObject {
    weak var window: NSWindow?
}

private struct DocumentWindowAccessor: NSViewRepresentable {
    let state: DocumentWindowState

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.state = state
        state.window = nsView.window
    }

    final class WindowReaderView: NSView {
        weak var state: DocumentWindowState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            state?.window = window
        }
    }
}
