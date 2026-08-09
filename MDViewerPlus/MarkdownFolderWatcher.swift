import Combine
import Darwin
import Foundation

@MainActor
final class MarkdownFolderWatcher: ObservableObject {
    static let defaultDebounce: Duration = .milliseconds(250)

    private let debounce: Duration
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var generation = 0
    private var onChange: (() -> Void)?

    @Published private(set) var watchedFolder: URL?

    init(debounce: Duration = .milliseconds(250)) {
        self.debounce = debounce
    }

    deinit {
        source?.cancel()
        debounceTask?.cancel()
    }

    @discardableResult
    func start(
        watching folderURL: URL,
        onChange: @escaping () -> Void
    ) -> Bool {
        stop()
        let canonicalFolder = MarkdownFileCatalog.canonical(folderURL)
        let descriptor = open(canonicalFolder.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        generation &+= 1
        let watchGeneration = generation
        watchedFolder = canonicalFolder
        self.onChange = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let terminal = source.data.intersection(
                [.rename, .delete, .revoke]
            ).isEmpty == false
            self.schedule(
                generation: watchGeneration,
                stopAfterNotification: terminal
            )
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
        return true
    }

    func stop() {
        generation &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        watchedFolder = nil
        onChange = nil
    }

    private func schedule(
        generation watchGeneration: Int,
        stopAfterNotification: Bool
    ) {
        guard watchGeneration == generation else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled,
                  watchGeneration == generation else { return }
            let callback = onChange
            if stopAfterNotification { stop() }
            callback?()
        }
    }
}
