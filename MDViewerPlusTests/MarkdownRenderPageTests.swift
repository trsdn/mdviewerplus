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

    func testLiteFrontmatterIsVerbatimAndExcludedFromOutline() async throws {
        guard EditionCapabilities.current.edition == .lite else {
            throw XCTSkip("Lite-only frontmatter test")
        }

        let webView = try await loadRenderPage()
        let markdown = "---\r\ntitle: <b>Literal</b>\r\n# Hidden heading\r\n---\r\n# Visible heading\r\n"
        try await render(markdown, in: webView)

        let result = try await values(
            """
            ({
              rawBlocks: document.querySelectorAll('.md-frontmatter-raw').length,
              rawText: document.querySelector('.md-frontmatter-raw code')?.textContent || '',
              rawElements: document.querySelectorAll('.md-frontmatter-raw b').length,
              headings: Array.from(document.querySelectorAll('#content h1'))
                .map((heading) => heading.textContent),
              rules: document.querySelectorAll('#content hr').length,
              outline: window.mdviewerOutline().map((entry) => entry.title)
            })
            """,
            in: webView
        )

        XCTAssertEqual(int(result, "rawBlocks"), 1)
        XCTAssertEqual(
            result["rawText"] as? String,
            "title: <b>Literal</b>\r\n# Hidden heading\r\n"
        )
        XCTAssertEqual(int(result, "rawElements"), 0)
        XCTAssertEqual(result["headings"] as? [String], ["Visible heading"])
        XCTAssertEqual(int(result, "rules"), 0)
        XCTAssertEqual(result["outline"] as? [String], ["Visible heading"])
    }

    func testTableAlignmentIsConstrainedToSafeCellValues() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            | Left | Center | Right |
            | :--- | :----: | ----: |
            | A | B | C |

            <table><tbody><tr>
            <td align="justify" style="text-align:right">bad</td>
            <td align=" RIGHT ">good</td>
            </tr></tbody></table>

            <div align="center">not a cell</div>
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
              const generated = document.querySelector('table');
              const cells = Array.from(document.querySelectorAll('td'));
              const invalid = cells.find((cell) => cell.textContent === 'bad');
              const normalized = cells.find((cell) => cell.textContent === 'good');
              const nonCell = Array.from(document.querySelectorAll('div'))
                .find((element) => element.textContent === 'not a cell');
              return {
                header: Array.from(generated.querySelectorAll('th'))
                  .map((cell) => cell.getAttribute('align')),
                body: Array.from(generated.querySelectorAll('td'))
                  .map((cell) => cell.getAttribute('align')),
                invalidAlign: invalid?.hasAttribute('align') === true,
                invalidStyle: invalid?.hasAttribute('style') === true,
                normalizedAlign: normalized?.getAttribute('align') || '',
                nonCellAlign: nonCell?.hasAttribute('align') === true
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["header"] as? [String], ["left", "center", "right"])
        XCTAssertEqual(result["body"] as? [String], ["left", "center", "right"])
        XCTAssertFalse(bool(result, "invalidAlign"))
        XCTAssertFalse(bool(result, "invalidStyle"))
        XCTAssertEqual(result["normalizedAlign"] as? String, "right")
        XCTAssertFalse(bool(result, "nonCellAlign"))
    }

    func testPreviewFindCountsOnlyVisibleNonOverlappingRenderedText() async throws {
        let webView = try await loadRenderPage()
        try await render("Al*ph*a ALPHA aaaa", in: webView)

        let result = try await values(
            """
            (() => {
              const content = document.getElementById('content');
              const button = document.createElement('button');
              button.textContent = 'alpha';
              const hidden = document.createElement('span');
              hidden.hidden = true;
              hidden.textContent = 'alpha';
              const ariaHidden = document.createElement('span');
              ariaHidden.setAttribute('aria-hidden', 'true');
              ariaHidden.textContent = 'alpha';
              const script = document.createElement('script');
              script.type = 'application/json';
              script.textContent = 'alpha';
              const style = document.createElement('style');
              style.textContent = '.alpha-test { color: red; }';
              content.append(button, hidden, ariaHidden, script, style);
              return {
                alpha: window.mdviewerCountMatches('alpha'),
                caseInsensitive: window.mdviewerCountMatches('ALPHA'),
                nonOverlapping: window.mdviewerCountMatches('aa'),
                empty: window.mdviewerCountMatches('')
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(int(result, "alpha"), 2)
        XCTAssertEqual(int(result, "caseInsensitive"), 2)
        XCTAssertEqual(int(result, "nonOverlapping"), 2)
        XCTAssertEqual(int(result, "empty"), 0)
    }

    func testTaskCheckboxesUseUniformReadOnlyGeometry() async throws {
        let webView = try await loadRenderPage()
        try await render("- [ ] Open\n- [x] Complete", in: webView)

        let result = try await values(
            """
            (() => {
              const inputs = Array.from(
                document.querySelectorAll('.md-task-item input[type="checkbox"]')
              );
              const styles = inputs.map((input) => getComputedStyle(input));
              return {
                count: inputs.length,
                disabled: inputs.every((input) => input.disabled),
                readonly: inputs.every(
                  (input) => input.getAttribute('aria-readonly') === 'true'
                ),
                labels: inputs.map((input) => input.getAttribute('aria-label')),
                widths: styles.map((style) => style.width),
                heights: styles.map((style) => style.height),
                radii: styles.map((style) => style.borderRadius),
                appearances: styles.map(
                  (style) => style.getPropertyValue('-webkit-appearance')
                ),
                backgrounds: styles.map((style) => style.backgroundColor)
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(int(result, "count"), 2)
        XCTAssertTrue(bool(result, "disabled"))
        XCTAssertTrue(bool(result, "readonly"))
        XCTAssertEqual(
            result["labels"] as? [String],
            ["Incomplete task", "Completed task"]
        )
        XCTAssertEqual(result["widths"] as? [String], ["14px", "14px"])
        XCTAssertEqual(result["heights"] as? [String], ["14px", "14px"])
        XCTAssertEqual(result["radii"] as? [String], ["4px", "4px"])
        XCTAssertEqual(result["appearances"] as? [String], ["none", "none"])
        let backgrounds = try XCTUnwrap(result["backgrounds"] as? [String])
        XCTAssertEqual(backgrounds.count, 2)
        XCTAssertNotEqual(backgrounds[0], backgrounds[1])
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

    func testFootnoteReferenceAndBacklinkNavigateBothDirections() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            Reference[^1].

            [^1]: Footnote body.
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
              const reference = document.querySelector('.md-footnote-ref');
              const backlink = document.querySelector('.md-footnote-backref');
              const forwardTarget = document.querySelector(
                reference?.getAttribute('href') || ''
              );
              const backTarget = document.querySelector(
                backlink?.getAttribute('href') || ''
              );
              return {
                forwardTargetExists: forwardTarget !== null,
                backTargetExists: backTarget !== null,
                forwardLabel: reference?.getAttribute('aria-label') || '',
                backLabel: backlink?.getAttribute('aria-label') || ''
              };
            })()
            """,
            in: webView
        )

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('.md-footnote-ref')?.click()"
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let forwardHash = try await webView.evaluateJavaScript(
            "location.hash"
        ) as? String

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('.md-footnote-backref')?.click()"
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let backHash = try await webView.evaluateJavaScript(
            "location.hash"
        ) as? String

        XCTAssertTrue(forwardHash?.hasPrefix("#footnote-") == true)
        XCTAssertTrue(backHash?.hasPrefix(
            "#footnote-ref-"
        ) == true)
        XCTAssertTrue(bool(result, "forwardTargetExists"))
        XCTAssertTrue(bool(result, "backTargetExists"))
        XCTAssertTrue(
            (result["forwardLabel"] as? String)?.hasPrefix("Footnote") == true
        )
        XCTAssertEqual(result["backLabel"] as? String, "Back to reference")
    }

    func testCodeControlsExposePressedStateAndCopyFeedback() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            ```swift
            let first = 1
            let second = 2
            ```
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
              const wrap = Array.from(document.querySelectorAll('.md-code-button'))
                .find((button) => button.textContent === 'Wrap');
              const lines = Array.from(document.querySelectorAll('.md-code-button'))
                .find((button) => button.textContent === 'Lines');
              const copy = document.querySelector('.md-code-copy');
              wrap.click();
              lines.click();
              copy.click();
              const pressedStyle = getComputedStyle(wrap);
              const separatorStyle = getComputedStyle(copy, '::before');
              return {
                wrapPressed: wrap.getAttribute('aria-pressed'),
                linesPressed: lines.getAttribute('aria-pressed'),
                pressedBackground: pressedStyle.backgroundColor,
                normalBackground: getComputedStyle(copy).backgroundColor,
                copyStatus: document.querySelector('.md-code-status')?.textContent || '',
                separatorWidth: separatorStyle.borderLeftWidth
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["wrapPressed"] as? String, "true")
        XCTAssertEqual(result["linesPressed"] as? String, "true")
        XCTAssertNotEqual(
            result["pressedBackground"] as? String,
            result["normalBackground"] as? String
        )
        XCTAssertEqual(result["copyStatus"] as? String, "Copied")
        XCTAssertEqual(result["separatorWidth"] as? String, "1px")
    }

    func testPreviewPaddingIsSymmetricAcrossRepresentativeWidths() async throws {
        let webView = try await loadRenderPage()
        try await render(
            Array(repeating: "A long line of preview content.", count: 80)
                .joined(separator: "\n\n"),
            in: webView
        )

        for width in [400, 600, 1_200] {
            webView.setFrameSize(NSSize(width: width, height: 500))
            let result = try await values(
                """
                (() => {
                  const body = getComputedStyle(document.body);
                  const root = getComputedStyle(document.documentElement);
                  return {
                    left: Number.parseFloat(body.paddingLeft),
                    right: Number.parseFloat(body.paddingRight),
                    gutter: root.scrollbarGutter
                  };
                })()
                """,
                in: webView
            )

            let left = (result["left"] as? NSNumber)?.doubleValue ?? -1
            let right = (result["right"] as? NSNumber)?.doubleValue ?? -1
            XCTAssertEqual(left, right, accuracy: 0.1, "Width \(width)")
            XCTAssertGreaterThanOrEqual(left, 24, "Width \(width)")
            XCTAssertTrue(
                (result["gutter"] as? String)?.contains("stable") == true,
                "Width \(width)"
            )
        }
    }

    func testEveryThemeUsesItsBackgroundForTheRenderedPage() async throws {
        let webView = try await loadRenderPage()

        for palette in ThemeRegistry.palettes {
            let applied = try await applyTheme(palette, in: webView)
            XCTAssertTrue(applied)
            let result = try await values(
                """
                (() => {
                  const root = getComputedStyle(document.documentElement);
                  const body = getComputedStyle(document.body);
                  return {
                    token: root.getPropertyValue('--color-bg').trim(),
                    rootBackground: root.backgroundColor,
                    bodyBackground: body.backgroundColor
                  };
                })()
                """,
                in: webView
            )
            let expected = cssRGB(palette.colors.background)
            XCTAssertEqual(result["token"] as? String, palette.colors.background.hex)
            XCTAssertEqual(
                result["rootBackground"] as? String,
                expected,
                palette.id.rawValue
            )
            XCTAssertEqual(
                result["bodyBackground"] as? String,
                expected,
                palette.id.rawValue
            )
        }
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
            author: Example
            status: draft
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
              open: document.querySelector('.md-frontmatter')?.open === true,
              preview: document.querySelector('.md-frontmatter-key-preview')
                ?.textContent || '',
              collapsedPreviewVisible: (() => {
                const card = document.querySelector('.md-frontmatter');
                const preview = document.querySelector('.md-frontmatter-key-preview');
                card.open = false;
                return preview ? getComputedStyle(preview).display !== 'none' : false;
              })(),
              title: document.querySelector('.md-frontmatter dd')?.textContent || '',
              rawDelimiter: document.getElementById('content').textContent.includes('---'),
              body: document.querySelectorAll('h1').length,
              outline: window.mdviewerOutline().map((entry) => entry.title)
            })
            """,
            in: webView
        )
        XCTAssertEqual(int(result, "cards"), 1)
        XCTAssertTrue(bool(result, "open"))
        XCTAssertEqual(result["preview"] as? String, "title, tags, author, …")
        XCTAssertTrue(bool(result, "collapsedPreviewVisible"))
        XCTAssertEqual(result["title"] as? String, "Safe title")
        XCTAssertFalse(bool(result, "rawDelimiter"))
        XCTAssertEqual(int(result, "body"), 1)
        XCTAssertEqual(result["outline"] as? [String], ["Body"])

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

    func testFullSwiftConstructorTokenUsesStyledUpstreamClass() async throws {
        guard EditionCapabilities.current.edition == .full else {
            throw XCTSkip("Full-only highlighting test")
        }

        let webView = try await loadRenderPage()
        try await render(
            """
            ```swift
            let view = Widget()
            let explicit = Widget.init()
            ```
            """,
            in: webView
        )
        try await waitUntil(
            "document.querySelectorAll('.md-code .hljs-type').length === 2",
            in: webView
        )

        let result = try await values(
            """
            (() => {
              const constructors = Array.from(
                document.querySelectorAll('.md-code .hljs-type')
              );
              const initializer = Array.from(
                document.querySelectorAll('.md-code .hljs-keyword')
              ).find((element) => element.textContent === 'init');
              return {
                constructorClasses: constructors.map((element) => element.className),
                initializerClass: initializer?.className || '',
                constructorColor: getComputedStyle(constructors[0]).color,
                codeColor: getComputedStyle(constructors[0].parentElement).color
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(
            result["constructorClasses"] as? [String],
            ["hljs-type", "hljs-type"]
        )
        XCTAssertEqual(result["initializerClass"] as? String, "hljs-keyword")
        XCTAssertNotEqual(
            result["constructorColor"] as? String,
            result["codeColor"] as? String
        )
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
            (() => {
              const container = document.querySelector('.md-diagram');
              const stage = container.querySelector('.md-diagram-stage');
              const svg = stage.querySelector('svg');
              const viewport = svg.querySelector('.svg-pan-zoom_viewport');
              const stageRect = stage.getBoundingClientRect();
              const svgRect = svg.getBoundingClientRect();
              const viewportRect = viewport.getBoundingClientRect();
              const buttons = Array.from(
                container.querySelectorAll('.md-diagram-button')
              );
              const panZoom = container.__mdviewerPanZoom;
              const zoomBefore = panZoom.getZoom();
              const panBefore = panZoom.getPan();
              stage.dispatchEvent(new KeyboardEvent('keydown', {
                key: '+',
                bubbles: true
              }));
              stage.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'ArrowRight',
                bubbles: true
              }));
              const panAfter = panZoom.getPan();
              return {
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
                ).length,
                stageHeight: stageRect.height,
                insetLeft: svgRect.left - stageRect.left,
                insetTop: svgRect.top - stageRect.top,
                viewportVisible:
                  viewportRect.left >= svgRect.left - 1 &&
                  viewportRect.top >= svgRect.top - 1 &&
                  viewportRect.right <= svgRect.right + 1 &&
                  viewportRect.bottom <= svgRect.bottom + 1,
                centered:
                  Math.abs(
                    (viewportRect.left + viewportRect.right) / 2 -
                    (svgRect.left + svgRect.right) / 2
                  ) < 2 &&
                  Math.abs(
                    (viewportRect.top + viewportRect.bottom) / 2 -
                    (svgRect.top + svgRect.bottom) / 2
                  ) < 2,
                controlsRole: container.querySelector('.md-diagram-controls')
                  ?.getAttribute('role') || '',
                buttonHeight: buttons[0]?.offsetHeight || 0,
                equalButtonHeights: buttons.length === 3 &&
                  buttons.every((button) => button.offsetHeight === buttons[0].offsetHeight),
                keyboardZoomed: panZoom.getZoom() > zoomBefore,
                keyboardPanned: panAfter.x !== panBefore.x ||
                  panAfter.y !== panBefore.y
              };
            })()
            """,
            in: webView
        )
        XCTAssertTrue(bool(result, "mermaidLoaded"))
        XCTAssertTrue(bool(result, "panZoomLoaded"))
        XCTAssertEqual(int(result, "diagrams"), 1)
        XCTAssertEqual(int(result, "scripts"), 0)
        XCTAssertEqual(int(result, "handlers"), 0)
        XCTAssertEqual(int(result, "foreignObjects"), 0)
        XCTAssertLessThan(
            (result["stageHeight"] as? NSNumber)?.doubleValue ?? .infinity,
            350
        )
        XCTAssertGreaterThanOrEqual(
            (result["insetLeft"] as? NSNumber)?.doubleValue ?? -1,
            23
        )
        XCTAssertGreaterThanOrEqual(
            (result["insetTop"] as? NSNumber)?.doubleValue ?? -1,
            23
        )
        XCTAssertTrue(bool(result, "viewportVisible"))
        XCTAssertTrue(bool(result, "centered"))
        XCTAssertEqual(result["controlsRole"] as? String, "group")
        XCTAssertTrue(bool(result, "equalButtonHeights"))
        XCTAssertEqual(int(result, "buttonHeight"), 28)
        XCTAssertTrue(bool(result, "keyboardZoomed"))
        XCTAssertTrue(bool(result, "keyboardPanned"))
    }

    func testFullPrintMermaidRemainsStaticAndComplete() async throws {
        guard EditionCapabilities.current.edition == .full else {
            throw XCTSkip("Full-only Mermaid print test")
        }

        let webView = try await loadRenderPage()
        try await render(
            """
            ```mermaid
            flowchart TD
              A[Start] --> B[Done]
            ```
            """,
            printMode: true,
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
            (() => {
              const container = document.querySelector('.md-diagram');
              const stage = container.querySelector('.md-diagram-stage');
              const svg = stage.querySelector('svg');
              return {
                rendered: container.getAttribute('data-md-diagram'),
                svgWidth: svg.getBoundingClientRect().width,
                svgHeight: svg.getBoundingClientRect().height,
                controls: container.querySelectorAll('.md-diagram-controls').length,
                panZoomLoaded: window.__mdviewerLoadedModules.panZoom === true,
                fallbackHidden: container.querySelector('.md-diagram-source')?.hidden === true,
                stageOverflow: getComputedStyle(stage).overflow
              };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["rendered"] as? String, "rendered")
        XCTAssertGreaterThan(
            (result["svgWidth"] as? NSNumber)?.doubleValue ?? 0,
            0
        )
        XCTAssertGreaterThan(
            (result["svgHeight"] as? NSNumber)?.doubleValue ?? 0,
            0
        )
        XCTAssertEqual(int(result, "controls"), 0)
        XCTAssertFalse(bool(result, "panZoomLoaded"))
        XCTAssertTrue(bool(result, "fallbackHidden"))
        XCTAssertEqual(result["stageOverflow"] as? String, "visible")
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
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: config
        )
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

    private func cssRGB(_ color: ThemeColor) -> String {
        let value = UInt32(color.hex.dropFirst(), radix: 16) ?? 0
        return "rgb(\((value >> 16) & 0xff), \((value >> 8) & 0xff), \(value & 0xff))"
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
