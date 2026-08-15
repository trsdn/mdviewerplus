import Foundation
import SwiftUI

@MainActor
final class FolderNavigatorState: ObservableObject {
    typealias ChildrenLoader = @Sendable (
        URL,
        String,
        Int,
        FolderNavigatorLimits
    ) throws -> FolderNavigatorChildren

    struct VisibleRow: Identifiable {
        let node: FolderNavigatorNode
        let level: Int
        var id: String { node.id }
    }

    @Published var isVisible: Bool {
        didSet { defaults.set(isVisible, forKey: Self.visibilityKey) }
    }
    @Published var width: Double {
        didSet { defaults.set(width, forKey: Self.widthKey) }
    }
    @Published private(set) var rootURL: URL?
    @Published private(set) var childrenByDirectory: [String: FolderNavigatorChildren] = [:]
    @Published private(set) var expandedRelativePaths: Set<String> = []
    @Published var selectedRelativePath: String?
    @Published private(set) var currentRelativePath: String?
    @Published private(set) var loadingDirectories: Set<String> = []
    @Published private(set) var statusMessage: String?

    private(set) var rootLease: FolderAccessLease?
    private let defaults: UserDefaults
    private let limits: FolderNavigatorLimits
    private let childrenLoader: ChildrenLoader
    private let watcher = RecursiveFolderNavigatorWatcher()
    private var generation = 0
    private var pendingRefreshDirectories: Set<String> = []

    static let visibilityKey = "folderNavigatorVisible"
    static let widthKey = "folderNavigatorWidth"

    init(
        defaults: UserDefaults = .standard,
        limits: FolderNavigatorLimits = .standard,
        childrenLoader: @escaping ChildrenLoader = {
            try FolderNavigatorTreeBuilder.children(
                rootURL: $0,
                relativeDirectory: $1,
                depth: $2,
                limits: $3
            )
        }
    ) {
        self.defaults = defaults
        self.limits = limits
        self.childrenLoader = childrenLoader
        isVisible = defaults.bool(forKey: Self.visibilityKey)
        let savedWidth = defaults.double(forKey: Self.widthKey)
        width = Self.clampedWidth(
            savedWidth == 0 ? FolderNavigatorMetrics.defaultWidth : savedWidth
        )
    }

    var loadedNodeCount: Int {
        childrenByDirectory.values.reduce(0) { $0 + $1.nodes.count }
    }

    var visibleRows: [VisibleRow] {
        func appendChildren(
            of directory: String,
            level: Int,
            to rows: inout [VisibleRow]
        ) {
            guard let children = childrenByDirectory[directory] else { return }
            for node in children.nodes {
                rows.append(VisibleRow(node: node, level: level))
                if node.kind == .directory,
                   expandedRelativePaths.contains(node.relativePath) {
                    appendChildren(
                        of: node.relativePath,
                        level: level + 1,
                        to: &rows
                    )
                }
            }
        }
        var rows: [VisibleRow] = []
        appendChildren(of: "", level: 0, to: &rows)
        return rows
    }

    func initialize(for documentURL: URL?) async {
        reset()
        guard let documentURL else {
            statusMessage = "Save this document to use the folder navigator."
            return
        }
        currentRelativePath = nil

        if let context = FolderNavigatorContextStore.shared.consume(
            for: documentURL
        ) {
            isVisible = context.isVisible
            width = Self.clampedWidth(context.width)
            do {
                guard let lease = try FolderAccessStore.shared
                    .restoredNavigatorAccess(
                        forDocumentContainedBy: documentURL,
                        preferredRoot: context.rootURL
                    ) else {
                    statusMessage = "Folder access is unavailable. Choose Open Folder… to authorize it."
                    return
                }
                await setRoot(
                    lease,
                    documentURL: documentURL,
                    expanded: context.expandedRelativePaths,
                    selected: context.selectedRelativePath
                )
            } catch {
                statusMessage = error.localizedDescription
            }
            return
        }

        guard isVisible else { return }
        await restoreBestRoot(for: documentURL)
    }

