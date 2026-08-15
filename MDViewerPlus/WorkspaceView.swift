import AppKit
import SwiftUI

/// Root view of a window: owns the workspace and hands it to the shell.
struct WorkspaceView: View {
    let appearanceMode: AppearanceMode
    let lightThemeID: String
    let darkThemeID: String

    @StateObject private var workspace = Workspace()

    var body: some View {
        WorkspaceShell(
            workspace: workspace,
            folderNavigator: workspace.folderNavigator,
            appearanceMode: appearanceMode,
            lightThemeID: lightThemeID,
            darkThemeID: darkThemeID
        )
    }
}

/// Observes both the workspace and the folder navigator so that sidebar
/// visibility changes from the toolbar, the menu or the code all take effect.
private struct WorkspaceShell: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var folderNavigator: FolderNavigatorState
    let appearanceMode: AppearanceMode
    let lightThemeID: String
    let darkThemeID: String

    @Environment(\.colorScheme) private var systemColorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isDropTargeted = false

    private var palette: ThemePalette {
        ThemeRegistry.resolve(
            appearanceMode: appearanceMode,
            lightThemeID: lightThemeID,
            darkThemeID: darkThemeID,
            systemColorScheme: systemColorScheme
        )
    }

    private var desiredColumnVisibility: NavigationSplitViewVisibility {
        folderNavigator.isVisible ? .doubleColumn : .detailOnly
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderNavigatorSidebar(
                state: folderNavigator,
                chooseRoot: workspace.chooseFolderNavigatorRoot,
                activate: { workspace.activate($0, disposition: .replaceCurrentTab) },
                activateInNewTab: { workspace.activate($0, disposition: .newTab) }
            )
        } detail: {
            VStack(spacing: 0) {
                if workspace.tabs.count > 1 {
                    DocumentTabBar(workspace: workspace, palette: palette)
                    Divider()
                }
                tabContents
            }
            .background(palette.colors.background.swiftUIColor)
            .overlay {
                FileDropCatcher(
                    isTargeted: $isDropTargeted,
                    perform: { workspace.openDropped($0) }
                )
            }
            .overlay {
                if isDropTargeted {
                    DropTargetOverlay(palette: palette)
                }
            }
        }
        .environmentObject(workspace)
        .navigationTitle(workspace.selectedTab.displayName)
        .modifier(
            NavigationDocumentModifier(url: workspace.selectedTab.fileURL)
        )
        .preferredColorScheme(appearanceMode.preferredColorScheme)
        .tint(palette.colors.splitterHover.swiftUIColor)
        .background(
            WorkspaceWindowSynchronizer(
                workspace: workspace,
                tab: workspace.selectedTab
            )
        )
        .onAppear { columnVisibility = desiredColumnVisibility }
        .onChange(of: columnVisibility) { newValue in
            folderNavigator.setVisible(
                newValue != .detailOnly,
                documentURL: workspace.selectedTab.fileURL
            )
        }
        .onChange(of: folderNavigator.isVisible) { _ in
            if columnVisibility != desiredColumnVisibility {
                columnVisibility = desiredColumnVisibility
            }
        }
        .alert(item: $workspace.alert) { alert in
            switch alert {
            case .error(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .task {
            WorkspaceRegistry.shared.register(workspace)
#if DEBUG
            if let testDocument = UITestHooks.consumeInitialDocumentURL() {
                workspace.openReportingErrors(
                    testDocument,
                    disposition: .replaceCurrentTab
                )
                return
            }
#endif
            workspace.synchronizeFolderNavigator()
        }
    }

    private var tabContents: some View {
        ZStack {
            ForEach(workspace.tabs) { tab in
                let isActive = tab.id == workspace.selectedTabID
                ContentView(
                    tab: tab,
                    isActive: isActive,
                    folderNavigator: folderNavigator,
                    appearanceMode: appearanceMode,
                    lightThemeID: lightThemeID,
                    darkThemeID: darkThemeID
                )
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                .zIndex(isActive ? 1 : 0)
            }
        }
    }
}

// MARK: - Tab bar

struct DocumentTabBar: View {
    @ObservedObject var workspace: Workspace
    let palette: ThemePalette

    enum Metrics {
        static let height: CGFloat = 30
        static let minimumTabWidth: CGFloat = 90
        static let maximumTabWidth: CGFloat = 220
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        DocumentTabItem(
                            tab: tab,
                            isActive: tab.id == workspace.selectedTabID,
                            palette: palette,
                            select: { workspace.select(tab.id) },
                            close: { workspace.closeTab(tab.id) }
                        )
                        Divider().frame(height: Metrics.height * 0.6)
                    }
                }
            }

            Button {
                workspace.newTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: Metrics.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .accessibilityLabel("New Tab")
            .accessibilityIdentifier("newTabButton")
        }
        .frame(height: Metrics.height)
        .background(palette.colors.gutterBackground.swiftUIColor)
        .accessibilityIdentifier("documentTabBar")
    }
}

