import Foundation

enum MarkdownResourceError: LocalizedError, Equatable {
    case invalidScheme
    case invalidHost
    case invalidPath
    case traversal
    case outsideAuthorizedRoot
    case unavailableRoot
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "The resource URL uses an unsupported scheme."
        case .invalidHost:
            return "The resource URL has an invalid host."
        case .invalidPath:
            return "The resource URL has an invalid path."
        case .traversal:
            return "The resource path attempts to leave the authorized folder."
        case .outsideAuthorizedRoot:
            return "The resource resolves outside the authorized folder."
        case .unavailableRoot:
            return "The document folder has not been authorized."
        case .unsupportedType:
            return "The local resource type is not supported."
        }
    }
}

struct MarkdownResourceResolver {
    static let scheme = "mdviewerplus-resource"
    static let host = "document"
    static let baseURL = URL(string: "\(scheme)://\(host)/")!

    static func resolve(_ resourceURL: URL, under authorizedRoot: URL?) throws -> URL {
        guard resourceURL.scheme?.lowercased() == scheme else {
            throw MarkdownResourceError.invalidScheme
        }
        guard resourceURL.host?.lowercased() == host else {
            throw MarkdownResourceError.invalidHost
        }
        guard resourceURL.query == nil, resourceURL.fragment == nil else {
            throw MarkdownResourceError.invalidPath
        }
        guard let authorizedRoot else {
            throw MarkdownResourceError.unavailableRoot
        }

        guard let encodedPath = URLComponents(
            url: resourceURL,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath,
              let decodedPath = encodedPath.removingPercentEncoding,
              !decodedPath.contains("\0") else {
            throw MarkdownResourceError.invalidPath
        }

        let components = decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            throw MarkdownResourceError.invalidPath
        }
        guard !components.contains("..") else {
            throw MarkdownResourceError.traversal
        }

        let canonicalRoot = authorizedRoot.standardizedFileURL.resolvingSymlinksInPath()
        var target = canonicalRoot
        for component in components where component != "." {
            target.appendPathComponent(component)
        }
        let canonicalTarget = target.standardizedFileURL.resolvingSymlinksInPath()

        let rootComponents = canonicalRoot.pathComponents
        let targetComponents = canonicalTarget.pathComponents
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            throw MarkdownResourceError.outsideAuthorizedRoot
        }

        return canonicalTarget
    }
}
