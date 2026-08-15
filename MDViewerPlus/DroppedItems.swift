import Foundation

/// Pure classification of a Finder drop into Markdown files, folders and
/// rejected items, kept free of AppKit so it can be unit tested.
enum DroppedItems {
    struct Classification: Equatable {
        var markdownFiles: [URL] = []
        var folders: [URL] = []
        var unsupported: [URL] = []
    }

    /// - Parameter isDirectory: Returns `true` for a folder, `false` for a
    ///   file and `nil` when the item does not exist.
    static func classify(
        _ urls: [URL],
        isDirectory: (URL) -> Bool?
    ) -> Classification {
        var result = Classification()
        var seenFiles: Set<URL> = []
        var seenFolders: Set<URL> = []

        for url in urls {
            guard let directory = isDirectory(url) else {
                result.unsupported.append(url)
                continue
            }

            let canonical = MarkdownFileCatalog.canonical(url)

            if directory {
                if seenFolders.insert(canonical).inserted {
                    result.folders.append(url)
                }
            } else if MarkdownFileCatalog.isSupportedMarkdownFile(url) {
                if seenFiles.insert(canonical).inserted {
                    result.markdownFiles.append(url)
                }
            } else {
                result.unsupported.append(url)
            }
        }

        return result
    }

    static func rejectionMessage(for unsupported: [URL]) -> String {
        let extensions = MarkdownFileCatalog.supportedExtensions
            .sorted()
            .map { ".\($0)" }
            .joined(separator: ", ")

        guard let first = unsupported.first else {
            return "Drop a Markdown file (\(extensions)) or a folder."
        }

        if unsupported.count == 1 {
            return "“\(first.lastPathComponent)” is not a Markdown file. "
                + "Drop a Markdown file (\(extensions)) or a folder."
        }

        return "None of the \(unsupported.count) dropped items is a Markdown "
            + "file. Drop a Markdown file (\(extensions)) or a folder."
    }
}
