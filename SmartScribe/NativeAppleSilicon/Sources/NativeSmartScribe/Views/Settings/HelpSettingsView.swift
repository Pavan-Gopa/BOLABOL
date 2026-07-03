import NativeSmartScribeCore
import SwiftUI

struct HelpSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HelpSection(
                    title: generalSettingsStore.text(.helpWelcomeTitle),
                    paragraphs: [generalSettingsStore.text(.helpWelcomeBody)]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpQuickStart),
                    bullets: [
                        generalSettingsStore.text(.helpRecordStep),
                        generalSettingsStore.text(.helpVariantsStep),
                        generalSettingsStore.text(.helpCopyStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpRecordingTitle),
                    bullets: [
                        generalSettingsStore.text(.helpHUDStep),
                        generalSettingsStore.text(.helpHotkeyStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpOfflineTranscription),
                    bullets: [
                        generalSettingsStore.text(.helpOfflineModelStep),
                        generalSettingsStore.text(.helpOfflineActivateStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpPolishingProviders),
                    bullets: [
                        generalSettingsStore.text(.helpPolishingProviderStep),
                        generalSettingsStore.text(.helpPromptsStep),
                        generalSettingsStore.text(.helpHotkeyStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpImportTitle),
                    bullets: [
                        generalSettingsStore.text(.helpImportStep),
                        generalSettingsStore.text(.helpTranslateStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpPermissionsTitle),
                    bullets: [
                        generalSettingsStore.text(.helpMicrophoneStep),
                        generalSettingsStore.text(.helpAccessibilityStep),
                        generalSettingsStore.text(.helpPermissionRefreshStep)
                    ]
                )

                HelpSection(
                    title: generalSettingsStore.text(.helpPrivacyTitle),
                    bullets: [
                        generalSettingsStore.text(.helpPrivacyLocalStep),
                        generalSettingsStore.text(.helpLogsStep)
                    ]
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .overlayScrollbar()
    }
}

private struct HelpSection: View {
    let title: String
    var paragraphs: [String] = []
    var bullets: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(bullet)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45))
        }
    }
}

#Preview {
    HelpSettingsView()
        .environmentObject(GeneralSettingsStore.live())
}
