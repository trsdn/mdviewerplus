---
goal: Remediate and verify the MDViewer+ UI review findings across Lite and Full editions
version: 1.0
date_created: 2026-08-15
last_updated: 2026-08-15
owner: MDViewer+ maintainers
status: 'Planned'
tags: [design, bug, ui, accessibility, rendering, macos]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

This plan converts the findings in `/Users/torstenmahr/Downloads/mdviewerplus-ui-review.md`
into deterministic implementation and verification work. It fixes confirmed
rendering and interaction defects first, then addresses navigation, modal,
settings, and visual polish. Findings controlled by macOS or third-party
highlighters are verified and documented rather than replaced with custom
behavior without evidence.

## 1. Requirements & Constraints

- **REQ-001**: Lite frontmatter enclosed by an opening and closing `---` delimiter must render verbatim without creating a horizontal rule or Setext heading, and must retain source line breaks.
- **REQ-002**: Frontmatter must never contribute headings to the native or web document outline in either edition.
- **REQ-003**: GFM table alignment markers must produce matching alignment on every `th` and `td` in the corresponding column.
- **REQ-004**: Full-edition Mermaid diagrams must open fully visible, centered, unclipped, and padded inside the diagram stage without requiring a Fit-button click.
- **REQ-005**: Existing CSP, DOMPurify policies, local-only rendering, generation cancellation, lazy module loading, print rendering, and edition-specific physical exclusions must remain intact.
- **REQ-006**: Quick Open and Outline sheets must size to whole visible rows, avoid excessive empty space, and remain scrollable when their content exceeds the configured maximum.
- **REQ-007**: Preview Find must expose a deterministic `current/total` status, a distinct zero-result state, and correct forward/backward wrap behavior.
- **REQ-008**: Toggle controls must expose visible pressed states and matching accessibility state; action controls must remain visually distinct.
- **REQ-009**: Folder Navigator rows must preserve filename extensions, expose full names through help text, use a stable indentation grid, and distinguish selection from the current-document marker.
- **REQ-010**: Settings and Help windows must use explicit, consistent auxiliary-window policies and fit their intended content without unexplained empty space.
- **REQ-011**: All accepted changes must work in Lite and Full, in GitHub Light and GitHub Dark, at 1× and 2× display scaling.
- **REQ-012**: Every P1 and P2 review finding must have an automated regression test or a documented system-managed disposition.
- **SEC-001**: Table alignment sanitization may retain only `left`, `center`, or `right` on `th` and `td`; arbitrary inline style and arbitrary alignment values must remain rejected.
- **SEC-002**: Lite frontmatter rendering must construct DOM nodes with `textContent`; it must not inject parsed YAML or raw HTML.
- **SEC-003**: Preview Find counting must inspect rendered text without widening the Markdown sanitizer or executing document-provided code.
- **CON-001**: The deployment target remains macOS 13.0 and Swift 5.9; do not use APIs unavailable on macOS 13 without availability guards and tested fallback behavior.
- **CON-002**: Do not add Swift packages, third-party native frameworks, runtime downloads, or network dependencies.
- **CON-003**: Do not modify vendored minified highlighter libraries to address subjective token-color findings.
- **CON-004**: Quick Open remains intentionally non-recursive within the current authorized directory; recursive discovery belongs to Folder Navigator and is not introduced by this remediation.
- **GUD-001**: Prefer native SwiftUI/AppKit behavior for sheets, selection, scrollbars, window controls, and search fields before adding custom drawing.
- **GUD-002**: Implement P3 and P4 changes only when the behavior is reproducible in a fresh build; record non-reproducible and OS-managed findings in the test evidence.
- **PAT-001**: Keep shared behavior in Common resources and gate only capability-specific behavior through `EditionCapabilities` and `window.__mdviewerEdition`.
- **PAT-002**: Extend existing render-page tests for DOM behavior, unit tests for pure Swift parsing and sizing, and UI tests for native layout and keyboard flows.

## 2. Implementation Steps

### Implementation Phase 1

