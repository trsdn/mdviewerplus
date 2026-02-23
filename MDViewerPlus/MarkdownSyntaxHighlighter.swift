import AppKit

struct MarkdownSyntaxHighlighter {
    let baseFont: NSFont
    let isDark: Bool

    // MARK: - Colors

    private var textColor: NSColor {
        isDark
            ? NSColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 1.0)
            : NSColor(red: 0.141, green: 0.161, blue: 0.184, alpha: 1.0)
    }

    private var accentColor: NSColor {
        isDark
            ? NSColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 1.0)   // #58a6ff
            : NSColor(red: 0.035, green: 0.412, blue: 0.855, alpha: 1.0) // #0969da
    }

    private var codeColor: NSColor {
        isDark
            ? NSColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 0.85)
            : NSColor(red: 0.141, green: 0.161, blue: 0.184, alpha: 0.85)
    }

    private var codeBgColor: NSColor {
        isDark
            ? NSColor(red: 0.086, green: 0.106, blue: 0.133, alpha: 1.0) // #161b22
            : NSColor(red: 0.965, green: 0.973, blue: 0.980, alpha: 1.0) // #f6f8fa
    }

    private var mutedColor: NSColor {
        isDark
            ? NSColor(red: 0.545, green: 0.580, blue: 0.620, alpha: 1.0) // #8b949e
            : NSColor(red: 0.396, green: 0.427, blue: 0.463, alpha: 1.0) // #656d76
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

    func highlight(_ textStorage: NSTextStorage?) {
        guard let textStorage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let source = textStorage.string

        textStorage.beginEditing()

        // Reset to base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
        ]
        textStorage.setAttributes(baseAttributes, range: fullRange)

        for (name, regex) in Self.compiledPatterns {
            let matches = regex.matches(in: source, range: fullRange)
            for match in matches {
                applyStyle(name: name, match: match, textStorage: textStorage)
            }
        }

        textStorage.endEditing()
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
