import SwiftUI
import VaniScriptCore

struct ConfigWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore

    private let langs = ["same", "Russian", "Czech", "French", "German", "Polish", "English", "Hindi", "Spanish", "Swedish", "Italian", "Portuguese", "Dutch"]

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

                    PickerBox(label: "Target Language", selection: targetLanguageBinding, values: langs)
                        .onboardingTarget("target-lang-select")

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
                        .disabled(store.workflow.targetLang == "same")
                        .opacity(store.workflow.targetLang == "same" ? 0.55 : 1)
                    }
                    .onboardingTarget("transcription-model-select")

                    HStack(spacing: 12) {
                        ReadOnlyChip(title: "Chunk Duration", value: "\(store.workflow.settings.chunkDurationMin) min")
                        ReadOnlyChip(title: "Slice Mode", value: store.workflow.settings.sliceMode.rawValue.capitalized)
                    }
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

    private var transcriptionProviders: [ProviderOption] {
        ProviderRegistry.availableTranscriptionProviders(settings: store.workflow.settings)
    }

    private var translationProviders: [ProviderOption] {
        ProviderRegistry.availableTranslationProviders(settings: store.workflow.settings, targetLang: store.workflow.targetLang).providers
    }

    private var transcriptionProviderIDs: [String] {
        transcriptionProviders.map(\.id)
    }

    private var translationProviderIDs: [String] {
        store.workflow.targetLang == "same" ? [""] : translationProviders.map(\.id)
    }

    private func providerLabel(_ id: String) -> String {
        if id.isEmpty { return "Disabled for Same" }
        return (transcriptionProviders + translationProviders).first { $0.id == id }?.label ?? id
    }

    private func binding(_ keyPath: WritableKeyPath<AudioMetadata, String>) -> Binding<String> {
        Binding {
            store.workflow.metadata[keyPath: keyPath]
        } set: { value in
            store.workflow.metadata[keyPath: keyPath] = value
        }
    }

    private var targetLanguageBinding: Binding<String> {
        Binding {
            store.workflow.targetLang
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
            store.workflow.translationProvider
        } set: { value in
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PickerBox: View {
    let label: String
    @Binding var selection: String
    let values: [String]
    var labelForValue: (String) -> String = { $0 == "same" ? "Keep original (Same)" : $0 }

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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.text1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.02))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
