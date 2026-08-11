import Foundation

struct FolderNavigatorPendingContext: Equatable {
    let rootURL: URL
    let isVisible: Bool
    let expandedRelativePaths: Set<String>
    let selectedRelativePath: String?
    let width: Double
}

@MainActor
final class FolderNavigatorContextStore {
    static let shared = FolderNavigatorContextStore()

    private struct Entry {
        let token: UUID
        let context: FolderNavigatorPendingContext
        let createdAt: Date
        let ordinal: UInt64
    }

    private let expirationInterval: TimeInterval
    private let maximumEntries: Int
    private let now: () -> Date
    private var contexts: [URL: Entry] = [:]
    private var nextOrdinal: UInt64 = 0

    init(
        expirationInterval: TimeInterval = 300,
        maximumEntries: Int = 128,
        now: @escaping () -> Date = Date.init
    ) {
        precondition(expirationInterval > 0)
        precondition(maximumEntries > 0)
        self.expirationInterval = expirationInterval
        self.maximumEntries = maximumEntries
        self.now = now
    }

    @discardableResult
    func store(
        _ context: FolderNavigatorPendingContext,
        for destination: URL
    ) -> UUID {
        pruneExpired()
        let token = UUID()
        nextOrdinal &+= 1
        contexts[FolderNavigatorPath.canonical(destination)] = Entry(
            token: token,
            context: context,
            createdAt: now(),
            ordinal: nextOrdinal
        )
        pruneOverflow()
        return token
    }

    func consume(for destination: URL) -> FolderNavigatorPendingContext? {
        pruneExpired()
        return contexts.removeValue(
            forKey: FolderNavigatorPath.canonical(destination)
        )?.context
    }

    func clear(for destination: URL, matching token: UUID? = nil) {
        pruneExpired()
        let key = FolderNavigatorPath.canonical(destination)
        guard token == nil || contexts[key]?.token == token else { return }
        contexts.removeValue(forKey: key)
    }

    var pendingCount: Int {
        pruneExpired()
        return contexts.count
    }

    private func pruneExpired() {
        let currentDate = now()
        contexts = contexts.filter {
            currentDate.timeIntervalSince($0.value.createdAt)
                < expirationInterval
        }
    }

    private func pruneOverflow() {
        guard contexts.count > maximumEntries else { return }
        let overflow = contexts.count - maximumEntries
        let oldestKeys = contexts.sorted {
            $0.value.ordinal < $1.value.ordinal
        }.prefix(overflow).map(\.key)
        for key in oldestKeys {
            contexts.removeValue(forKey: key)
        }
    }
}
