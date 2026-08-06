import AppKit

struct MarkdownSyntaxHighlighter {
    let baseFont: NSFont
    let palette: MarkdownSyntaxPalette

    // MARK: - Colors

    private var textColor: NSColor {
        palette.text.nsColor
    }

    private var accentColor: NSColor {
        palette.accent.nsColor
    }

    private var codeColor: NSColor {
        palette.code.nsColor
    }

    private var codeBgColor: NSColor {
        palette.codeBackground.nsColor
    }

    private var mutedColor: NSColor {
        palette.muted.nsColor
    }

    // MARK: - Fonts

    private var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)
    }

    private var italicFont: NSFont {
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    // MARK: - Patterns

    private static let compiledPatterns: [(name: String, regex: NSRegularExpression)] = {
        let defs: [(String, String, NSRegularExpression.Options)] = [
            ("heading",     "^#{1,6}\\s.*$",                             .anchorsMatchLines),
            ("bold",        "\\*\\*(.+?)\\*\\*",                         []),
            ("italic",      "(?<![\\*_])([\\*_])(?!\\1)(.+?)\\1(?!\\1)", []),
            ("fencedCode",  "^```[\\s\\S]*?^```",                        .anchorsMatchLines),
            ("inlineCode",  "`([^`\n]+?)`",                              []),
            ("link",        "\\[.+?\\]\\(.+?\\)",                        []),
            ("blockquote",  "^>.*$",                                     .anchorsMatchLines),
            ("listMarker",  "^(\\s*[-*+]|\\s*\\d+\\.)\\s",              .anchorsMatchLines),
        ]
        return defs.compactMap { name, pattern, options in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return nil
            }
            return (name, regex)
        }
    }()

    // MARK: - Highlight

    func highlight(
        _ textStorage: NSTextStorage?,
        editedRange: NSRange? = nil,
        rehighlightToEnd: Bool = false
    ) {
        guard let textStorage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let source = textStorage.string
        let targetRange = targetRange(
            in: source,
            fullRange: fullRange,
            editedRange: editedRange,
            rehighlightToEnd: rehighlightToEnd
        )

        textStorage.beginEditing()

        // Reset to base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
        ]
        textStorage.setAttributes(baseAttributes, range: targetRange)

        for (name, regex) in Self.compiledPatterns {
            let matches = regex.matches(in: source, range: targetRange)
            for match in matches {
                applyStyle(name: name, match: match, textStorage: textStorage)
            }
        }

        textStorage.endEditing()
    }

    private func targetRange(
        in source: String,
        fullRange: NSRange,
        editedRange: NSRange?,
        rehighlightToEnd: Bool
    ) -> NSRange {
        guard let editedRange else { return fullRange }

        let nsSource = source as NSString
        let location = min(max(editedRange.location, 0), fullRange.length)
        let length = min(
            max(editedRange.length, 0),
            fullRange.length - location
        )
        var target = nsSource.lineRange(
            for: NSRange(location: location, length: length)
        )

        if rehighlightToEnd {
            target.length = fullRange.length - target.location
            return target
        }

        guard let fencedCodeRegex = Self.compiledPatterns.first(
            where: { $0.name == "fencedCode" }
        )?.regex else {
            return target
        }

        for match in fencedCodeRegex.matches(in: source, range: fullRange)
        where NSIntersectionRange(match.range, target).length > 0 {
            target = NSUnionRange(target, match.range)
        }
        return target
    }

    private func applyStyle(name: String, match: NSTextCheckingResult, textStorage: NSTextStorage) {
        let range = match.range
        switch name {
        case "heading":
            textStorage.addAttributes([
                .foregroundColor: accentColor,
                .font: boldFont,
            ], range: range)

        case "bold":
            textStorage.addAttribute(.font, value: boldFont, range: range)

        case "italic":
            textStorage.addAttribute(.font, value: italicFont, range: range)

        case "fencedCode":
            textStorage.addAttributes([
                .foregroundColor: codeColor,
                .backgroundColor: codeBgColor,
            ], range: range)

        case "inlineCode":
            textStorage.addAttributes([
                .foregroundColor: codeColor,
                .backgroundColor: codeBgColor,
            ], range: range)

        case "link":
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: range)

        case "blockquote":
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)

        case "listMarker":
            // Only color the marker portion (capture group 1), not the trailing space
            if match.numberOfRanges > 1 {
                let markerRange = match.range(at: 1)
                textStorage.addAttribute(.foregroundColor, value: accentColor, range: markerRange)
            }

        default:
            break
        }
    }
}
