import Foundation

enum MarkdownFrontmatter {
    struct Split: Equatable {
        let source: String
        let body: String
        let bodyUTF16Offset: Int
    }

    static func split(_ markdown: String) -> Split? {
        let text = markdown as NSString
        guard text.length > 0 else { return nil }

        var firstStart = 0
        var firstEnd = 0
        var firstContentsEnd = 0
        text.getLineStart(
            &firstStart,
            end: &firstEnd,
            contentsEnd: &firstContentsEnd,
            for: NSRange(location: 0, length: 0)
        )
        guard firstStart == 0,
              text.substring(
                with: NSRange(location: 0, length: firstContentsEnd)
              ) == "---",
              firstEnd > firstContentsEnd else {
            return nil
        }

        let sourceStart = firstEnd
        var lineStart = firstEnd
        while lineStart < text.length {
            var currentStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                &currentStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: lineStart, length: 0)
            )

            let line = text.substring(
                with: NSRange(
                    location: currentStart,
                    length: contentsEnd - currentStart
                )
            )
            if line == "---" {
                return Split(
                    source: text.substring(
                        with: NSRange(
                            location: sourceStart,
                            length: currentStart - sourceStart
                        )
                    ),
                    body: text.substring(
                        from: lineEnd
                    ),
                    bodyUTF16Offset: lineEnd
                )
            }
            lineStart = lineEnd
        }

        return nil
    }
}
