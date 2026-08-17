import NativeBolabolCore
import SwiftUI

@MainActor
struct HotkeySettingsView: View {
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var transcriptionEngineStore: TranscriptionEngineStore

    private enum ActiveHotkeyField: Hashable {
        case primary
        case secondary
        case tertiary
        case settings
    }

    @State private var captureOwner = UUID()
    @State private var activeField: ActiveHotkeyField? = nil
    @State private var rejectionReasons: [ActiveHotkeyField: HotkeyCaptureRejectionReason] = [:]
    var body: some View {
        Form {
            Section(header: Text(generalSettingsStore.text(.globalHotkey))) {
                Toggle(generalSettingsStore.text(.enableHotkey), isOn: settingsEnabled)
                    .padding(.vertical, 0)

                if hotkeySettingsStore.settings.enabled {
                    Toggle(isOn: holdToRecordBinding) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.holdToRecordLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.holdToRecordDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 0)

                    // Row for Primary Hotkey
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.hotkeyPrimaryLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.hotkeyPrimaryDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HotkeyRecorder(
                            title: generalSettingsStore.text(.hotkeyPrimaryLabel),
                            value: hotkeySettingsStore.settings.hotkey,
                            isRecording: activeField == .primary,
                            allowsRightModifierOnly: true,
                            rejectionReason: rejectionReasons[.primary],
                            onBegin: { beginCapture(for: .primary) },
                            onCommit: { commitCapture(for: .primary, value: $0) },
                            onCancel: { cancelCapture(for: .primary) },
                            onReject: { handleRejection(for: .primary, reason: $0) }
                        )

                        Button {
                            hotkeySettingsStore.settings.hotkey = HotkeySettings.defaultPrimaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 0)

                    // Row for Full Translation Window Hotkey (Option+1)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.translationWindowLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.translationWindowDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HotkeyRecorder(
                            title: generalSettingsStore.text(.translationWindowLabel),
                            value: hotkeySettingsStore.settings.secondaryHotkey,
                            isRecording: activeField == .secondary,
                            allowsRightModifierOnly: false,
                            rejectionReason: rejectionReasons[.secondary],
                            onBegin: { beginCapture(for: .secondary) },
                            onCommit: { commitCapture(for: .secondary, value: $0) },
                            onCancel: { cancelCapture(for: .secondary) },
                            onReject: { handleRejection(for: .secondary, reason: $0) }
                        )

                        Button {
                            hotkeySettingsStore.settings.secondaryHotkey = HotkeySettings.defaultSecondaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 0)
                    // Row for Quick Translation Hotkey (Option+2)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.quickTranslationLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.quickTranslationDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HotkeyRecorder(
                            title: generalSettingsStore.text(.quickTranslationLabel),
                            value: hotkeySettingsStore.settings.tertiaryHotkey,
                            isRecording: activeField == .tertiary,
                            allowsRightModifierOnly: false,
                            rejectionReason: rejectionReasons[.tertiary],
                            onBegin: { beginCapture(for: .tertiary) },
                            onCommit: { commitCapture(for: .tertiary, value: $0) },
                            onCancel: { cancelCapture(for: .tertiary) },
                            onReject: { handleRejection(for: .tertiary, reason: $0) }
                        )

                        Button {
                            hotkeySettingsStore.settings.tertiaryHotkey = HotkeySettings.defaultTertiaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 0)
                    Toggle(isOn: humorSliderEnabledBinding) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.humorSlider))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.humorSliderDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    Picker(generalSettingsStore.text(.humorStyle), selection: humorPromptModeBinding) {
                        ForEach(HumorPromptMode.allCases) { mode in
                            Text(generalSettingsStore.text(mode.appTextKey))
                                .tag(mode)
                        }
                    }
                    .padding(.vertical, 0)

                }

                // Row for Settings Hotkey (Option+~) - always visible
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(generalSettingsStore.text(.openSettingsLabel))
                            .font(.body.weight(.medium))
                        Text(generalSettingsStore.text(.openSettingsDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HotkeyRecorder(
                        title: generalSettingsStore.text(.openSettingsLabel),
                        value: hotkeySettingsStore.settings.settingsHotkey,
                        isRecording: activeField == .settings,
                        allowsRightModifierOnly: false,
                        rejectionReason: rejectionReasons[.settings],
                        onBegin: { beginCapture(for: .settings) },
                        onCommit: { commitCapture(for: .settings, value: $0) },
                        onCancel: { cancelCapture(for: .settings) },
                        onReject: { handleRejection(for: .settings, reason: $0) }
                    )

                    Button {
                        hotkeySettingsStore.settings.settingsHotkey = HotkeySettings.defaultSettingsHotkey
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .help(generalSettingsStore.text(.reset))
                }
                .padding(.vertical, 2)
            }

            // Your Languages — primary + additional speech-language pair (plan §7).
            // Reads/writes GeneralSettingsStore.speechLanguages — the same blob the
            // onboarding writes (single source of truth, plan §3.3). This is a
            // separate preference from the engine-level Recognition Language control
            // below: Parakeet/Whisper auto-detect stays untouched (plan §4.1).
            // Copy never calls additional a "target" / "always output" language.
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(generalSettingsStore.text(.languagePairSectionTitle))
                        .font(.title3.weight(.bold))
                        .padding(.top, -10)
                        .padding(.bottom, -6)

                     Picker(generalSettingsStore.text(.primaryLanguage), selection: primaryLanguageSelection) {
                         ForEach(availableSpeechLanguages) { language in
                            Text(language.displayName)
                                .tag(language.code)
                        }
                    }

                    Text(generalSettingsStore.text(.primaryLanguageHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .opacity(0.5)
                        .padding(.vertical, 4)

                     Picker(generalSettingsStore.text(.additionalLanguage), selection: additionalLanguageSelection) {
                         ForEach(availableSpeechLanguages) { language in
                            Text(language.displayName)
                                .tag(language.code)
                        }
                    }

                    Text(generalSettingsStore.text(.additionalLanguageHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(generalSettingsStore.text(.additionalSameAsPrimary), isOn: sameAsPrimaryBinding)

                    Text(generalSettingsStore.text(.languagePairEngineNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            // Side-by-side Recognition Language & Output block
            if hotkeySettingsStore.settings.enabled {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        // Left Column: Recognition Language
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generalSettingsStore.text(.hotkeyTargetLanguage))
                                .font(.headline)

                            if let activeCoreMLSession {
                                switch activeCoreMLSession {
                                case .available(let session):
                                    let sourceText = session.plan.sourceLanguageChoices
                                        .map(LanguagePickerOrder.displayName(for:))
                                        .joined(separator: " / ")
                                    LabeledContent(
                                        generalSettingsStore.text(.resolvedLanguage),
                                        value: sourceText
                                    )
                                    Text(generalSettingsStore.formattedText(
                                        .localModelsNoAutomaticLanguageNotice,
                                        generalSettingsStore.text(.localModelsLanguageModesHelpPath)
                                    ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                case .unavailable(let reason):
                                    Text(unavailableMessage(for: reason))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
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
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Right Column: Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generalSettingsStore.text(.output))
                                .font(.headline)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Compact Accessibility Permission block at the bottom
            Section(generalSettingsStore.text(.accessibilityPermission)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Label(
                            accessibilityPermissionStore.isTrusted
                                ? generalSettingsStore.text(.accessibilityTrusted)
                                : generalSettingsStore.text(.accessibilityNotTrusted),
                            systemImage: accessibilityPermissionStore.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(accessibilityPermissionStore.isTrusted ? .green : .orange)
                        .font(.body.weight(.medium))

                        Spacer()

                        HStack(spacing: 6) {
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

                            Button {
                                accessibilityPermissionStore.openSettings()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help(generalSettingsStore.text(.openAccessibilitySettings))
                        }
                    }

                    Text(generalSettingsStore.text(.accessibilityPermissionDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityPermissionStore.refresh()
        }
        .onDisappear {
            if activeField != nil {
                activeField = nil
                hotkeySettingsStore.endShortcutCapture(owner: captureOwner)
            }
        }
    }

    private var settingsEnabled: Binding<Bool> {
        Binding(
            get: { hotkeySettingsStore.settings.enabled },
            set: { hotkeySettingsStore.settings.enabled = $0 }
        )
    }

    private var holdToRecordBinding: Binding<Bool> {
        Binding(
            get: { hotkeySettingsStore.settings.holdToRecord },
            set: { hotkeySettingsStore.settings.holdToRecord = $0 }
        )
    }
    private func handleRejection(for field: ActiveHotkeyField, reason: HotkeyCaptureRejectionReason) {
        rejectionReasons[field] = reason
        let message: String
        switch reason {
        case .modifierRequired:
            message = generalSettingsStore.text(.hotkeyRejectModifierRequired)
        case .unsupportedKey:
            message = generalSettingsStore.text(.hotkeyRejectUnsupportedKey)
        case .modifierOnlyPrimary:
            message = generalSettingsStore.text(.hotkeyRejectModifierOnlyPrimary)
        }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func beginCapture(for field: ActiveHotkeyField) {
        rejectionReasons[field] = nil
        if hotkeySettingsStore.beginShortcutCapture(owner: captureOwner) {
            activeField = field
        }
    }

    private func commitCapture(for field: ActiveHotkeyField, value: String) {
        guard activeField == field else { return }
        activeField = nil
        rejectionReasons[field] = nil

        switch field {
        case .primary:
            hotkeySettingsStore.settings.hotkey = value
        case .secondary:
            hotkeySettingsStore.settings.secondaryHotkey = value
        case .tertiary:
            hotkeySettingsStore.settings.tertiaryHotkey = value
        case .settings:
            hotkeySettingsStore.settings.settingsHotkey = value
        }

        hotkeySettingsStore.endShortcutCapture(owner: captureOwner)
    }

    private func cancelCapture(for field: ActiveHotkeyField) {
        guard activeField == field else { return }
        activeField = nil
        rejectionReasons[field] = nil
        hotkeySettingsStore.endShortcutCapture(owner: captureOwner)
    }
    private var humorSliderEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeySettingsStore.settings.humorSliderEnabled },
            set: { hotkeySettingsStore.settings.humorSliderEnabled = $0 }
        )
    }

    private var humorPromptModeBinding: Binding<HumorPromptMode> {
        Binding(
            get: { hotkeySettingsStore.settings.humorPromptMode },
            set: { hotkeySettingsStore.settings.humorPromptMode = $0 }
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

    private var activeCoreMLSession: TranscriptionEngineSessionResolution? {
        guard let model = transcriptionModelStore.activeModel,
              model.backend == .canaryCoreML || model.backend == .gigaAMCoreML
        else {
            return nil
        }
        return transcriptionEngineStore.makeSession(
            modelStore: transcriptionModelStore,
            operation: .asr
        )
    }

    private var availableSpeechLanguages: [SpeechLanguage] {
        LanguagePickerOrder.speechLanguages
    }

    private func unavailableMessage(
        for reason: TranscriptionSessionUnavailableReason
    ) -> String {
        switch reason {
        case .noActiveModel:
            generalSettingsStore.text(.noLocalModelSelected)
        case .incompleteModel, .invalidCapabilities:
            generalSettingsStore.text(.localModelsPackageUnavailable)
        case .unsupportedOS:
            generalSettingsStore.text(.localModelsRequiresMacOS)
        case .noSupportedSource:
            generalSettingsStore.text(.localModelsCanaryLanguageBlock)
        case .unsupportedSourceLanguage(_, let requestedCode, let supportedCodes):
            generalSettingsStore.formattedText(
                .localModelsCanaryClampWarning,
                supportedCodes.map(TranscriptionLanguageOption.displayName(for:)).joined(separator: ", "),
                TranscriptionLanguageOption.displayName(for: requestedCode)
            )
        case .englishSourceRequired:
            generalSettingsStore.text(.localModelsCanary1BEnglishRequired)
        case .translationUnsupported, .unsupportedOperation:
            generalSettingsStore.text(.transcriptionSessionTranslationUnavailable)
        case .engineIdentityMismatch:
            generalSettingsStore.text(.transcriptionSessionEngineMismatch)
        }
    }

    private var customLanguageCode: Binding<String> {
        Binding(
            get: { transcriptionModelStore.customLanguageCode },
            set: { transcriptionModelStore.setCustomLanguageCode($0) }
        )
    }

    // MARK: - Speech-language pair (plan §7)

    /// Primary picker writes the canonical pair through `settingPrimary` so the
    /// same-as-primary mirror stays intact (identical semantics to onboarding,
    /// plan §6.2, §7.1).
    private var primaryLanguageSelection: Binding<String> {
        Binding(
            get: { generalSettingsStore.speechLanguages.primaryLanguageCode },
            set: { code in
                generalSettingsStore.speechLanguages = generalSettingsStore.speechLanguages
                    .settingPrimary(code)
            }
        )
    }

    /// Additional picker writes the explicit second language. Picking a value
    /// equal to primary returns the pair to the same-as-primary state (the
    /// toggle below reflects that automatically) — same behavior as onboarding.
    private var additionalLanguageSelection: Binding<String> {
        Binding(
            get: { generalSettingsStore.speechLanguages.additionalLanguageCode },
            set: { code in
                generalSettingsStore.speechLanguages = generalSettingsStore.speechLanguages
                    .settingAdditional(code)
            }
        )
    }

    /// "Same as primary" mirrors additional to primary (plan §3.4, §7.1).
    /// Turning the mirror off picks the most common second language — English,
    /// or the first Europe-group language when primary is already English —
    /// matching the onboarding fallback exactly (plan §6.2).
    private var sameAsPrimaryBinding: Binding<Bool> {
        Binding(
            get: { generalSettingsStore.speechLanguages.usesSameAdditionalAsPrimary },
            set: { isSame in
                if isSame {
                    generalSettingsStore.speechLanguages = generalSettingsStore.speechLanguages
                        .settingAdditionalSameAsPrimary()
                } else {
                    let current = generalSettingsStore.speechLanguages
                    let fallback =
                        current.primaryLanguageCode == LanguagePickerOrder.englishCode
                        ? LanguagePickerOrder.europeCodes.first
                          ?? LanguagePickerOrder.englishCode
                        : LanguagePickerOrder.englishCode
                    generalSettingsStore.speechLanguages = UserSpeechLanguages(
                        primaryLanguageCode: current.primaryLanguageCode,
                        additionalLanguageCode: fallback
                    )
                }
            }
        )
    }
}

#Preview {
    HotkeySettingsView()
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(AccessibilityPermissionStore.live())
        .environmentObject(TranscriptionModelStore.live())
        .environmentObject(TranscriptionEngineStore.live())
}
