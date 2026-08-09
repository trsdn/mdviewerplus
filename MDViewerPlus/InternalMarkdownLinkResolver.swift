import Foundation

enum InternalMarkdownLinkError: LocalizedError, Equatable {
    case malformed
    case emptyPath
    case notRelative
    case unsupportedQuery
    case traversal
    case unsupportedExtension
    case outsideAuthorizedRoot
    case notARegularFile

    var errorDescription: String? {
        switch self {
        case .malformed:
            return "The Markdown link could not be decoded."
        case .emptyPath:
            return "The Markdown link does not name a file."
        case .notRelative:
            return "Only relative Markdown links can be opened internally."
        case .unsupportedQuery:
            return "Queries are not supported in internal Markdown links."
        case .traversal:
            return "The Markdown link attempts to leave the authorized folder."
        case .unsupportedExtension:
            return "The link is not a supported Markdown document."
        case .outsideAuthorizedRoot:
            return "The link resolves outside the authorized folder."
        case .notARegularFile:
            return "The linked Markdown document is unavailable."
        }
    }
}

struct InternalMarkdownLink: Equatable {
    let fileURL: URL
    let fragment: String?
}

@MainActor
final class PendingDocumentFragmentStore {
    static let shared = PendingDocumentFragmentStore()

    private var fragments: [String: String] = [:]

    func store(fragment: String, for fileURL: URL) {
        let decoded = fragment.removingPercentEncoding ?? fragment
        guard !decoded.isEmpty, decoded.utf8.count <= 512 else { return }
        fragments[MarkdownFileCatalog.canonical(fileURL).path] = decoded
    }

    func consume(for fileURL: URL) -> String? {
        fragments.removeValue(
            forKey: MarkdownFileCatalog.canonical(fileURL).path
        )
    }
}

enum InternalMarkdownLinkResolver {
    static let maximumRawLength = 2048

    static func relativeLink(from resourceURL: URL) throws -> String {
        guard resourceURL.scheme?.lowercased()
                == MarkdownResourceResolver.scheme,
              resourceURL.host?.lowercased()
                == MarkdownResourceResolver.host,
              resourceURL.query == nil,
              let components = URLComponents(
                url: resourceURL,
                resolvingAgainstBaseURL: false
              ) else {
            throw InternalMarkdownLinkError.malformed
        }

        var result = String(
            components.percentEncodedPath.drop(while: { $0 == "/" })
        )
        if let fragment = components.percentEncodedFragment {
            result += "#\(fragment)"
        }
        return result
    }

    static func resolve(
        rawLink: String,
        documentURL: URL,
        authorizedRoot: URL,
        fileManager: FileManager = .default
    ) throws -> InternalMarkdownLink {
        guard !rawLink.isEmpty,
              rawLink.utf16.count <= maximumRawLength else {
            throw InternalMarkdownLinkError.malformed
        }

        let pieces = rawLink.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let rawPath = String(pieces[0])
        let fragment = pieces.count == 2 && !pieces[1].isEmpty
            ? String(pieces[1]).removingPercentEncoding
            : nil

        guard !rawPath.isEmpty else {
            throw InternalMarkdownLinkError.emptyPath
        }
        guard !rawPath.contains("?") else {
            throw InternalMarkdownLinkError.unsupportedQuery
        }
        guard !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("\\"),
              !rawPath.contains("\\"),
              !rawPath.contains(":") else {
            throw InternalMarkdownLinkError.notRelative
        }
        guard let decodedPath = rawPath.removingPercentEncoding,
              !decodedPath.isEmpty,
              !decodedPath.contains("\0"),
              !decodedPath.hasPrefix("/"),
              !decodedPath.contains("\\") else {
            throw InternalMarkdownLinkError.malformed
        }

        let rawComponents = rawPath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        let components = decodedPath.split(
            separator: "/",
            omittingEmptySubsequences: true
        ).map(String.init)
        guard !components.isEmpty else {
            throw InternalMarkdownLinkError.emptyPath
        }
        guard !rawComponents.contains(".."), !components.contains("..") else {
            throw InternalMarkdownLinkError.traversal
        }

        let meaningful = components.filter { $0 != "." }
        guard !meaningful.isEmpty else {
            throw InternalMarkdownLinkError.emptyPath
        }

        let canonicalRoot = MarkdownFileCatalog.canonical(authorizedRoot)
        let documentFolder = MarkdownFileCatalog.canonical(
            documentURL.deletingLastPathComponent()
        )
        guard contains(documentFolder, in: canonicalRoot) else {
            throw InternalMarkdownLinkError.outsideAuthorizedRoot
        }

        var target = documentFolder
        for component in meaningful {
            target.appendPathComponent(component)
        }
        let canonicalTarget = MarkdownFileCatalog.canonical(target)
        guard contains(canonicalTarget, in: canonicalRoot) else {
            throw InternalMarkdownLinkError.outsideAuthorizedRoot
        }
        guard MarkdownFileCatalog.isSupportedMarkdownFile(canonicalTarget) else {
            throw InternalMarkdownLinkError.unsupportedExtension
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: canonicalTarget.path,
            isDirectory: &isDirectory
        ),
              !isDirectory.boolValue,
              let values = try? canonicalTarget.resourceValues(
                forKeys: [.isRegularFileKey]
              ),
              values.isRegularFile == true else {
            throw InternalMarkdownLinkError.notARegularFile
        }
        return InternalMarkdownLink(
            fileURL: canonicalTarget,
            fragment: fragment
        )
    }

    private static func contains(_ url: URL, in root: URL) -> Bool {
        if url == root { return true }
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        return urlComponents.count > rootComponents.count
            && Array(urlComponents.prefix(rootComponents.count))
                == rootComponents
    }
}
