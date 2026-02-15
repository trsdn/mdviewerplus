# MDViewer

A minimal macOS Markdown viewer. No editor, no bloat — just clean rendering with automatic Dark Mode support.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Size](https://img.shields.io/badge/App_Size-328KB-2ea44f)
![Memory](https://img.shields.io/badge/Memory-~87MB-2ea44f)

## Features

- **GitHub-flavored rendering** via [marked.js](https://marked.js.org)
- **Dark Mode** — automatic (system), light, or dark via View > Appearance
- **Zoom** — Cmd+/Cmd- with persistent zoom level
- **Native file handling** — Open, Recent Files, drag & drop
- **328 KB total** — no Electron, no runtime, no dependencies

## Performance

| Metric | Value |
|--------|-------|
| App size | 328 KB |
| Download (zip) | 107 KB |
| Cold start | ~57 ms |
| Memory (idle) | ~69 MB |
| Memory (133 KB file) | ~87 MB |

Measured with a 133 KB Markdown file containing 500 sections with tables and code blocks.

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
