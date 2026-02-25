import SwiftUI
import WebKit
import PDFKit

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
        context.coordinator.webView = webView
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
        weak var webView: WKWebView?
        private var printObserver: NSObjectProtocol?
        private var printWebView: WKWebView?

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            super.init()
            printObserver = NotificationCenter.default.addObserver(
                forName: .printDocument, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let webView = self.webView,
                      webView.window?.isKeyWindow == true else { return }
                self.startPrint()
            }
        }

        deinit {
            if let observer = printObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private static let printPageWidth: CGFloat = 595
        private static let printPageHeight: CGFloat = 842

        private static let printCSS = """
            body { font-size: 12px; line-height: 1.5; padding: 24px 36px; }
            h1 { font-size: 1.8em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
            pre { font-size: 85%; padding: 12px; }
            th, td { padding: 4px 10px; }
            """

        private static let pageBreakJS = """
            (function() {
                const PAGE_HEIGHT = \(printPageHeight);
                for (let pass = 0; pass < 5; pass++) {
                    const elements = document.querySelectorAll('#content > *');
                    let changed = false;
                    for (const el of elements) {
                        const rect = el.getBoundingClientRect();
                        if (rect.height === 0) continue;
                        const startPage = Math.floor(rect.top / PAGE_HEIGHT);
                        const endPage = Math.floor((rect.bottom - 1) / PAGE_HEIGHT);
                        if (startPage !== endPage && rect.height < PAGE_HEIGHT * 0.8) {
                            const nextPageTop = (startPage + 1) * PAGE_HEIGHT;
                            const shift = nextPageTop - rect.top;
                            const current = parseFloat(getComputedStyle(el).marginTop) || 0;
                            el.style.marginTop = (current + shift) + 'px';
                            changed = true;
                        }
                    }
                    if (!changed) break;
                }
                return document.body.scrollHeight;
            })()
            """

        private func startPrint() {
            guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "html"),
                  let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
                  var html = try? String(contentsOf: templateURL, encoding: .utf8),
                  let markedJS = try? String(contentsOf: markedURL, encoding: .utf8)
            else { return }

            let jsonData = try? JSONSerialization.data(withJSONObject: lastText, options: .fragmentsAllowed)
            let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

            html = html
                .replacingOccurrences(of: "{{MARKED_JS}}", with: markedJS)
                .replacingOccurrences(of: "{{MARKDOWN_CONTENT}}", with: jsonString)

            // Inject print-optimized CSS
            html = html.replacingOccurrences(
                of: "</style>",
                with: Self.printCSS + "\n</style>"
            )

            let config = WKWebViewConfiguration()
            let pWebView = WKWebView(
                frame: NSRect(x: 0, y: 0, width: Self.printPageWidth, height: Self.printPageHeight),
                configuration: config
            )
            pWebView.appearance = NSAppearance(named: .aqua)
            pWebView.navigationDelegate = self
            self.printWebView = pWebView

            if let fileDir = lastFileURL?.deletingLastPathComponent() {
                html = html.replacingOccurrences(
                    of: "<head>",
                    with: "<head>\n<base href=\"\(fileDir.absoluteString)\">"
                )
                let tempFile = fileDir.appendingPathComponent(".mdviewerplus-print.html")
                try? html.write(to: tempFile, atomically: true, encoding: .utf8)
                pWebView.loadFileURL(tempFile, allowingReadAccessTo: fileDir)
            } else {
                pWebView.loadHTMLString(html, baseURL: templateURL.deletingLastPathComponent())
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView === printWebView {
                // Adjust content so page breaks fall between elements, then capture
                webView.evaluateJavaScript(Self.pageBreakJS) { [weak self] result, _ in
                    guard let self = self,
                          let contentHeight = result as? CGFloat,
                          contentHeight > 0 else {
                        self?.printWebView = nil
                        return
                    }
                    self.capturePages(webView: webView, contentHeight: contentHeight, pageIndex: 0,
                                      numPages: Int(ceil(contentHeight / Self.printPageHeight)),
                                      accumulated: PDFDocument())
                }
                return
            }

            let fraction = pendingScrollFraction
            let js = "window.scrollTo(0, \(fraction) * (document.body.scrollHeight - window.innerHeight));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func capturePages(webView: WKWebView, contentHeight: CGFloat, pageIndex: Int,
                                   numPages: Int, accumulated: PDFDocument) {
            if pageIndex >= numPages {
                printWebView = nil
                guard accumulated.pageCount > 0,
                      let printOp = accumulated.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: true)
                else { return }
                printOp.showsPrintPanel = true
                printOp.showsProgressPanel = true
                printOp.run()
                return
            }

            let y = CGFloat(pageIndex) * Self.printPageHeight
            let pdfConfig = WKPDFConfiguration()
            pdfConfig.rect = CGRect(x: 0, y: y, width: Self.printPageWidth, height: Self.printPageHeight)

            webView.createPDF(configuration: pdfConfig) { [weak self] result in
                DispatchQueue.main.async {
                    if case .success(let data) = result,
                       let pagePDF = PDFDocument(data: data),
                       let page = pagePDF.page(at: 0) {
                        accumulated.insert(page, at: accumulated.pageCount)
                    }
                    self?.capturePages(webView: webView, contentHeight: contentHeight,
                                       pageIndex: pageIndex + 1, numPages: numPages,
                                       accumulated: accumulated)
                }
            }
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

        let jsonData = try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)
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
            let tempFile = fileDir.appendingPathComponent(".mdviewerplus-preview.html")
            try? html.write(to: tempFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempFile, allowingReadAccessTo: fileDir)
        } else {
            webView.loadHTMLString(html, baseURL: templateURL.deletingLastPathComponent())
        }
    }
}
