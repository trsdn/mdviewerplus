import Foundation

struct DebounceScheduler {
    typealias Cancellation = () -> Void
    let schedule: (
        _ delay: TimeInterval,
        _ action: @escaping () -> Void
    ) -> Cancellation

    static let main = DebounceScheduler { delay, action in
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
        return { workItem.cancel() }
    }
}

final class LatestValueDebouncer<Value> {
    private let delay: TimeInterval
    private let scheduler: DebounceScheduler
    private var cancellation: DebounceScheduler.Cancellation?
    private var generation = 0

    init(delay: TimeInterval, scheduler: DebounceScheduler = .main) {
        self.delay = delay
        self.scheduler = scheduler
    }

    func submit(_ value: Value, action: @escaping (Value) -> Void) {
        cancellation?()
        generation += 1
        let scheduledGeneration = generation

        cancellation = scheduler.schedule(delay) { [weak self] in
            guard let self, self.generation == scheduledGeneration else { return }
            self.cancellation = nil
            action(value)
        }
    }

    func cancel() {
        cancellation?()
        cancellation = nil
        generation += 1
    }
}
