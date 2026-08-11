#if DEBUG
import Foundation

@MainActor
enum UITestHooks {
    private static var consumedInitialDocument = false
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MDVIEWER_UI_TEST_MODE"] == "1"
    }

    static var authorizedFolderURL: URL? {
        guard isEnabled else { return nil }
        return ProcessInfo.processInfo.environment["MDVIEWER_UI_TEST_FOLDER"].map {
            FolderNavigatorPath.canonical(URL(fileURLWithPath: $0))
        }
    }

    static func consumeInitialDocumentURL() -> URL? {
        guard isEnabled,
              !consumedInitialDocument,
              let path = ProcessInfo.processInfo.environment[
                "MDVIEWER_UI_TEST_DOCUMENT"
              ] else {
            return nil
        }
        consumedInitialDocument = true
        return FolderNavigatorPath.canonical(URL(fileURLWithPath: path))
    }
}
#endif
