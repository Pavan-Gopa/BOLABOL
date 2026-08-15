import SwiftUI
import VaniScriptCore

struct ConfigWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore

    private let targetLanguageValues = NativeLanguagePolicy.targetLanguageOptions.map(\.code)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            LogoHeader(compact: true)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text("Engine Configuration")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                }

                if store.workflow.sourceKind == .document {
                    documentConfigFields
                } else {
                    mediaConfigFields
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        store.cancelConfig()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button {
                        store.startSession()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Initialize Engine")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!store.workflow.canStartSession)
                    .onboardingTarget("start-engine-btn")
                }
                .padding(.top, 4)
            }
            .frame(width: 500)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .glassPanel()

            AppFooter()
                .padding(.top, 20)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentConfigFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Document Metadata")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VaniScriptTheme.text2)
                Spacer()
                if let format = store.workflow.documentState?.format {
                    Text(format.accuracyBadge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VaniScriptTheme.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(VaniScriptTheme.accent.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityIdentifier("document-accuracy-badge")
                }
            }

            if let format = store.workflow.documentState?.format {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text(format.accuracyBadge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VaniScriptTheme.text1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(VaniScriptTheme.control)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VaniScriptTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("document-accuracy-badge-banner")
            }

            HStack(spacing: 12) {
                ReadOnlyChip(title: "Title", value: documentTitle)
                ReadOnlyChip(title: "Author", value: documentAuthor)
            }

            HStack(spacing: 12) {
                ReadOnlyChip(title: "Source Language", value: "Auto (detect)")
                PickerBox(
                    label: "Target Language",
                    selection: targetLanguageBinding,
                    values: targetLanguageValues,
                    labelForValue: languageLabel
                )
            }
            .onboardingTarget("target-lang-select")

            PickerBox(
                label: "Translation Model",
                selection: translationBinding,
                values: translationProviderIDs,
                labelForValue: providerLabel
            )
            .disabled(!translationNeeded)
            .opacity(translationNeeded ? 1 : 0.55)
            .onboardingTarget("translation-model-select")

            Toggle(
                "Auto-approve valid translations",
                isOn: Binding(
                    get: { store.workflow.documentApprovalMode == .automatic },
                    set: { store.workflow.documentApprovalMode = $0 ? .automatic : .manual }
                )
            )
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .medium))
            .onboardingTarget("document-auto-approve")
        }
    }

    private var mediaConfigFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audio Metadata")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VaniScriptTheme.text2)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    FieldBox(label: "Date", text: binding(\.date))
                    FieldBox(label: "Location", text: binding(\.location))
                }
                HStack(spacing: 12) {
                    FieldBox(label: "Lecturer", text: binding(\.lecturer))
                    FieldBox(label: "Interviewer / Participants", text: binding(\.participants))
                }
            }
            .onboardingTarget("config-metadata")

            HStack(spacing: 12) {
                PickerBox(
                    label: "Source Language",
                    selection: sourceLanguageBinding,
                    values: sourceLanguageValues,
                    labelForValue: languageLabel
                )
                PickerBox(
                    label: "Target Language",
                    selection: targetLanguageBinding,
                    values: targetLanguageValues,
                    labelForValue: languageLabel
                )
            }
            .onboardingTarget("target-lang-select")

            if sourceLanguageIsUnsupported {
                Label(
                    "Choose a supported source language for \(selectedASRDescriptor?.displayName ?? "the selected transcription provider").",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 12) {
                PickerBox(
                    label: "Transcription Model",
                    selection: transcriptionBinding,
                    values: transcriptionProviderIDs,
                    labelForValue: providerLabel
                )
                PickerBox(
                    label: "Translation Model",
                    selection: translationBinding,
                    values: translationProviderIDs,
                    labelForValue: providerLabel
                )
                .disabled(!translationNeeded)
                .opacity(translationNeeded ? 1 : 0.55)
            }
            .onboardingTarget("transcription-model-select")

            HStack(spacing: 12) {
                ReadOnlyChip(title: "Chunk Duration", value: "\(store.workflow.settings.chunkDurationMin) min")
                ReadOnlyChip(title: "Slice Mode", value: store.workflow.settings.sliceMode.rawValue.capitalized)
            }
        }
    }

    private var documentTitle: String {
        let title = store.workflow.documentState?.metadata.title ?? ""
        return title.isEmpty ? store.workflow.sourceFileName : title
    }

    private var documentAuthor: String {
        let author = store.workflow.documentState?.metadata.author ?? ""
        return author.isEmpty ? "Unknown" : author
    }

    private var transcriptionProviders: [ProviderOption] {
        ProviderRegistry.availableTranscriptionProviders(settings: store.workflow.settings)
    }

    private var translationNeeded: Bool {
        NativeLanguagePolicy.translationNeeded(
            sourceLang: store.workflow.sourceLang,
            targetLang: store.workflow.targetLang
        )
    }

    private var translationProviders: [ProviderOption] {
        guard translationNeeded else { return [] }
        return ProviderRegistry
            .availableTranslationProviders(
                settings: store.workflow.settings,
                targetLang: store.workflow.targetLang
            )
            .providers
    }

    private var transcriptionProviderIDs: [String] {
        transcriptionProviders.map(\.id)
    }

    private var translationProviderIDs: [String] {
        translationNeeded ? translationProviders.map(\.id) : [""]
    }

    private var selectedASRDescriptor: LocalASRModelDescriptor? {
        if let descriptor = NativeModelCatalog.descriptor(for: store.workflow.transcriptionProvider) {
            return descriptor
        }
        return NativeModelCatalog.activeLocalASRModel(
            settings: store.workflow.settings,
            providerID: store.workflow.transcriptionProvider
        )?.descriptor
    }

    private var sourceLanguageOptions: [NativeLanguageOption] {
        NativeLanguagePolicy.sourceLanguageOptions(for: selectedASRDescriptor)
    }

    private var sourceLanguageIsUnsupported: Bool {
        let sourceCode = NativeLanguagePolicy.canonicalCode(store.workflow.sourceLang)
        return !sourceLanguageOptions.contains(where: { $0.code == sourceCode })
    }

    private var sourceLanguageValues: [String] {
        var values = sourceLanguageOptions.map(\.code)
        if sourceLanguageIsUnsupported {
            values.append(NativeLanguagePolicy.chooseSourceCode)
        }
        return values
    }

    private func languageLabel(_ value: String) -> String {
        if value == NativeLanguagePolicy.chooseSourceCode {
            return "Choose Source Language"
        }
        return NativeLanguagePolicy.displayName(for: value)
    }

    private func providerLabel(_ id: String) -> String {
        if id.isEmpty { return "Disabled for Same Language" }
        let providers = store.workflow.sourceKind == .document
            ? translationProviders
            : transcriptionProviders + translationProviders
        return providers.first { $0.id == id }?.label ?? id
    }

    private func binding(_ keyPath: WritableKeyPath<AudioMetadata, String>) -> Binding<String> {
        Binding {
            store.workflow.metadata[keyPath: keyPath]
        } set: { value in
            store.workflow.metadata[keyPath: keyPath] = value
        }
    }

    private var sourceLanguageBinding: Binding<String> {
        Binding {
            let sourceCode = NativeLanguagePolicy.canonicalCode(store.workflow.sourceLang)
            return sourceLanguageOptions.contains(where: { $0.code == sourceCode })
                ? sourceCode
                : NativeLanguagePolicy.chooseSourceCode
        } set: { value in
            store.setSourceLanguage(value)
        }
    }

    private var targetLanguageBinding: Binding<String> {
        Binding {
            NativeLanguagePolicy.canonicalCode(store.workflow.targetLang)
        } set: { value in
            store.setTargetLanguage(value)
        }
    }

    private var transcriptionBinding: Binding<String> {
        Binding {
            store.workflow.transcriptionProvider
        } set: { value in
            store.setTranscriptionProvider(value)
        }
    }

    private var translationBinding: Binding<String> {
        Binding {
            translationNeeded ? store.workflow.translationProvider : ""
        } set: { value in
            guard translationNeeded else { return }
            store.setTranslationProvider(value)
        }
    }
}

private struct FieldBox: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VaniScriptTheme.text2)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(VaniScriptTheme.text0)
                .padding(.horizontal, 11)
                .frame(height: 38)
                    .background(VaniScriptTheme.input)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PickerBox: View {
    let label: String
    @Binding var selection: String
    let values: [String]
    var labelForValue: (String) -> String = { NativeLanguagePolicy.displayName(for: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VaniScriptTheme.text2)
            Picker(label, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(labelForValue(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(VaniScriptTheme.text0)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(VaniScriptTheme.input)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReadOnlyChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
            Spacer()
            Text(value)
                .foregroundStyle(VaniScriptTheme.accent)
                .fontWeight(.bold)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
