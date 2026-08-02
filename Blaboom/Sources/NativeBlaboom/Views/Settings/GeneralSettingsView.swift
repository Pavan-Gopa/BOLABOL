import NativeBlaboomCore
import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    var body: some View {
        Form {
            // Consolidated Interface & Theme Section (2x more compact in height!)
            Section {
                Picker(generalSettingsStore.text(.appearance), selection: themeSelection) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(themeTitle(theme))
                            .tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(generalSettingsStore.text(.uiFontSize))
                    Spacer()
                    Slider(value: uiScale, in: 0.8...1.4, step: 0.05)
                        .frame(width: 265)
                    Text("\(generalSettingsStore.uiScalePercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text(generalSettingsStore.text(.contentTextSize))
                    Spacer()
                    Slider(value: contentTextScale, in: 1.0...2.0, step: 0.05)
                        .frame(width: 265)
                    Text("\(Int(generalSettingsStore.settings.textScale * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                Picker(generalSettingsStore.text(.contentFont), selection: contentFontSelection) {
                    Text(generalSettingsStore.text(.fontSystem)).tag(TextFontPreference.system)
                    Text(generalSettingsStore.text(.fontSerif)).tag(TextFontPreference.serif)
                    Text(generalSettingsStore.text(.fontMonospaced)).tag(TextFontPreference.monospaced)
                }

                Picker(generalSettingsStore.text(.interfaceLanguage), selection: languageSelection) {
                    ForEach(UILanguagePreference.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            } header: {
                Text(generalSettingsStore.text(.theme))
                    .font(.title3.weight(.bold))
                    .padding(.top, -10)
                    .padding(.bottom, -6)
            }

            // Audio Archive Retention & Storage Section
            Section {
                HStack(spacing: 14) {
                    Toggle(
                        generalSettingsStore.text(.autoDeleteOldRecordings),
                        isOn: Binding(
                            get: { generalSettingsStore.settings.isAutoArchiveCleanupEnabled },
                            set: { newValue in
                                generalSettingsStore.update { $0.isAutoArchiveCleanupEnabled = newValue }
                            }
                        )
                    )

                    Spacer()

                    HStack(spacing: 6) {
                        Text(generalSettingsStore.text(.maxSavedRecordings))
                            .foregroundStyle(generalSettingsStore.settings.isAutoArchiveCleanupEnabled ? .primary : .secondary)

                        RetentionLimitPicker(
                            value: Binding(
                                get: { generalSettingsStore.settings.maxSavedAudioRecordings },
                                set: { newValue in
                                    generalSettingsStore.update { $0.maxSavedAudioRecordings = newValue }
                                }
                            ),
                            isEnabled: generalSettingsStore.settings.isAutoArchiveCleanupEnabled
                        )
                    }

                    Divider()

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NoteStore.defaultRecordingsDirectoryURL.path)
                    } label: {
                        Label(generalSettingsStore.text(.revealArchiveFolder), systemImage: "folder.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, -2)
            } header: {
                Text(generalSettingsStore.text(.audioArchiveRetention))
                    .font(.title3.weight(.bold))
                    .padding(.top, -10)
                    .padding(.bottom, -6)
            }

            // Compact Overlay HUD Section with 2-column layout!
            Section {
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Vertical HUD style selector buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.hudStyle))
                            .font(.subheadline.weight(.semibold))

                        VStack(spacing: 6) {
                            ForEach(OverlayHUDStyle.allCases) { style in
                                HUDStyleCardView(
                                    style: style,
                                    isSelected: generalSettingsStore.settings.overlay.style == style,
                                    title: hudStyleTitle(style),
                                    action: { overlayStyle.wrappedValue = style }
                                )
                                .frame(height: 36)
                            }
                        }
                    }
                    .frame(width: 170)

                    Divider()

                    // Right Column: Sub-divided into Size/Transparency (top) and Sound (bottom)
                    VStack(alignment: .leading, spacing: 0) {
                        // Top part: Size and Transparency
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(generalSettingsStore.text(.size))
                                Spacer()
                                Slider(value: overlayScale, in: 0.8...1.6, step: 0.05)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayScalePercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }

                            HStack {
                                Text(generalSettingsStore.text(.transparency))
                                Spacer()
                                Slider(value: overlayCapsuleOpacity, in: 0.12...1, step: 0.02)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayTransparencyPercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .padding(.top, 2)

                        Divider()
                            .opacity(0.5)
                            .padding(.vertical, 8)

                        // Bottom part: Play sound, Sound Volume, and Test HUD Sounds button
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(generalSettingsStore.text(.playSound), isOn: overlaySoundEnabled)

                            HStack {
                                Text(generalSettingsStore.text(.soundVolume))
                                Spacer()
                                Slider(value: overlayVolume, in: 0.1...2, step: 0.02)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayVolumePercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .disabled(!generalSettingsStore.settings.overlay.soundEnabled)

                            Spacer(minLength: 4)

                            HStack {
                                Spacer()
                                Button {
                                    generalSettingsStore.testOverlayHUDSounds()
                                } label: {
                                    Label(generalSettingsStore.text(.testHUDSounds), systemImage: "speaker.wave.2")
                                }
                                .disabled(!generalSettingsStore.settings.overlay.soundEnabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, -2)
            } header: {
                Text(generalSettingsStore.text(.overlayHUD))
                    .font(.title3.weight(.bold))
                    .padding(.top, -10)
                    .padding(.bottom, -6)
            }

            // Consolidated Log Level & Troubleshooting side-by-side block!
            Section {
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Log Level
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.logLevel))
                            .font(.title3.weight(.bold))

                        Picker(generalSettingsStore.text(.level), selection: logLevelSelection) {
                            ForEach(AppLogLevel.allCases) { level in
                                Text(logLevelTitle(level))
                                    .tag(level)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Right Column: Troubleshooting
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.troubleshooting))
                            .font(.title3.weight(.bold))

                        HStack(spacing: 8) {
                            Button {
                                generalSettingsStore.exportSystemLogs()
                            } label: {
                                Label(generalSettingsStore.text(.exportSystemLogs), systemImage: "square.and.arrow.down")
                            }

                            Button {
                                generalSettingsStore.reset()
                            } label: {
                                Label(generalSettingsStore.text(.resetGeneral), systemImage: "arrow.counterclockwise")
                            }
                        }

                        if let message = generalSettingsStore.logExportMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private func hudStyleTitle(_ style: OverlayHUDStyle) -> String {
        switch style {
        case .capsule:
            generalSettingsStore.text(.hudStyleCapsule)
        case .tech:
            generalSettingsStore.text(.hudStyleTech)
        case .vertical:
            generalSettingsStore.text(.hudStyleVertical)
        }
    }

    private var themeSelection: Binding<ThemePreference> {
        Binding(
            get: { generalSettingsStore.settings.theme },
            set: { theme in
                generalSettingsStore.update { $0.theme = theme }
            }
        )
    }

    private func themeTitle(_ theme: ThemePreference) -> String {
        switch theme {
        case .dark:
            generalSettingsStore.text(.themeDark)
        case .light:
            generalSettingsStore.text(.themeLight)
        case .system:
            generalSettingsStore.text(.themeSystem)
        }
    }

    private func logLevelTitle(_ level: AppLogLevel) -> String {
        switch level {
        case .error:
            generalSettingsStore.text(.levelError)
        case .warn:
            generalSettingsStore.text(.levelWarn)
        case .info:
            generalSettingsStore.text(.levelInfo)
        case .debug:
            generalSettingsStore.text(.levelDebug)
        }
    }

    private var uiScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.uiScale },
            set: { scale in
                generalSettingsStore.update { $0.uiScale = scale }
            }
        )
    }

    private var contentTextScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.textScale },
            set: { scale in
                generalSettingsStore.update { $0.textScale = scale }
            }
        )
    }

    private var contentFontSelection: Binding<TextFontPreference> {
        Binding(
            get: { generalSettingsStore.settings.textFont },
            set: { font in
                generalSettingsStore.update { $0.textFont = font }
            }
        )
    }

    private var languageSelection: Binding<UILanguagePreference> {
        Binding(
            get: { generalSettingsStore.settings.uiLanguage },
            set: { language in
                generalSettingsStore.update { $0.uiLanguage = language }
            }
        )
    }

    private var overlayScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.scale },
            set: { scale in
                generalSettingsStore.update { $0.overlay.scale = scale }
            }
        )
    }

    private var overlayStyle: Binding<OverlayHUDStyle> {
        Binding(
            get: { generalSettingsStore.settings.overlay.style },
            set: { style in
                generalSettingsStore.update { $0.overlay.style = style }
            }
        )
    }

    private var overlayCapsuleOpacity: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.capsuleOpacity },
            set: { opacity in
                generalSettingsStore.update { $0.overlay.capsuleOpacity = opacity }
            }
        )
    }

    private var overlaySoundEnabled: Binding<Bool> {
        Binding(
            get: { generalSettingsStore.settings.overlay.soundEnabled },
            set: { isEnabled in
                generalSettingsStore.update { $0.overlay.soundEnabled = isEnabled }
            }
        )
    }

    private var overlayVolume: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.volume },
            set: { volume in
                generalSettingsStore.update { $0.overlay.volume = volume }
            }
        )
    }

    private var logLevelSelection: Binding<AppLogLevel> {
        Binding(
            get: { generalSettingsStore.settings.logLevel },
            set: { level in
                generalSettingsStore.update { $0.logLevel = level }
            }
        )
    }
}

private struct HUDStyleCardView: View {
    let style: OverlayHUDStyle
    let isSelected: Bool
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 14, height: 14)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                    }
                }

                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(isHovered ? 0.06 : 0.03)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.6)
                            : Color.white.opacity(isHovered ? 0.15 : 0.05),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RetentionLimitPicker: View {
    @Binding var value: Int
    var isEnabled: Bool

    static let options = [
        5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100,
        120, 140, 160, 180, 200, 250, 300, 400, 500
    ]

    private func step(by delta: Int) {
        let sorted = Self.options
        if let currentIndex = sorted.firstIndex(of: value) {
            let nextIndex = min(max(0, currentIndex + delta), sorted.count - 1)
            value = sorted[nextIndex]
        } else {
            let closest = sorted.min(by: { abs($0 - value) < abs($1 - value) }) ?? 50
            value = closest
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)

            Stepper("", onIncrement: {
                step(by: 1)
            }, onDecrement: {
                step(by: -1)
            })
            .labelsHidden()
            .disabled(!isEnabled)
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(GeneralSettingsStore.live())
}
