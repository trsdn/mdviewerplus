# Changelog

## Unreleased

- Added drag and drop from Finder: dropping Markdown files opens them as tabs
  (the first one reuses the current tab), dropping a folder makes it the Folder
  Navigator root, and dropping unsupported items explains why they were
  rejected.
- Added toolbar controls for the view mode, Quick Open, and the document
  outline.

## 2.2.1

- The Folder Navigator selection now follows the active tab, so the highlight
  and the current-document marker no longer disagree after switching tabs.

## 2.2.0

- Replaced the document-per-window model with an in-window tab workspace:
  opening a file from the Folder Navigator now reuses the current tab instead
  of spawning a window, so tab switches and Finder opens no longer flicker.
- Added a tab bar with a `+` button that appears only once a second tab exists,
  plus **New Tab** (`Cmd T`), **Close Tab** (`Cmd W`) and a Folder Navigator
  **Open in New Tab** context command.
- Added explicit **Open…**, **Save**, and **Save As…** commands with an
  unsaved-changes prompt when closing tabs or windows.
- Finder and Dock opens now land as a tab in the active window instead of
  creating an extra window.
- One shared Folder Navigator per window: the sidebar keeps its folder and
  scroll state across tabs, and the duplicate toolbar toggle is gone.
- Fixed the sidebar toggle and `Cmd Shift B` failing to hide the navigator.
- Replaced the misleading "new folder" glyph on the navigator's parent-folder
  control and removed the stray titlebar rule and background shift in Edit
  mode.

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
