import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage("appearanceMode") private var storedAppearanceMode =
        AppearanceMode.system.rawValue
    @AppStorage("lightThemeID") private var lightThemeID =
        ThemeRegistry.defaultLightThemeID.rawValue
    @AppStorage("darkThemeID") private var darkThemeID =
        ThemeRegistry.defaultDarkThemeID.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 16,
                verticalSpacing: 14
            ) {
                GridRow {
                    Text("Appearance")
                        .gridColumnAlignment(.trailing)

                    Picker("Appearance", selection: appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("appearanceModeSelector")
                }

                GridRow {
                    Text("Light theme")

                    themePicker(
                        title: "Light theme",
                        selection: lightThemeSelection,
                        palettes: ThemeRegistry.lightPalettes,
                        accessibilityIdentifier: "lightThemePicker"
                    )
                    .labelsHidden()
                }

                GridRow {
                    Text("Dark theme")

                    themePicker(
                        title: "Dark theme",
                        selection: darkThemeSelection,
                        palettes: ThemeRegistry.darkPalettes,
                        accessibilityIdentifier: "darkThemePicker"
                    )
                    .labelsHidden()
                }
            }

            Text(
                "System follows the current macOS appearance and uses the " +
                "selected light or dark palette."
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.headline)

                Text(AppVersion.summary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("editionVersion")

                Text(
                    AppVersion.edition == .full
                        ? "Full includes lazy offline Mermaid, broad syntax highlighting, and YAML metadata cards."
                        : "Lite includes the minimal Prism language set and physically excludes all Full-only renderers."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            AuxiliaryWindowConfigurator(policy: .settings)
                .frame(width: 0, height: 0)
        )
    }

    private var appearanceMode: Binding<String> {
        Binding(
            get: {
                AppearanceMode(rawValue: storedAppearanceMode)?.rawValue
                    ?? AppearanceMode.system.rawValue
            },
            set: { storedAppearanceMode = $0 }
        )
    }

    private var lightThemeSelection: Binding<String> {
        Binding(
            get: {
                ThemeRegistry.palette(id: lightThemeID, category: .light).id.rawValue
            },
            set: { lightThemeID = $0 }
        )
    }

    private var darkThemeSelection: Binding<String> {
        Binding(
            get: {
                ThemeRegistry.palette(id: darkThemeID, category: .dark).id.rawValue
            },
            set: { darkThemeID = $0 }
        )
    }

    private func themePicker(
        title: String,
        selection: Binding<String>,
        palettes: [ThemePalette],
        accessibilityIdentifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(palettes) { palette in
                ThemePickerLabel(palette: palette)
                    .tag(palette.id.rawValue)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ThemePickerLabel: View {
    let palette: ThemePalette

    var body: some View {
        HStack {
            Text(palette.name)
            Spacer()
            HStack(spacing: 3) {
                swatch(palette.colors.background)
                swatch(palette.colors.foreground)
                swatch(palette.colors.link)
                swatch(palette.colors.codeBackground)
            }
            .accessibilityHidden(true)
        }
    }

    private func swatch(_ color: ThemeColor) -> some View {
        Circle()
            .fill(color.swiftUIColor)
            .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
            .frame(width: 11, height: 11)
    }
}
