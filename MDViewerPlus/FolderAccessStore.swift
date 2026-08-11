import AppKit
import Foundation

enum FolderAccessError: LocalizedError {
    case wrongFolder
    case accessDenied
    case symbolicLink

    var errorDescription: String? {
        switch self {
        case .wrongFolder:
            return "Choose this document’s folder or one of its parent folders."
        case .accessDenied:
            return "macOS did not grant access to the selected folder."
        case .symbolicLink:
            return "Symbolic links cannot be used as navigator roots."
        }
    }
}

enum FolderAccessPurpose: Equatable {
    case relativeResources
    case siblingNavigation
    case navigationTools
    case folderNavigator

    func panelMessage(for documentURL: URL) -> String {
        switch self {
        case .relativeResources:
            return "Choose the folder containing \(documentURL.lastPathComponent) to load relative images and open relative links."
        case .siblingNavigation:
            return "Choose the folder containing \(documentURL.lastPathComponent) to navigate between Markdown files."
        case .navigationTools:
            return "Choose the folder containing \(documentURL.lastPathComponent) to use Quick Open, the folder watcher, and internal Markdown links."
        case .folderNavigator:
            return "Choose this document’s folder or a parent folder to browse Markdown files."
        }
    }
}

enum FolderAccessTrigger {
    case documentPreflight
    case explicitNavigation
    case relativeResourceRequest
}

enum FolderAccessAuthorizationDecision: Equatable {
    case useRestoredAccess
    case unavailable
    case requestAccess
}

struct FolderAccessAuthorizationPolicy {
    static func decision(
        for trigger: FolderAccessTrigger,
        hasRestoredAccess: Bool
    ) -> FolderAccessAuthorizationDecision {
        if hasRestoredAccess {
            return .useRestoredAccess
        }

        switch trigger {
        case .documentPreflight:
            return .unavailable
        case .explicitNavigation, .relativeResourceRequest:
            return .requestAccess
        }
    }

    static func navigationAvailable(afterAccessWasGranted granted: Bool) -> Bool {
        granted
    }
}

final class FolderAccessLease {
    let rootURL: URL
    private let securityScopedURL: URL
    private let isAccessing: Bool

    init(securityScopedURL: URL, rootURL: URL) throws {
        self.securityScopedURL = securityScopedURL
        self.rootURL = rootURL
        isAccessing = securityScopedURL.startAccessingSecurityScopedResource()
        guard isAccessing else {
            throw FolderAccessError.accessDenied
        }
    }

#if DEBUG
    init(testingRootURL: URL) {
        securityScopedURL = testingRootURL
        rootURL = FolderNavigatorPath.canonical(testingRootURL)
        isAccessing = false
    }
#endif

    deinit {
        if isAccessing {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }
}

@MainActor
final class FolderAccessStore {
    static let shared = FolderAccessStore()

    private let defaults: UserDefaults
    private let bookmarksKey = "authorizedDocumentFolderBookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoredAccess(for documentURL: URL) throws -> FolderAccessLease? {
        let expectedRoot = canonicalFolder(for: documentURL)
        let savedBookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var validBookmarks: [Data] = []
        var matchingAccess: FolderAccessLease?

        for bookmark in savedBookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let metadata = try url.resourceValues(forKeys: [
                    .isSymbolicLinkKey
                ])
                guard metadata.isSymbolicLink != true else { continue }
                let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
                var retainedBookmark = bookmark

