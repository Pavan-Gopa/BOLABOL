import NativeSmartScribeCore
import SwiftUI

struct APIProvidersSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    var body: some View {
        Form {
            Section(generalSettingsStore.text(.textPolishingProviders)) {
                APIProviderEditor(
                    title: "Google Gemini",
                    subtitle: generalSettingsStore.text(.googleProviderSubtitle),
                    kind: .google,
                    configuration: binding(for: .google),
                    showsName: false,
                    showsBaseURL: false,
                    apiKeyURL: URL(string: "https://aistudio.google.com/app/apikey")
                )

                APIProviderEditor(
                    title: "OpenAI",
                    subtitle: generalSettingsStore.text(.openAIProviderSubtitle),
                    kind: .openAI,
                    configuration: binding(for: .openAI),
                    showsName: false,
                    showsBaseURL: false,
                    apiKeyURL: URL(string: "https://platform.openai.com/api-keys")
                )

                APIProviderEditor(
                    title: "Anthropic",
                    subtitle: generalSettingsStore.text(.anthropicProviderSubtitle),
                    kind: .anthropic,
                    configuration: binding(for: .anthropic),
                    showsName: false,
                    showsBaseURL: false,
                    apiKeyURL: URL(string: "https://console.anthropic.com/settings/keys")
                )

                APIProviderEditor(
                    title: "Custom OpenAI-Compatible",
                    subtitle: generalSettingsStore.text(.customProviderSubtitle),
                    kind: .custom,
                    configuration: binding(for: .custom),
                    showsName: true,
                    showsBaseURL: true,
                    apiKeyURL: nil
                )
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for kind: APIProviderKind) -> Binding<APIProviderConfiguration> {
        Binding(
            get: {
                polishingEngineStore.apiSettings.configuration(for: kind)
            },
            set: { configuration in
                polishingEngineStore.updateAPIConfiguration(configuration, for: kind)
            }
        )
    }
}

private struct APIProviderEditor: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    let title: String
    let subtitle: String
    let kind: APIProviderKind
    @Binding var configuration: APIProviderConfiguration
    let showsName: Bool
    let showsBaseURL: Bool
    let apiKeyURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isConfigured {
                    Text(generalSettingsStore.text(.configured))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            if showsName {
                TextField(generalSettingsStore.text(.providerName), text: $configuration.name)
                    .textFieldStyle(.roundedBorder)
            }

            SecureField(generalSettingsStore.text(.apiKey), text: $configuration.apiKey)
                .textFieldStyle(.roundedBorder)

            if showsBaseURL {
                TextField(generalSettingsStore.text(.baseURL), text: $configuration.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            TextField(generalSettingsStore.text(.textModelField), text: $configuration.textModel)
                .textFieldStyle(.roundedBorder)

            HStack {
                if let apiKeyURL {
                    Link(destination: apiKeyURL) {
                        Label(generalSettingsStore.text(.getAPIKey), systemImage: "key")
                    }
                }

                Spacer()

                Button {
                    polishingEngineStore.selectAPIProvider(kind)
                } label: {
                    Label(
                        polishingEngineStore.selectedEngineID == kind.polishingEngineID
                            ? generalSettingsStore.text(.selected)
                            : generalSettingsStore.text(.useForPolishing),
                        systemImage: polishingEngineStore.selectedEngineID == kind.polishingEngineID
                            ? "checkmark.circle.fill"
                            : "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConfigured || polishingEngineStore.selectedEngineID == kind.polishingEngineID)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5))
        }
    }

    private var isConfigured: Bool {
        switch kind {
        case .google, .openAI, .anthropic:
            configuration.hasAPIKey && !configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:
            configuration.hasAPIKey
                && !configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

#Preview {
    APIProvidersSettingsView()
        .environmentObject(PolishingEngineStore.live())
}