- **GOAL-001**: Establish deterministic fixtures and classify every review item before changing behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add a UI-review fixture directory under `MDViewerPlusUITests/Fixtures/UIReview/` containing `overview.md`, `guide.md`, `release-notes.md`, `reference/shortcuts.md`, a long filename, duplicate filenames in separate folders, long headings, a multi-line code block, YAML frontmatter, tasks, a footnote, and one Mermaid diagram. Copy fixtures into the UI-test bundle through `project.yml`. | | |
| TASK-002 | Add a disposition table to this plan's implementation PR description mapping MDV-001 through MDV-058 and MDV-T01 through MDV-T10 to `fix`, `verify`, `duplicate`, or `not-a-defect`. Use these fixed dispositions: MDV-020 and MDV-058 are duplicates of MDV-001; MDV-T01 passes when only direct children are returned per CON-004; MDV-040, MDV-044, MDV-050, MDV-053, and MDV-054 require verification before any customization; all other findings remain implementation or regression-test candidates. | | |
| TASK-003 | Capture baseline screenshots from fresh Lite and Full Debug builds at a 1200×800-point main window in GitHub Dark and GitHub Light. Store test-run attachments outside the repository and record pixel dimensions, appearance, edition, and issue IDs in the test report. | | |

### Implementation Phase 2

- **GOAL-002**: Correct the three confirmed P1 rendering defects and their outline side effects.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-004 | Create `MDViewerPlus/MarkdownFrontmatter.swift` with a pure `MarkdownFrontmatter.split(_:)` function that recognizes only a delimiter on the first line, requires a later standalone closing delimiter, returns exact `source`, `body`, and UTF-16 body offset, preserves line endings, and returns `nil` for incomplete delimiters. Use it from `DocumentOutlineParser.parse(_:)` so native outline parsing starts at the body and source locations are offset back into the complete document. | | |
| TASK-005 | In `MDViewerPlus/Resources/Common/render.js`, add an edition-independent frontmatter separator with the same delimiter contract as TASK-004. For Lite, construct `<pre class="md-frontmatter-raw"><code>…</code></pre>` using `textContent` and parse only the body with marked. For Full, pass the separated source and body to the existing safe YAML card path without changing YAML limits or error handling. Exclude frontmatter from `decorateHeadings`. | | |
| TASK-006 | In `render.js` sanitizer hooks, retain an `align` attribute only when the node is `TH` or `TD` and the normalized value is `left`, `center`, or `right`. Add `align` to the explicit allowlist and add CSS selectors in `styles.css` that apply the retained alignment to both header and body cells. Reject all other align values and continue rejecting inline styles. | | |
| TASK-007 | In `Resources/Full/full.js`, make `attachPanZoom(container, svg)` perform `resize()`, `fit()`, and `center()` on the next animation frame after the SVG and controls are attached. Add a bounded `ResizeObserver` for the diagram stage that repeats the operation only when stage dimensions change and disconnect it when the diagram is replaced. Apply 24-point-equivalent visual padding through the pan/zoom fit calculation or an inner stage inset without clipping nodes. | | |
| TASK-008 | Update `styles.css` so Lite raw frontmatter is visually neutral and verbatim, table alignment is visible, and `.md-diagram-stage` does not create unexplained empty vertical space for diagrams whose fitted aspect ratio needs less height. Preserve the existing print-mode behavior and ensure print diagrams remain static and complete. | | |

### Implementation Phase 3

