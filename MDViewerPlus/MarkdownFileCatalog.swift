import Foundation

enum MarkdownFileCatalog {
    static let supportedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd"
    ]

    static func isSupportedMarkdownFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func files(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isHiddenKey, .isRegularFileKey, .isSymbolicLinkKey
        ]
        let entries = try fileManager.contentsOfDirectory(
            at: canonical(directoryURL),
            includingPropertiesForKeys: Array(keys),
            options: [
                .skipsHiddenFiles,
                .skipsSubdirectoryDescendants,
                .skipsPackageDescendants
            ]
        )

        return try entries.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  isSupportedMarkdownFile(url) else {
                return false
            }
            let values = try url.resourceValues(forKeys: keys)
            return values.isRegularFile == true
                && values.isHidden != true
                && values.isSymbolicLink != true
        }
        .map(canonical)
        .sorted(by: filenamePrecedes)
    }

    static func filenamePrecedes(_ lhs: URL, _ rhs: URL) -> Bool {
        let locale = Locale(identifier: "en_US_POSIX")
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent
        let lhsFolded = Array(
            lhsName.folding(options: [.caseInsensitive], locale: locale).utf8
        )
        let rhsFolded = Array(
            rhsName.folding(options: [.caseInsensitive], locale: locale).utf8
        )
        if lhsFolded != rhsFolded {
            return lhsFolded.lexicographicallyPrecedes(rhsFolded)
        }
        return lhsName.utf8.lexicographicallyPrecedes(rhsName.utf8)
    }
}
