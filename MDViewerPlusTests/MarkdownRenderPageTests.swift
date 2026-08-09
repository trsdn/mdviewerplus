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

    func testFootnotesAlertsTasksOutlineAndCodeControls() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            # Hello World
            # Hello World

            > [!WARNING]
            > Take care.

            - [x] Complete

            ```swift
            let value = 42
            ```

            Reference[^1].

            [^1]: Footnote body.
            """,
            in: webView
        )

        let result = try await values(
            """
            ({
              firstSlug: document.querySelector('h1')?.id || '',
              secondSlug: document.querySelectorAll('h1')[1]?.id || '',
              alerts: document.querySelectorAll('.md-alert-warning').length,
              disabledTasks: document.querySelectorAll(
                '.md-task-item input[type="checkbox"][disabled]'
              ).length,
              codeControls: document.querySelectorAll('.md-code-toolbar').length,
              footnotes: document.querySelectorAll('.md-footnotes').length,
              backrefs: document.querySelectorAll('.md-footnote-backref').length,
              outline: window.mdviewerOutline().length
            })
            """,
            in: webView
        )

        XCTAssertEqual(result["firstSlug"] as? String, "hello-world")
        XCTAssertEqual(result["secondSlug"] as? String, "hello-world-1")
        XCTAssertEqual(int(result, "alerts"), 1)
        XCTAssertEqual(int(result, "disabledTasks"), 1)
        XCTAssertEqual(int(result, "codeControls"), 1)
        XCTAssertEqual(int(result, "footnotes"), 1)
        XCTAssertGreaterThanOrEqual(int(result, "backrefs"), 1)
        XCTAssertGreaterThanOrEqual(int(result, "outline"), 2)
    }

    func testImageViewerUsesOnlySanitizedLocalImage() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            ![local](image.png)
            ![remote](https://example.com/image.png)
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
              const images = document.querySelectorAll('#content img');
              images[0].click();
              return {
                images: images.length,
                viewer: document.querySelectorAll('.md-image-viewer').length,
                viewerSource: document.querySelector('.md-image-full')
                  ?.getAttribute('src') || ''
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(int(result, "images"), 2)
        XCTAssertEqual(int(result, "viewer"), 1)
        XCTAssertEqual(result["viewerSource"] as? String, "image.png")
    }

    func testEditionSpecificHighlightingAndLazyModules() async throws {
        let webView = try await loadRenderPage()
        let before = try await values(
            """
            ({
              edition: window.mdviewerCapabilities().edition,
              loaded: Object.keys(window.__mdviewerLoadedModules || {}).length
            })
            """,
            in: webView
        )
        XCTAssertEqual(
            before["edition"] as? String,
            EditionCapabilities.current.edition.rawValue
        )
        XCTAssertEqual(int(before, "loaded"), 0)

        try await render(
            """
            ```swift
            let greeting = "hello"
            ```
            """,
            in: webView
        )

        if EditionCapabilities.current.edition == .lite {
            let tokens = try await webView.evaluateJavaScript(
                "document.querySelectorAll('.md-code .token').length"
            ) as? NSNumber
            XCTAssertGreaterThan(tokens?.intValue ?? 0, 0)
        } else {
            try await waitUntil(
                "window.__mdviewerLoadedModules.highlight === true",
                in: webView
            )
            let moduleError = try await webView.evaluateJavaScript(
                "window.__mdviewerModuleErrors.highlight || ''"
            ) as? String
            XCTAssertEqual(moduleError, "", moduleError ?? "Unknown error")
            let highlighted = try await webView.evaluateJavaScript(
                "document.querySelectorAll('.md-code .hljs').length"
            ) as? NSNumber
            XCTAssertEqual(highlighted?.intValue, 1)
        }
    }

    func testFullModuleSchemeImportsAllowlistedModule() async throws {
        guard EditionCapabilities.current.edition == .full else {
            throw XCTSkip("Full-only module test")
        }
        let webView = try await loadRenderPage()
        let hooks = try await values(
            """
            ({
              frontmatter: typeof window.__mdviewerReadFrontmatter,
              highlight: typeof window.__mdviewerHighlightBlocks,
              mermaid: typeof window.__mdviewerRenderDiagrams
            })
            """,
            in: webView
        )
        XCTAssertEqual(hooks["frontmatter"] as? String, "function")
        XCTAssertEqual(hooks["highlight"] as? String, "function")
        XCTAssertEqual(hooks["mermaid"] as? String, "function")
        let result = try await webView.callAsyncJavaScript(
            """
            try {
              const module = await import(
                window.__mdviewerModuleBase + 'js-yaml.esm.min.mjs'
              );
              return typeof module.load === 'function' ? 'ok' : 'missing export';
            } catch (error) {
              return String(error && (error.stack || error.message || error));
            }
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        XCTAssertEqual(result, "ok", result ?? "No module result")
    }

    func testFullFrontmatterIsLazyAndRejectsUnsafeTags() async throws {
        guard EditionCapabilities.current.edition == .full else {
            throw XCTSkip("Full-only frontmatter test")
        }

        let webView = try await loadRenderPage()
        try await render(
            """
            ---
            title: Safe title
            tags:
              - one
              - two
            ---
            # Body
            """,
            in: webView
        )
        try await waitUntil(
            "window.__mdviewerLoadedModules.yaml === true",
            in: webView
        )
        let moduleError = try await webView.evaluateJavaScript(
            "window.__mdviewerModuleErrors.yaml || ''"
        ) as? String
        XCTAssertEqual(moduleError, "", moduleError ?? "Unknown error")
        var result = try await values(
            """
            ({
              cards: document.querySelectorAll('.md-frontmatter').length,
              title: document.querySelector('.md-frontmatter dd')?.textContent || '',
              rawDelimiter: document.getElementById('content').textContent.includes('---'),
              body: document.querySelectorAll('h1').length
            })
            """,
            in: webView
        )
        XCTAssertEqual(int(result, "cards"), 1)
        XCTAssertEqual(result["title"] as? String, "Safe title")
        XCTAssertFalse(bool(result, "rawDelimiter"))
        XCTAssertEqual(int(result, "body"), 1)

        try await render(
            """
            ---
            payload: !!js/function "function() { return 1; }"
            ---
            Safe body
            """,
            in: webView
        )
        result = try await values(
            """
            ({
              errors: document.querySelectorAll('.md-inline-error').length,
              body: document.getElementById('content').textContent.includes('Safe body')
            })
            """,
            in: webView
        )
        XCTAssertEqual(int(result, "errors"), 1)
        XCTAssertTrue(bool(result, "body"))

        try await render(
            """
            ---
            shared: &items
              - one
            repeated: *items
            ---
            Alias body
            """,
            in: webView
        )
        result = try await values(
            """
            ({
              errors: document.querySelectorAll('.md-inline-error').length,
              body: document.getElementById('content').textContent.includes(
                'Alias body'
              )
            })
            """,
            in: webView
        )
        XCTAssertEqual(int(result, "errors"), 1)
        XCTAssertTrue(bool(result, "body"))
    }

    func testFullMermaidLoadsOnlyForDiagramAndSanitizesSVG() async throws {
        guard EditionCapabilities.current.edition == .full else {
            throw XCTSkip("Full-only Mermaid test")
        }
        let webView = try await loadRenderPage()
        try await render(
            """
            ```mermaid
            flowchart LR
              A[Start] --> B[Done]
            ```
            """,
            in: webView
        )
        _ = try await webView.callAsyncJavaScript(
            "return await window.waitForResources(15000);",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let result = try await values(
            """
            ({
              mermaidLoaded: window.__mdviewerLoadedModules.mermaid === true,
              panZoomLoaded: window.__mdviewerLoadedModules.panZoom === true,
              diagrams: document.querySelectorAll(
                '.md-diagram[data-md-diagram="rendered"] svg'
              ).length,
              scripts: document.querySelectorAll('.md-diagram script').length,
              handlers: document.querySelectorAll(
                '.md-diagram [onclick],.md-diagram [onload]'
              ).length,
              foreignObjects: document.querySelectorAll(
                '.md-diagram foreignObject'
              ).length
            })
            """,
            in: webView
        )
        XCTAssertTrue(bool(result, "mermaidLoaded"))
        XCTAssertTrue(bool(result, "panZoomLoaded"))
        XCTAssertEqual(int(result, "diagrams"), 1)
        XCTAssertEqual(int(result, "scripts"), 0)
        XCTAssertEqual(int(result, "handlers"), 0)
        XCTAssertEqual(int(result, "foreignObjects"), 0)
    }

    private func loadRenderPage(
        configuration: WKWebViewConfiguration? = nil,
        baseURL: URL? = nil
    ) async throws -> WKWebView {
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if configuration == nil {
            config.setURLSchemeHandler(
                MarkdownResourceSchemeHandler(authorizedRoot: nil),
                forURLScheme: MarkdownResourceResolver.scheme
            )
        }
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
                    baseURL: baseURL ?? MarkdownResourceResolver.baseURL
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

    private func waitUntil(
        _ expression: String,
        in webView: WKWebView,
        attempts: Int = 100
    ) async throws {
        for _ in 0..<attempts {
            if try await webView.evaluateJavaScript(expression) as? Bool == true {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for \(expression)")
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
