import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    @State private var text: String

    init(document: MarkdownDocument, fileURL: URL?, appearanceMode: AppearanceMode, zoomLevel: Double) {
        self.document = document
        self.fileURL = fileURL
        self.appearanceMode = appearanceMode
        self.zoomLevel = zoomLevel
        self._text = State(initialValue: document.text)
    }

    var body: some View {
        MarkdownWebView(text: text, appearanceMode: appearanceMode, zoomLevel: zoomLevel)
            .onReceive(NotificationCenter.default.publisher(for: .reloadDocument)) { _ in
                reload()
            }
    }

    private func reload() {
        guard let url = fileURL,
              let newText = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        text = newText
    }
}
