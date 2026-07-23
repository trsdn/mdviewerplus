import XCTest
@testable import MDViewerPlus

final class LatestValueDebouncerTests: XCTestCase {
    func testOnlyLatestSubmittedValueRuns() {
        let scheduler = TestDebounceScheduler()
        let debouncer = LatestValueDebouncer<String>(
            delay: 0.15,
            scheduler: scheduler.scheduler
        )
        var received: [String] = []

        debouncer.submit("first") { received.append($0) }
        debouncer.submit("second") { received.append($0) }
        debouncer.submit("latest") { received.append($0) }
        scheduler.runAll()

        XCTAssertEqual(received, ["latest"])
    }

    func testCancelPreventsPendingAction() {
        let scheduler = TestDebounceScheduler()
        let debouncer = LatestValueDebouncer<Int>(
            delay: 0.15,
            scheduler: scheduler.scheduler
        )
        var received: [Int] = []

        debouncer.submit(1) { received.append($0) }
        debouncer.cancel()
        scheduler.runAll()

        XCTAssertTrue(received.isEmpty)
    }
}

private final class TestDebounceScheduler {
    private struct Entry {
        let action: () -> Void
        var isCancelled: Bool
    }

    private var entries: [Entry] = []

    lazy var scheduler = DebounceScheduler { [weak self] _, action in
        guard let self else { return {} }
        let index = entries.count
        entries.append(Entry(action: action, isCancelled: false))
        return { [weak self] in
            guard let self, entries.indices.contains(index) else { return }
            entries[index].isCancelled = true
        }
    }

    func runAll() {
        let pending = entries
        entries.removeAll()
        for entry in pending where !entry.isCancelled {
            entry.action()
        }
    }
}
