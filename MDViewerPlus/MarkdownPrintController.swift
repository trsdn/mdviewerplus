import Combine
import PDFKit
import WebKit

enum MarkdownPrintError: LocalizedError {
    case alreadyPrinting
    case invalidContentHeight
    case emptyDocument
    case invalidPDFPage
    case missingPrintOperation

    var errorDescription: String? {
        switch self {
        case .alreadyPrinting:
            return "A print job is already being prepared."
        case .invalidContentHeight:
            return "The printable document height couldn’t be determined."
        case .emptyDocument:
            return "The printable document is empty."
        case .invalidPDFPage:
            return "A printable PDF page couldn’t be decoded."
        case .missingPrintOperation:
            return "No printable PDF pages were produced."
        }
    }
}

@MainActor
final class MarkdownPrintController: NSObject, ObservableObject, WKNavigationDelegate {
    typealias PrintRunner = (PDFDocument) throws -> Void

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842

    private static let pageBreakJavaScript = """
        (function() {
            const PAGE_HEIGHT = \(pageHeight);
            for (let pass = 0; pass < 5; pass++) {
                const elements = document.querySelectorAll('#content > *');
                let changed = false;
                for (const element of elements) {
                    const rect = element.getBoundingClientRect();
                    if (rect.height === 0) continue;
                    const startPage = Math.floor(rect.top / PAGE_HEIGHT);
                    const endPage = Math.floor((rect.bottom - 1) / PAGE_HEIGHT);
                    if (startPage !== endPage && rect.height < PAGE_HEIGHT * 0.8) {
                        const nextPageTop = (startPage + 1) * PAGE_HEIGHT;
                        const shift = nextPageTop - rect.top;
                        const current = parseFloat(
                            getComputedStyle(element).marginTop
                        ) || 0;
                        element.style.marginTop = (current + shift) + 'px';
                        changed = true;
                    }
                }
                if (!changed) break;
            }
            return document.body.scrollHeight;
        })()
        """

    private let printRunner: PrintRunner
    private var webView: WKWebView?
    private var markdown = ""
    private var errorHandler: ((String) -> Void)?

    override init() {
        printRunner = Self.runPrintPanel
        super.init()
    }

    init(printRunner: @escaping PrintRunner) {
        self.printRunner = printRunner
        super.init()
    }

    func print(
        markdown: String,
        resourceRoot: URL?,
        onError: @escaping (String) -> Void
    ) {
        guard webView == nil else {
            onError(MarkdownPrintError.alreadyPrinting.localizedDescription)
            return
        }

        do {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.setURLSchemeHandler(
                MarkdownResourceSchemeHandler(authorizedRoot: resourceRoot),
                forURLScheme: MarkdownResourceResolver.scheme
            )

            let webView = WKWebView(
                frame: CGRect(
                    x: 0,
                    y: 0,
                    width: Self.pageWidth,
                    height: Self.pageHeight
                ),
                configuration: config
            )
            webView.appearance = NSAppearance(named: .aqua)
            webView.navigationDelegate = self

            self.markdown = markdown
            errorHandler = onError
            self.webView = webView
            webView.loadHTMLString(
                try MarkdownRenderPage.makeHTML(),
                baseURL: MarkdownResourceResolver.baseURL
            )
        } catch {
            fail(error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }

        webView.callAsyncJavaScript(
            """
            await window.renderMarkdown(markdown, true);
            await window.waitForResources();
            return true;
            """,
            arguments: ["markdown": markdown],
            in: nil,
            in: .page
        ) { [weak self, weak webView] result in
            guard let self, let webView else { return }

            switch result {
            case .success:
                self.preparePages(in: webView)
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        fail(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail(error)
    }

    private func preparePages(in webView: WKWebView) {
        webView.evaluateJavaScript(Self.pageBreakJavaScript) { [weak self, weak webView] value, error in
            guard let self, let webView else { return }

            if let error {
                self.fail(error)
                return
            }
            guard let number = value as? NSNumber else {
                self.fail(MarkdownPrintError.invalidContentHeight)
                return
            }

            let contentHeight = CGFloat(truncating: number)
            guard contentHeight > 0 else {
                self.fail(MarkdownPrintError.emptyDocument)
                return
            }

            self.capturePages(
                in: webView,
                pageIndex: 0,
                pageCount: Int(ceil(contentHeight / Self.pageHeight)),
                document: PDFDocument()
            )
        }
    }

    private func capturePages(
        in webView: WKWebView,
        pageIndex: Int,
        pageCount: Int,
        document: PDFDocument
    ) {
        guard pageIndex < pageCount else {
            finish(with: document)
            return
        }

        let config = WKPDFConfiguration()
        config.rect = CGRect(
            x: 0,
            y: CGFloat(pageIndex) * Self.pageHeight,
            width: Self.pageWidth,
            height: Self.pageHeight
        )

        webView.createPDF(configuration: config) { [weak self, weak webView] result in
            DispatchQueue.main.async {
                guard let self, let webView else { return }

                switch result {
                case .success(let data):
                    guard let pageDocument = PDFDocument(data: data),
                          let page = pageDocument.page(at: 0) else {
                        self.fail(MarkdownPrintError.invalidPDFPage)
                        return
                    }
                    document.insert(page, at: document.pageCount)
                    self.capturePages(
                        in: webView,
                        pageIndex: pageIndex + 1,
                        pageCount: pageCount,
                        document: document
                    )
                case .failure(let error):
                    self.fail(error)
                }
            }
        }
    }

    private func finish(with document: PDFDocument) {
        guard document.pageCount > 0 else {
            fail(MarkdownPrintError.missingPrintOperation)
            return
        }

        let handler = errorHandler
        reset()
        do {
            try printRunner(document)
        } catch {
            handler?(error.localizedDescription)
        }
    }

    private func fail(_ error: Error) {
        let handler = errorHandler
        reset()
        handler?(error.localizedDescription)
    }

    private func reset() {
        webView?.navigationDelegate = nil
        webView = nil
        markdown = ""
        errorHandler = nil
    }

    private static func runPrintPanel(for document: PDFDocument) throws {
        guard let operation = document.printOperation(
            for: .shared,
            scalingMode: .pageScaleToFit,
            autoRotate: true
        ) else {
            throw MarkdownPrintError.missingPrintOperation
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}