private struct DocumentTabItem: View {
    @ObservedObject var tab: DocumentTab
    let isActive: Bool
    let palette: ThemePalette
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: close) {
                Image(
                    systemName: tab.isDirty && !isHovering
                        ? "circle.fill"
                        : "xmark"
                )
                .font(.system(size: tab.isDirty && !isHovering ? 7 : 9,
                              weight: .semibold))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
                .opacity(isHovering || tab.isDirty ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
            .accessibilityLabel("Close Tab")

            Text(tab.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(
            minWidth: DocumentTabBar.Metrics.minimumTabWidth,
            maxWidth: DocumentTabBar.Metrics.maximumTabWidth,
            maxHeight: .infinity
        )
        .background(
            isActive
                ? palette.colors.background.swiftUIColor
                : Color.clear
        )
        .foregroundStyle(isActive ? .primary : .secondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(tab.fileURL?.path ?? tab.displayName)
        .accessibilityIdentifier("documentTab")
        .accessibilityLabel(tab.displayName)
    }
}

// MARK: - Window bridging

private struct WorkspaceWindowSynchronizer: View {
    let workspace: Workspace
    @ObservedObject var tab: DocumentTab

    var body: some View {
        WorkspaceWindowAccessor(
            workspace: workspace,
            isEdited: workspace.hasUnsavedChanges
        )
    }
}

private struct NavigationDocumentModifier: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}

private struct WorkspaceWindowAccessor: NSViewRepresentable {
    let workspace: Workspace
    let isEdited: Bool

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView()
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.apply(workspace: workspace, isEdited: isEdited)
    }

    final class WindowReaderView: NSView {
        private var workspace: Workspace?
        private var isEdited = false
        private let closeGuard = WorkspaceWindowCloseGuard()

        @MainActor
        func apply(workspace: Workspace, isEdited: Bool) {
            self.workspace = workspace
            self.isEdited = isEdited
            configureWindow()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        private var activationObserver: NSObjectProtocol?

        private func observeActivation(of window: NSWindow) {
            guard activationObserver == nil else { return }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let workspace = self?.workspace else { return }
                    WorkspaceRegistry.shared.noteActivated(workspace)
                }
            }
        }

        deinit {
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
            }
        }

        private func configureWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if self.workspace?.window !== window {
                    self.workspace?.window = window
                }
                self.workspace?.performPendingCloseIfNeeded()
                // The app draws its own tab bar, so native window tabs would
                // stack a second tab strip on top of it.
                window.tabbingMode = .disallowed
                window.titlebarAppearsTransparent = false
                window.isDocumentEdited = self.isEdited
                self.closeGuard.install(on: window, workspace: self.workspace)
                self.observeActivation(of: window)
            }
        }
    }
}

/// Keeps SwiftUI's window delegate intact while adding a close confirmation.
@MainActor
private final class WorkspaceWindowCloseGuard {
    private var proxy: DelegateProxy?

    func install(on window: NSWindow, workspace: Workspace?) {
        guard let workspace else { return }
        if let proxy, window.delegate === proxy {
            proxy.workspace = workspace
            return
        }
        guard !(window.delegate is DelegateProxy) else { return }

        let proxy = DelegateProxy()
        proxy.workspace = workspace
        proxy.next = window.delegate
        self.proxy = proxy
        window.delegate = proxy
    }

    private final class DelegateProxy: NSObject, NSWindowDelegate {
        weak var workspace: Workspace?
        weak var next: NSWindowDelegate?

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return next?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            next
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            workspace?.shouldCloseWindow() ?? true
        }

        func windowWillClose(_ notification: Notification) {
            if let workspace {
                WorkspaceRegistry.shared.unregister(workspace)
            }
            if next?.responds(
                to: #selector(NSWindowDelegate.windowWillClose(_:))
            ) == true {
                next?.windowWillClose?(notification)
            }
        }
    }
}

/// Transparent AppKit drop destination layered above the document area.
///
/// SwiftUI's `onDrop` never sees Finder drags here because AppKit routes them to
/// the front-most registered view, which is the preview web view or the editor
/// text view. This catcher sits above both, accepts file URLs only, and stays
/// click-through so normal interaction is untouched. Drags without file URLs
/// return an empty operation so AppKit keeps searching the views below.
private struct FileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let perform: ([URL]) -> Void

    func makeNSView(context: Context) -> DropCatcherView {
        let view = DropCatcherView()
        view.registerForDraggedTypes([.fileURL])
        view.onTargetingChange = { isTargeted = $0 }
        view.onDrop = perform
        return view
    }

    func updateNSView(_ nsView: DropCatcherView, context: Context) {
        nsView.onTargetingChange = { isTargeted = $0 }
        nsView.onDrop = perform
    }

    final class DropCatcherView: NSView {
        var onTargetingChange: ((Bool) -> Void)?
        var onDrop: (([URL]) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override var acceptsFirstResponder: Bool { false }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard !fileURLs(from: sender).isEmpty else { return [] }
            onTargetingChange?(true)
            return .copy
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            fileURLs(from: sender).isEmpty ? [] : .copy
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            onTargetingChange?(false)
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            onTargetingChange?(false)
        }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            !fileURLs(from: sender).isEmpty
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            onTargetingChange?(false)
            let urls = fileURLs(from: sender)
            guard !urls.isEmpty else { return false }
            onDrop?(urls)
            return true
        }

        private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let objects = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: options
            )
            return (objects as? [URL]) ?? []
        }
    }
}

/// Highlight shown while a valid Finder drag hovers the document area.
private struct DropTargetOverlay: View {
    let palette: ThemePalette

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                palette.colors.splitterHover.swiftUIColor,
                style: StrokeStyle(lineWidth: 3, dash: [10, 6])
            )
            .background(
                palette.colors.splitterHover.swiftUIColor
                    .opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .padding(8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
