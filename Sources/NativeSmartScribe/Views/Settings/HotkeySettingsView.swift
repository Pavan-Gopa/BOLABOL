import NativeSmartScribeCore
import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore

    var body: some View {
        Form {
            Section(
                header: Text(generalSettingsStore.text(.globalHotkey)),
                footer: Text(generalSettingsStore.text(.hotkeyDescription))
            ) {
                Toggle(generalSettingsStore.text(.enableHotkey), isOn: settingsEnabled)

                if hotkeySettingsStore.settings.enabled {
                    // Row for Primary Hotkey
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generalSettingsStore.text(.hotkeyPrimaryLabel))
                                .font(.body)
                                .bold()
                            Text(generalSettingsStore.text(.hotkeyPrimaryDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        TextField("", text: hotkeyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .multilineTextAlignment(.trailing)

                        Button {
                            hotkeySettingsStore.settings.hotkey = "Alt+S"
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 4)

                    // Row for Secondary Hotkey
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generalSettingsStore.text(.hotkeySecondaryLabel))
                                .font(.body)
                                .bold()
                            Text(generalSettingsStore.text(.hotkeySecondaryDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        TextField("", text: secondaryHotkeyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .multilineTextAlignment(.trailing)

                        Button {
                            hotkeySettingsStore.settings.secondaryHotkey = "Alt+Shift+S"
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 4)
                }
            }

            if hotkeySettingsStore.settings.enabled {
                Section(generalSettingsStore.text(.hotkeyTargetLanguage)) {
                    Picker(generalSettingsStore.text(.transcriptionLanguage), selection: languageSelection) {
                        Text(generalSettingsStore.text(.autoDetect)).tag("auto")
                        ForEach(TranscriptionLanguageOption.builtIn) { language in
                            Text("\(language.displayName) (\(language.code))")
                                .tag(language.code)
                        }
                        Text(generalSettingsStore.text(.customCode)).tag("custom")
                    }

                    if transcriptionModelStore.languageSelectionTag == "custom" {
                        TextField(generalSettingsStore.text(.languageCode), text: customLanguageCode)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent(generalSettingsStore.text(.resolvedLanguage), value: transcriptionModelStore.resolvedLanguageCode)

                    Text(generalSettingsStore.text(.transcriptionLanguageHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(generalSettingsStore.text(.accessibilityPermission)) {
                HStack {
                    Label(
                        accessibilityPermissionStore.isTrusted
                            ? generalSettingsStore.text(.accessibilityTrusted)
                            : generalSettingsStore.text(.accessibilityNotTrusted),
                        systemImage: accessibilityPermissionStore.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityPermissionStore.isTrusted ? .green : .orange)

                    Spacer()

                    Button {
                        accessibilityPermissionStore.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .help(generalSettingsStore.text(.refreshPermissionStatus))

                    Button {
                        accessibilityPermissionStore.requestPermission()
                    } label: {
                        Image(systemName: "hand.raised")
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .help(generalSettingsStore.text(.requestAccessibilityPermission))
                    .disabled(accessibilityPermissionStore.isTrusted)
                }

                Text(generalSettingsStore.text(.accessibilityPermissionDescription))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    accessibilityPermissionStore.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .help(generalSettingsStore.text(.openAccessibilitySettings))
            }

            Section(generalSettingsStore.text(.output)) {
                Picker(generalSettingsStore.text(.target), selection: targetSelection) {
                    ForEach(HotkeyTarget.allCases) { target in
                        Text(targetTitle(target))
                            .tag(target)
                    }
                }

                Picker(generalSettingsStore.text(.mode), selection: outputModeSelection) {
                    ForEach(HotkeyOutputMode.allCases) { mode in
                        Text(outputModeTitle(mode))
                            .tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityPermissionStore.refresh()
        }
    }

    private var settingsEnabled: Binding<Bool> {
        Binding(
            get: { hotkeySettingsStore.settings.enabled },
            set: { hotkeySettingsStore.settings.enabled = $0 }
        )
    }

    private var hotkeyText: Binding<String> {
        Binding(
            get: { hotkeySettingsStore.settings.hotkey },
            set: { hotkeySettingsStore.settings.hotkey = $0 }
        )
    }

    private var secondaryHotkeyText: Binding<String> {
        Binding(
            get: { hotkeySettingsStore.settings.secondaryHotkey },
            set: { hotkeySettingsStore.settings.secondaryHotkey = $0 }
        )
    }

    private var targetSelection: Binding<HotkeyTarget> {
        Binding(
            get: { hotkeySettingsStore.settings.target },
            set: { hotkeySettingsStore.settings.target = $0 }
        )
    }

    private var outputModeSelection: Binding<HotkeyOutputMode> {
        Binding(
            get: { hotkeySettingsStore.settings.mode },
            set: { hotkeySettingsStore.settings.mode = $0 }
        )
    }

    private func targetTitle(_ target: HotkeyTarget) -> String {
        switch target {
        case .raw:
            generalSettingsStore.text(.raw)
        case .note:
            generalSettingsStore.text(.variantOne)
        case .x2:
            generalSettingsStore.text(.variantTwo)
        }
    }

    private func outputModeTitle(_ mode: HotkeyOutputMode) -> String {
        switch mode {
        case .clipboard:
            generalSettingsStore.text(.clipboardMode)
        case .typing:
            generalSettingsStore.text(.typeIntoActiveApp)
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { transcriptionModelStore.languageSelectionTag },
            set: { transcriptionModelStore.setLanguageSelectionTag($0) }
        )
    }

    private var customLanguageCode: Binding<String> {
        Binding(
            get: { transcriptionModelStore.customLanguageCode },
            set: { transcriptionModelStore.setCustomLanguageCode($0) }
        )
    }
}

#Preview {
    HotkeySettingsView()
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(AccessibilityPermissionStore.live())
        .environmentObject(TranscriptionModelStore.live())
}
