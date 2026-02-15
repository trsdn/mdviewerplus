# MDViewer

A minimal macOS Markdown viewer. No editor, no bloat — just clean rendering with automatic Dark Mode support.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Size](https://img.shields.io/badge/App_Size-<500KB-2ea44f)
![Memory](https://img.shields.io/badge/Memory-<100MB-2ea44f)

## Features

- **GitHub-flavored rendering** via [marked.js](https://marked.js.org)
- **Dark Mode** — automatic (system), light, or dark via View > Appearance
- **Zoom** — Cmd+/Cmd- with persistent zoom level
- **Reload** — Cmd+R to refresh after external edits
- **Native file handling** — Open, Recent Files, drag & drop
- **< 500 KB total** — no Electron, no runtime, no dependencies

## Performance

| Metric | Value |
|--------|-------|
| App size | < 500 KB |
| Download (zip) | < 150 KB |
| Cold start | < 50 ms |
| Memory | < 100 MB |

## Install

Download the latest `.app` from [Releases](https://github.com/trsdn/mdviewer/releases) or build from source:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme MDViewer -configuration Release build
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Reload | `Cmd R` |
| Zoom In | `Cmd +` |
| Zoom Out | `Cmd -` |
| Actual Size | `Cmd 0` |
| System Appearance | `Cmd Shift 0` |
| Light Mode | `Cmd Shift 1` |
| Dark Mode | `Cmd Shift 2` |

## Dependencies

| Library | Version | License | Purpose |
|---------|---------|---------|---------|
| [marked](https://github.com/markedjs/marked) | 15.0.7 | MIT | Markdown → HTML parsing |

No Swift package dependencies. No external frameworks.

## License

[MIT](LICENSE)
