import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.userContentController.add(context.coordinator, name: "scrollHandler")

        let scrollJS = """
        window.addEventListener('scroll', function() {
            var maxScroll = document.body.scrollHeight - window.innerHeight;
            if (maxScroll > 0) {
                var fraction = window.scrollY / maxScroll;
                window.webkit.messageHandlers.scrollHandler.postMessage(fraction);
            }
        });
        """
        let script = WKUserScript(source: scrollJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.pendingScrollFraction = scrollFraction
        context.coordinator.lastText = text
        context.coordinator.lastAppearance = appearanceMode
        context.coordinator.lastZoom = zoomLevel
        applyAppearance(to: webView)
        webView.pageZoom = zoomLevel
        loadContent(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let needsReload = coordinator.lastText != text
            || coordinator.lastAppearance != appearanceMode
            || coordinator.lastZoom != zoomLevel

        coordinator.pendingScrollFraction = scrollFraction

        if needsReload {
            coordinator.lastText = text
            coordinator.lastAppearance = appearanceMode
            coordinator.lastZoom = zoomLevel
            applyAppearance(to: webView)
            webView.pageZoom = zoomLevel
            loadContent(into: webView)
        } else if scrollSource == .editor {
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
        var lastAppearance: AppearanceMode = .system
        var lastZoom: Double = 1.0
        var isSyncing = false

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let fraction = pendingScrollFraction
            let js = "window.scrollTo(0, \(fraction) * (document.body.scrollHeight - window.innerHeight));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isSyncing, let fraction = message.body as? Double else { return }
            parent.scrollSource = .preview
            parent.scrollFraction = min(max(CGFloat(fraction), 0), 1)
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

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        html = html
            .replacingOccurrences(of: "{{MARKED_JS}}", with: markedJS)
            .replacingOccurrences(of: "{{MARKDOWN_CONTENT}}", with: escaped)

        webView.loadHTMLString(html, baseURL: templateURL.deletingLastPathComponent())
    }
}
