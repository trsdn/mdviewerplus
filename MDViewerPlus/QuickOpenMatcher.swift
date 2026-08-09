import Foundation

struct QuickOpenItem: Identifiable, Equatable {
    let url: URL

    var name: String { url.lastPathComponent }
    var id: String { url.path }
}

enum QuickOpenMatcher {
    static let resultLimit = 200

    private enum Rank: Int {
        case exact
        case prefix
        case wordPrefix
        case substring
        case subsequence
    }

    private struct Match {
        let item: QuickOpenItem
        let rank: Rank
        let offset: Int
    }

    static func filter(
        _ items: [QuickOpenItem],
        query: String
    ) -> [QuickOpenItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return Array(items.prefix(resultLimit))
        }

        let needle = Array(query.lowercased())
        var matches: [Match] = []
        for item in items {
            guard let score = score(
                haystack: Array(item.name.lowercased()),
                needle: needle
            ) else {
                continue
            }
            matches.append(
                Match(item: item, rank: score.rank, offset: score.offset)
            )
        }
        matches.sort {
            if $0.rank != $1.rank {
                return $0.rank.rawValue < $1.rank.rawValue
            }
            if $0.offset != $1.offset { return $0.offset < $1.offset }
            if $0.item.name.count != $1.item.name.count {
                return $0.item.name.count < $1.item.name.count
            }
            return MarkdownFileCatalog.filenamePrecedes(
                $0.item.url,
                $1.item.url
            )
        }
        return matches.prefix(resultLimit).map(\.item)
    }

    private static func score(
        haystack: [Character],
        needle: [Character]
    ) -> (rank: Rank, offset: Int)? {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return nil
        }
        if haystack == needle { return (.exact, 0) }
        if haystack.starts(with: needle) { return (.prefix, 0) }
        if let offset = contiguousOffset(of: needle, in: haystack) {
            let isWordStart = offset == 0 || isSeparator(haystack[offset - 1])
            return (isWordStart ? .wordPrefix : .substring, offset)
        }

        var needleIndex = 0
        var firstOffset: Int?
        for (index, character) in haystack.enumerated() {
            guard character == needle[needleIndex] else { continue }
            if firstOffset == nil { firstOffset = index }
            needleIndex += 1
            if needleIndex == needle.count {
                return (.subsequence, firstOffset ?? index)
            }
        }
        return nil
    }

    private static func contiguousOffset(
        of needle: [Character],
        in haystack: [Character]
    ) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_"
            || character == "." || character == "/"
    }
}
