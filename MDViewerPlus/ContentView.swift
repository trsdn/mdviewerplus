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

enum ScrollSource {
    case editor, preview
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    @State private var viewMode: ViewMode = .view
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollSource: ScrollSource = .editor

    var body: some View {
        Group {
            switch viewMode {
            case .view:
                MarkdownWebView(
                    text: document.text,
                    appearanceMode: appearanceMode,
                    zoomLevel: zoomLevel,
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource
                )
            case .split:
                HSplitView {
                    MarkdownEditorView(
                        text: $document.text,
                        appearanceMode: appearanceMode,
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource
                    )
                    .frame(minWidth: 200)
                    MarkdownWebView(
                        text: document.text,
                        appearanceMode: appearanceMode,
                        zoomLevel: zoomLevel,
                        scrollFraction: $scrollFraction,
                        scrollSource: $scrollSource
                    )
                    .frame(minWidth: 200)
                }
            case .edit:
                MarkdownEditorView(
                    text: $document.text,
                    appearanceMode: appearanceMode,
                    scrollFraction: $scrollFraction,
                    scrollSource: $scrollSource
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadDocument)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
            viewMode = viewMode.next
        }
    }

    private func reload() {
        guard let url = fileURL,
              let newText = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        document.text = newText
    }
}
