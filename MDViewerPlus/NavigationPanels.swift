import SwiftUI

struct QuickOpenPalette: View {
    let items: [QuickOpenItem]
    let onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection: QuickOpenItem.ID?

    private var filteredItems: [QuickOpenItem] {
        QuickOpenMatcher.filter(items, query: query)
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search Markdown files", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("quickOpenSearch")
                .onSubmit { openSelected() }

            List(filteredItems, selection: $selection) { item in
                Text(item.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(item) }
            }
            .accessibilityIdentifier("quickOpenResults")
            .overlay {
                if filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                        Text("No Matching Markdown Files")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(filteredItems.count) result\(filteredItems.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") { openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedItem == nil)
            }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 340)
        .onAppear {
            selection = filteredItems.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _ in
            selection = filteredItems.first?.id
        }
    }

    private var selectedItem: QuickOpenItem? {
        filteredItems.first { $0.id == selection } ?? filteredItems.first
    }

    private func openSelected() {
        guard let selectedItem else { return }
        open(selectedItem)
    }

    private func open(_ item: QuickOpenItem) {
        dismiss()
        onOpen(item.url)
    }
}

struct OutlinePalette: View {
    let entries: [OutlineEntry]
    let onSelect: (OutlineEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection: OutlineEntry.ID?

    private var filteredEntries: [OutlineEntry] {
        OutlineFilter.filter(entries, query: query)
    }

    private var indentations: [Int] {
        OutlineFilter.indentationLevels(for: filteredEntries)
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search headings", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("outlineSearch")
                .onSubmit { selectCurrent() }

            List(selection: $selection) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) {
                    index, entry in
                    Text(entry.title)
                        .padding(.leading, CGFloat(indentations[index]) * 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { select(entry) }
                }
            }
            .accessibilityIdentifier("outlineResults")
            .overlay {
                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .font(.largeTitle)
                        Text("No Matching Headings")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(filteredEntries.count) heading\(filteredEntries.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go") { selectCurrent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 340)
        .onAppear {
            selection = filteredEntries.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _ in
            selection = filteredEntries.first?.id
        }
    }

    private var selectedEntry: OutlineEntry? {
        filteredEntries.first { $0.id == selection }
            ?? filteredEntries.first
    }

    private func selectCurrent() {
        guard let selectedEntry else { return }
        select(selectedEntry)
    }

    private func select(_ entry: OutlineEntry) {
        dismiss()
        onSelect(entry)
    }
}

struct PreviewFindBar: View {
    @Binding var query: String
    let status: String
    let onSearch: (Bool) -> Void
    let onDismiss: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            TextField("Find in preview", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($searchFocused)
                .accessibilityIdentifier("previewFindField")
                .onSubmit { onSearch(false) }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
            Button {
                onSearch(true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Previous Match")
            .disabled(query.isEmpty)
            Button {
                onSearch(false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Next Match")
            .disabled(query.isEmpty)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Dismiss Find")
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .onAppear { searchFocused = true }
    }
}
