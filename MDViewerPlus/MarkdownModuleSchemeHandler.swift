import Foundation
import WebKit

enum MarkdownModuleError: LocalizedError, Equatable {
    case unavailable
    case invalidURL
    case unknownModule
    case unreadableModule

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This edition does not bundle web modules."
        case .invalidURL:
            return "The module URL is invalid."
        case .unknownModule:
            return "The requested module is not allowlisted."
        case .unreadableModule:
            return "The bundled module could not be read."
        }
    }
}

struct ResolvedMarkdownModule {
    let fileURL: URL
    let byteCount: Int
}

enum MarkdownModuleResolver {
    static let pathPrefix = "/__mdviewer__/module/"
    static let baseURL = URL(
        string: "\(MarkdownResourceResolver.scheme)://\(MarkdownResourceResolver.host)\(pathPrefix)"
    )!

    private static let allowlist: Set<String> = loadAllowlist()

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path.count <= 512,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        return path.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "."
                || $0 == "-" || $0 == "_" || $0 == "/"
        }
    }

    static func resolve(
        _ requestURL: URL,
        bundle: Bundle = .main,
        allowedPaths: Set<String>? = nil
    ) throws -> ResolvedMarkdownModule {
        guard EditionCapabilities.current.bundledModules else {
            throw MarkdownModuleError.unavailable
        }
        guard requestURL.scheme?.lowercased()
                == MarkdownResourceResolver.scheme,
              requestURL.host?.lowercased()
                == MarkdownResourceResolver.host,
              requestURL.query == nil,
              requestURL.fragment == nil,
              requestURL.user == nil,
              requestURL.password == nil,
              requestURL.port == nil,
              let encodedPath = URLComponents(
                url: requestURL,
                resolvingAgainstBaseURL: false
              )?.percentEncodedPath,
              let decodedPath = encodedPath.removingPercentEncoding else {
            throw MarkdownModuleError.invalidURL
        }

        guard decodedPath.hasPrefix(pathPrefix) else {
            throw MarkdownModuleError.invalidURL
        }
        let relativePath = String(
            decodedPath.dropFirst(pathPrefix.count)
        )
        guard isSafeRelativePath(relativePath),
              (allowedPaths ?? allowlist).contains(relativePath) else {
            throw MarkdownModuleError.unknownModule
        }

        guard let root = bundle.url(
            forResource: "modules",
            withExtension: nil,
            subdirectory: "Full"
        ) else {
            throw MarkdownModuleError.unreadableModule
        }

        var fileURL = root
        for component in relativePath.split(separator: "/") {
            fileURL.appendPathComponent(String(component))
        }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = canonicalRoot.pathComponents
        let fileComponents = canonicalFile.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count))
                == rootComponents,
              let values = try? canonicalFile.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              let byteCount = values.fileSize else {
            throw MarkdownModuleError.unreadableModule
        }
        return ResolvedMarkdownModule(
            fileURL: canonicalFile,
            byteCount: byteCount
        )
    }

    static func isModuleURL(_ requestURL: URL) -> Bool {
        requestURL.scheme?.lowercased() == MarkdownResourceResolver.scheme
            && requestURL.host?.lowercased() == MarkdownResourceResolver.host
            && requestURL.path.hasPrefix(pathPrefix)
    }

    private static func loadAllowlist(bundle: Bundle = .main) -> Set<String> {
        guard EditionCapabilities.current.bundledModules,
              let url = bundle.url(
                forResource: "module-allowlist",
                withExtension: "json",
                subdirectory: "Full"
              ),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let modules = object["modules"] as? [[String: Any]] else {
            return []
        }
        return Set(
            modules.compactMap {
                guard let path = $0["path"] as? String,
                      isSafeRelativePath(path) else { return nil }
                return path
            }
        )
    }
}