    /// True when `url` lives under the currently loaded root, so switching to
    /// it only requires updating the highlight instead of rebuilding the tree.
    func canRepresent(_ url: URL) -> Bool {
        guard let rootURL else { return false }
        return FolderNavigatorPath.relativePath(of: url, under: rootURL) != nil
    }

    func updateCurrentDocument(_ documentURL: URL?) {
        guard let rootURL, let documentURL else {
            currentRelativePath = nil
            return
        }
        currentRelativePath = FolderNavigatorPath.relativePath(
            of: documentURL,
            under: rootURL
        )
    }

    func restoreBestRoot(for documentURL: URL) async {
        do {
            guard let lease = try FolderAccessStore.shared
                .restoredNavigatorAccess(forDocumentContainedBy: documentURL)
            else {
                statusMessage = "Folder access is unavailable. Choose Open Folder… to authorize it."
                return
            }
            await setRoot(lease, documentURL: documentURL)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setRoot(
        _ lease: FolderAccessLease,
        documentURL: URL,
        expanded: Set<String> = [],
        selected: String? = nil
    ) async {
        reset()
        rootLease = lease
        rootURL = lease.rootURL
        currentRelativePath = FolderNavigatorPath.relativePath(
            of: documentURL,
            under: lease.rootURL
        )
        selectedRelativePath = selected
        expandedRelativePaths = expanded.filter {
            (try? FolderNavigatorPath.validatedComponents($0).count) ?? 99
                <= limits.maximumDepth
        }
        statusMessage = "Loading…"
        startWatcher(rootURL: lease.rootURL)
        await load(relativeDirectory: "", depth: 0)
        if !expandedRelativePaths.isEmpty {
            await restoreExpandedDirectories()
        }
        if childrenByDirectory[""]?.nodes.isEmpty == true {
            statusMessage = "No Markdown files or folders."
        } else if statusMessage == "Loading…" {
            statusMessage = nil
        }
    }

    func toggleVisibility(documentURL: URL?) {
        setVisible(!isVisible, documentURL: documentURL)
    }

    func setVisible(_ visible: Bool, documentURL: URL?) {
        guard isVisible != visible else { return }
        isVisible = visible
        guard visible, rootLease == nil, let documentURL else { return }
        Task { await restoreBestRoot(for: documentURL) }
    }

    func setWidth(_ value: Double) {
        let clamped = Self.clampedWidth(value)
        if abs(width - clamped) >= 1 { width = clamped }
    }

    func toggleExpansion(_ node: FolderNavigatorNode) {
        guard node.kind == .directory, node.isExpandable else {
            if node.kind == .directory {
                statusMessage = FolderNavigatorError.depthLimit.localizedDescription
            }
            return
        }
        if expandedRelativePaths.remove(node.relativePath) != nil { return }
        expandedRelativePaths.insert(node.relativePath)
        if childrenByDirectory[node.relativePath] == nil {
            Task {
                await load(
                    relativeDirectory: node.relativePath,
                    depth: node.depth
                )
            }
        }
    }

    func select(_ node: FolderNavigatorNode) {
        selectedRelativePath = node.relativePath
    }

    func moveSelection(_ direction: MoveCommandDirection) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }
        let index = selectedRelativePath.flatMap { selected in
            rows.firstIndex { $0.node.relativePath == selected }
        }
        switch direction {
        case .up:
            selectedRelativePath = rows[max((index ?? 1) - 1, 0)]
                .node.relativePath
        case .down:
            selectedRelativePath = rows[min((index ?? -1) + 1, rows.count - 1)]
                .node.relativePath
        case .left:
            guard let index else { return }
            let node = rows[index].node
            if expandedRelativePaths.contains(node.relativePath) {
                expandedRelativePaths.remove(node.relativePath)
            } else {
                let parent = node.relativePath.split(separator: "/")
                    .dropLast().joined(separator: "/")
                if !parent.isEmpty { selectedRelativePath = parent }
            }
        case .right:
            guard let index else { return }
            let node = rows[index].node
            if node.kind == .directory,
               !expandedRelativePaths.contains(node.relativePath) {
                toggleExpansion(node)
            }
        @unknown default:
            break
        }
    }

