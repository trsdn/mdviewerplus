import Foundation

struct OutlineEntry: Identifiable, Equatable {
    let slug: String
    let level: Int
    let title: String
    let sourceLocation: Int?

    var id: String { slug }

    init(
        slug: String,
        level: Int,
        title: String,
        sourceLocation: Int? = nil
    ) {
        self.slug = slug
        self.level = min(max(level, 1), 6)
        self.title = title
        self.sourceLocation = sourceLocation
    }

    init?(payload: [String: Any]) {
        guard let slug = payload["slug"] as? String,
              !slug.isEmpty,
              let title = payload["title"] as? String else {
            return nil
        }
        self.init(
            slug: slug,
            level: (payload["level"] as? NSNumber)?.intValue ?? 1,
            title: title
        )
    }
}

enum HeadingSlugger {
    static func slug(_ title: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !result.isEmpty { previousWasSeparator = true }
                continue
            }
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar.value > 127 || scalar == "_" {
                if previousWasSeparator, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if scalar == "-" {
                if !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                previousWasSeparator = false
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }

    static func unique(_ title: String, used: inout Set<String>) -> String {
        let base = slug(title)
        var candidate = base
        var suffix = 1
        while used.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }
}

enum DocumentOutlineParser {
    static let maximumEntries = 5_000

    static func parse(_ markdown: String) -> [OutlineEntry] {
        let nsText = markdown as NSString
        var entries: [OutlineEntry] = []
        var used = Set<String>()
        var inFence = false
        var previousLine: (text: String, location: Int)?

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, enclosingRange, stop in
            let line = nsText.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                previousLine = nil
                return
            }
            guard !inFence else { return }

            if let heading = atxHeading(line) {
                let title = plainTitle(heading.title)
                entries.append(
                    OutlineEntry(
                        slug: HeadingSlugger.unique(title, used: &used),
                        level: heading.level,
                        title: title,
                        sourceLocation: lineRange.location
                    )
                )
                previousLine = nil
            } else if let candidate = previousLine,
                      !candidate.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty,
                      let level = setextLevel(trimmed) {
                let title = plainTitle(candidate.text)
                entries.append(
                    OutlineEntry(
                        slug: HeadingSlugger.unique(title, used: &used),
                        level: level,
                        title: title,
                        sourceLocation: candidate.location
                    )
                )
                previousLine = nil
            } else {
                previousLine = (
                    nsText.substring(with: lineRange),
                    enclosingRange.location
                )
            }

            if entries.count >= maximumEntries {
                stop.pointee = true
            }
        }
        return entries
    }

    private static func atxHeading(
        _ line: String
    ) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let index = trimmed.index(trimmed.startIndex, offsetBy: hashes)
        guard index < trimmed.endIndex,
              trimmed[index].isWhitespace else { return nil }
        var title = String(trimmed[index...])
            .trimmingCharacters(in: .whitespaces)
        title = title.replacingOccurrences(
            of: #"[ \t]+#+[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        return (hashes, title)
    }

    private static func setextLevel(_ line: String) -> Int? {
        guard line.count >= 1 else { return nil }
        if line.allSatisfy({ $0 == "=" }) { return 1 }
        if line.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func plainTitle(_ title: String) -> String {
        title
            .replacingOccurrences(
                of: #"!\[([^\]]*)\]\([^)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[*_~`]+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

enum OutlineFilter {
    static func filter(
        _ entries: [OutlineEntry],
        query: String
    ) -> [OutlineEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    static func indentationLevels(for entries: [OutlineEntry]) -> [Int] {
        guard let minimum = entries.map(\.level).min() else { return [] }
        return entries.map { $0.level - minimum }
    }
}
