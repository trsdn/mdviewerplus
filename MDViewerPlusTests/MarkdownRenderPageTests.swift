import WebKit
import XCTest
@testable import MDViewerPlus

@MainActor
final class MarkdownRenderPageTests: XCTestCase {
    func testExecutableHTMLIsRemoved() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            <script>window.__owned = true</script>
            <img src="https://example.com/tracker.png" onerror="window.__owned = true">
            <svg onload="window.__owned = true"><circle></circle></svg>
            <a href="javascript:window.__owned = true">bad</a>
            """,
            in: webView
        )

        let result = try await values(
            """
            ({
                executed: window.__owned === true,
                scripts: document.querySelectorAll('#content script').length,
                svgs: document.querySelectorAll('#content svg').length,
                eventAttributes: document.querySelectorAll('#content [onerror], #content [onload]').length,
                remoteImageKept: document.querySelector('#content img')?.hasAttribute('src') === true,
                unsafeLinkKept: document.querySelector('#content a')?.hasAttribute('href') === true
            })
            """,
            in: webView
        )

        XCTAssertFalse(bool(result, "executed"))
        XCTAssertEqual(int(result, "scripts"), 0)
        XCTAssertEqual(int(result, "svgs"), 0)
        XCTAssertEqual(int(result, "eventAttributes"), 0)
        XCTAssertFalse(bool(result, "remoteImageKept"))
        XCTAssertFalse(bool(result, "unsafeLinkKept"))
    }

    func testApprovedGitHubStyleHTMLIsPreserved() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            <details open><summary>More</summary>H<sub>2</sub>O and x<sup>2</sup></details>

            - [x] Complete

            | Name | Value |
            | --- | --- |
            | A | B |
            """,
            in: webView
        )

        let result = try await values(
            """
            ({
                details: document.querySelectorAll('#content details[open]').length,
                summary: document.querySelectorAll('#content summary').length,
                sub: document.querySelectorAll('#content sub').length,
                sup: document.querySelectorAll('#content sup').length,
                tables: document.querySelectorAll('#content table').length,
                checkboxType: document.querySelector('#content input')?.type || '',
                checkboxDisabled: document.querySelector('#content input')?.disabled === true,
                checkboxChecked: document.querySelector('#content input')?.checked === true
            })
            """,
            in: webView
        )

        XCTAssertEqual(int(result, "details"), 1)
        XCTAssertEqual(int(result, "summary"), 1)
        XCTAssertEqual(int(result, "sub"), 1)
        XCTAssertEqual(int(result, "sup"), 1)
        XCTAssertEqual(int(result, "tables"), 1)
        XCTAssertEqual(result["checkboxType"] as? String, "checkbox")
        XCTAssertTrue(bool(result, "checkboxDisabled"))
        XCTAssertTrue(bool(result, "checkboxChecked"))
    }

    func testOnlyExternalLinksAndRelativeResourcesSurvive() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            [web](https://example.com) [mail](mailto:test@example.com) [local](docs/next.md)

            ![remote](https://example.com/image.png)
            ![local image](images/image.png)
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
                const anchors = Object.fromEntries(
                    Array.from(document.querySelectorAll('#content a'))
                        .map((anchor) => [anchor.textContent, anchor.getAttribute('href')])
                );
                const images = Object.fromEntries(
                    Array.from(document.querySelectorAll('#content img'))
                        .map((image) => [image.getAttribute('alt'), image.getAttribute('src')])
                );
                return {
                    web: anchors.web,
                    mail: anchors.mail,
                    local: anchors.local,
                    remoteImage: images.remote,
                    localImage: images['local image']
                };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["web"] as? String, "https://example.com")
        XCTAssertEqual(result["mail"] as? String, "mailto:test@example.com")
        XCTAssertEqual(result["local"] as? String, "docs/next.md")
        XCTAssertTrue(result["remoteImage"] is NSNull)
        XCTAssertEqual(result["localImage"] as? String, "images/image.png")
    }

    func testAuthorizedRelativeImageLoadsThroughCustomScheme() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let png = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        try png.write(to: rootURL.appendingPathComponent("pixel.png"))

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(
            MarkdownResourceSchemeHandler(authorizedRoot: rootURL),
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let webView = try await loadRenderPage(
            configuration: config,
            baseURL: MarkdownResourceResolver.baseURL
        )
        try await render("![pixel](pixel.png)", in: webView)

        var loaded = false
        for _ in 0..<20 {
            loaded = try await webView.evaluateJavaScript(
                "document.querySelector('#content img')?.naturalWidth === 1"
            ) as? Bool == true
            if loaded { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(loaded)
    }

    func testThemeUpdateChangesCSSWithoutRenderingOrReplacingContent() async throws {
        let webView = try await loadRenderPage()
        try await render("# Preserved\n\nCurrent content", in: webView)
        let before = try await values(
            """
            ({
                html: document.getElementById('content').innerHTML,
                renders: window.markdownRenderCount,
                scrollX: window.scrollX,
                scrollY: window.scrollY
            })
            """,
            in: webView
        )

        let palette = ThemeRegistry.palette(
            id: ThemeID.dracula.rawValue,
            category: .dark
        )
        let applied = try await applyTheme(palette, in: webView)
        let after = try await values(
            """
            ({
                html: document.getElementById('content').innerHTML,
                renders: window.markdownRenderCount,
                background: getComputedStyle(document.documentElement)
                    .getPropertyValue('--color-bg').trim(),
                selection: getComputedStyle(document.documentElement)
                    .getPropertyValue('--color-selection-bg').trim(),
                colorScheme: document.documentElement.style.colorScheme,
                scrollX: window.scrollX,
                scrollY: window.scrollY
            })
            """,
            in: webView
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(after["html"] as? String, before["html"] as? String)
        XCTAssertEqual(int(after, "renders"), int(before, "renders"))
        XCTAssertEqual(after["background"] as? String, "#282a36")
        XCTAssertEqual(after["selection"] as? String, "#44475a")
        XCTAssertEqual(after["colorScheme"] as? String, "dark")
        XCTAssertEqual(int(after, "scrollX"), int(before, "scrollX"))
        XCTAssertEqual(int(after, "scrollY"), int(before, "scrollY"))
    }

    func testPrintModeKeepsDedicatedPaletteIsolatedFromScreenTheme() async throws {
        let webView = try await loadRenderPage()
        let screenPalette = ThemeRegistry.palette(
            id: ThemeID.nord.rawValue,
            category: .dark
        )
        let applied = try await applyTheme(screenPalette, in: webView)
        XCTAssertTrue(applied)

        try await render("# Print colors", printMode: true, in: webView)
        var colors = try await computedThemeColors(in: webView)
        XCTAssertEqual(colors["background"] as? String, "#ffffff")
        XCTAssertEqual(colors["foreground"] as? String, "#24292f")
        XCTAssertEqual(colors["codeBackground"] as? String, "#f6f8fa")

        try await render("# Screen colors", printMode: false, in: webView)
        colors = try await computedThemeColors(in: webView)
        XCTAssertEqual(colors["background"] as? String, "#2e3440")
        XCTAssertEqual(colors["foreground"] as? String, "#eceff4")
        XCTAssertEqual(colors["codeBackground"] as? String, "#3b4252")
    }

    private func loadRenderPage(
        configuration: WKWebViewConfiguration? = nil,
        baseURL: URL? = nil
    ) async throws -> WKWebView {
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        try await withCheckedThrowingContinuation { continuation in
            waiter.completion = { result in
                continuation.resume(with: result)
            }

            do {
                webView.loadHTMLString(
                    try MarkdownRenderPage.makeHTML(),
                    baseURL: baseURL
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return webView
    }

    private func render(
        _ markdown: String,
        printMode: Bool = false,
        in webView: WKWebView
    ) async throws {
        _ = try await webView.callAsyncJavaScript(
            "return window.renderMarkdown(markdown, printMode);",
            arguments: ["markdown": markdown, "printMode": printMode],
            in: nil,
            contentWorld: .page
        )
    }

    private func applyTheme(
        _ palette: ThemePalette,
        in webView: WKWebView
    ) async throws -> Bool {
        try await webView.callAsyncJavaScript(
            "return window.applyTheme(theme);",
            arguments: ["theme": palette.webTheme],
            in: nil,
            contentWorld: .page
        ) as? Bool == true
    }

    private func computedThemeColors(in webView: WKWebView) async throws -> [String: Any] {
        try await values(
            """
            (() => {
                const style = getComputedStyle(document.documentElement);
                return {
                    background: style.getPropertyValue('--color-bg').trim(),
                    foreground: style.getPropertyValue('--color-fg').trim(),
                    codeBackground: style.getPropertyValue('--color-code-bg').trim()
                };
            })()
            """,
            in: webView
        )
    }

    private func values(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func bool(_ values: [String: Any], _ key: String) -> Bool {
        (values[key] as? NSNumber)?.boolValue == true
    }

    private func int(_ values: [String: Any], _ key: String) -> Int {
        (values[key] as? NSNumber)?.intValue ?? -1
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, Error>) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion?(.success(()))
        completion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        completion?(.failure(error))
        completion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        completion?(.failure(error))
        completion = nil
    }
}
