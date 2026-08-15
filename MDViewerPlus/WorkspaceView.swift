import AppKit
import SwiftUI

/// Root view of a window: shared folder navigator, tab bar and tab contents.
struct WorkspaceView: View {
    let appearanceMode: AppearanceMode
    let lightThemeID: String
    let darkThemeID: String

    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var workspace = Workspace()

    private var palette: ThemePalette {
        ThemeRegistry.resolve(
            appearanceMode: appearanceMode,
            lightThemeID: lightThemeID,
            darkThemeID: darkThemeID,
            systemColorScheme: systemColorScheme
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: navigatorColumnVisibility) {
            FolderNavigatorSidebar(
                state: workspace.folderNavigator,
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
                    folderNavigator: workspace.folderNavigator,
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

    private var navigatorColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspace.folderNavigator.isVisible ? .all : .detailOnly },
            set: { visibility in
                let visible = visibility != .detailOnly
                guard workspace.folderNavigator.isVisible != visible else {
                    return
                }
                workspace.folderNavigator.toggleVisibility(
                    documentURL: workspace.selectedTab.fileURL
                )
            }
        )
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
