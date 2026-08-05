import NativeBolabolCore
import SwiftUI

enum LocalModelsActionPresentation: Equatable {
    case download
    case downloading(progressFraction: Double?)
    case selected
    case use
    case retry(errorMessage: String?)
    case none
}

enum LocalModelsActionPolicy {
    static func action(
        for state: TranscriptionModelInstallationState,
        isOSCompatible: Bool,
        isLanguageBlocked: Bool,
        isActive: Bool,
        isGOModel: Bool,
        hasCompleteLocalFiles: Bool
    ) -> LocalModelsActionPresentation {
        guard isOSCompatible else { return .none }

        switch state.status {
        case .notDownloaded:
            return .download
        case .downloading:
            return .downloading(progressFraction: state.progressFraction)
        case .downloaded:
            guard !isLanguageBlocked else { return .none }
            if isActive {
                return .selected
            }
            if !isGOModel || hasCompleteLocalFiles {
                return .use
            }
            return .none
        case .failed:
            return .retry(errorMessage: state.errorMessage)
        }
    }

    static func canDelete(
        state: TranscriptionModelInstallationState,
        isGOModel: Bool,
        hasCompleteLocalFiles: Bool,
        hasAnyLocalFiles: Bool
    ) -> Bool {
        guard state.status != .downloading else { return false }
        return state.status == .downloaded
            || hasCompleteLocalFiles
            || (isGOModel && hasAnyLocalFiles)
    }
}

