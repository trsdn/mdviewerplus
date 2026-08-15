import AppKit
import SwiftUI

enum ViewMode: Equatable {
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
    @ObservedObject var tab: DocumentTab
    let isActive: Bool
    @ObservedObject var folderNavigator: FolderNavigatorState
    let appearanceMode: AppearanceMode
    let lightThemeID: String
    let darkThemeID: String
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14.0
    @State private var viewMode: ViewMode = .view
    @State private var activePane: ActivePane = .preview
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollSource: ScrollSource = .editor
    @State private var editorCommandRequest: EditorCommandRequest?
    @State private var editorFindRequest: FindCommandRequest?
    @State private var previewFindRequest: PreviewFindRequest?
    @State private var editorOutlineRequest: EditorOutlineRequest?
    @State private var previewOutlineRequest: PreviewOutlineRequest?
    @State private var previewFindQuery = ""
    @State private var previewFindResult: PreviewFindResult?
    @State private var isPreviewFindSearching = false
    @State private var isPreviewFindPresented = false
    @State private var isQuickOpenPresented = false
    @State private var quickOpenItems: [QuickOpenItem] = []
    @State private var isOutlinePresented = false
    @State private var outlineEntries: [OutlineEntry] = []
    @State private var pendingQuickOpen = false
    @State private var pendingInitialFragment: String?
    @State private var documentAlert: DocumentAlert?
    @State private var folderAccess: FolderAccessLease?
    @State private var relativeResourcesRequested = false
    @State private var resourceAccessDeclined = false
    @State private var isRequestingResourceAccess = false
    @State private var resourceAccessGeneration = 0
    @State private var pendingRelativeLink: URL?
    @State private var siblingFiles = MarkdownSiblingFiles.unavailable
    @State private var isNavigating = false
    @State private var presentingSize = CGSize(width: 800, height: 600)
    @StateObject private var windowState = DocumentWindowState()
    @StateObject private var printController = MarkdownPrintController()
    @StateObject private var folderWatcher = MarkdownFolderWatcher()

    private var document: MarkdownDocument { tab.document }

    private var documentText: Binding<String> { $tab.document.text }

    private var fileURL: URL? { tab.fileURL }

    private var palette: ThemePalette {
        ThemeRegistry.resolve(
            appearanceMode: appearanceMode,
            lightThemeID: lightThemeID,
            darkThemeID: darkThemeID,
            systemColorScheme: systemColorScheme
        )
    }

