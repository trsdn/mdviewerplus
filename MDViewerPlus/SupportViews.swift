import SwiftUI

enum AppSupport {
    static let websiteURL = URL(string: "https://trsdn.github.io/mdviewerplus/")!
    static let sourceURL = URL(string: "https://github.com/trsdn/mdviewerplus")!
    static let issueURL = URL(
        string: "https://github.com/trsdn/mdviewerplus/issues/new"
    )!
    static let copyright = "Copyright © 2026 Torsten Mahr"
}

struct AuxiliaryWindowPolicy: Equatable {
    let allowsMinimize: Bool
    let allowsZoom: Bool

    static let settings = AuxiliaryWindowPolicy(
        allowsMinimize: false,
        allowsZoom: false
    )
    static let help = AuxiliaryWindowPolicy(
        allowsMinimize: true,
        allowsZoom: false
    )
}

struct AuxiliaryWindowConfigurator: NSViewRepresentable {
    let policy: AuxiliaryWindowPolicy

    func makeNSView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.policy = policy
        return view
    }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        nsView.policy = policy
        nsView.applyPolicy()
    }

    final class ConfigurationView: NSView {
        var policy = AuxiliaryWindowPolicy.settings {
            didSet {
                applyPolicy()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyPolicy()
        }

        func applyPolicy() {
            guard let window else { return }

            if policy.allowsMinimize {
                window.styleMask.insert(.miniaturizable)
            } else {
                window.styleMask.remove(.miniaturizable)
            }

            window.standardWindowButton(.miniaturizeButton)?.isEnabled =
                policy.allowsMinimize
            window.standardWindowButton(.zoomButton)?.isEnabled =
                policy.allowsZoom
        }
    }
}

struct SupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MDViewer+") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .help) {
            Button("MDViewer+ Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Link("MDViewer+ Website", destination: AppSupport.websiteURL)
            Link("View Source on GitHub", destination: AppSupport.sourceURL)
            Link("Report an Issue…", destination: AppSupport.issueURL)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("MDViewer+")
                .font(.largeTitle.bold())

            Text(AppVersion.edition.displayName + " Edition")
                .font(.headline)

            Text(
                "Version \(AppVersion.marketingVersion) " +
                "(Build \(AppVersion.buildVersion))"
            )
            .foregroundStyle(.secondary)

            Text(AppSupport.copyright)
                .font(.callout)

            Divider()

            VStack(spacing: 8) {
                Link("Website", destination: AppSupport.websiteURL)
                Link("Source Code", destination: AppSupport.sourceURL)
                Link("Report an Issue", destination: AppSupport.issueURL)
            }
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(width: 420)
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Native, offline Markdown editing and preview.")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                helpSection("Get started") {
                    Text(
                        "Open a Markdown file, then use the mode control in the " +
                        "toolbar to switch between View, Split, and Edit."
                    )
                }

                helpSection("Folder Navigator") {
                    Text(
                        "The optional Folder Navigator is hidden by default and " +
                        "stays available in View, Split, and Edit modes. Use " +
                        "File > Open Folder… to authorize the current folder or " +
                        "a parent folder, and Navigate > Reveal Current Document " +
                        "in Folder Navigator to locate the open file."
                    )
                    Text(
                        "The navigator is read-only and local-only. It loads one " +
                        "directory at a time, excludes hidden items, packages, " +
                        "symbolic links, and unsupported files, and limits browsing " +
                        "to 12 levels, 500 children per folder, and 5,000 loaded " +
                        "items. Only loaded folders refresh after filesystem events. " +
                        "Opening another file keeps a source window with unsaved " +
                        "edits open."
                    )
                }

                helpSection("Keyboard shortcuts") {
                    VStack(spacing: 0) {
                        shortcut("Show or hide Folder Navigator", "⇧⌘B")
                        shortcut("Find", "⌘F")
                        shortcut("Quick Open in the current folder", "⌘K")
                        shortcut("Document Outline", "⇧⌘O")
                        shortcut("Previous Markdown file", "⌥⌘←")
                        shortcut("Next Markdown file", "⌥⌘→")
                        shortcut("Toggle view mode", "⌘E")
                        shortcut("Reload preview", "⌘R")
                        shortcut("Print", "⌘P")
                        shortcut("Zoom in, out, or reset", "⌘+  ⌘−  ⌘0")
                    }
                }

                helpSection("Lite and Full") {
                    Text(
                        "Both editions share the same native features. Full adds " +
                        "broad syntax highlighting, YAML frontmatter, and Mermaid " +
                        "diagrams. Lite keeps a smaller offline footprint."
                    )
                }

                helpSection("Support") {
                    Link("MDViewer+ Website", destination: AppSupport.websiteURL)
                    Link("Source Code and Documentation", destination: AppSupport.sourceURL)
                    Link("Report an Issue", destination: AppSupport.issueURL)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 600, height: 580)
        .background(
            AuxiliaryWindowConfigurator(policy: .help)
                .frame(width: 0, height: 0)
        )
    }

    private func helpSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    private func shortcut(_ action: String, _ keys: String) -> some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
