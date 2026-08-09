import Foundation

enum MarkdownRenderPageError: LocalizedError {
    case missingResource(String)
    case unreadableResource(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "The bundled render resource “\(name)” is missing."
        case .unreadableResource(let name, let error):
            return "The bundled render resource “\(name)” couldn’t be read: \(error.localizedDescription)"
        }
    }
}

struct MarkdownRenderPage {
    private struct Resources {
        let template: String
        let styles: String
        let marked: String
        let domPurify: String
        let footnotes: String
        let renderer: String
        let editionRenderer: String

        static func load(
            from bundle: Bundle,
            capabilities: EditionCapabilities
        ) throws -> Resources {
            let editionDirectory = capabilities.edition.displayName
            let editionFile = capabilities.prism ? "prism-lite.min" : "full"
            let editionExtension = capabilities.prism ? "js" : "js"

            return Resources(
                template: try read(
                    "template",
                    extension: "html",
                    subdirectory: "Common",
                    from: bundle
                ),
                styles: try read(
                    "styles",
                    extension: "css",
                    subdirectory: "Common",
                    from: bundle
                ),
                marked: try read(
                    "marked.min",
                    extension: "js",
                    subdirectory: "Common",
                    from: bundle
                ),
                domPurify: try read(
                    "dompurify.min",
                    extension: "js",
                    subdirectory: "Common",
                    from: bundle
                ),
                footnotes: try read(
                    "marked-footnote.min",
                    extension: "js",
                    subdirectory: "Common",
                    from: bundle
                ),
                renderer: try read(
                    "render",
                    extension: "js",
                    subdirectory: "Common",
                    from: bundle
                ),
                editionRenderer: try read(
                    editionFile,
                    extension: editionExtension,
                    subdirectory: editionDirectory,
                    from: bundle
                )
            )
        }

        private static func read(
            _ name: String,
            extension fileExtension: String,
            subdirectory: String,
            from bundle: Bundle
        ) throws -> String {
            let displayName = "\(subdirectory)/\(name).\(fileExtension)"
            guard let url = bundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: subdirectory
            ) else {
                throw MarkdownRenderPageError.missingResource(displayName)
            }

            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw MarkdownRenderPageError.unreadableResource(
                    displayName,
                    error
                )
            }
        }
    }

    private static let cachedResources = Result {
        try Resources.load(
            from: .main,
            capabilities: EditionCapabilities.current
        )
    }

    static func makeHTML() throws -> String {
        let resources = try cachedResources.get()
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        return resources.template
            .replacingOccurrences(of: "{{CSP_NONCE}}", with: nonce)
            .replacingOccurrences(
                of: "{{EDITION}}",
                with: EditionCapabilities.current.edition.rawValue
            )
            .replacingOccurrences(
                of: "{{MODULE_BASE}}",
                with: MarkdownModuleResolver.baseURL.absoluteString
            )
            .replacingOccurrences(of: "{{STYLES_CSS}}", with: resources.styles)
            .replacingOccurrences(of: "{{MARKED_JS}}", with: resources.marked)
            .replacingOccurrences(
                of: "{{DOMPURIFY_JS}}",
                with: resources.domPurify
            )
            .replacingOccurrences(
                of: "{{FOOTNOTE_JS}}",
                with: resources.footnotes
            )
            .replacingOccurrences(
                of: "{{EDITION_JS}}",
                with: resources.editionRenderer
            )
            .replacingOccurrences(
                of: "{{RENDER_JS}}",
                with: resources.renderer
            )
    }
}
