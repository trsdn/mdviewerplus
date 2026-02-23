import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource
    var onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController.add(context.coordinator, name: "focusHandler")

        let injectedJS = """
        window.addEventListener('scroll', function() {
            var maxScroll = document.body.scrollHeight - window.innerHeight;
            if (maxScroll > 0) {
                var fraction = window.scrollY / maxScroll;
                window.webkit.messageHandlers.scrollHandler.postMessage(fraction);
            }
        });
        window.addEventListener('mousedown', function() {
            window.webkit.messageHandlers.focusHandler.postMessage(true);
        });
        """
        let script = WKUserScript(source: injectedJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.pendingScrollFraction = scrollFraction
        context.coordinator.lastText = text
        context.coordinator.lastFileURL = fileURL
        context.coordinator.lastAppearance = appearanceMode
        context.coordinator.lastZoom = zoomLevel
        applyAppearance(to: webView)
        webView.pageZoom = zoomLevel
        loadContent(into: webView)
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollHandler")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "focusHandler")
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let needsReload = coordinator.lastText != text
            || coordinator.lastFileURL != fileURL
            || coordinator.lastAppearance != appearanceMode
            || coordinator.lastZoom != zoomLevel

        coordinator.pendingScrollFraction = scrollFraction

        if needsReload {
            coordinator.lastText = text
            coordinator.lastFileURL = fileURL
            coordinator.lastAppearance = appearanceMode
            coordinator.lastZoom = zoomLevel
            applyAppearance(to: webView)
            webView.pageZoom = zoomLevel
            loadContent(into: webView)
        } else if scrollSource == .editor, coordinator.lastSyncedFraction != scrollFraction {
            coordinator.lastSyncedFraction = scrollFraction
            let fraction = scrollFraction
            let js = "window.scrollTo(0, \(fraction) * (document.body.scrollHeight - window.innerHeight));"
            coordinator.isSyncing = true
            webView.evaluateJavaScript(js) { _, _ in
                DispatchQueue.main.async {
                    coordinator.isSyncing = false
                }
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        var pendingScrollFraction: CGFloat = 0
        var lastText: String = ""
        var lastFileURL: URL?
        var lastAppearance: AppearanceMode = .system
        var lastZoom: Double = 1.0
        var isSyncing = false
        var lastSyncedFraction: CGFloat = -1

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let fraction = pendingScrollFraction
            let js = "window.scrollTo(0, \(fraction) * (document.body.scrollHeight - window.innerHeight));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "focusHandler" {
                parent.onFocus?()
                return
            }
            guard !isSyncing, let fraction = message.body as? Double else { return }
            parent.onFocus?()
            parent.scrollSource = .preview
            parent.scrollFraction = min(max(CGFloat(fraction), 0), 1)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func applyAppearance(to webView: WKWebView) {
        switch appearanceMode {
        case .system:
            webView.appearance = nil
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func loadContent(into webView: WKWebView) {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "html"),
              let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
              var html = try? String(contentsOf: templateURL, encoding: .utf8),
              let markedJS = try? String(contentsOf: markedURL, encoding: .utf8)
        else { return }

        let jsonData = try? JSONSerialization.data(withJSONObject: text)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        html = html
            .replacingOccurrences(of: "{{MARKED_JS}}", with: markedJS)
            .replacingOccurrences(of: "{{MARKDOWN_CONTENT}}", with: jsonString)

        if let fileDir = fileURL?.deletingLastPathComponent() {
            // Inject <base> so relative image paths resolve against the markdown file's directory
            html = html.replacingOccurrences(
                of: "<head>",
                with: "<head>\n<base href=\"\(fileDir.absoluteString)\">"
            )
            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mdviewerplus-preview.html")
            try? html.write(to: tempFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempFile, allowingReadAccessTo: fileDir)
        } else {
            webView.loadHTMLString(html, baseURL: templateURL.deletingLastPathComponent())
        }
    }
}