    var body: some View {
        Group {
                switch viewMode {
                case .view:
                MarkdownWebView(
                    text: document.text,
                    fileURL: fileURL,
                    palette: palette,
                    zoomLevel: zoomLevel,
                    resourceRoot: folderAccess?.rootURL,
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    findRequest: previewFindRequest,
                    outlineRequest: previewOutlineRequest,
                    onFocus: { activePane = .preview },
                    onError: showRenderError,
                    onRelativeResources: handleRelativeResources,
                    onOutline: updateOutline,
                    onFindResult: updatePreviewFindStatus,
                    onOpenRelativeLink: openRelativeLink
                )
                case .split:
                HSplitView {
                    MarkdownEditorView(
                        text: documentText,
                        palette: palette,
                        fontSize: CGFloat(editorFontSize),
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        commandRequest: editorCommandRequest,
                        findRequest: editorFindRequest,
                        outlineRequest: editorOutlineRequest,
                        onFocus: { activePane = .editor }
                    )
                    .frame(minWidth: 200)
                    MarkdownWebView(
                        text: document.text,
                        fileURL: fileURL,
                        palette: palette,
                        zoomLevel: zoomLevel,
                        resourceRoot: folderAccess?.rootURL,
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        findRequest: previewFindRequest,
                        outlineRequest: previewOutlineRequest,
                        onFocus: { activePane = .preview },
                        onError: showRenderError,
                        onRelativeResources: handleRelativeResources,
                        onOutline: updateOutline,
                        onFindResult: updatePreviewFindStatus,
                        onOpenRelativeLink: openRelativeLink
                    )
                    .frame(minWidth: 200)
                }
                .background(palette.colors.splitter.swiftUIColor)
                case .edit:
                MarkdownEditorView(
                    text: documentText,
                    palette: palette,
                    fontSize: CGFloat(editorFontSize),
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    commandRequest: editorCommandRequest,
                    findRequest: editorFindRequest,
                    outlineRequest: editorOutlineRequest,
                    onFocus: { activePane = .editor }
                )
            }
        }
        .background(palette.colors.background.swiftUIColor)
        .tint(palette.colors.splitterHover.swiftUIColor)
        .preferredColorScheme(appearanceMode.preferredColorScheme)
        .background(DocumentWindowAccessor(state: windowState))
        .overlay(alignment: .topTrailing) {
            resourceAccessNotice
        }
        .overlay {
            GeometryReader { geometry in
                if isPreviewFindPresented {
                    PreviewFindBar(
                        query: $previewFindQuery,
                        result: previewFindResult,
                        isSearching: isPreviewFindSearching,
                        onSearch: performPreviewFind,
                        onDismiss: dismissPreviewFind
                    )
                    .padding(.top, 10)
                    .padding(
                        .trailing,
                        NavigationPanelSizing.previewContentInset(
                            for: geometry.size.width
                        )
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PresentingSizePreferenceKey.self,
                    value: geometry.size
                )
            }
        }
        .onPreferenceChange(PresentingSizePreferenceKey.self) {
            presentingSize = $0
        }
        .onChange(of: previewFindQuery) { newQuery in
            if previewFindRequest?.query != newQuery {
                previewFindResult = nil
                isPreviewFindSearching = false
            }
        }
        .focusedSceneValue(
            \.documentCommandActions,
            isActive ? commandActions : nil
        )
        .task(id: fileURL) {
            resetFolderAccess()
        }
        .onDisappear {
            folderWatcher.stop()
        }
        .sheet(isPresented: $isQuickOpenPresented) {
            QuickOpenPalette(
                items: quickOpenItems,
                presentingHeight: presentingSize.height
            ) { url in
                openNativeDocument(at: url, fragment: nil)
            }
        }
        .sheet(isPresented: $isOutlinePresented) {
            OutlinePalette(
                entries: outlineEntries,
                presentingHeight: presentingSize.height
            ) { entry in
                selectOutlineEntry(entry)
            }
        }
        .alert(item: $documentAlert) { alert in
            switch alert {
            case .confirmReload(let diskText):
                return Alert(
                    title: Text("Reload Document?"),
                    message: Text("Reloading will discard unsaved changes in this document."),
                    primaryButton: .destructive(Text("Reload")) {
                        tab.load(text: diskText, url: fileURL)
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
            canNavigatePrevious: siblingFiles.previous != nil && !isNavigating,
            canNavigateNext: siblingFiles.next != nil && !isNavigating,
            canPrepareNavigation: fileURL != nil
                && !isNavigating
                && !isRequestingResourceAccess,
            canQuickOpen: fileURL != nil
                && !isNavigating
                && !isRequestingResourceAccess,
            canShowOutline: !outlineEntries.isEmpty,
            canDismissFind: isPreviewFindPresented,
            canToggleFolderNavigator: true,
            canChooseFolderNavigatorRoot: !isNavigating,
            canRevealInFolderNavigator:
                folderNavigator.currentRelativePath != nil,
            canSave: tab.isDirty || fileURL == nil,
            canCloseTab: true,
            navigationPreparationTitle:
                SiblingNavigationFreshnessPolicy.preparationCommandTitle(
                    hasFolderAccess: folderAccess != nil
                ),
            reload: reload,
            navigatePrevious: { navigate(to: .previous) },
            navigateNext: { navigate(to: .next) },
            prepareNavigation: prepareSiblingNavigation,
            toggleEditMode: toggleEditMode,
            zoomIn: { handleZoom(.zoomIn) },
            zoomOut: { handleZoom(.zoomOut) },
            zoomReset: { handleZoom(.zoomReset) },
            printDocument: printCurrentDocument,
            find: handleFind,
            quickOpen: presentQuickOpen,
            showOutline: { isOutlinePresented = true },
            toggleFolderNavigator: {
                folderNavigator.toggleVisibility(documentURL: fileURL)
            },
            chooseFolderNavigatorRoot: workspace.chooseFolderNavigatorRoot,
            revealInFolderNavigator: folderNavigator.revealCurrentDocument,
            newTab: { workspace.newTab() },
            closeTab: workspace.closeSelectedTab,
            openFile: workspace.presentOpenPanel,
            save: { workspace.save(tab) },
            saveAs: { workspace.saveAs(tab) },
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
                        requestFolderAccess(for: .relativeResources)
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

    private func handleFind(_ command: FindCommand) {
        let target: ActivePane
        switch viewMode {
        case .view: target = .preview
        case .edit: target = .editor
        case .split: target = activePane
        }

        switch target {
        case .editor:
            if command == .dismiss {
                isPreviewFindPresented = false
            }
            editorFindRequest = FindCommandRequest(command: command)
        case .preview:
            switch command {
            case .show:
                isPreviewFindPresented = true
                previewFindResult = nil
                isPreviewFindSearching = false
            case .next:
                if previewFindQuery.isEmpty {
                    isPreviewFindPresented = true
                } else {
                    performPreviewFind(backwards: false)
                }
            case .previous:
                if previewFindQuery.isEmpty {
                    isPreviewFindPresented = true
                } else {
                    performPreviewFind(backwards: true)
                }
            case .dismiss:
                dismissPreviewFind()
            }
        }
    }

    private func performPreviewFind(backwards: Bool) {
        guard !previewFindQuery.isEmpty else {
            previewFindResult = nil
            isPreviewFindSearching = false
            return
        }
        previewFindResult = nil
        isPreviewFindSearching = true
        previewFindRequest = PreviewFindRequest(
            query: previewFindQuery,
            backwards: backwards
        )
    }

    private func updatePreviewFindStatus(_ result: PreviewFindResult) {
        guard previewFindRequest?.query == previewFindQuery else { return }
        previewFindResult = result
        isPreviewFindSearching = false
    }

    private func dismissPreviewFind() {
        isPreviewFindPresented = false
        previewFindResult = nil
        isPreviewFindSearching = false
        previewFindRequest = PreviewFindRequest(query: "", clear: true)
    }

    private func updateOutline(_ renderedEntries: [OutlineEntry]) {
        let nativeEntries = DocumentOutlineParser.parse(document.text)
        let nativeBySlug = Dictionary(
            uniqueKeysWithValues: nativeEntries.map { ($0.slug, $0) }
        )
        outlineEntries = renderedEntries.map { rendered in
            OutlineEntry(
                slug: rendered.slug,
                level: rendered.level,
                title: rendered.title,
                sourceLocation: nativeBySlug[rendered.slug]?.sourceLocation
            )
        }

        if let fragment = pendingInitialFragment {
            pendingInitialFragment = nil
            previewOutlineRequest = PreviewOutlineRequest(slug: fragment)
        }
    }

    private func selectOutlineEntry(_ entry: OutlineEntry) {
        previewOutlineRequest = PreviewOutlineRequest(slug: entry.slug)
        if viewMode != .view, let sourceLocation = entry.sourceLocation {
            editorOutlineRequest = EditorOutlineRequest(
                location: sourceLocation
            )
        }
    }

    private func presentQuickOpen() {
        guard fileURL != nil else { return }
        guard folderAccess != nil else {
            pendingQuickOpen = true
            requestFolderAccess(for: .navigationTools)
            return
        }
        reloadQuickOpen(reportErrors: true)
        isQuickOpenPresented = true
    }

    private func reloadQuickOpen(reportErrors: Bool) {
        guard let folderAccess else {
            quickOpenItems = []
            return
        }
        do {
            let rootURL = folderAccess.rootURL
            quickOpenItems = try MarkdownFileCatalog.files(in: rootURL).map {
                QuickOpenItem(
                    url: $0,
                    displayRelativePath: displayRelativePath(
                        for: $0,
                        relativeTo: rootURL
                    )
                )
            }
        } catch {
            quickOpenItems = []
            if reportErrors {
                documentAlert = .error(
                    title: "Couldn’t List Markdown Files",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func displayRelativePath(
        for fileURL: URL,
        relativeTo rootURL: URL
    ) -> String {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: rootComponents) else {
            return fileURL.lastPathComponent
        }
        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty
            ? fileURL.lastPathComponent
            : relativeComponents.joined(separator: "/")
    }

    private func reload() {
        guard let url = fileURL else { return }
        defer {
            updateSiblingNavigation(for: .reload)
        }

        do {
            let diskText = try String(contentsOf: url, encoding: .utf8)
            switch ReloadPolicy.decide(
                currentText: document.text,
                diskText: diskText,
                hasUnsavedChanges: tab.isDirty
            ) {
            case .unchanged:
                break
            case .apply(let text):
                tab.load(text: text, url: url)
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

    private func refreshSiblingFiles(reportErrors: Bool) {
        guard let fileURL, let folderAccess else {
            siblingFiles = .unavailable
            return
        }

        do {
            siblingFiles = try MarkdownSiblingNavigator.siblings(
                of: fileURL,
                in: folderAccess.rootURL
            )
        } catch {
            siblingFiles = .unavailable
            if reportErrors {
                showNavigationError(
                    title: "Couldn’t List Markdown Files",
                    error: error
                )
            }
        }
    }

    private func navigate(to direction: MarkdownSiblingDirection) {
        guard !isNavigating,
              let fileURL,
              let navigationAccess = folderAccess else { return }
        isNavigating = true

        Task { @MainActor in
            defer {
                // Extend the security-scoped lease through the awaited native open.
                _ = navigationAccess
                isNavigating = false
            }

            let destination: URL
            do {
                guard let siblingURL = try MarkdownSiblingNavigator.destination(
                    from: fileURL,
                    in: navigationAccess.rootURL,
                    direction: direction
                ) else {
                    refreshSiblingFiles(reportErrors: false)
                    return
                }
                destination = siblingURL
            } catch {
                refreshSiblingFiles(reportErrors: false)
                showNavigationError(
                    title: "Couldn’t List Markdown Files",
                    error: error
                )
                return
            }

            do {
                try withExtendedLifetime(navigationAccess) {
                    try workspace.open(
                        destination,
                        disposition: .replaceCurrentTab
                    )
                }
            } catch {
                siblingFiles = SiblingNavigationTargetPolicy.afterOpenFailure(
                    currentTargets: siblingFiles
                )
                showNavigationError(
                    title: "Couldn’t Open Markdown File",
                    error: error
                )
            }
        }
    }

    private func prepareSiblingNavigation() {
        updateSiblingNavigation(for: .explicitPreparation)
    }

    private func updateSiblingNavigation(
        for event: SiblingNavigationFreshnessEvent
    ) {
        let action = SiblingNavigationFreshnessPolicy.action(
            for: event,
            hasFolderAccess: folderAccess != nil
        )

        switch action {
        case .clearSilently:
            siblingFiles = .unavailable
        case .enumerateSilently, .enumerateReportingErrors:
            refreshSiblingFiles(reportErrors: action.reportsErrors)
        case .requestAuthorization:
            requestFolderAccess(for: .siblingNavigation)
        }
    }

    private func showNavigationError(title: String, error: Error) {
        documentAlert = .error(
            title: title,
            message: error.localizedDescription
        )
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
        requestFolderAccess(for: .relativeResources)
    }

    private func restoreFolderAccess() {
        guard let fileURL else { return }

        do {
            folderAccess = try FolderAccessStore.shared.restoredAccess(for: fileURL)
        } catch {
            folderAccess = nil
        }
    }

    private func resetFolderAccess() {
        resourceAccessGeneration += 1
        folderWatcher.stop()
        folderAccess = nil
        relativeResourcesRequested = false
        resourceAccessDeclined = false
        isRequestingResourceAccess = false
        pendingRelativeLink = nil
        pendingQuickOpen = false
        isQuickOpenPresented = false
        quickOpenItems = []
        outlineEntries = []
        pendingInitialFragment = fileURL.flatMap {
            PendingDocumentFragmentStore.shared.consume(for: $0)
        }
        restoreFolderAccess()
        siblingFiles = .unavailable

        let decision = FolderAccessAuthorizationPolicy.decision(
            for: .documentPreflight,
            hasRestoredAccess: folderAccess != nil
        )
        if decision == .useRestoredAccess {
            refreshSiblingFiles(reportErrors: false)
            startFolderWatcher()
        }
    }

    private func requestFolderAccess(for purpose: FolderAccessPurpose) {
        guard !isRequestingResourceAccess, let fileURL else { return }
        isRequestingResourceAccess = true
        let generation = resourceAccessGeneration

        Task { @MainActor in
            do {
                let access = try await FolderAccessStore.shared.requestAccess(
                    for: fileURL,
                    purpose: purpose,
                    attachedTo: windowState.window
                )
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                folderAccess = access
                if access == nil {
                    pendingQuickOpen = false
                }
                if purpose == .relativeResources {
                    resourceAccessDeclined = access == nil
                }
                if FolderAccessAuthorizationPolicy.navigationAvailable(
                    afterAccessWasGranted: access != nil
                ) {
                    refreshSiblingFiles(
                        reportErrors: purpose == .siblingNavigation
                    )
                }
                if let rootURL = access?.rootURL {
                    openPendingRelativeLink(under: rootURL)
                    startFolderWatcher()
                    if pendingQuickOpen {
                        pendingQuickOpen = false
                        reloadQuickOpen(reportErrors: true)
                        isQuickOpenPresented = true
                    }
                }
            } catch {
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                switch purpose {
                case .relativeResources:
                    resourceAccessDeclined = true
                    showResourceError(error)
                case .siblingNavigation, .navigationTools, .folderNavigator:
                    showNavigationError(
                        title: "Couldn’t Enable Folder Navigation",
                        error: error
                    )
                }
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
            requestFolderAccess(for: .relativeResources)
        }
    }

    private func openPendingRelativeLink(under rootURL: URL) {
        guard let pendingRelativeLink else { return }

        do {
            guard let sourceURL = fileURL else {
                throw InternalMarkdownLinkError.notRelative
            }
            let rawLink = try InternalMarkdownLinkResolver.relativeLink(
                from: pendingRelativeLink
            )
            let link = try InternalMarkdownLinkResolver.resolve(
                rawLink: rawLink,
                documentURL: sourceURL,
                authorizedRoot: rootURL
            )
            self.pendingRelativeLink = nil
            openNativeDocument(
                at: link.fileURL,
                fragment: link.fragment
            )
        } catch {
            showResourceError(error)
        }
    }

    private func startFolderWatcher() {
        guard let folderAccess else { return }
        folderWatcher.start(watching: folderAccess.rootURL) {
            refreshSiblingFiles(reportErrors: false)
            if isQuickOpenPresented {
                reloadQuickOpen(reportErrors: false)
            }
        }
    }

    private func openNativeDocument(
        at destination: URL,
        fragment: String?,
        navigatorAccess: FolderAccessLease? = nil,
        disposition: DocumentOpenDisposition = .replaceCurrentTab
    ) {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }
        let access = navigatorAccess ?? folderAccess

        do {
            if let fragment {
                PendingDocumentFragmentStore.shared.store(
                    fragment: fragment,
                    for: destination
                )
            }
            try withExtendedLifetime(access) {
                try workspace.open(destination, disposition: disposition)
            }
        } catch {
            if fragment != nil {
                _ = PendingDocumentFragmentStore.shared.consume(
                    for: destination
                )
            }
            documentAlert = .error(
                title: "Couldn’t Open Markdown File",
                message: error.localizedDescription
            )
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

private struct PresentingSizePreferenceKey: PreferenceKey {
    static var defaultValue = CGSize(width: 800, height: 600)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
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
        nsView.installToolbarPolicy()
    }

    final class WindowReaderView: NSView {
        weak var state: DocumentWindowState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            state?.window = window
            installToolbarPolicy()
        }

        func installToolbarPolicy() {}
    }
}
