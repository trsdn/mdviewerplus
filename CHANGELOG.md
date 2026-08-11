# Changelog

## 2.1.0

- Added an optional, accessible, collapsed-by-default Folder Navigator to Lite
  and Full across View, Split, and Edit modes.
- Added secure lazy folder enumeration, explicit ancestor-folder
  authorization, bounded loading, current-file reveal, and loaded-directory
  filesystem refresh.
- Added **File > Open Folder…**, **View > Folder Navigator** (`Cmd Shift B`),
  a toolbar toggle, and a current-document reveal command.
- Navigator opens retain folder access through the asynchronous native open.
  Clean source windows close after success; edited source windows remain open,
  and failed opens preserve the source and pending context safely.

## 2.0.1

- Added native Help and custom About windows with edition, version, build,
  copyright, project links, and direct issue reporting.
- Updated the README and project website with support resources.

## 2.0.0

- Added Lite and Full editions from one shared source tree with audited
  physical dependency exclusions.
- Added focus-aware Find, secure internal Markdown links, Quick Open, native
  folder watching, and a searchable document outline.
- Added footnotes, GitHub alerts, accessible task lists, local image zoom, and
  code-block copy/wrap/line-number controls.
- Added custom Lite Prism highlighting.
- Added lazy Full highlight.js, safe YAML frontmatter cards, complete offline
  modular Mermaid, and svg-pan-zoom.
- Hardened generation cancellation, print preparation, CSP, module allowlists,
  sanitizer boundaries, URL handling, and local-resource confinement.
- Added dual-edition tests, CI, release packaging, bundle audits, checksums, and
  generated third-party notices.

The lightweight workflow requests were informed by discussion in the
`sdkks/mdviewer` fork. MDViewer+ retains its own sandbox, rendering security,
and editable-document lifecycle.