- **GOAL-003**: Fix navigation, sheet sizing, toolbar duplication, and editor split-view clarity.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-009 | Remove the redundant custom `ToolbarItem(placement: .navigation)` from `ContentView` when `NavigationSplitView` already supplies its sidebar toggle. Keep the `View > Folder Navigator` command and `⇧⌘B` shortcut. Verify that exactly one sidebar control remains, its help text is available, and its position is stable when the sidebar opens and closes. If macOS 13 does not expose help for the automatic control, suppress the automatic toggle and provide one custom control rather than displaying two. | | |
| TASK-010 | Configure the editor `NSScrollView` in `MarkdownEditorView.makeNSView` with overlay scrollers, automatic hiding, and no horizontal scroller. Keep the text container inset at 16 points, ensure the vertical scroller belongs visually to the editor, and give the split boundary a separate one-point palette-derived divider in `ContentView` rather than relying on a wide persistent scroller as the boundary. | | |
| TASK-011 | Refactor `FolderNavigatorSidebar.navigatorRow(_:)` into a fixed grid with an indentation region, a 12-point disclosure column reserved for files and directories, an icon column, a middle-truncated filename, and a current-document indicator column. Add `.help(row.node.name)` to the filename, keep the current-document dot labeled `Current document`, and use the List selection background for keyboard selection rather than applying the current-document marker as selection. | | |
| TASK-012 | Add pure sizing helpers in `NavigationPanels.swift`: Quick Open height equals search/header height plus `min(max(resultCount, 1), 8)` complete 24-point rows plus footer and padding; Outline height equals search/header height plus `min(max(entryCount, 1), 10)` complete 24-point rows plus footer and padding. Clamp both sheets to 60% of the presenting window height through a macOS-13-compatible geometry value. Use the helpers for exact `idealHeight` and `maxHeight`, preserving scrolling beyond the row limit. | | |
| TASK-013 | Replace the Quick Open and Outline query `TextField` instances with a shared macOS search-field wrapper backed by `NSSearchField`, including a magnifier, native focus ring, clear action, Escape dismissal, and the existing accessibility identifiers. Use accent selection for the active list row and system hover behavior. | | |
| TASK-014 | Extend `QuickOpenItem` with a display-relative-path supplied by `ContentView.reloadQuickOpen`. Show the filename as the primary text and the parent relative path as secondary text only when duplicate basenames exist. Keep matching and ordering based on the filename and retain direct-child-only catalog behavior. | | |

### Implementation Phase 4

- **GOAL-004**: Make preview search status and code/diagram controls explicit and accessible.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-015 | Replace the boolean preview-find callback with a `PreviewFindResult` value containing `matchFound`, `currentIndex`, and `totalCount`. Add a page-world JavaScript function in `render.js` that counts non-overlapping, case-insensitive text matches through a `TreeWalker` over visible text nodes while excluding script, style, controls, and hidden fallback content. In `MarkdownWebView.Coordinator`, reset the index when the query changes, increment or decrement only after successful `WKWebView.find`, wrap within `1...totalCount`, and return `0/0` when no matches exist. | | |
| TASK-016 | Update `PreviewFindBar` to display `current/total`, use a compact flexible field-to-buttons layout with 8-point gaps, align its trailing edge to the preview content/scrollbar grid, and apply an accessible error state when `totalCount == 0` after a completed search. Do not implement animation-dependent shake behavior; use a red system error tint and `No matches` accessibility value. | | |
| TASK-017 | In `styles.css`, style `.md-code-button[aria-pressed="true"]` with the theme accent and selected foreground, add a separator before the Copy action, retain `aria-pressed` updates in `render.js`, and keep the existing `Copied` live-region feedback. Group Mermaid minus, plus, and Fit controls visually as one segmented control with equal compact button heights and explicit focus-visible states. | | |
| TASK-018 | Add full-row click and hover affordance to `.md-frontmatter-summary`, open Full metadata cards by default in `full.js`, and include a collapsed summary preview listing up to the first three sanitized keys. Persist no state in version 1; every document render begins expanded. | | |

### Implementation Phase 5