                if canonicalURL == expectedRoot {
                    let access = try FolderAccessLease(
                        securityScopedURL: url,
                        rootURL: canonicalURL
                    )
                    if isStale {
                        retainedBookmark = try url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    }
                    matchingAccess = access
                }
                validBookmarks.append(retainedBookmark)
            } catch {
                continue
            }
        }

        if validBookmarks.count != savedBookmarks.count
            || !zip(validBookmarks, savedBookmarks).allSatisfy({ $0 == $1 }) {
            defaults.set(validBookmarks, forKey: bookmarksKey)
        }

        return matchingAccess
    }

    func restoredNavigatorAccess(
        forDocumentContainedBy documentURL: URL,
        preferredRoot: URL? = nil
    ) throws -> FolderAccessLease? {
#if DEBUG
        if let testingRoot = UITestHooks.authorizedFolderURL,
           (preferredRoot == nil
                || FolderNavigatorPath.canonical(preferredRoot!) == testingRoot),
           FolderNavigatorPath.isContained(
                canonicalFolder(for: documentURL),
                by: testingRoot
           ) {
            return FolderAccessLease(testingRootURL: testingRoot)
        }
#endif
        let documentFolder = canonicalFolder(for: documentURL)
        let preferred = preferredRoot.map(FolderNavigatorPath.canonical)
        let savedBookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var validBookmarks: [Data] = []
        var candidates: [(URL, URL, Data, Bool)] = []

        for bookmark in savedBookmarks {
            do {
                var isStale = false
                let scopedURL = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let metadata = try scopedURL.resourceValues(forKeys: [
                    .isSymbolicLinkKey
                ])
                guard metadata.isSymbolicLink != true else { continue }
                let root = FolderNavigatorPath.canonical(scopedURL)
                var retained = bookmark
                if isStale {
                    retained = try scopedURL.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                validBookmarks.append(retained)
                if FolderNavigatorPath.isContained(documentFolder, by: root),
                   preferred == nil || preferred == root {
                    candidates.append((root, scopedURL, retained, isStale))
                }
            } catch {
                continue
            }
        }
        if validBookmarks != savedBookmarks {
            defaults.set(validBookmarks, forKey: bookmarksKey)
        }

        guard let match = candidates.max(by: {
            $0.0.pathComponents.count < $1.0.pathComponents.count
        }) else { return nil }
        return try FolderAccessLease(
            securityScopedURL: match.1,
            rootURL: match.0
        )
    }

    func requestAccess(
        for documentURL: URL,
        purpose: FolderAccessPurpose,
        attachedTo window: NSWindow?
    ) async throws -> FolderAccessLease? {
        let expectedRoot = canonicalFolder(for: documentURL)
#if DEBUG
        if purpose == .folderNavigator,
           let testingRoot = UITestHooks.authorizedFolderURL {
            guard FolderNavigatorPath.isContained(expectedRoot, by: testingRoot)
            else {
                throw FolderAccessError.wrongFolder
            }
            return FolderAccessLease(testingRootURL: testingRoot)
        }
#endif
        let panel = NSOpenPanel()
        panel.title = "Grant Folder Access"
        panel.message = purpose.panelMessage(for: documentURL)
        panel.prompt = "Grant Access"
        panel.directoryURL = expectedRoot
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        let response = await panelResponse(panel, attachedTo: window)
        guard response == .OK, let selectedURL = panel.url else { return nil }

        let selectedValues = try selectedURL.resourceValues(forKeys: [
            .isSymbolicLinkKey, .isDirectoryKey
        ])
        guard selectedValues.isSymbolicLink != true else {
            throw FolderAccessError.symbolicLink
        }
        let canonicalSelection = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        let isAllowed = purpose == .folderNavigator
            ? FolderNavigatorPath.isContained(expectedRoot, by: canonicalSelection)
            : canonicalSelection == expectedRoot
        guard isAllowed, selectedValues.isDirectory == true else {
            throw FolderAccessError.wrongFolder
        }

        let access = try FolderAccessLease(
            securityScopedURL: selectedURL,
            rootURL: canonicalSelection
        )
        let bookmark = try selectedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try save(bookmark: bookmark, for: canonicalSelection)
        return access
    }

    private func canonicalFolder(for documentURL: URL) -> URL {
        documentURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func panelResponse(
        _ panel: NSOpenPanel,
        attachedTo window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            } else {
                continuation.resume(returning: panel.runModal())
            }
        }
    }

    private func save(bookmark: Data, for rootURL: URL) throws {
        let existing = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var retained: [Data] = []

        for data in existing {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }

            if url.standardizedFileURL.resolvingSymlinksInPath() != rootURL {
                retained.append(data)
            }
        }

        retained.append(bookmark)
        defaults.set(retained, forKey: bookmarksKey)
    }
}
