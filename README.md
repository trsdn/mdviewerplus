# MDViewer+

A native, offline macOS Markdown editor and viewer with live preview.

MDViewer+ 2.2.1 ships from one source tree in two editions:

| | Lite | Full |
| --- | --- | --- |
| Recommended for | Minimum footprint | Most users |
| Shared native features | Folder Navigator, Find, Quick Open, secure internal links, folder watcher, outline, editing, printing | Same |
| Shared Markdown features | Footnotes, alerts, tasks, image zoom, code controls | Same |
| Code highlighting | Custom Prism: Swift, JavaScript/TypeScript, JSON, Bash, Python, Rust, HTML, CSS | Lazy highlight.js common-language bundle |
| Metadata | Raw Markdown | Lazy safe YAML frontmatter card |
| Diagrams | — | Lazy offline Mermaid with svg-pan-zoom |

Both editions use the same bundle identifier, application name, document
associations, sandbox, and native `DocumentGroup` lifecycle. Installing one
edition replaces the other. **Full is the recommended download.**

## Highlights

- View, split, and edit modes with responsive live preview
- Bidirectional editor/preview scroll synchronization
- Focus-aware Find: native `NSTextView` Find in the editor and `WKWebView.find`
  in the preview
- Current-folder Quick Open with deterministic, dependency-free matching
- An optional, read-only Folder Navigator across View, Split, and Edit modes
- Secure relative Markdown links opened through the native document lifecycle
- Debounced native folder events; no polling or background index
- Searchable transient document outline with duplicate and Unicode heading IDs
- Footnotes, GitHub alerts, read-only task lists, local image inspection, and
  accessible code-block controls
- Eight coordinated light/dark themes and context-aware zoom
- Dedicated print rendering that waits for images and Full lazy renderers
- No rendered-content network access, runtime downloads, Electron, Swift
  packages, or third-party native frameworks

## Editions and offline rendering

Lite physically excludes Mermaid, svg-pan-zoom, highlight.js, js-yaml, and
their notices. Full physically excludes Prism. Full modules are served only
from a generated app-bundle allowlist and are imported on demand:

- highlight.js only when a non-Mermaid code fence exists
- js-yaml only when the document begins with a valid frontmatter delimiter
- Mermaid only for fenced `mermaid` blocks
- svg-pan-zoom only after a diagram renders successfully

Ordinary Markdown in Full initializes none of these modules.

## Install

Download one of the signed and notarized release artifacts:

- `MDViewerPlus-Full-macos.dmg` — recommended
- `MDViewerPlus-Lite-macos.dmg` — minimum footprint

Every DMG has a matching `.sha256` file.