- **GOAL-005**: Apply reproducible rendering and layout polish without overriding correct native or theme behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-019 | Replace native checkbox appearance in the preview with a CSS-controlled 14×14 rounded-square shape shared by checked and unchecked tasks; vary only fill, border, and checkmark. Retain disabled and read-only semantics from `decorateTaskLists`. | | |
| TASK-020 | Normalize preview horizontal padding through a single CSS custom property and reserve the overlay scrollbar gutter so left and right content insets are visually equal in View and Split modes. Verify at 400-, 600-, and 1200-point preview widths and do not reduce the minimum content padding below 24 points. | | |
| TASK-021 | Verify editor and preview computed backgrounds against `ThemePalette.colors.background` for all eight palettes. Because `MarkdownEditorView.applyAppearance` and the web theme already use the same token, change code only if computed-color assertions fail; otherwise close MDV-026 as not reproducible with fresh builds. | | |
| TASK-022 | Verify Full Swift constructor highlighting with the unmodified highlight.js bundle. Do not patch vendor output for MDV-050. Record the observed token classes and close the finding as an upstream grammar behavior unless the call-site token is emitted with a class that the app CSS incorrectly leaves unstyled. | | |

### Implementation Phase 6

- **GOAL-006**: Refine Settings and Help while preserving native macOS conventions.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-023 | Change `ThemeSettingsView` from a fixed-height expanding form to content-fitting vertical layout with a 460-point width, explicit minimum padding, and no extra flexible spacer. Verify Settings remains non-minimizable and non-zoomable under the native `Settings` scene. Do not rename the system-generated `MDViewer+ Settings` title. | | |
| TASK-024 | Refactor `HelpView` so explanatory Folder Navigator prose appears before a contiguous shortcut table; split previous and next file shortcuts into separate rows; constrain prose to a 520-point readable column; remove the duplicated top-level `MDViewer+ Help` heading while retaining the native window title and descriptive subtitle. | | |
| TASK-025 | Rename the custom Help window scene title to `Help`, set an explicit content-size policy, and configure it as minimizable but not zoomable. Keep Settings non-minimizable and non-zoomable. Add an auxiliary-window test that asserts the intentional policy rather than requiring both windows to expose identical yellow-button states. | | |
| TASK-026 | Verify native segmented-control insets, main document title placement, proxy icon behavior, and sheet centering on macOS 13 and the current development macOS. Do not replace system controls or titlebar behavior for MDV-040, MDV-044, or MDV-054 unless the same defect reproduces in a minimal native control using the same APIs. | | |

### Implementation Phase 7

- **GOAL-007**: Complete regression coverage and produce review-ready visual evidence.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-027 | Extend `MarkdownRenderPageTests` with Lite raw-frontmatter DOM assertions, Full frontmatter default-open/key-preview assertions, secure table alignment assertions, uniform task-checkbox class/state assertions, code-toggle pressed-state assertions, Copy feedback assertions, footnote navigation assertions, and Mermaid fitted bounding-box assertions after resource settling. | | |
| TASK-028 | Extend `EditionAndNavigationTests` with frontmatter exclusion and source-offset tests for `DocumentOutlineParser`, Quick Open direct-child behavior, duplicate-name display-path behavior, and sheet-height helper boundary tests. | | |
| TASK-029 | Extend `MDViewerPlusUITests` with flows for one toolbar sidebar button, full filename help, current-vs-selected navigator rows, adaptive Quick Open height, whole-row Outline viewport, preview find `current/total` and zero state, split scroll synchronization with Mermaid, outline anchor navigation, and auxiliary-window button policies. | | |
| TASK-030 | Run `scripts/test_editions.sh`, both release builds with `REQUIRE_SIGNING=0`, `scripts/audit_bundle.sh` for Lite and Full, and targeted UI tests. Reject the change if bundle audits show cross-edition resource leakage or if any existing security/render test regresses. | | |
| TASK-031 | Recapture the ten documentation screenshots in `docs/ui-overview/` with identical 1200×800-point geometry and update `docs/ui-overview/README.md` only where behavior changed. Include additional test-run screenshots for Light mode, expanded metadata, zero-result Find, Copy feedback, and Mermaid keyboard focus without increasing the committed overview beyond ten images. | | |
| TASK-032 | Close the review with a final issue matrix listing every MDV identifier, implemented task, automated test, before/after evidence, and disposition. The matrix must show zero unresolved P1/P2 findings and explicitly record system-managed or upstream P3/P4 findings. | | |

## 3. Alternatives

