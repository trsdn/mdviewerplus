import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let palette: ThemePalette
    var fontSize: CGFloat = 14
    @Binding var scrollFraction: CGFloat
    @Binding var scrollSource: ScrollSource
    let commandRequest: EditorCommandRequest?
    let findRequest: FindCommandRequest?
    let outlineRequest: EditorOutlineRequest?
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
        textView.setAccessibilityIdentifier("markdownEditor")
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
        context.coordinator.lastHandledCommandID = commandRequest?.id
        context.coordinator.lastHandledFindID = findRequest?.id
        context.coordinator.lastHandledOutlineID = outlineRequest?.id
        applyAppearance(to: scrollView)
        applyHighlighting(to: textView)
        context.coordinator.lastHighlightedText = text
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastPaletteID = palette.id
        textView.textStorage?.delegate = context.coordinator

        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        var requiresFullHighlight = false

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            coordinator.isApplyingExternalText = true
            textView.string = text
            coordinator.isApplyingExternalText = false
            textView.selectedRanges = clamped(
                selectedRanges,
                toUTF16Length: (text as NSString).length
            )
            coordinator.lastHighlightedText = text
            requiresFullHighlight = true
        }

        if coordinator.lastFontSize != fontSize {
            coordinator.lastFontSize = fontSize
            textView.font = NSFont.monospacedSystemFont(
                ofSize: fontSize,
                weight: .regular
            )
            requiresFullHighlight = true
        }

        if coordinator.lastPaletteID != palette.id {
            coordinator.lastPaletteID = palette.id
            requiresFullHighlight = true
        }

        applyAppearance(to: scrollView)
        if requiresFullHighlight {
            applyHighlighting(to: textView)
        }
        coordinator.handle(commandRequest)
        coordinator.handle(findRequest)
        coordinator.handle(outlineRequest)

        // Apply incoming scroll from preview
        if scrollSource == .preview, let documentView = scrollView.documentView {
            let contentHeight = documentView.frame.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = contentHeight - visibleHeight
            if maxScroll > 0 {
                let targetY = scrollFraction * maxScroll
                let currentY = scrollView.contentView.bounds.origin.y
                if abs(targetY - currentY) > 1 {
                    coordinator.isSyncing = true
                    scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    DispatchQueue.main.async {
                        coordinator.isSyncing = false
                    }
                }
            }
        }
    }

    private func applyHighlighting(
        to textView: NSTextView,
        editedRange: NSRange? = nil,
        rehighlightToEnd: Bool = false
    ) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: font,
            palette: palette.syntax
        )
        highlighter.highlight(
            textView.textStorage,
            editedRange: editedRange,
            rehighlightToEnd: rehighlightToEnd
        )
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.colors.foreground.nsColor,
        ]
    }

    private func clamped(
        _ ranges: [NSValue],
        toUTF16Length length: Int
    ) -> [NSValue] {
        ranges.map { value in
            let range = value.rangeValue
            let location = min(range.location, length)
            return NSValue(
                range: NSRange(
                    location: location,
                    length: min(range.length, length - location)
                )
            )
        }
    }

    private func applyAppearance(to scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        scrollView.appearance = palette.category.appearance
        textView.appearance = palette.category.appearance
        textView.backgroundColor = palette.colors.background.nsColor
        textView.textColor = palette.colors.foreground.nsColor
        textView.insertionPointColor = palette.colors.caret.nsColor
        textView.selectedTextAttributes = [
            .backgroundColor: palette.colors.selectionBackground.nsColor,
            .foregroundColor: palette.colors.selectionForeground.nsColor,
        ]
        scrollView.backgroundColor = palette.colors.gutterBackground.nsColor
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditorView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isSyncing = false
        var isApplyingExternalText = false
        var lastHighlightedText = ""
        var lastFontSize: CGFloat = 0
        var lastPaletteID: ThemeID?
        var lastHandledCommandID: UUID?
        var lastHandledFindID: UUID?
        var lastHandledOutlineID: UUID?
        private var notificationObservers: [NSObjectProtocol] = []

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            super.init()

            let scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleScroll(notification)
            }

            notificationObservers = [scrollObserver]
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
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters),
                  !isApplyingExternalText,
                  let textView else { return }

            let currentText = textStorage.string
            let affectsFence = editTouchesFence(
                previousText: lastHighlightedText,
                currentText: currentText,
                editedRange: editedRange,
                changeInLength: delta
            )
            parent.applyHighlighting(
                to: textView,
                editedRange: editedRange,
                rehighlightToEnd: affectsFence
            )
            lastHighlightedText = currentText
        }

        func handle(_ request: EditorCommandRequest?) {
            guard let request, request.id != lastHandledCommandID else { return }
            lastHandledCommandID = request.id

            switch request.command {
            case .bold:
                wrapSelection(with: "**")
            case .italic:
                wrapSelection(with: "_")
            case .link:
                insertLink()
            }
        }

        func handle(_ request: FindCommandRequest?) {
            guard let request,
                  request.id != lastHandledFindID,
                  let textView else { return }
            lastHandledFindID = request.id

            let action: NSFindPanelAction
            switch request.command {
            case .show: action = .showFindPanel
            case .next: action = .next
            case .previous: action = .previous
            case .dismiss:
                textView.window?.makeFirstResponder(textView)
                return
            }
            let sender = NSMenuItem()
            sender.tag = Int(action.rawValue)
            textView.window?.makeFirstResponder(textView)
            textView.performFindPanelAction(sender)
        }

        func handle(_ request: EditorOutlineRequest?) {
            guard let request,
                  request.id != lastHandledOutlineID,
                  let textView else { return }
            lastHandledOutlineID = request.id
            let location = min(
                max(request.location, 0),
                (textView.string as NSString).length
            )
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.window?.makeFirstResponder(textView)
            parent.onFocus?()
        }

        private func wrapSelection(with marker: String) {
            guard let textView = textView,
                  textView.window?.firstResponder == textView else { return }
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
            guard let textView = textView,
                  textView.window?.firstResponder == textView else { return }
            let range = textView.selectedRange()
            let string = textView.string as NSString
            let selected = string.substring(with: range)
            let replacement = "[\(selected)](url)"
            textView.insertText(replacement, replacementRange: range)
            let urlStart = range.location + (selected as NSString).length + 2
            textView.setSelectedRange(NSRange(location: urlStart, length: 3))
        }

        private func editTouchesFence(
            previousText: String,
            currentText: String,
            editedRange: NSRange,
            changeInLength: Int
        ) -> Bool {
            line(
                in: currentText,
                at: editedRange
            ).contains("```") || line(
                in: previousText,
                at: NSRange(
                    location: min(
                        editedRange.location,
                        (previousText as NSString).length
                    ),
                    length: max(0, editedRange.length - changeInLength)
                )
            ).contains("```")
        }

        private func line(in text: String, at range: NSRange) -> String {
            let nsText = text as NSString
            let location = min(range.location, nsText.length)
            let length = min(max(range.length, 0), nsText.length - location)
            return nsText.substring(
                with: nsText.lineRange(
                    for: NSRange(location: location, length: length)
                )
            )
        }
    }
}