To build locally:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme MDViewerPlus-Lite -configuration Release build
xcodebuild -scheme MDViewerPlus-Full -configuration Release build
```

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Find / next / previous | `Cmd F` / `Cmd G` / `Cmd Shift G` |
| Quick Open | `Cmd K` |
| Show or hide Folder Navigator | `Cmd Shift B` |
| Document Outline | `Cmd Shift O` |
| Toggle View Mode | `Cmd E` |
| Bold / Italic / Link | `Cmd B` / `Cmd I` / `Cmd Shift K` |
| Print | `Cmd P` |
| Previous / next Markdown file | `Cmd Option Left` / `Cmd Option Right` |
| Reload | `Cmd R` |
| Zoom in / out / actual size | `Cmd +` / `Cmd -` / `Cmd 0` |
| System / light / dark appearance | `Cmd Shift 0` / `Cmd Shift 1` / `Cmd Shift 2` |
| Help | `Cmd ?` |

## Help and support

Choose **Help > MDViewer+ Help** for the native in-app guide. **About
MDViewer+** shows the installed Lite or Full edition, version, and build.

- [MDViewer+ website](https://trsdn.github.io/mdviewerplus/)
- [Source and documentation](https://github.com/trsdn/mdviewerplus)
- [Report an issue](https://github.com/trsdn/mdviewerplus/issues/new)

## Security model

- Release builds use App Sandbox and Hardened Runtime.
- The Folder Navigator is local-only, collapsed by default, and uses an
  explicitly authorized current or ancestor folder. Choose **File > Open
  Folder…** to change its root and **Navigate > Reveal Current Document in
  Folder Navigator** to locate the open file.
- Folder contents load one directory at a time. Hidden items, packages,
  symbolic links, non-regular files, and files other than `.md`, `.markdown`,
  `.mdown`, and `.mkd` are excluded. Enumeration is bounded to depth 12, 500
  direct children, and 5,000 loaded items. Native filesystem events refresh
  only directories that are already loaded.
- Opening from the navigator uses the normal document lifecycle. A clean
  source window closes after a successful open; a source window with unsaved
  edits stays open, and failures never discard edited text.
- WebKit requires the sandbox network-client entitlement to launch its content
  process, but the render-page CSP blocks all connections and remote resources.
- A restrictive CSP blocks network connections, frames, objects, workers,
  forms, base navigation, remote images, and untrusted scripts.
- Markdown HTML is sanitized by a narrow DOMPurify policy before insertion.
- Highlighter output and Mermaid SVG use separate constrained sanitizers.
- Local resources are limited to raster images under a user-authorized folder;
  symlink escapes and unsupported types are rejected.
- Internal links accept only supported relative Markdown files under that
  folder. Absolute paths, queries, traversal, encoded traversal, unsupported
  extensions, directories, and symlink escapes are rejected.
- YAML uses `FAILSAFE_SCHEMA` plus source, depth, node, collection, key, and
  display limits. Unsafe tags and prototype-related keys are rejected.
- Mermaid uses strict security, disabled HTML labels, bounded source/count/
  concurrency/time, generation cancellation, and no remote resources.

## Dependencies and measured web assets

| Library | Version | Edition | License |
| --- | --- | --- | --- |
| marked | 15.0.7 | Common | MIT |
| DOMPurify | 3.4.12 | Common | Apache-2.0 OR MPL-2.0 |
| marked-footnote | 1.4.0 | Common | MIT |
| Prism | 1.30.0 | Lite | MIT |
| highlight.js | 11.11.1 | Full | BSD-3-Clause |
| js-yaml | 5.2.3 | Full | MIT |
| Mermaid | 11.16.0 | Full | MIT |
| svg-pan-zoom | 3.6.2 | Full | BSD-2-Clause |

`vendor/manifest.json` records every shipped file's SHA-256, exact package
version, source, license, and edition. `THIRD-PARTY-NOTICES.md` and the bundled
license files contain the corresponding notices.

As of 2026-08-09, `npm audit` reports two moderate upstream advisories without
a published fixed release. MDViewer+ never enables DOMPurify `IN_PLACE`;
Mermaid uses trusted configuration, bounded/concurrent/timed rendering, and
separately sanitized SVG. There are no high or critical audit findings.

The generated Lite-only Prism asset is 31.6 KiB minified. This is above the
original approximate 10–20 KiB target because all eight promised language
families and their required Prism grammar dependencies are retained; Lite
still has no plugins, autoloader, theme asset, or Full dependency. The source
and bundle audits enforce a 36 KiB Lite-only ceiling and physical exclusions.

## Test and release

```bash
scripts/vendor_web_assets.sh  # deterministic assets, hashes, notices
scripts/test_editions.sh      # all unit/render/security tests in both editions

REQUIRE_SIGNING=0 EDITION=lite scripts/build_release.sh
REQUIRE_SIGNING=0 EDITION=full scripts/build_release.sh
scripts/audit_bundle.sh lite dist/lite/MDViewer+.app
scripts/audit_bundle.sh full dist/full/MDViewer+.app
```

For a signed local release, copy `.release.env.example` to `.release.env` and
run `scripts/release_macos.sh`. It builds, audits, packages, notarizes, staples,
Gatekeeper-checks, and hashes both editions.

## License

[MIT](LICENSE)
