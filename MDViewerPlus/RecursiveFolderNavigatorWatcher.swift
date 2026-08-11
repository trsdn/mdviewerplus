import Combine
import CoreServices
import Foundation

@MainActor
final class RecursiveFolderNavigatorWatcher: ObservableObject {
    static let defaultLatency: CFTimeInterval = 0.25

    private var stream: FSEventStreamRef?
    private var generation = 0
    private var callback: (([URL], Bool, Bool) -> Void)?

    private final class StreamCallbackContext {
        weak var watcher: RecursiveFolderNavigatorWatcher?
        let generation: Int

        init(watcher: RecursiveFolderNavigatorWatcher, generation: Int) {
            self.watcher = watcher
            self.generation = generation
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    @discardableResult
    func start(
        rootURL: URL,
        onChange: @escaping ([URL], Bool, Bool) -> Void
    ) -> Bool {
        stop()
        generation &+= 1
        let streamGeneration = generation
        callback = onChange
        let callbackContext = StreamCallbackContext(
            watcher: self,
            generation: streamGeneration
        )
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackContext).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<StreamCallbackContext>
                    .fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<StreamCallbackContext>
                    .fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let created = FSEventStreamCreate(
            nil,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let context = Unmanaged<StreamCallbackContext>
                    .fromOpaque(info).takeUnretainedValue()
                let values = unsafeBitCast(paths, to: NSArray.self)
                var urls: [URL] = []
                var terminal = false
                var needsFullRefresh = false
                for index in 0..<count {
                    if let path = values[index] as? String {
                        urls.append(URL(fileURLWithPath: path))
                    }
                    let eventFlags = flags[index]
                    terminal = terminal
                        || RecursiveFolderNavigatorWatcher
                            .isTerminal(flags: eventFlags)
                    needsFullRefresh = needsFullRefresh
                        || RecursiveFolderNavigatorWatcher
                            .requiresFullRefresh(flags: eventFlags)
                }
                Task { @MainActor in
                    context.watcher?.deliver(
                        urls,
                        terminal: terminal,
                        requiresFullRefresh: needsFullRefresh,
                        producingGeneration: context.generation
                    )
                }
            },
            &context,
            [FolderNavigatorPath.canonical(rootURL).path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.defaultLatency,
            flags
        ) else { return false }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        generation &+= 1
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        callback = nil
    }

    private func deliver(
        _ urls: [URL],
        terminal: Bool,
        requiresFullRefresh: Bool,
        producingGeneration: Int
    ) {
        guard Self.shouldDeliver(
            producingGeneration: producingGeneration,
            currentGeneration: generation
        ) else { return }
        let handler = callback
        if terminal { stop() }
        handler?(urls, terminal, requiresFullRefresh)
    }

    nonisolated static func shouldDeliver(
        producingGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        producingGeneration == currentGeneration
    }

    nonisolated static func requiresFullRefresh(
        flags: FSEventStreamEventFlags
    ) -> Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
        ) != 0
    }

    nonisolated static func isTerminal(
        flags: FSEventStreamEventFlags
    ) -> Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagUnmount
        ) != 0
    }
}
