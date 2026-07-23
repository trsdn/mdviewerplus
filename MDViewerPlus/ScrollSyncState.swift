import CoreGraphics

struct PreviewScrollCommand: Equatable {
    let fraction: CGFloat
    let generation: Int
}

struct ScrollSyncState {
    private let epsilon: CGFloat
    private var nextGeneration = 0
    private var lastEditorFraction: CGFloat?

    init(epsilon: CGFloat = 0.001) {
        self.epsilon = epsilon
    }

    mutating func command(
        forEditorFraction fraction: CGFloat,
        force: Bool = false
    ) -> PreviewScrollCommand? {
        let clamped = min(max(fraction, 0), 1)
        if !force,
           let lastEditorFraction,
           abs(lastEditorFraction - clamped) <= epsilon {
            return nil
        }

        nextGeneration += 1
        lastEditorFraction = clamped
        return PreviewScrollCommand(
            fraction: clamped,
            generation: nextGeneration
        )
    }

    mutating func shouldAcceptPreviewScroll(generation: Int?) -> Bool {
        guard generation == nil else { return false }
        lastEditorFraction = nil
        return true
    }
}
