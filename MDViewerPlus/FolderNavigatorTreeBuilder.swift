import Foundation

enum FolderNavigatorTreeBuilder {
    static func children(
        rootURL: URL,
        relativeDirectory: String,
        depth: Int,
        limits: FolderNavigatorLimits = .standard,
        fileManager: FileManager = .default,
        candidateCountObserver: ((Int) -> Void)? = nil
    ) throws -> FolderNavigatorChildren {
        guard depth >= 0, depth < limits.maximumDepth else {
            throw FolderNavigatorError.depthLimit
        }
        let components = try FolderNavigatorPath.validatedComponents(
            relativeDirectory
        )
        guard components.count == depth else {
            throw FolderNavigatorError.invalidRelativePath
        }

        let root = FolderNavigatorPath.canonical(rootURL)
        var directory = root
        for component in components {
            guard !component.hasPrefix(".") else {
                throw FolderNavigatorError.accessDenied
            }
            let unresolved = directory.appendingPathComponent(
                component,
                isDirectory: true
            )
            let metadata = try unresolved.resourceValues(forKeys: [
                .isSymbolicLinkKey, .isDirectoryKey, .isHiddenKey,
                .isPackageKey
            ])
            guard metadata.isHidden != true, metadata.isPackage != true else {
                throw FolderNavigatorError.accessDenied
            }
            guard metadata.isSymbolicLink != true else {
                throw FolderNavigatorError.symbolicLink
            }
            directory = FolderNavigatorPath.canonical(unresolved)
            guard FolderNavigatorPath.isContained(directory, by: root),
                  metadata.isDirectory == true else {
                throw FolderNavigatorError.outsideRoot
            }
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isHiddenKey,
            .isSymbolicLinkKey, .isPackageKey
        ]
        var enumerationError: Error?
        guard let entries = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [
                .skipsHiddenFiles,
                .skipsSubdirectoryDescendants,
                .skipsPackageDescendants
            ],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw FolderNavigatorError.accessDenied
        }

        var candidates: [(URL, FolderNavigatorNodeKind)] = []
        var qualifyingCount = 0
        while let unresolved = entries.nextObject() as? URL {
            guard !unresolved.lastPathComponent.hasPrefix(".") else { continue }
            let values = try unresolved.resourceValues(forKeys: keys)
            guard values.isHidden != true,
                  values.isSymbolicLink != true,
                  values.isPackage != true else { continue }

            let kind: FolderNavigatorNodeKind
            if values.isDirectory == true {
                kind = .directory
            } else if values.isRegularFile == true,
                      MarkdownFileCatalog.supportedExtensions.contains(
                        unresolved.pathExtension.lowercased()
                      ) {
                kind = .file
            } else {
                continue
            }

            let canonical = FolderNavigatorPath.canonical(unresolved)
            guard FolderNavigatorPath.isContained(canonical, by: root) else {
                continue
            }
            qualifyingCount += 1
            if candidates.count < limits.maximumChildren {
                candidates.append((canonical, kind))
            } else if limits.maximumChildren > 0 {
                let greatest = candidates.indices.max {
                    candidatePrecedes(candidates[$0], candidates[$1])
                }
                if let greatest,
                   candidatePrecedes((canonical, kind), candidates[greatest]) {
                    candidates[greatest] = (canonical, kind)
                }
            }
            candidateCountObserver?(candidates.count)
        }
        if enumerationError != nil {
            throw FolderNavigatorError.accessDenied
        }

        candidates.sort(by: candidatePrecedes)
        let truncated = qualifyingCount > limits.maximumChildren
        let generation = root.path
        var nodes = candidates.compactMap {
            url, kind -> FolderNavigatorNode? in
            guard let relative = FolderNavigatorPath.relativePath(
                of: url,
                under: root
            ) else { return nil }
            return FolderNavigatorNode(
                id: "\(generation)#\(relative)",
                name: url.lastPathComponent,
                relativePath: relative,
                kind: kind,
                depth: depth + 1,
                isExpandable: kind == .directory
                    && depth + 1 < limits.maximumDepth,
                isTruncated: false
            )
        }
        if truncated, !nodes.isEmpty {
            nodes[nodes.count - 1].isTruncated = true
        }
        return FolderNavigatorChildren(
            relativeDirectory: relativeDirectory,
            nodes: nodes,
            isTruncated: truncated
        )
    }

    private static func candidatePrecedes(
        _ lhs: (URL, FolderNavigatorNodeKind),
        _ rhs: (URL, FolderNavigatorNodeKind)
    ) -> Bool {
        if lhs.1 != rhs.1 { return lhs.1 == .directory }
        return MarkdownFileCatalog.filenamePrecedes(lhs.0, rhs.0)
    }

    static func resolvedMarkdownFile(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        let components = try FolderNavigatorPath.validatedComponents(relativePath)
        guard !components.isEmpty,
              components.count <= FolderNavigatorLimits.standard.maximumDepth
        else { throw FolderNavigatorError.invalidRelativePath }

        let root = FolderNavigatorPath.canonical(rootURL)
        var candidate = root
        for (index, component) in components.enumerated() {
            guard !component.hasPrefix(".") else {
                throw FolderNavigatorError.accessDenied
            }
            let unresolved = candidate.appendingPathComponent(component)
            let values = try unresolved.resourceValues(forKeys: [
                .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey,
                .isHiddenKey, .isPackageKey
            ])
            guard values.isHidden != true, values.isPackage != true else {
                throw FolderNavigatorError.accessDenied
            }
            guard values.isSymbolicLink != true else {
                throw FolderNavigatorError.symbolicLink
            }
            if index < components.count - 1,
               values.isDirectory != true {
                throw FolderNavigatorError.accessDenied
            }
            candidate = FolderNavigatorPath.canonical(unresolved)
            guard FolderNavigatorPath.isContained(candidate, by: root) else {
                throw FolderNavigatorError.outsideRoot
            }
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true,
              MarkdownFileCatalog.supportedExtensions.contains(
                candidate.pathExtension.lowercased()
              ) else {
            throw FolderNavigatorError.accessDenied
        }
        return candidate
    }
}
