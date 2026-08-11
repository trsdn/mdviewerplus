import Foundation

enum FolderNavigatorNodeKind: String, Equatable {
    case directory
    case file
}

struct FolderNavigatorNode: Identifiable, Equatable {
    let id: String
    let name: String
    let relativePath: String
    let kind: FolderNavigatorNodeKind
    let depth: Int
    let isExpandable: Bool
    var isTruncated: Bool
}

struct FolderNavigatorChildren: Equatable {
    let relativeDirectory: String
    let nodes: [FolderNavigatorNode]
    let isTruncated: Bool
}

struct FolderNavigatorLimits: Equatable {
    static let standard = FolderNavigatorLimits()

    let maximumDepth: Int
    let maximumChildren: Int
    let maximumLoadedNodes: Int
    let debounceMilliseconds: Int
    let maximumPayloadBytes: Int

    init(
        maximumDepth: Int = 12,
        maximumChildren: Int = 500,
        maximumLoadedNodes: Int = 5_000,
        debounceMilliseconds: Int = 250,
        maximumPayloadBytes: Int = 1_048_576
    ) {
        self.maximumDepth = maximumDepth
        self.maximumChildren = maximumChildren
        self.maximumLoadedNodes = maximumLoadedNodes
        self.debounceMilliseconds = debounceMilliseconds
        self.maximumPayloadBytes = maximumPayloadBytes
    }
}

enum FolderNavigatorError: LocalizedError, Equatable {
    case invalidRelativePath
    case outsideRoot
    case symbolicLink
    case accessDenied
    case movedRoot
    case depthLimit
    case nodeLimit

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath: return "The folder path is invalid."
        case .outsideRoot: return "The item is outside the authorized folder."
        case .symbolicLink: return "Symbolic links are not available in the folder navigator."
        case .accessDenied: return "The folder could not be read."
        case .movedRoot: return "The authorized folder was moved or removed."
        case .depthLimit: return "The navigator’s maximum depth has been reached."
        case .nodeLimit: return "The navigator’s 5,000-item loaded limit has been reached."
        }
    }
}

enum FolderNavigatorMetrics {
    static let defaultWidth: Double = 240
    static let minimumWidth: Double = 180
    static let maximumWidth: Double = 420
    static let shortcut = "Cmd+Shift+B"
}

enum FolderNavigatorRefreshPolicy {
    static func loadedDirectories(
        affectedBy paths: [URL],
        rootURL: URL,
        loadedRelativeDirectories: Set<String>,
        pathExists: (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        }
    ) -> Set<String> {
        var affected: Set<String> = []
        for eventURL in paths {
            guard FolderNavigatorPath.isContained(eventURL, by: rootURL),
                  let relative = FolderNavigatorPath.relativePath(
                    of: eventURL,
                    under: rootURL
                  ) else { continue }
            if loadedRelativeDirectories.contains(relative),
               pathExists(eventURL) {
                affected.insert(relative)
            }

            var parentComponents = relative.split(separator: "/").dropLast()
            var parent = parentComponents.joined(separator: "/")
            guard loadedRelativeDirectories.contains(parent) else { continue }
            while !pathExists(
                parent.isEmpty
                    ? rootURL
                    : rootURL.appendingPathComponent(parent)
            ), !parent.isEmpty {
                parentComponents = parentComponents.dropLast()
                parent = parentComponents.joined(separator: "/")
            }
            if loadedRelativeDirectories.contains(parent) {
                affected.insert(parent)
            }
        }
        return affected
    }
}

enum FolderNavigatorKeyboardSelection {
    static func boundaryPath(_ visiblePaths: [String], first: Bool) -> String? {
        first ? visiblePaths.first : visiblePaths.last
    }
}

enum FolderNavigatorPath {
    static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootComponents = canonical(root).pathComponents
        let candidateComponents = canonical(candidate).pathComponents
        return candidateComponents.count >= rootComponents.count
            && zip(rootComponents, candidateComponents).allSatisfy(==)
    }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func relativePath(of url: URL, under root: URL) -> String? {
        let canonicalRoot = canonical(root)
        let canonicalURL = canonical(url)
        guard isContained(canonicalURL, by: canonicalRoot) else { return nil }
        return canonicalURL.pathComponents
            .dropFirst(canonicalRoot.pathComponents.count)
            .joined(separator: "/")
    }

    static func mostSpecificAncestor(
        of candidate: URL,
        among roots: [URL]
    ) -> URL? {
        roots.map(canonical)
            .filter { isContained(candidate, by: $0) }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }

    static func validatedComponents(_ relativePath: String) throws -> [String] {
        guard !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0") else {
            throw FolderNavigatorError.invalidRelativePath
        }
        if relativePath.isEmpty { return [] }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".."
                && $0.removingPercentEncoding == $0
        }) else {
            throw FolderNavigatorError.invalidRelativePath
        }
        return components
    }
}
