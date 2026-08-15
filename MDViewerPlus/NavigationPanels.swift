import AppKit
import SwiftUI

enum NavigationPanelSizing {
    static let rowHeight: CGFloat = 24
    static let searchHeaderHeight: CGFloat = 28
    static let footerHeight: CGFloat = 28
    static let verticalSpacing: CGFloat = 20
    static let verticalPadding: CGFloat = 28
    static let quickOpenRowLimit = 8
    static let outlineRowLimit = 10
    static let maximumWindowFraction: CGFloat = 0.6

    private static var chromeHeight: CGFloat {
        searchHeaderHeight + footerHeight + verticalSpacing + verticalPadding
    }

    static func quickOpenHeight(
        resultCount: Int,
        presentingHeight: CGFloat
    ) -> CGFloat {
        panelHeight(
            count: resultCount,
            rowLimit: quickOpenRowLimit,
            presentingHeight: presentingHeight
        )
    }

    static func outlineHeight(
        entryCount: Int,
        presentingHeight: CGFloat
    ) -> CGFloat {
        panelHeight(
            count: entryCount,
            rowLimit: outlineRowLimit,
            presentingHeight: presentingHeight
        )
    }

    static func rowViewportHeight(for panelHeight: CGFloat) -> CGFloat {
        max(panelHeight - chromeHeight, 0)
    }

    static func previewContentInset(for width: CGFloat) -> CGFloat {
        min(max(width * 0.06, 24), 48)
    }

