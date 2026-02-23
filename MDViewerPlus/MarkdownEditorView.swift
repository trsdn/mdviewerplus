import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var appearanceMode: AppearanceMode = .system
    var fontSize: CGFloat = 14
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource
    var onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindPanel = true

        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.insertionPointColor = .textColor

        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.textContainerInset = NSSize(width: 16, height: 16)

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        applyAppearance(to: scrollView)
        applyHighlighting(to: textView)

        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        applyAppearance(to: scrollView)
        applyHighlighting(to: textView)

        // Apply incoming scroll from preview
        if scrollSource == .preview, let documentView = scrollView.documentView {
            let contentHeight = documentView.frame.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = contentHeight - visibleHeight
            if maxScroll > 0 {
                let targetY = scrollFraction * maxScroll
                let currentY = scrollView.contentView.bounds.origin.y
                if abs(targetY - currentY) > 1 {
                    context.coordinator.isSyncing = true
                    scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    DispatchQueue.main.async {
                        context.coordinator.isSyncing = false
                    }
                }
            }
        }
    }

    private func isDark() -> Bool {
        switch appearanceMode {
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .light:
            return false
        case .dark:
            return true
        }
    }

    private func applyHighlighting(to textView: NSTextView) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let highlighter = MarkdownSyntaxHighlighter(baseFont: font, isDark: isDark())
        highlighter.highlight(textView.textStorage)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: isDark() ? Self.darkFg : Self.lightFg,
        ]
    }

    private static let lightBg = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    private static let lightFg = NSColor(red: 0.141, green: 0.161, blue: 0.184, alpha: 1.0)
    private static let darkBg = NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1.0)
    private static let darkFg = NSColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 1.0)

    private func applyAppearance(to scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        switch appearanceMode {
        case .system:
            scrollView.appearance = nil
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textView.backgroundColor = isDark ? Self.darkBg : Self.lightBg
            textView.textColor = isDark ? Self.darkFg : Self.lightFg
            scrollView.backgroundColor = textView.backgroundColor
        case .light:
            scrollView.appearance = NSAppearance(named: .aqua)
            textView.backgroundColor = Self.lightBg
            textView.textColor = Self.lightFg
            scrollView.backgroundColor = Self.lightBg
        case .dark:
            scrollView.appearance = NSAppearance(named: .darkAqua)
            textView.backgroundColor = Self.darkBg
            textView.textColor = Self.darkFg
            scrollView.backgroundColor = Self.darkBg
        }
        textView.insertionPointColor = textView.textColor ?? .textColor
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isSyncing = false
        private var notificationObservers: [NSObjectProtocol] = []

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            super.init()

            let boldObserver = NotificationCenter.default.addObserver(
                forName: .formatBold, object: nil, queue: .main
            ) { [weak self] _ in self?.wrapSelection(with: "**") }

            let italicObserver = NotificationCenter.default.addObserver(
                forName: .formatItalic, object: nil, queue: .main
            ) { [weak self] _ in self?.wrapSelection(with: "_") }

            let linkObserver = NotificationCenter.default.addObserver(
                forName: .formatLink, object: nil, queue: .main
            ) { [weak self] _ in self?.insertLink() }

            let scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleScroll(notification)
            }

            notificationObservers = [boldObserver, italicObserver, linkObserver, scrollObserver]
        }

        deinit {
            for observer in notificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func handleScroll(_ notification: Notification) {
            guard !isSyncing,
                  let clipView = notification.object as? NSClipView,
                  clipView == scrollView?.contentView,
                  let documentView = scrollView?.documentView else { return }
            let contentHeight = documentView.frame.height
            let visibleHeight = clipView.bounds.height
            let maxScroll = contentHeight - visibleHeight
            guard maxScroll > 0 else { return }
            let fraction = clipView.bounds.origin.y / maxScroll
            parent.scrollSource = .editor
            parent.scrollFraction = min(max(fraction, 0), 1)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.onFocus?()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.applyHighlighting(to: textView)
        }

        private func wrapSelection(with marker: String) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let string = textView.string as NSString
            let selected = string.substring(with: range)
            let replacement = "\(marker)\(selected)\(marker)"
            textView.insertText(replacement, replacementRange: range)
            if range.length == 0 {
                let cursorPos = range.location + marker.count
                textView.setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
        }

        private func insertLink() {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let string = textView.string as NSString
            let selected = string.substring(with: range)
            let replacement = "[\(selected)](url)"
            textView.insertText(replacement, replacementRange: range)
            let urlStart = range.location + selected.count + 2
            textView.setSelectedRange(NSRange(location: urlStart, length: 3))
        }
    }
}
