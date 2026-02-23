import SwiftUI

enum ViewMode {
    case view, split, edit

    var next: ViewMode {
        switch self {
        case .view: return .split
        case .split: return .edit
        case .edit: return .view
        }
    }
}

enum ActivePane {
    case editor, preview
}

enum ScrollSource {
    case editor, preview
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14.0
    @State private var viewMode: ViewMode = .view
    @State private var activePane: ActivePane = .preview
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollSource: ScrollSource = .editor

    var body: some View {
        Group {
            switch viewMode {
            case .view:
                MarkdownWebView(
                    text: document.text,
                    fileURL: fileURL,
                    appearanceMode: appearanceMode,
                    zoomLevel: zoomLevel,
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    onFocus: { activePane = .preview }
                )
            case .split:
                HSplitView {
                    MarkdownEditorView(
                        text: $document.text,
                        appearanceMode: appearanceMode,
                        fontSize: CGFloat(editorFontSize),
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        onFocus: { activePane = .editor }
                    )
                    .frame(minWidth: 200)
                    MarkdownWebView(
                        text: document.text,
                        fileURL: fileURL,
                        appearanceMode: appearanceMode,
                        zoomLevel: zoomLevel,
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource,
                        onFocus: { activePane = .preview }
                    )
                    .frame(minWidth: 200)
                }
            case .edit:
                MarkdownEditorView(
                    text: $document.text,
                    appearanceMode: appearanceMode,
                    fontSize: CGFloat(editorFontSize),
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource,
                    onFocus: { activePane = .editor }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadDocument)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
            viewMode = viewMode.next
            switch viewMode {
            case .view: activePane = .preview
            case .edit: activePane = .editor
            case .split: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            handleZoom(.zoomIn)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            handleZoom(.zoomOut)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
            handleZoom(.zoomReset)
        }
    }

    private var zoomTarget: ActivePane {
        switch viewMode {
        case .view: return .preview
        case .edit: return .editor
        case .split: return activePane
        }
    }

    private func handleZoom(_ action: Notification.Name) {
        switch zoomTarget {
        case .preview:
            switch action {
            case .zoomIn: zoomLevel = min(zoomLevel + 0.1, 3.0)
            case .zoomOut: zoomLevel = max(zoomLevel - 0.1, 0.5)
            case .zoomReset: zoomLevel = 1.0
            default: break
            }
        case .editor:
            switch action {
            case .zoomIn: editorFontSize = min(editorFontSize + 1, 72)
            case .zoomOut: editorFontSize = max(editorFontSize - 1, 8)
            case .zoomReset: editorFontSize = 14.0
            default: break
            }
        }
    }

    private func reload() {
        guard let url = fileURL,
              let newText = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        document.text = newText
    }
}