    func selectBoundary(first: Bool) {
        selectedRelativePath = FolderNavigatorKeyboardSelection.boundaryPath(
            visibleRows.map(\.node.relativePath),
            first: first
        )
    }

    var selectedNode: FolderNavigatorNode? {
        guard let selectedRelativePath else { return nil }
        return visibleRows.first {
            $0.node.relativePath == selectedRelativePath
        }?.node
    }

    func resolvedFile(for node: FolderNavigatorNode) throws -> URL {
        guard node.kind == .file, let rootURL else {
            throw FolderNavigatorError.accessDenied
        }
        return try FolderNavigatorTreeBuilder.resolvedMarkdownFile(
            rootURL: rootURL,
            relativePath: node.relativePath
        )
    }

    func pendingContext() -> FolderNavigatorPendingContext? {
        guard let rootURL else { return nil }
        return FolderNavigatorPendingContext(
            rootURL: rootURL,
            isVisible: isVisible,
            expandedRelativePaths: expandedRelativePaths,
            selectedRelativePath: selectedRelativePath,
            width: width
        )
    }

    func revealCurrentDocument() {
        guard let relative = currentRelativePath else {
            statusMessage = "The current document is outside the authorized folder."
            return
        }
        Task {
            let components = relative.split(separator: "/").map(String.init)
            guard components.count <= limits.maximumDepth + 1 else {
                statusMessage = FolderNavigatorError.depthLimit.localizedDescription
                return
            }
            var path = ""
            for component in components.dropLast() {
                path = path.isEmpty ? component : "\(path)/\(component)"
                expandedRelativePaths.insert(path)
                if childrenByDirectory[path] == nil {
                    await load(
                        relativeDirectory: path,
                        depth: path.split(separator: "/").count
                    )
                }
            }
            selectedRelativePath = relative
        }
    }

    func reset() {
        generation &+= 1
        watcher.stop()
        rootLease = nil
        rootURL = nil
        childrenByDirectory = [:]
        expandedRelativePaths = []
        selectedRelativePath = nil
        currentRelativePath = nil
        loadingDirectories = []
        pendingRefreshDirectories = []
        statusMessage = nil
    }

    private func load(relativeDirectory: String, depth: Int) async {
        guard let rootURL, rootLease != nil else { return }
        if loadingDirectories.contains(relativeDirectory) {
            pendingRefreshDirectories.insert(relativeDirectory)
            return
        }
        let requestGeneration = generation
        let requestLimits = limits
        let requestLoader = childrenLoader
        loadingDirectories.insert(relativeDirectory)
        defer {
            if requestGeneration == generation {
                loadingDirectories.remove(relativeDirectory)
            }
        }
        while requestGeneration == generation {
            pendingRefreshDirectories.remove(relativeDirectory)
            do {
                let result = try await Task.detached {
                    try requestLoader(
                        rootURL,
                        relativeDirectory,
                        depth,
                        requestLimits
                    )
                }.value
                guard requestGeneration == generation else { break }
                let previous = childrenByDirectory[relativeDirectory]
                let replacing = previous?.nodes.count ?? 0
                let available = limits.maximumLoadedNodes
                    - (loadedNodeCount - replacing)
                if available <= 0 {
                    statusMessage =
                        FolderNavigatorError.nodeLimit.localizedDescription
                } else {
                    var bounded = result
                    if result.nodes.count > available {
                        bounded = FolderNavigatorChildren(
                            relativeDirectory: result.relativeDirectory,
                            nodes: Array(result.nodes.prefix(available)),
                            isTruncated: true
                        )
                    }
                    childrenByDirectory[relativeDirectory] = bounded
                    reconcileAfterRefresh(
                        relativeDirectory: relativeDirectory,
                        previous: previous
                    )
                    if bounded.isTruncated {
                        statusMessage = available < result.nodes.count
                            ? FolderNavigatorError.nodeLimit.localizedDescription
                            : "Only the first 500 items are shown."
                    }
                }
            } catch {
                guard requestGeneration == generation else { break }
                statusMessage = error.localizedDescription
            }
            guard pendingRefreshDirectories.remove(relativeDirectory) != nil
            else { break }
        }
    }