- **ALT-001**: Parse Lite frontmatter as YAML using the Full js-yaml module. Rejected because Lite must physically exclude Full-only modules and only needs safe verbatim display.
- **ALT-002**: Preserve table alignment through arbitrary inline `style` attributes. Rejected because it unnecessarily widens the sanitizer; a constrained `align` allowlist satisfies the requirement.
- **ALT-003**: Replace `WKWebView.find` with custom DOM `<mark>` mutation for all search behavior. Rejected because it risks disturbing selection, outline anchors, sanitized content, and scroll synchronization; counting is added separately while native WebKit remains responsible for match navigation.
- **ALT-004**: Make Quick Open recursively enumerate the authorized tree. Rejected because current behavior and documentation define the current directory as its scope; Folder Navigator provides recursive browsing.
- **ALT-005**: Replace native macOS titlebars, sheets, segmented controls, and search fields with custom chrome. Rejected because it increases maintenance and accessibility risk for findings that may be OS-managed.
- **ALT-006**: Patch vendored highlight.js or Mermaid source. Rejected because vendor artifacts are generated, audited, and version-pinned; app-owned integration and CSS are the supported remediation surfaces.

## 4. Dependencies

- **DEP-001**: Xcode 16-compatible toolchain with macOS 13 deployment support.
- **DEP-002**: Existing `xcodegen`, `xcodebuild`, and `scripts/test_editions.sh` workflows.
- **DEP-003**: Existing bundled marked, DOMPurify, Prism, highlight.js, js-yaml, Mermaid, and svg-pan-zoom assets.
- **DEP-004**: The source UI review at `/Users/torstenmahr/Downloads/mdviewerplus-ui-review.md`.
- **DEP-005**: Existing screenshot documentation under `docs/ui-overview/`.

## 5. Files

- **FILE-001**: `MDViewerPlus/MarkdownFrontmatter.swift` — new shared native frontmatter delimiter parser.
- **FILE-002**: `MDViewerPlus/DocumentOutline.swift` — exclude frontmatter and preserve source offsets.
- **FILE-003**: `MDViewerPlus/Resources/Common/render.js` — Lite frontmatter, table alignment, search counting, and control behavior.
- **FILE-004**: `MDViewerPlus/Resources/Common/styles.css` — raw frontmatter, alignment, tasks, controls, padding, and diagram layout.
- **FILE-005**: `MDViewerPlus/Resources/Full/full.js` — metadata default state and Mermaid fit lifecycle.
- **FILE-006**: `MDViewerPlus/ContentView.swift` — toolbar, find-result state, Quick Open paths, and split divider.
- **FILE-007**: `MDViewerPlus/MarkdownWebView.swift` — counted find coordination and result transport.
- **FILE-008**: `MDViewerPlus/MarkdownEditorView.swift` — native scroller behavior.
- **FILE-009**: `MDViewerPlus/NavigationPanels.swift` — search fields, adaptive sheets, whole-row lists, and find layout.
- **FILE-010**: `MDViewerPlus/QuickOpenMatcher.swift` — duplicate-name context model while preserving filename matching.
- **FILE-011**: `MDViewerPlus/FolderNavigatorSidebar.swift` — row grid, truncation, help, and selection semantics.
- **FILE-012**: `MDViewerPlus/ThemeSettingsView.swift` — content-fitting settings layout.
- **FILE-013**: `MDViewerPlus/SupportViews.swift` — Help hierarchy, readable width, and shortcut table.
- **FILE-014**: `MDViewerPlus/MDViewerPlusApp.swift` — Help scene title and window policy.
- **FILE-015**: `MDViewerPlusTests/MarkdownRenderPageTests.swift` — render/security regressions.
- **FILE-016**: `MDViewerPlusTests/EditionAndNavigationTests.swift` — parser, catalog, matching, and sizing regressions.
- **FILE-017**: `MDViewerPlusUITests/MDViewerPlusUITests.swift` — native interaction and layout regressions.
- **FILE-018**: `MDViewerPlusUITests/Fixtures/UIReview/` — deterministic UI-review fixture set.
- **FILE-019**: `project.yml` — UI-test fixture resource inclusion if required by XcodeGen.
- **FILE-020**: `docs/ui-overview/README.md` and its ten PNG files — refreshed final evidence.