    private static func panelHeight(
        count: Int,
        rowLimit: Int,
        presentingHeight: CGFloat
    ) -> CGFloat {
        let desiredRows = min(max(count, 1), rowLimit)
        let unclampedHeight =
            chromeHeight + CGFloat(desiredRows) * rowHeight
        let maximumHeight =
            floor(max(presentingHeight, 0) * maximumWindowFraction)
        guard maximumHeight < unclampedHeight else {
            return unclampedHeight
        }

        let completeRows = max(
            Int(floor((maximumHeight - chromeHeight) / rowHeight)),
            0
        )
        guard completeRows > 0 else { return maximumHeight }
        return chromeHeight
            + CGFloat(min(desiredRows, completeRows)) * rowHeight
    }
}

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityIdentifier: String
    var autoFocus = true
    var isError = false
    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.delegate = context.coordinator
        searchField.placeholderString = placeholder
        searchField.stringValue = text
        searchField.focusRingType = .default
        searchField.bezelStyle = .roundedBezel
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.setAccessibilityIdentifier(accessibilityIdentifier)
        searchField.setAccessibilityLabel(placeholder)
        Self.applyErrorAppearance(isError, to: searchField)
        focusIfNeeded(searchField, coordinator: context.coordinator)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        searchField.placeholderString = placeholder
        searchField.setAccessibilityIdentifier(accessibilityIdentifier)
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        Self.applyErrorAppearance(isError, to: searchField)
        focusIfNeeded(searchField, coordinator: context.coordinator)
    }

    static func applyErrorAppearance(
        _ isError: Bool,
        to searchField: NSSearchField
    ) {
        searchField.wantsLayer = true
        searchField.textColor = isError ? .systemRed : .controlTextColor
        searchField.layer?.cornerRadius = 6
        searchField.layer?.borderWidth = isError ? 1 : 0
        searchField.layer?.borderColor = isError
            ? NSColor.systemRed.cgColor
            : NSColor.clear.cgColor
        searchField.setAccessibilityHelp(isError ? "No matches" : nil)
    }

    private func focusIfNeeded(
        _ searchField: NSSearchField,
        coordinator: Coordinator
    ) {
        guard autoFocus, !coordinator.hasFocused else { return }
        DispatchQueue.main.async {
            guard let window = searchField.window else { return }
            coordinator.hasFocused = true
            window.makeFirstResponder(searchField)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        var hasFocused = false

        init(parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField
            else { return }
            parent.text = searchField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

struct QuickOpenPalette: View {
    let items: [QuickOpenItem]
    let presentingHeight: CGFloat
    let onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: QuickOpenItem.ID?

    private var filteredItems: [QuickOpenItem] {
        QuickOpenMatcher.filter(items, query: query)
    }

    private var duplicateBasenames: Set<String> {
        QuickOpenMatcher.duplicateBasenames(in: items)
    }

    private var panelHeight: CGFloat {
        NavigationPanelSizing.quickOpenHeight(
            resultCount: filteredItems.count,
            presentingHeight: presentingHeight
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            NativeSearchField(
                text: $query,
                placeholder: "Search Markdown files",
                accessibilityIdentifier: "quickOpenSearch",
                onSubmit: openSelected,
                onEscape: dismiss.callAsFunction
            )
            .frame(height: NavigationPanelSizing.searchHeaderHeight)

            List(filteredItems, selection: $selection) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if QuickOpenMatcher.hasDuplicateBasename(
                        item,
                        duplicateBasenames: duplicateBasenames
                    ) {
                        Text(item.displayParentPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .padding(.horizontal, 6)
                .frame(
                    maxWidth: .infinity,
                    minHeight: NavigationPanelSizing.rowHeight,
                    maxHeight: NavigationPanelSizing.rowHeight,
                    alignment: .leading
                )
                .tag(item.id)
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets())
                .onTapGesture(count: 2) { open(item) }
            }
            .listStyle(.plain)
            .tint(.accentColor)
            .frame(
                height: NavigationPanelSizing.rowViewportHeight(
                    for: panelHeight
                )
            )
            .accessibilityIdentifier("quickOpenResults")
            .overlay {
                if filteredItems.isEmpty {
                    Label(
                        "No Matching Markdown Files",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(
                    "\(filteredItems.count) result"
                        + (filteredItems.count == 1 ? "" : "s")
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") { openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedItem == nil)
            }
            .frame(height: NavigationPanelSizing.footerHeight)
        }
        .padding(14)
        .frame(
            minWidth: 480,
            idealHeight: panelHeight,
            maxHeight: panelHeight
        )
        .onAppear {
            selection = filteredItems.first?.id
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
    let presentingHeight: CGFloat
    let onSelect: (OutlineEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: OutlineEntry.ID?

    private var filteredEntries: [OutlineEntry] {
        OutlineFilter.filter(entries, query: query)
    }

    private var indentations: [Int] {
        OutlineFilter.indentationLevels(for: filteredEntries)
    }

    private var panelHeight: CGFloat {
        NavigationPanelSizing.outlineHeight(
            entryCount: filteredEntries.count,
            presentingHeight: presentingHeight
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            NativeSearchField(
                text: $query,
                placeholder: "Search headings",
                accessibilityIdentifier: "outlineSearch",
                onSubmit: selectCurrent,
                onEscape: dismiss.callAsFunction
            )
            .frame(height: NavigationPanelSizing.searchHeaderHeight)

            List(selection: $selection) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) {
                    index, entry in
                    Text(entry.title)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(indentations[index]) * 14 + 6)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: NavigationPanelSizing.rowHeight,
                            maxHeight: NavigationPanelSizing.rowHeight,
                            alignment: .leading
                        )
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets())
                        .onTapGesture(count: 2) { select(entry) }
                }
            }
            .listStyle(.plain)
            .tint(.accentColor)
            .frame(
                height: NavigationPanelSizing.rowViewportHeight(
                    for: panelHeight
                )
            )
            .accessibilityIdentifier("outlineResults")
            .overlay {
                if filteredEntries.isEmpty {
                    Label(
                        "No Matching Headings",
                        systemImage: "list.bullet.indent"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(
                    "\(filteredEntries.count) heading"
                        + (filteredEntries.count == 1 ? "" : "s")
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go") { selectCurrent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
            .frame(height: NavigationPanelSizing.footerHeight)
        }
        .padding(14)
        .frame(
            minWidth: 480,
            idealHeight: panelHeight,
            maxHeight: panelHeight
        )
        .onAppear {
            selection = filteredEntries.first?.id
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
    let result: PreviewFindResult?
    let isSearching: Bool
    let onSearch: (Bool) -> Void
    let onDismiss: () -> Void

    private var isZeroResult: Bool {
        !isSearching && result?.totalCount == 0
    }

    private var status: String {
        if isSearching { return "…" }
        guard let result else { return "" }
        return "\(result.currentIndex)/\(result.totalCount)"
    }

    private var accessibleStatus: String {
        if isSearching { return "Searching" }
        guard let result else { return "" }
        if result.totalCount == 0 { return "No matches" }
        return "\(result.currentIndex) of \(result.totalCount) matches"
    }

    var body: some View {
        HStack(spacing: 8) {
            NativeSearchField(
                text: $query,
                placeholder: "Find in preview",
                accessibilityIdentifier: "previewFindField",
                isError: isZeroResult,
                onSubmit: { onSearch(false) },
                onEscape: onDismiss
            )
            .frame(minWidth: 160, idealWidth: 220, maxWidth: .infinity)

            Text(status)
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    isZeroResult
                        ? Color(nsColor: .systemRed)
                        : Color.secondary
                )
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityIdentifier("previewFindStatus")
                .accessibilityLabel("Find result")
                .accessibilityValue(accessibleStatus)

            Button {
                onSearch(true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Previous Match")
            .help("Previous Match")
            .disabled(query.isEmpty)

            Button {
                onSearch(false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Next Match")
            .help("Next Match")
            .disabled(query.isEmpty)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Dismiss Find")
            .help("Dismiss Find")
        }
        .padding(8)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}
