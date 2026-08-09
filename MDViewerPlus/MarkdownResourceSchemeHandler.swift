import Foundation
import UniformTypeIdentifiers
import WebKit

final class MarkdownResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var rootURL: URL?

    init(authorizedRoot: URL?) {
        rootURL = authorizedRoot
    }

    var authorizedRoot: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return rootURL
        }
        set {
            lock.lock()
            rootURL = newValue
            lock.unlock()
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard urlSchemeTask.request.httpMethod == nil
                    || urlSchemeTask.request.httpMethod == "GET",
                  let requestURL = urlSchemeTask.request.url else {
                throw MarkdownResourceError.invalidPath
            }

            if MarkdownModuleResolver.isModuleURL(requestURL) {
                let module = try MarkdownModuleResolver.resolve(requestURL)
                let data = try Data(
                    contentsOf: module.fileURL,
                    options: .mappedIfSafe
                )
                let response = URLResponse(
                    url: requestURL,
                    mimeType: "text/javascript",
                    expectedContentLength: module.byteCount,
                    textEncodingName: "utf-8"
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                return
            }

            let fileURL = try MarkdownResourceResolver.resolve(
                requestURL,
                under: authorizedRoot
            )
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ])
            guard values.isRegularFile == true else {
                throw CocoaError(.fileReadNoSuchFile)
            }

            let mimeType = try safeMIMEType(for: fileURL)
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: values.fileSize ?? data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func safeMIMEType(for fileURL: URL) throws -> String {
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image),
              type != .svg,
              let mimeType = type.preferredMIMEType else {
            throw MarkdownResourceError.unsupportedType
        }
        return mimeType
    }
}
