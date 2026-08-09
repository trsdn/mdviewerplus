import Foundation

enum BuildEdition: String, CaseIterable, Sendable {
    case lite
    case full

    var displayName: String {
        switch self {
        case .lite: return "Lite"
        case .full: return "Full"
        }
    }
}

struct EditionCapabilities: Equatable, Sendable {
    let edition: BuildEdition
    let prism: Bool
    let broadHighlighting: Bool
    let frontmatter: Bool
    let mermaid: Bool

    var bundledModules: Bool {
        broadHighlighting || frontmatter || mermaid
    }

    static let lite = EditionCapabilities(
        edition: .lite,
        prism: true,
        broadHighlighting: false,
        frontmatter: false,
        mermaid: false
    )

    static let full = EditionCapabilities(
        edition: .full,
        prism: false,
        broadHighlighting: true,
        frontmatter: true,
        mermaid: true
    )

    #if MDVIEWER_FULL
    static let current = EditionCapabilities.full
    #else
    static let current = EditionCapabilities.lite
    #endif
}

enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "0"
    }

    static var edition: BuildEdition {
        guard let raw = Bundle.main.object(
            forInfoDictionaryKey: "MDViewerEdition"
        ) as? String,
              let edition = BuildEdition(rawValue: raw.lowercased()) else {
            return EditionCapabilities.current.edition
        }
        return edition
    }

    static var summary: String {
        "MDViewer+ \(edition.displayName) \(marketingVersion) (\(buildVersion))"
    }
}
