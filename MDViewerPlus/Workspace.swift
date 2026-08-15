import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A single document that is displayed in one tab of a window.
@MainActor
final class DocumentTab: ObservableObject, Identifiable {
    nonisolated let id = UUID()

    @Published var document: MarkdownDocument
    @Published private(set) var fileURL: URL?
    @Published private(set) var savedText: String

    init(text: String = "", fileURL: URL? = nil) {
        document = MarkdownDocument(text: text)
        self.fileURL = fileURL
        savedText = text
    }

    var isDirty: Bool {
        document.text != savedText
    }

    /// An untitled, unmodified tab can be reused instead of opening a new one.
    var isReusable: Bool {
        fileURL == nil && !isDirty
    }

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    func load(text: String, url: URL?) {
        document.text = text
        savedText = text
        fileURL = url
    }

    func markSaved(at url: URL) {
        fileURL = url
        savedText = document.text
    }
}

enum WorkspaceAlert: Identifiable {
    case error(title: String, message: String)

    var id: String {
        switch self {
        case .error(let title, let message):
            return title + message
        }
    }
}

enum WorkspaceTabClosePolicy {
    case close
    case keepOpen
}

/// Owns the tabs of a single window plus the shared folder navigator.
@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var tabs: [DocumentTab]
    @Published private(set) var selectedTabID: DocumentTab.ID
    @Published var alert: WorkspaceAlert?

    let folderNavigator = FolderNavigatorState()

    weak var window: NSWindow? {
        didSet { performPendingCloseIfNeeded() }
    }
    let createdAt = Date()
    private var isClosingWindow = false
    private var closeRequested = false

    /// A window that SwiftUI just spawned and that holds nothing worth keeping.
    var isEmptyDraft: Bool {
        tabs.count == 1 && tabs[0].isReusable
    }

    init() {
        let tab = DocumentTab()
        tabs = [tab]
        selectedTabID = tab.id
    }

    var selectedTab: DocumentTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    var hasUnsavedChanges: Bool {
        tabs.contains(where: \.isDirty)
    }

    // MARK: - Tab lifecycle

    func select(_ id: DocumentTab.ID) {
        guard selectedTabID != id, tabs.contains(where: { $0.id == id }) else {
            return
        }
        selectedTabID = id
        synchronizeFolderNavigator()
    }

    @discardableResult
    func newTab() -> DocumentTab {
        let tab = DocumentTab()
        tabs.append(tab)
        selectedTabID = tab.id
        synchronizeFolderNavigator()
        return tab
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func closeTab(_ id: DocumentTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        guard resolveUnsavedChanges(for: tab) == .close else { return }

        guard tabs.count > 1 else {
            closeWindowIgnoringUnsavedChanges()
            return
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        synchronizeFolderNavigator()
    }

    /// Closes this window as soon as its `NSWindow` is available. SwiftUI
    /// attaches the window one runloop turn after the scene is created.
    func requestClose() {
        closeRequested = true
        performPendingCloseIfNeeded()
    }

    func performPendingCloseIfNeeded() {
        guard closeRequested, isEmptyDraft, let window else { return }
        closeRequested = false
        isClosingWindow = true
        window.close()
    }

    /// Called from the window delegate before the window closes.
    func shouldCloseWindow() -> Bool {
        if isClosingWindow { return true }
        for tab in tabs where resolveUnsavedChanges(for: tab) != .close {
            return false
        }
        return true
    }

    private func closeWindowIgnoringUnsavedChanges() {
        isClosingWindow = true
        window?.close()
    }

    // MARK: - Opening

    func open(_ url: URL, disposition: DocumentOpenDisposition) throws {
        let canonical = FolderNavigatorPath.canonical(url)
        if let existing = tabs.first(where: {
            $0.fileURL.map(FolderNavigatorPath.canonical) == canonical
        }) {
            selectedTabID = existing.id
            synchronizeFolderNavigator()
            return
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let target: DocumentTab

        switch disposition {
        case .replaceCurrentTab:
            let current = selectedTab
            target = current.isDirty ? appendTab() : current
        case .newTab:
            target = selectedTab.isReusable ? selectedTab : appendTab()
        }

        target.load(text: text, url: url)
        selectedTabID = target.id
        objectWillChange.send()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        synchronizeFolderNavigator()
    }

    func openReportingErrors(
        _ url: URL,
        disposition: DocumentOpenDisposition
    ) {
        do {
            try open(url, disposition: disposition)
        } catch {
            alert = .error(
                title: "Couldn’t Open Markdown File",
                message: error.localizedDescription
            )
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdownText, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        for (index, url) in panel.urls.enumerated() {
            openReportingErrors(
                url,
                disposition: index == 0 ? .replaceCurrentTab : .newTab
            )
        }
    }

    private func appendTab() -> DocumentTab {
        let tab = DocumentTab()
        tabs.append(tab)
        return tab
    }

    // MARK: - Folder navigator

    func activate(
        _ node: FolderNavigatorNode,
        disposition: DocumentOpenDisposition
    ) {
        do {
            let destination = try folderNavigator.resolvedFile(for: node)
            if disposition == .replaceCurrentTab,
               let current = selectedTab.fileURL,
               FolderNavigatorPath.canonical(current)
                == FolderNavigatorPath.canonical(destination) {
                folderNavigator.revealCurrentDocument()
                return
            }
            guard let lease = folderNavigator.rootLease else {
                throw FolderNavigatorError.accessDenied
            }
            try withExtendedLifetime(lease) {
                try open(destination, disposition: disposition)
            }
        } catch {
            alert = .error(
                title: "Couldn’t Open Markdown File",
                message: error.localizedDescription
            )
        }
    }

    func chooseFolderNavigatorRoot() {
        let referenceURL = selectedTab.fileURL
        Task { @MainActor in
            do {
                guard let access = try await FolderAccessStore.shared
                    .requestAccess(
                        for: referenceURL,
                        purpose: .folderNavigator,
                        attachedTo: window
                    ) else { return }
                folderNavigator.isVisible = true
                await folderNavigator.setRoot(
                    access,
                    documentURL: referenceURL ?? access.rootURL
                )
            } catch {
                alert = .error(
                    title: "Couldn’t Open Folder",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Keeps the navigator's highlighted row in sync without rebuilding the
    /// tree when the newly selected document already lives under its root.
    func synchronizeFolderNavigator() {
        let url = selectedTab.fileURL

        if folderNavigator.rootURL != nil {
            if let url, !folderNavigator.canRepresent(url) {
                Task { await folderNavigator.initialize(for: url) }
            } else {
                folderNavigator.updateCurrentDocument(url)
            }
            return
        }

        guard url != nil else { return }
        Task { await folderNavigator.initialize(for: url) }
    }

    // MARK: - Saving

    @discardableResult
    func save(_ tab: DocumentTab) -> Bool {
        guard let url = tab.fileURL else { return saveAs(tab) }
        return write(tab, to: url)
    }

    @discardableResult
    func saveAs(_ tab: DocumentTab) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdownText]
        panel.nameFieldStringValue = tab.fileURL?.lastPathComponent
            ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(tab, to: url)
    }

    private func write(_ tab: DocumentTab, to url: URL) -> Bool {
        do {
            try Data(tab.document.text.utf8).write(to: url, options: .atomic)
            tab.markSaved(at: url)
            objectWillChange.send()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            synchronizeFolderNavigator()
            return true
        } catch {
            alert = .error(
                title: "Couldn’t Save Document",
                message: error.localizedDescription
            )
            return false
        }
    }

    private func resolveUnsavedChanges(
        for tab: DocumentTab
    ) -> WorkspaceTabClosePolicy {
        guard tab.isDirty else { return .close }

        let alert = NSAlert()
        alert.messageText = "Save changes to “\(tab.displayName)”?"
        alert.informativeText =
            "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save(tab) ? .close : .keepOpen
        case .alertThirdButtonReturn:
            return .close
        default:
            return .keepOpen
        }
    }
}

/// Routes files opened from Finder or the Dock to the frontmost window.
@MainActor
final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()

    private final class WeakWorkspace {
        weak var value: Workspace?
        init(_ value: Workspace) { self.value = value }
    }

    private var workspaces: [WeakWorkspace] = []
    private var pendingURLs: [URL] = []

    /// SwiftUI spawns a fresh window for every incoming open-document event.
    /// Anything younger than this is treated as such a throwaway window.
    private let draftWindowLifetime: TimeInterval = 5
    private var throwawayWindowExpectedAt: Date?

    func register(_ workspace: Workspace) {
        prune()
        guard !workspaces.contains(where: { $0.value === workspace }) else {
            return
        }
        workspaces.append(WeakWorkspace(workspace))

        if let expectedAt = throwawayWindowExpectedAt,
           Date().timeIntervalSince(expectedAt) < draftWindowLifetime,
           workspace.isEmptyDraft,
           workspaces.contains(where: {
               $0.value !== workspace && $0.value?.isEmptyDraft == false
           }) {
            throwawayWindowExpectedAt = nil
            workspace.requestClose()
            return
        }

        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        deliver(urls, to: workspace, preferringCurrentTab: true)
    }

    func unregister(_ workspace: Workspace) {
        workspaces.removeAll { $0.value === workspace || $0.value == nil }
    }

    var frontmost: Workspace? {
        prune()
        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           let match = workspaces.first(where: { $0.value?.window === keyWindow }) {
            return match.value
        }
        return workspaces.last?.value
    }

    /// Moves the most recently focused window to the end of the list so that
    /// incoming documents land in the window the user actually looked at.
    func noteActivated(_ workspace: Workspace) {
        prune()
        guard let index = workspaces.firstIndex(where: {
            $0.value === workspace
        }), index != workspaces.count - 1 else { return }
        let entry = workspaces.remove(at: index)
        workspaces.append(entry)
    }

    func open(_ urls: [URL]) {
        prune()
        let live = workspaces.compactMap(\.value)
        let established = live.last { !$0.isEmptyDraft }

        guard let target = established ?? live.last else {
            pendingURLs.append(contentsOf: urls)
            return
        }

        throwawayWindowExpectedAt = Date()
        deliver(
            urls,
            to: target,
            preferringCurrentTab: target.isEmptyDraft
        )
        discardThrowawayWindows(keeping: target)
    }

    private func discardThrowawayWindows(keeping target: Workspace) {
        let now = Date()
        for workspace in workspaces.compactMap(\.value)
        where workspace !== target
            && workspace.isEmptyDraft
            && now.timeIntervalSince(workspace.createdAt) < draftWindowLifetime {
            workspace.requestClose()
        }
    }

    private func deliver(
        _ urls: [URL],
        to workspace: Workspace,
        preferringCurrentTab: Bool
    ) {
        for (index, url) in urls.enumerated() {
            let disposition: DocumentOpenDisposition =
                (index == 0 && (preferringCurrentTab
                    || workspace.selectedTab.isReusable))
                ? .replaceCurrentTab
                : .newTab
            workspace.openReportingErrors(url, disposition: disposition)
        }
        workspace.window?.makeKeyAndOrderFront(nil)
    }

    private func prune() {
        workspaces.removeAll { $0.value == nil }
    }
}
