import SwiftUI
import AppKit

struct FolderNavigatorSidebar: View {
    @ObservedObject var state: FolderNavigatorState
    let chooseRoot: () -> Void
    let activate: (FolderNavigatorNode) -> Void
    let activateInNewTab: (FolderNavigatorNode) -> Void

    enum NavigatorRowMetrics {
        static let indentationStep: CGFloat = 14
        static let disclosureWidth: CGFloat = 12
        static let iconWidth: CGFloat = 16
        static let currentIndicatorWidth: CGFloat = 10
        static let columnSpacing: CGFloat = 4

        static func indentationWidth(for level: Int) -> CGFloat {
            CGFloat(max(level, 0)) * indentationStep
        }
    }

    struct NavigatorRowState: Equatable {
        let isSelected: Bool
        let isCurrentDocument: Bool
    }

    static func rowState(
        relativePath: String,
        selectedRelativePath: String?,
        currentRelativePath: String?
    ) -> NavigatorRowState {
        NavigatorRowState(
            isSelected: selectedRelativePath == relativePath,
            isCurrentDocument: currentRelativePath == relativePath
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.rootURL?.lastPathComponent ?? "Folder Navigator")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Open Folder", systemImage: "folder") {
                    chooseRoot()
                }
                .labelStyle(.iconOnly)
                .help("Open Folder…")
                .accessibilityLabel("Open Folder…")
            }
            .padding(10)

            Divider()

            if state.rootURL == nil {
                unavailable
            } else {
                List(selection: $state.selectedRelativePath) {
                    ForEach(state.visibleRows) { row in
                        navigatorRow(row)
                            .tag(row.node.relativePath)
                    }
                    if !state.loadingDirectories.isEmpty {
                        Label("Loading…", systemImage: "progress.indicator")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Folder Navigator")
                .onMoveCommand(perform: state.moveSelection)
                .onCommand(
                    #selector(NSResponder.moveToBeginningOfDocument(_:))
                ) {
                    state.selectBoundary(first: true)
                }
                .onCommand(
                    #selector(NSResponder.scrollToBeginningOfDocument(_:))
                ) {
                    state.selectBoundary(first: true)
                }
                .onCommand(#selector(NSResponder.moveToEndOfDocument(_:))) {
                    state.selectBoundary(first: false)
                }
                .onCommand(#selector(NSResponder.scrollToEndOfDocument(_:))) {
                    state.selectBoundary(first: false)
                }
                .onCommand(#selector(NSResponder.insertNewline(_:))) {
                    performPrimaryKeyboardAction()
                }
            }

            if let message = state.statusMessage {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .accessibilityLabel("Folder navigator status: \(message)")
            }
        }
        .frame(
            minWidth: FolderNavigatorMetrics.minimumWidth,
            idealWidth: state.width,
            maxWidth: FolderNavigatorMetrics.maximumWidth
        )
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width) { newWidth in
                    state.setWidth(newWidth)
                }
            }
        }
        .accessibilityIdentifier("folderNavigator")
        .background {
            NavigatorSpaceKeyMonitor(action: performPrimaryKeyboardAction)
        }
    }

    enum NavigatorSpaceKeyPolicy {
        static func shouldActivate(
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags
        ) -> Bool {
            let disallowed = modifiers.intersection([.command, .control, .option])
            return keyCode == 49 && disallowed.isEmpty
        }

        static func isTreeFocused(_ responder: NSResponder?) -> Bool {
            var view = responder as? NSView
            while let current = view {
                if current is NSButton || current is NSTextView {
                    return false
                }
                if current is NSTableView {
                    return true
                }
                view = current.superview
            }
            return false
        }
    }

    private struct NavigatorSpaceKeyMonitor: NSViewRepresentable {
        let action: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(action: action)
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.action = action
            context.coordinator.install(for: view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.action = action
            context.coordinator.install(for: nsView)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.uninstall()
        }

        final class Coordinator {
            var action: () -> Void
            private weak var view: NSView?
            private var monitor: Any?

            init(action: @escaping () -> Void) {
                self.action = action
            }

            func install(for view: NSView) {
                self.view = view
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self] event in
                    guard let self,
                          NavigatorSpaceKeyPolicy.shouldActivate(
                            keyCode: event.keyCode,
                            modifiers: event.modifierFlags
                          ),
                          isNavigatorFocused(for: event) else {
                        return event
                    }
                    action()
                    return nil
                }
            }

            func uninstall() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }

            private func isNavigatorFocused(for event: NSEvent) -> Bool {
                guard let view,
                      let window = event.window,
                      view.window === window,
                      let responder = window.firstResponder as? NSView,
                      NavigatorSpaceKeyPolicy.isTreeFocused(
                        responder
                      ) else {
                    return false
                }
                return view.convert(view.bounds, to: nil).intersects(
                    responder.convert(responder.bounds, to: nil)
                )
            }

            deinit {
                uninstall()
            }
        }
    }

    private func performPrimaryKeyboardAction() {
        guard let node = state.selectedNode else { return }
        if node.kind == .directory {
            state.toggleExpansion(node)
        } else {
            activate(node)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("No authorized folder")
                .font(.headline)
            Text("Choose the current document’s folder or a parent folder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Folder…", action: chooseRoot)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigatorRow(_ row: FolderNavigatorState.VisibleRow) -> some View {
        let rowState = Self.rowState(
            relativePath: row.node.relativePath,
            selectedRelativePath: state.selectedRelativePath,
            currentRelativePath: state.currentRelativePath
        )

        return HStack(spacing: NavigatorRowMetrics.columnSpacing) {
            Color.clear.frame(
                width: NavigatorRowMetrics.indentationWidth(for: row.level),
                height: 1
            )
            Group {
                if row.node.kind == .directory {
                    Button {
                        state.toggleExpansion(row.node)
                    } label: {
                        Image(
                            systemName: state.expandedRelativePaths.contains(
                                row.node.relativePath
                            ) ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.node.isExpandable)
                    .accessibilityLabel(
                        state.expandedRelativePaths.contains(row.node.relativePath)
                            ? "Collapse \(row.node.name)" : "Expand \(row.node.name)"
                    )
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: NavigatorRowMetrics.disclosureWidth)
            Image(systemName: row.node.kind == .directory ? "folder" : "doc.text")
                .frame(width: NavigatorRowMetrics.iconWidth)
                .accessibilityHidden(true)
            Text(row.node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Group {
                if rowState.isCurrentDocument {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .accessibilityLabel("Current document")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: NavigatorRowMetrics.currentIndicatorWidth)
        }
        .contentShape(Rectangle())
        .help(row.node.name)
        .onTapGesture {
            state.select(row.node)
            if row.node.kind == .file {
                activate(row.node)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "folderNavigatorRow-" +
                row.node.relativePath.replacingOccurrences(of: "/", with: "--")
        )
        .accessibilityLabel(
            "\(row.node.kind == .directory ? "Folder" : "Markdown file"), \(row.node.name)"
        )
        .accessibilityValue(
            [
                rowState.isSelected ? "Selected" : nil,
                rowState.isCurrentDocument ? "Current document" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
        .accessibilityAddTraits(
            rowState.isSelected
                ? .isSelected : []
        )
        .contextMenu {
            if row.node.kind == .file {
                Button("Open") { activate(row.node) }
                Button("Open in New Tab") {
                    activateInNewTab(row.node)
                }
            }
        }
    }
}