## 6. Testing

- **TEST-001**: Lite frontmatter renders exactly one verbatim block, zero frontmatter-derived `hr`, zero frontmatter-derived heading, and preserves every source line.
- **TEST-002**: Native and web outlines exclude frontmatter and return correct body heading levels, slugs, counts, and editor source offsets.
- **TEST-003**: Sanitized tables retain only valid cell alignment and reject arbitrary style or invalid align values.
- **TEST-004**: Mermaid SVG bounding rectangle is fully contained within the stage rectangle with at least 20 CSS pixels of effective padding after initial render and resize.
- **TEST-005**: Quick Open and Outline sheet heights use complete rows at minimum, typical, and overflow counts.
- **TEST-006**: Preview Find returns correct `current/total` through next, previous, query change, wrap, zero results, and dismissal.
- **TEST-007**: Code Wrap and Lines expose visible and accessible pressed states; Copy exposes `Copied` live feedback.
- **TEST-008**: Navigator selection background, current-document indicator, filename extension, tooltip, and indentation remain correct for root and nested rows.
- **TEST-009**: Split view uses overlay auto-hiding editor scrollbars, a separate divider, synchronized scrolling, and symmetric preview padding.
- **TEST-010**: Settings and Help fit content and expose their intended minimize/zoom policies.
- **TEST-011**: Light and dark visual checks cover Lite View/Split and Full metadata/Mermaid states at 1× and 2× scaling.
- **TEST-012**: Existing CSP, sanitizer, bundle allowlist, print, lazy loading, source audit, and artifact-size tests remain green.
- **TEST-013**: Quick Open returns only direct child Markdown files and displays disambiguating parent paths when supplied duplicate-name fixtures.
- **TEST-014**: Footnote forward/back navigation, outline Go offset, Mermaid keyboard pan/zoom, and Copy feedback satisfy MDV-T02, MDV-T03, MDV-T09, and MDV-T10.

## 7. Risks & Assumptions

- **RISK-001**: DOMPurify may remove marked-generated alignment before postprocessing if the hook order is incorrect; tests must inspect the final DOM, not parser output.
- **RISK-002**: svg-pan-zoom can calculate against a zero-size or not-yet-laid-out stage; requestAnimationFrame and resize observation must be generation-safe and bounded.
- **RISK-003**: Native SwiftUI sheet and toolbar behavior differs across macOS releases; UI assertions must target semantic controls and geometry tolerances rather than private view hierarchies.
- **RISK-004**: Counting text separately from `WKWebView.find` can diverge for Unicode normalization or cross-node matches; fixtures must cover accented text and inline markup, and status must fall back to `Match found` if exact counting cannot be guaranteed.
- **RISK-005**: Custom checkbox appearance can differ between WebKit versions; render tests must assert computed geometry and shape tokens rather than screenshot color alone.
- **ASSUMPTION-001**: The first-line standalone `---` plus a later standalone `---` is the accepted frontmatter delimiter contract for both editions.
- **ASSUMPTION-002**: Current-document and selected-row are distinct concepts; the dot means current open document, not unsaved edits.
- **ASSUMPTION-003**: Native Settings title generation and main document titlebar placement are correct macOS conventions unless reproduced as an application-specific defect.
- **ASSUMPTION-004**: The committed documentation remains limited to ten overview screenshots; additional acceptance evidence is attached to test or pull-request artifacts.

## 8. Related Specifications / Further Reading

- [UI review source](/Users/torstenmahr/Downloads/mdviewerplus-ui-review.md)
- [Current UI overview](../docs/ui-overview/README.md)
- [Project README](../README.md)
- [Apple Human Interface Guidelines for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [WebKit WKWebView find API](https://developer.apple.com/documentation/webkit/wkwebview/find(_:configuration:completionhandler:))
- [DOMPurify documentation](https://github.com/cure53/DOMPurify)
