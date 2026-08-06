import AppKit
import Foundation

enum MarkdownSiblingDirection {
    case previous
    case next
}

struct MarkdownSiblingFiles: Equatable {
    let previous: URL?
    let next: URL?

    static let unavailable = MarkdownSiblingFiles(previous: nil, next: nil)
}

struct SiblingNavigationTargetPolicy {
    static func afterOpenFailure(
        currentTargets: MarkdownSiblingFiles
    ) -> MarkdownSiblingFiles {
        _ = currentTargets
        return .unavailable
    }
}

enum SiblingNavigationFreshnessEvent {
    case reload
    case explicitPreparation
}

enum SiblingNavigationFreshnessAction: Equatable {
    case clearSilently
    case enumerateSilently
    case enumerateReportingErrors
    case requestAuthorization
}

struct SiblingNavigationFreshnessPolicy {
    static func preparationCommandTitle(hasFolderAccess: Bool) -> String {
        hasFolderAccess
            ? "Refresh Sibling Navigation"
            : "Enable Sibling Navigation…"
    }

    static func action(
        for event: SiblingNavigationFreshnessEvent,
        hasFolderAccess: Bool
    ) -> SiblingNavigationFreshnessAction {
        switch (event, hasFolderAccess) {
        case (.reload, false):
            return .clearSilently
        case (.reload, true):
            return .enumerateSilently
        case (.explicitPreparation, false):
            return .requestAuthorization
        case (.explicitPreparation, true):
            return .enumerateReportingErrors
        }
    }
}

extension SiblingNavigationFreshnessAction {
    var reportsErrors: Bool {
        switch self {
        case .enumerateReportingErrors:
            return true
        case .clearSilently, .enumerateSilently, .requestAuthorization:
            return false
        }
    }
}

struct SecurityScopedLeaseLifetime {
    static func retaining<Lease: AnyObject, Result>(
        _ lease: Lease,
        during operation: () async throws -> Result
    ) async rethrows -> Result {
        defer { withExtendedLifetime(lease) {} }
        return try await operation()
    }
}

enum MarkdownSiblingNavigationError: LocalizedError, Equatable {
    case currentFileNotFound

    var errorDescription: String? {
        switch self {
        case .currentFileNotFound:
            return "The current document is not present in its containing folder."
        }
    }
}

struct MarkdownSiblingNavigator {
    static let supportedExtensions = Set(["md", "markdown", "mdown", "mkd"])

    static func siblings(
        of documentURL: URL,
        in authorizedFolderURL: URL,
        fileManager: FileManager = .default
    ) throws -> MarkdownSiblingFiles {
        let folderURL = canonicalURL(authorizedFolderURL)
        let currentURL = canonicalURL(documentURL)
        guard canonicalURL(currentURL.deletingLastPathComponent()) == folderURL else {
            throw MarkdownSiblingNavigationError.currentFileNotFound
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        let markdownFiles = try contents.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  supportedExtensions.contains(url.pathExtension.lowercased())
            else {
                return false
            }

            let values = try url.resourceValues(forKeys: resourceKeys)
            return values.isRegularFile == true
                && values.isHidden != true
                && values.isSymbolicLink != true
        }
        .sorted(by: filenamePrecedes)

        guard let index = markdownFiles.firstIndex(where: {
            canonicalURL($0) == currentURL
        }) else {
            throw MarkdownSiblingNavigationError.currentFileNotFound
        }

        return MarkdownSiblingFiles(
            previous: index > markdownFiles.startIndex
                ? canonicalURL(markdownFiles[index - 1])
                : nil,
            next: index < markdownFiles.index(before: markdownFiles.endIndex)
                ? canonicalURL(markdownFiles[index + 1])
                : nil
        )
    }

    static func destination(
        from documentURL: URL,
        in authorizedFolderURL: URL,
        direction: MarkdownSiblingDirection,
        fileManager: FileManager = .default
    ) throws -> URL? {
        let siblings = try siblings(
            of: documentURL,
            in: authorizedFolderURL,
            fileManager: fileManager
        )
        switch direction {
        case .previous:
            return siblings.previous
        case .next:
            return siblings.next
        }
    }

    static func filenamePrecedes(_ lhs: URL, _ rhs: URL) -> Bool {
        let locale = Locale(identifier: "en_US_POSIX")
        let lhsFolded = lhs.lastPathComponent.folding(
            options: [.caseInsensitive],
            locale: locale
        )
        let rhsFolded = rhs.lastPathComponent.folding(
            options: [.caseInsensitive],
            locale: locale
        )
        let foldedLHS = Array(lhsFolded.utf8)
        let foldedRHS = Array(rhsFolded.utf8)
        if foldedLHS != foldedRHS {
            return foldedLHS.lexicographicallyPrecedes(foldedRHS)
        }

        return Array(lhs.lastPathComponent.utf8).lexicographicallyPrecedes(
            Array(rhs.lastPathComponent.utf8)
        )
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

enum SourceDocumentDisposition: Equatable {
    case keepOpen
    case close
}

struct DocumentOpeningPolicy {
    static func sourceDisposition(
        openSucceeded: Bool,
        hasUnsavedChanges: Bool
    ) -> SourceDocumentDisposition {
        guard openSucceeded, !hasUnsavedChanges else { return .keepOpen }
        return .close
    }

    @MainActor
    static func handleSuccessfulOpen(sourceWindow: NavigationSourceWindow?) {
        guard sourceDisposition(
            openSucceeded: true,
            hasUnsavedChanges: sourceWindow?.isDocumentEdited == true
        ) == .close else {
            return
        }
        sourceWindow?.closeAfterSuccessfulNavigation()
    }
}

protocol NavigationSourceWindow: AnyObject {
    var isDocumentEdited: Bool { get }
    func closeAfterSuccessfulNavigation()
}

extension NSWindow: NavigationSourceWindow {
    func closeAfterSuccessfulNavigation() {
        performClose(nil)
    }
}
