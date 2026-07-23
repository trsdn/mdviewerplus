import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    let resourceRoot: URL?
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource
    var onFocus: (() -> Void)?
    var onError: ((String) -> Void)?
    var onRelativeResources: (([String]) -> Void)?
    var onOpenRelativeLink: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let resourceHandler = MarkdownResourceSchemeHandler(authorizedRoot: resourceRoot)
        config.setURLSchemeHandler(
            resourceHandler,
            forURLScheme: MarkdownResourceResolver.scheme
        )
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController.add(context.coordinator, name: "focusHandler")

        let injectedJS = """
        let programmaticScroll = { generation: null };
        window.mdviewerScrollTo = function(fraction, generation) {
            programmaticScroll.generation = generation;
            window.scrollTo(
                0,
                fraction * (document.body.scrollHeight - window.innerHeight)
            );
            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    if (programmaticScroll.generation === generation) {
                        programmaticScroll.generation = null;
                    }
                });
            });
        };
        window.addEventListener('scroll', function() {
            const maxScroll = document.body.scrollHeight - window.innerHeight;
            if (maxScroll > 0) {
                const generation = programmaticScroll.generation;
                programmaticScroll.generation = null;
                window.webkit.messageHandlers.scrollHandler.postMessage({
                    fraction: window.scrollY / maxScroll,
                    generation: generation
                });
            }
        });
        window.addEventListener('mousedown', function() {
            window.webkit.messageHandlers.focusHandler.postMessage(true);
        });
        """
        config.userContentController.addUserScript(
            WKUserScript(
                source: injectedJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setAccessibilityIdentifier("markdownPreview")
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let coordinator = context.coordinator
        coordinator.webView = webView
        coordinator.resourceHandler = resourceHandler
        coordinator.pendingScrollFraction = scrollFraction
        coordinator.pendingText = text
        coordinator.lastAppearance = appearanceMode
        coordinator.lastZoom = zoomLevel
        coordinator.lastResourceRoot = resourceRoot

        applyAppearance(to: webView)
        webView.pageZoom = zoomLevel
        coordinator.loadRenderPage()
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "scrollHandler"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "focusHandler"
        )
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.pendingScrollFraction = scrollFraction
        if coordinator.lastResourceRoot != resourceRoot {
            coordinator.lastResourceRoot = resourceRoot
            coordinator.resourceHandler?.authorizedRoot = resourceRoot
            coordinator.invalidateRender()
        }

        if coordinator.lastAppearance != appearanceMode {
            coordinator.lastAppearance = appearanceMode
            applyAppearance(to: webView)
        }

        if coordinator.lastZoom != zoomLevel {
            coordinator.lastZoom = zoomLevel
            webView.pageZoom = zoomLevel
        }

        coordinator.requestRender(text)

        if scrollSource == .editor,
           let command = coordinator.scrollSyncState.command(
            forEditorFraction: scrollFraction
           ) {
            coordinator.scrollPreview(using: command)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        var pendingScrollFraction: CGFloat = 0
        var pendingText = ""
        var lastAppearance: AppearanceMode = .system
        var lastZoom: Double = 1.0
        var lastResourceRoot: URL?
        var scrollSyncState = ScrollSyncState()
        weak var webView: WKWebView?
        var resourceHandler: MarkdownResourceSchemeHandler?

        private var isPageReady = false
        private var lastRequestedText: String?
        private var renderGeneration = 0
        private let renderDebouncer = LatestValueDebouncer<String>(delay: 0.15)

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            super.init()
        }

        deinit {
            renderDebouncer.cancel()
        }

        func loadRenderPage() {
            guard let webView else { return }

            do {
                isPageReady = false
                lastRequestedText = nil
                webView.loadHTMLString(
                    try MarkdownRenderPage.makeHTML(),
                    baseURL: MarkdownResourceResolver.baseURL
                )
            } catch {
                report(error)
            }
        }

        func invalidateRender() {
            lastRequestedText = nil
            requestRender(pendingText, immediate: true)
        }

        func requestRender(_ text: String, immediate: Bool = false) {
            pendingText = text
            guard isPageReady,
                  lastRequestedText != text else { return }

            if immediate {
                renderDebouncer.cancel()
                performRender(text)
            } else {
                renderDebouncer.submit(text) { [weak self] latestText in
                    self?.performRender(latestText)
                }
            }
        }

        private func performRender(_ text: String) {
            guard isPageReady,
                  pendingText == text,
                  lastRequestedText != text,
                  let webView else { return }
            lastRequestedText = text
            renderGeneration += 1
            let generation = renderGeneration

            webView.callAsyncJavaScript(
                "return window.renderMarkdown(markdown, false);",
                arguments: ["markdown": text],
                in: nil,
                in: .page
            ) { [weak self, weak webView] result in
                guard let self, generation == self.renderGeneration else { return }

                switch result {
                case .success(let value):
                    self.restoreScroll(in: webView)
                    if let values = value as? [String: Any],
                       let resources = values["resources"] as? [String],
                       !resources.isEmpty {
                        self.parent.onRelativeResources?(resources)
                    }
                case .failure(let error):
                    self.lastRequestedText = nil
                    self.report(error)
                }
            }
        }

        func scrollPreview(using command: PreviewScrollCommand) {
            guard let webView else { return }

            let js = """
            window.mdviewerScrollTo(\(command.fraction), \(command.generation));
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func restoreScroll(in webView: WKWebView?) {
            guard webView === self.webView,
                  let command = scrollSyncState.command(
                    forEditorFraction: pendingScrollFraction,
                    force: true
                  ) else { return }
            scrollPreview(using: command)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === self.webView else { return }
            isPageReady = true
            lastRequestedText = nil
            requestRender(pendingText, immediate: true)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "focusHandler" {
                parent.onFocus?()
                return
            }

            guard let payload = message.body as? [String: Any],
                  let fraction = (payload["fraction"] as? NSNumber)?.doubleValue else {
                return
            }
            let generation = (payload["generation"] as? NSNumber)?.intValue
            guard scrollSyncState.shouldAcceptPreviewScroll(generation: generation) else {
                return
            }
            parent.onFocus?()
            parent.scrollSource = .preview
            parent.scrollFraction = min(max(CGFloat(fraction), 0), 1)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    openLink(url)
                }
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame == true,
               let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme != "about",
               scheme != MarkdownResourceResolver.scheme {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                openLink(url)
            }
            return nil
        }

        private func openLink(_ url: URL) {
            if url.scheme?.lowercased() == MarkdownResourceResolver.scheme {
                parent.onOpenRelativeLink?(url)
                return
            }

            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        }

        private func report(_ error: Error) {
            report(error.localizedDescription)
        }

        private func report(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onError?(message)
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
}
