import SwiftUI
import WebKit

final class WebThemeApplicationState {
    struct Request: Equatable {
        let generation: Int
        let palette: ThemePalette
    }

    private(set) var desiredPalette: ThemePalette
    private(set) var successfullyAppliedPaletteID: ThemeID?
    private(set) var inFlightGeneration: Int?
    private(set) var inFlightPaletteID: ThemeID?
    private var isPageReady = false
    private var generation = 0
    private var consecutiveFailures = 0

    init(desiredPalette: ThemePalette) {
        self.desiredPalette = desiredPalette
    }

    func pageWillLoad() {
        generation += 1
        isPageReady = false
        successfullyAppliedPaletteID = nil
        inFlightGeneration = nil
        inFlightPaletteID = nil
        consecutiveFailures = 0
    }

    func pageDidBecomeReady() -> Request? {
        isPageReady = true
        successfullyAppliedPaletteID = nil
        inFlightGeneration = nil
        inFlightPaletteID = nil
        consecutiveFailures = 0
        return nextRequest()
    }

    func request(_ palette: ThemePalette) -> Request? {
        if desiredPalette.id != palette.id {
            desiredPalette = palette
            consecutiveFailures = 0
        } else if inFlightGeneration == nil,
                  successfullyAppliedPaletteID != palette.id {
            // A later SwiftUI update retries a previously exhausted request.
            consecutiveFailures = 0
        }
        return nextRequest()
    }

    func complete(
        generation: Int,
        succeeded: Bool
    ) -> (wasCurrent: Bool, next: Request?) {
        guard inFlightGeneration == generation else {
            return (false, nil)
        }

        let completedPaletteID = inFlightPaletteID
        inFlightGeneration = nil
        inFlightPaletteID = nil

        if succeeded {
            successfullyAppliedPaletteID = completedPaletteID
            consecutiveFailures = 0
            return (true, nextRequest())
        }

        guard completedPaletteID == desiredPalette.id,
              successfullyAppliedPaletteID != desiredPalette.id,
              consecutiveFailures == 0 else {
            return (true, nextRequest(allowFailureRetry: false))
        }

        consecutiveFailures = 1
        return (true, nextRequest())
    }

    func isCurrent(_ request: Request) -> Bool {
        inFlightGeneration == request.generation
            && inFlightPaletteID == request.palette.id
    }

    private func nextRequest(allowFailureRetry: Bool = true) -> Request? {
        guard isPageReady,
              inFlightGeneration == nil,
              successfullyAppliedPaletteID != desiredPalette.id,
              allowFailureRetry || consecutiveFailures == 0 else {
            return nil
        }

        generation += 1
        let request = Request(
            generation: generation,
            palette: desiredPalette
        )
        inFlightGeneration = request.generation
        inFlightPaletteID = request.palette.id
        return request
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let fileURL: URL?
    let palette: ThemePalette
    let zoomLevel: Double
    let resourceRoot: URL?
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource
    let findRequest: PreviewFindRequest?
    let outlineRequest: PreviewOutlineRequest?
    var onFocus: (() -> Void)?
    var onError: ((String) -> Void)?
    var onRelativeResources: (([String]) -> Void)?
    var onOutline: (([OutlineEntry]) -> Void)?
    var onFindResult: ((Bool) -> Void)?
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
        config.userContentController.add(context.coordinator, name: "clipboardHandler")

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
        coordinator.lastZoom = zoomLevel
        coordinator.lastResourceRoot = resourceRoot
        coordinator.lastHandledFindID = findRequest?.id
        coordinator.lastHandledOutlineID = outlineRequest?.id

        applyNativeAppearance(to: webView)
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
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "clipboardHandler"
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

        if coordinator.desiredPalette.id != palette.id {
            applyNativeAppearance(to: webView)
        }
        coordinator.requestTheme(palette)

        if coordinator.lastZoom != zoomLevel {
            coordinator.lastZoom = zoomLevel
            webView.pageZoom = zoomLevel
        }

        coordinator.requestRender(text)
        coordinator.handle(findRequest)
        coordinator.handle(outlineRequest)

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
        var lastZoom: Double = 1.0
        var lastResourceRoot: URL?
        var scrollSyncState = ScrollSyncState()
        weak var webView: WKWebView?
        var resourceHandler: MarkdownResourceSchemeHandler?
        var lastHandledFindID: UUID?
        var lastHandledOutlineID: UUID?

        private var isPageReady = false
        private var lastRequestedText: String?
        private var renderGeneration = 0
        private let themeState: WebThemeApplicationState
        private let renderDebouncer = LatestValueDebouncer<String>(delay: 0.15)

        var desiredPalette: ThemePalette {
            themeState.desiredPalette
        }

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            themeState = WebThemeApplicationState(
                desiredPalette: parent.palette
            )
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
                themeState.pageWillLoad()
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

        func requestTheme(_ palette: ThemePalette) {
            if let request = themeState.request(palette) {
                performThemeRequest(request)
            }
        }

        private func performThemeRequest(
            _ request: WebThemeApplicationState.Request,
            after delay: TimeInterval = 0
        ) {
            guard let webView else { return }

            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.themeState.isCurrent(request) else { return }
                    self.performThemeRequest(request)
                }
                return
            }