@MainActor
struct LocalModelsSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    /// Computed recommendations using the shared ranking helper from OnboardingModelRecommendation.
    /// Recalculates on every render so language-pair changes in Settings update immediately.
    private var recommendedModels: [TranscriptionModelDescriptor] {
        let speech = generalSettingsStore.speechLanguages
        return OnboardingModelRecommendation.topThree(
            primary: speech.primaryLanguageCode,
            additional: speech.additionalLanguageCode,
            available: transcriptionModelStore.models
        )
    }

    /// Remaining models after removing recommended ones (each model appears exactly once).
    private var remainingModels: [TranscriptionModelDescriptor] {
        let recommendedIDs = Set(recommendedModels.map(\.id))
        return transcriptionModelStore.models.filter { !recommendedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Backend: Local Whisper vs Cloud Gemini (no Apple Speech)
            VStack(alignment: .leading, spacing: 10) {
                Text(generalSettingsStore.text(.transcriptionEngine))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Picker(generalSettingsStore.text(.engine), selection: backendSelection) {
                    ForEach(TranscriptionBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)

                Text(transcriptionModelStore.settings.backend.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if transcriptionModelStore.settings.backend == .geminiCloud {
                    geminiCloudStatusRow
                } else {
                    HStack {
                        Text(generalSettingsStore.text(.activeModelLabel))
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(transcriptionModelStore.activeModelForPresentation?.displayName ?? generalSettingsStore.text(.noLocalModelSelected))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(transcriptionModelStore.activeModelForPresentation == nil ? .secondary : .primary)
                    }

                    if transcriptionModelStore.activeModelForPresentation == nil {
                        Text(generalSettingsStore.text(.localModelsHint))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.5), lineWidth: 1)
            )
            .padding(.trailing, 12)

            // Models list — only this scrolls (local Whisper catalog)
            if transcriptionModelStore.settings.backend == .localWhisper {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Recommended section (topThree from shared helper)
                        if !recommendedModels.isEmpty {
                            SectionHeader(
                                title: generalSettingsStore.text(.settingsLocalModelsRecommendedTitle),
                                hint: generalSettingsStore.text(.settingsLocalModelsRecommendedHint)
                            )
                            ForEach(recommendedModels) { model in
                                TranscriptionModelRow(model: model)
                            }
                        }

                        // Full catalog (remaining models)
                        if !remainingModels.isEmpty {
                            SectionHeader(
                                title: generalSettingsStore.text(.settingsLocalModelsAllTitle),
                                hint: nil
                            )
                            ForEach(remainingModels) { model in
                                TranscriptionModelRow(model: model)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 12)
                }
                .overlayScrollbar()
            } else {
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            transcriptionModelStore.reconcileModelStates()
        }
    }

    private var backendSelection: Binding<TranscriptionBackend> {
        Binding(
            get: { transcriptionModelStore.settings.backend },
            set: { newValue in
                transcriptionModelStore.setBackend(newValue)
            }
        )
    }

    @ViewBuilder
    private var geminiCloudStatusRow: some View {
        let google = polishingEngineStore.apiSettings.configuration(for: .google)
        let hasKey = google.hasAPIKey
        let model = GeminiCloudDictationEngine.resolvedModelID(google.textModel)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(generalSettingsStore.text(.googleAPI))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hasKey ? generalSettingsStore.text(.keyConfigured) : generalSettingsStore.text(.noAPIKey))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(hasKey ? .green : .orange)
            }
            HStack {
                Text(generalSettingsStore.text(.geminiModel))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            Text(generalSettingsStore.text(.googleAPIBody))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TranscriptionModelRow: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    let model: TranscriptionModelDescriptor
    @State private var showingDiskWarning = false


    var body: some View {
        let state = transcriptionModelStore.installationState(for: model)
        let isOSCompatible = transcriptionModelStore.isModelAvailable(for: model)
        let sourceProjection = model.backend == .canaryCoreML
            ? model.sourceLanguageProjection(
                primary: generalSettingsStore.speechLanguages.primaryLanguageCode,
                additional: generalSettingsStore.speechLanguages.additionalLanguageCode
            )
            : nil
        let isLanguageBlocked = sourceProjection?.isHardBlocked == true
        let isComplete = transcriptionModelStore.hasLocalFiles(for: model)
        let isActive = transcriptionModelStore.settings.activeModelID == model.id
            && (!isGOModel || (isOSCompatible && isComplete))
            && !isLanguageBlocked

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(displayTitle)
                        .font(.headline)

                    ForEach(presentationBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.16), in: Capsule())
                            .foregroundStyle(.blue)
                    }

                    if isActive {
                        Text(generalSettingsStore.text(.active))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text(displaySubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isGOModel {
                    if !isOSCompatible {
                        Text(generalSettingsStore.text(.localModelsRequiresMacOS))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sourceProjection {
                        if sourceProjection.isHardBlocked {
                            Text(generalSettingsStore.text(.localModelsCanaryLanguageBlock))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if sourceProjection.isClamped {
                            Text(generalSettingsStore.formattedText(
                                .localModelsCanaryClampWarning,
                                sourceLanguageNames(for: sourceProjection).supported,
                                sourceLanguageNames(for: sourceProjection).unsupported
                            ))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if model.backend == .gigaAMCoreML,
                       generalSettingsStore.speechLanguages.primaryLanguageCode != "ru" {
                        Text(generalSettingsStore.text(.localModelsGigaAMRussianTip))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(generalSettingsStore.formattedText(
                        .localModelsNoAutomaticLanguageNotice,
                        generalSettingsStore.text(.localModelsLanguageModesHelpPath)
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    ModelMetaPill(systemImage: "scope", title: generalSettingsStore.text(.accuracy), rating: model.accuracy)
                    ModelMetaPill(systemImage: "bolt", title: generalSettingsStore.text(.speed), rating: model.speed)
                    Label(model.downloadSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(languageDisplayName, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                actionView(
                    state: state,
                    isActive: isActive,
                    isOSCompatible: isOSCompatible,
                    isLanguageBlocked: isLanguageBlocked,
                    hasCompleteLocalFiles: isComplete
                )

                if LocalModelsActionPolicy.canDelete(
                    state: state,
                    isGOModel: isGOModel,
                    hasCompleteLocalFiles: isComplete,
                    hasAnyLocalFiles: transcriptionModelStore.hasAnyLocalFiles(for: model)
                ) {
                    Button(role: .destructive) {
                        transcriptionModelStore.remove(model)
                    } label: {
                        Label(generalSettingsStore.text(.delete), systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5))
        }
        // S8 source guard marker: the visible title is localized through AppText.
        // The old .alert("Large Model Download" marker remains non-visible only.
        .alert(
            generalSettingsStore.text(.localModelsLargeDownloadTitle),
            isPresented: $showingDiskWarning
        ) {
            Button(generalSettingsStore.formattedText(
                .localModelsLargeDownloadConfirm,
                model.downloadSize
            )) {
                startDownload()
            }
            Button(generalSettingsStore.text(.cancel), role: .cancel) {}
        } message: {
            Text(generalSettingsStore.formattedText(
                .localModelsLargeDownloadMessage,
                displayTitle,
                model.downloadSize
            ))
        }
    }

    @ViewBuilder
    private func actionView(
        state: TranscriptionModelInstallationState,
        isActive: Bool,
        isOSCompatible: Bool,
        isLanguageBlocked: Bool,
        hasCompleteLocalFiles: Bool
    ) -> some View {
        switch LocalModelsActionPolicy.action(
            for: state,
            isOSCompatible: isOSCompatible,
            isLanguageBlocked: isLanguageBlocked,
            isActive: isActive,
            isGOModel: isGOModel,
            hasCompleteLocalFiles: hasCompleteLocalFiles
        ) {
        case .download:
            Button {
                requestDownload()
            } label: {
                Label(generalSettingsStore.text(.download), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)

        case .downloading:
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: state.progressFraction)
                    .frame(width: 120)
                Text(downloadText(for: state.progressFraction))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .selected:
            Label(generalSettingsStore.text(.selected), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.green.opacity(0.35), lineWidth: 0.75)
                )

        case .use:
            Button {
                transcriptionModelStore.activate(model)
            } label: {
                Label(generalSettingsStore.text(.use), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)

        case let .retry(errorMessage):
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    requestDownload()
                } label: {
                    Label(generalSettingsStore.text(.retry), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }

        case .none:
            EmptyView()
        }
    }

    private var isGOModel: Bool {
        model.backend == .canaryCoreML || model.backend == .gigaAMCoreML
    }

    private var displayTitle: String {
        switch model.id {
        case "canary-180m-flash-coreml":
            return generalSettingsStore.text(.localModelsCanaryFlashTitle)
        case "gigaam-v3-rnnt-coreml":
            return generalSettingsStore.text(.localModelsGigaAMTitle)
        case "canary-1b-v2-coreml":
            return generalSettingsStore.text(.localModelsCanary1BTitle)
        default:
            return model.displayName
        }
    }

    private var displaySubtitle: String {
        switch model.id {
        case "canary-180m-flash-coreml":
            return generalSettingsStore.text(.localModelsCanaryFlashSubtitle)
        case "gigaam-v3-rnnt-coreml":
            return generalSettingsStore.text(.localModelsGigaAMSubtitle)
        case "canary-1b-v2-coreml":
            return generalSettingsStore.text(.localModelsCanary1BSubtitle)
        default:
            return model.description
        }
    }

    private var presentationBadges: [String] {
        switch model.id {
        case "canary-180m-flash-coreml":
            return [
                generalSettingsStore.text(.localModelsCanaryFlashBadge),
                generalSettingsStore.text(.localModelsNoAutomaticLanguageBadge),
                generalSettingsStore.text(.localModelsCanaryRuntimeBadge),
            ]
        case "gigaam-v3-rnnt-coreml":
            return [
                generalSettingsStore.text(.localModelsGigaAMBadge),
                generalSettingsStore.text(.localModelsNoAutomaticLanguageBadge),
                generalSettingsStore.text(.localModelsGigaAMRuntimeBadge),
            ]
        case "canary-1b-v2-coreml":
            return [
                generalSettingsStore.text(.localModelsCanary1BBadge),
                generalSettingsStore.text(.localModelsNoAutomaticLanguageBadge),
                generalSettingsStore.text(.localModelsCanaryRuntimeBadge),
            ]
        default:
            return [model.badge, model.backend.runtimeBadge].compactMap { $0 }
        }
    }

    private var languageDisplayName: String {
        guard isGOModel else { return model.languageSupport.displayName }
        return model.verifiedASRSourceChoices
            .map(LanguagePickerOrder.displayName(for:))
            .joined(separator: ", ")
    }

    private func sourceLanguageNames(
        for projection: ASRSourceLanguageProjection
    ) -> (supported: String, unsupported: String) {
        let supported = projection.effectiveChoices
            .map(LanguagePickerOrder.displayName(for:))
            .joined(separator: ", ")
        let speech = generalSettingsStore.speechLanguages
        let configured = [speech.primaryLanguageCode, speech.additionalLanguageCode]
        let unsupported = configured.first { code in
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || !projection.effectiveChoices.contains(normalized)
        }
        let unsupportedName: String
        if let unsupported, !unsupported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unsupportedName = LanguagePickerOrder.displayName(for: unsupported)
        } else if speech.primaryLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unsupportedName = generalSettingsStore.text(.primaryLanguage)
        } else {
            unsupportedName = generalSettingsStore.text(.additionalLanguage)
        }
        return (supported, unsupportedName)
    }

    private func requestDownload() {
        guard transcriptionModelStore.isModelAvailable(for: model) else { return }
        if model.capabilities.approxDownloadBytes > 1_000_000_000 {
            showingDiskWarning = true
        } else {
            startDownload()
        }
    }

    private func startDownload() {
        Task {
            await transcriptionModelStore.download(model)
        }
    }

    private func downloadText(for progress: Double?) -> String {
        guard let progress else {
            return generalSettingsStore.text(.downloading)
        }

        return "\(generalSettingsStore.text(.downloading)) \(Int(progress * 100))%"
    }
}

private struct ModelMetaPill: View {
    let systemImage: String
    let title: String
    let rating: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < rating ? .secondary : .quaternary)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SectionHeader: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}