    private func restoreExpandedDirectories() async {
        for path in expandedRelativePaths.sorted(by: {
            $0.split(separator: "/").count < $1.split(separator: "/").count
        }) {
            let depth = path.split(separator: "/").count
            if depth <= limits.maximumDepth {
                await load(relativeDirectory: path, depth: depth)
            }
        }
    }

    private func startWatcher(rootURL: URL) {
        let watchGeneration = generation
        let started = watcher.start(
            rootURL: rootURL,
            onChange: { [weak self] paths, terminal, requiresFullRefresh in
                guard let self, watchGeneration == self.generation else { return }
                if terminal {
                    self.statusMessage =
                        FolderNavigatorError.movedRoot.localizedDescription
                    self.rootLease = nil
                    return
                }
                Task {
                    await self.handleFilesystemChanges(
                        paths: paths,
                        requiresFullRefresh: requiresFullRefresh
                    )
                }
            }
        )
        if !started {
            statusMessage = "Live folder refresh is unavailable."
        }
    }

    func handleFilesystemChanges(
        paths: [URL],
        requiresFullRefresh: Bool
    ) async {
        guard let rootURL else { return }
        let loaded = Set(childrenByDirectory.keys)
            .union(loadingDirectories)
        let affected = requiresFullRefresh
            ? loaded
            : FolderNavigatorRefreshPolicy.loadedDirectories(
                affectedBy: paths,
                rootURL: rootURL,
                loadedRelativeDirectories: loaded
            )
        for directory in affected.sorted(by: {
            $0.split(separator: "/").count < $1.split(separator: "/").count
        }) {
            guard childrenByDirectory[directory] != nil
                    || loadingDirectories.contains(directory)
            else { continue }
            await load(
                relativeDirectory: directory,
                depth: directory.isEmpty
                    ? 0 : directory.split(separator: "/").count
            )
        }
    }

    private func reconcileAfterRefresh(
        relativeDirectory: String,
        previous: FolderNavigatorChildren?
    ) {
        let currentDirectories = Set(
            childrenByDirectory[relativeDirectory]?.nodes
                .filter { $0.kind == .directory }
                .map(\.relativePath) ?? []
        )
        let removedDirectories = Set(
            previous?.nodes.filter { $0.kind == .directory }
                .map(\.relativePath) ?? []
        ).subtracting(currentDirectories)
        for removed in removedDirectories {
            expandedRelativePaths = expandedRelativePaths.filter {
                $0 != removed && !$0.hasPrefix("\(removed)/")
            }
            for loaded in Array(childrenByDirectory.keys)
            where loaded == removed || loaded.hasPrefix("\(removed)/") {
                childrenByDirectory.removeValue(forKey: loaded)
            }
        }
        let files = Set(
            childrenByDirectory.values.flatMap(\.nodes).map(\.relativePath)
        )
        if let selectedRelativePath, !files.contains(selectedRelativePath) {
            self.selectedRelativePath = nil
        }
    }

    private static func clampedWidth(_ width: Double) -> Double {
        min(
            max(width, FolderNavigatorMetrics.minimumWidth),
            FolderNavigatorMetrics.maximumWidth
        )
    }
}