            webView.callAsyncJavaScript(
                "return window.applyTheme(theme);",
                arguments: ["theme": request.palette.webTheme],
                in: nil,
                in: .page
            ) { [weak self] result in
                guard let self else { return }

                let succeeded: Bool
                let errorMessage: String?
                switch result {
                case .success(let value):
                    succeeded = (value as? Bool) == true
                    errorMessage = succeeded
                        ? nil
                        : "The preview rejected the selected theme."
                case .failure(let error):
                    succeeded = false
                    errorMessage = error.localizedDescription
                }

                let completion = self.themeState.complete(
                    generation: request.generation,
                    succeeded: succeeded
                )
                guard completion.wasCurrent else { return }

                if let next = completion.next {
                    self.performThemeRequest(next, after: succeeded ? 0 : 0.05)
                } else if !succeeded,
                          self.themeState.successfullyAppliedPaletteID
                            != self.themeState.desiredPalette.id,
                          let errorMessage {
                    self.report(errorMessage)
                }
            }
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
                    if let values = value as? [String: Any] {
                        if let resources = values["resources"] as? [String],
                           !resources.isEmpty {
                            self.parent.onRelativeResources?(resources)
                        }
                        if let payload = values["outline"]
                            as? [[String: Any]] {
                            self.parent.onOutline?(
                                payload.compactMap(OutlineEntry.init(payload:))
                            )
                        }
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

        func handle(_ request: PreviewFindRequest?) {
            guard let request,
                  request.id != lastHandledFindID,
                  let webView else { return }
            lastHandledFindID = request.id

            let configuration = WKFindConfiguration()
            configuration.backwards = request.backwards
            configuration.wraps = true
            configuration.caseSensitive = false
            webView.find(
                request.clear ? "" : request.query,
                configuration: configuration
            ) { [weak self] result in
                self?.parent.onFindResult?(
                    request.clear ? false : result.matchFound
                )
            }
        }

        func handle(_ request: PreviewOutlineRequest?) {
            guard let request,
                  request.id != lastHandledOutlineID,
                  let webView else { return }
            lastHandledOutlineID = request.id
            webView.callAsyncJavaScript(
                "return window.mdviewerScrollToSlug(slug);",
                arguments: ["slug": request.slug],
                in: nil,
                in: .page
            ) { [weak self] result in
                if case .failure(let error) = result {
                    self?.report(error)
                }
            }
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
            if let request = themeState.pageDidBecomeReady() {
                performThemeRequest(request)
            }
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
            if message.name == "clipboardHandler" {
                guard let payload = message.body as? [String: Any],
                      let text = payload["text"] as? String,
                      text.utf8.count <= 1_000_000 else {
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
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
                if url.path == "/", let fragment = url.fragment {
                    webView?.callAsyncJavaScript(
                        """
                        const target = document.getElementById(fragment);
                        if (!target) return false;
                        target.scrollIntoView({block: "start"});
                        target.focus({preventScroll: true});
                        return true;
                        """,
                        arguments: ["fragment": fragment],
                        in: nil,
                        in: .page
                    )
                    return
                }
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

    private func applyNativeAppearance(to webView: WKWebView) {
        webView.appearance = palette.category.appearance
        webView.underPageBackgroundColor = palette.colors.background.nsColor
    }
}
