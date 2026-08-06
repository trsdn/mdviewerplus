import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage("appearanceMode") private var storedAppearanceMode =
        AppearanceMode.system.rawValue
    @AppStorage("lightThemeID") private var lightThemeID =
        ThemeRegistry.defaultLightThemeID.rawValue
    @AppStorage("darkThemeID") private var darkThemeID =
        ThemeRegistry.defaultDarkThemeID.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearanceModeSelector")

            themePicker(
                title: "Light theme",
                selection: lightThemeSelection,
                palettes: ThemeRegistry.lightPalettes,
                accessibilityIdentifier: "lightThemePicker"
            )

            themePicker(
                title: "Dark theme",
                selection: darkThemeSelection,
                palettes: ThemeRegistry.darkPalettes,
                accessibilityIdentifier: "darkThemePicker"
            )

            Text("System follows the current macOS appearance and uses the selected light or dark palette.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
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
