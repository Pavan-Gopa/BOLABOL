import NativeBolabolCore
import SwiftUI

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
                        Text(transcriptionModelStore.activeModel?.displayName ?? generalSettingsStore.text(.noLocalModelSelected))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(transcriptionModelStore.activeModel == nil ? .secondary : .primary)
                    }

                    if transcriptionModelStore.activeModel == nil {
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
        let isActive = transcriptionModelStore.settings.activeModelID == model.id

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.headline)

                    if let badge = model.badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.16), in: Capsule())
                            .foregroundStyle(.blue)
                    }

                    Text(model.backend.runtimeBadge)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.10), in: Capsule())
                        .foregroundStyle(.secondary)

                    if isActive {
                        Text(generalSettingsStore.text(.active))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text(model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ModelMetaPill(systemImage: "scope", title: generalSettingsStore.text(.accuracy), rating: model.accuracy)
                    ModelMetaPill(systemImage: "bolt", title: generalSettingsStore.text(.speed), rating: model.speed)
                    Label(model.downloadSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(model.languageSupport.displayName, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                actionView(state: state, isActive: isActive)

                if state.status == .downloaded || transcriptionModelStore.hasLocalFiles(for: model) {
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
    }

    @ViewBuilder
    private func actionView(
        state: TranscriptionModelInstallationState,
        isActive: Bool
    ) -> some View {
        switch state.status {
        case .notDownloaded:
            Button {
                if model.capabilities.approxDownloadBytes > 1_000_000_000 {
                    showingDiskWarning = true
                } else {
                    Task {
                        await transcriptionModelStore.download(model)
                    }
                }
            } label: {
                Label(generalSettingsStore.text(.download), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .alert("Large Model Download", isPresented: $showingDiskWarning) {
                Button("Download (\(model.downloadSize))") {
                    Task {
                        await transcriptionModelStore.download(model)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(model.displayName) requires approximately \(model.downloadSize) of disk space. Do you want to proceed?")
            }

        case .downloading:
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: state.progressFraction)
                    .frame(width: 120)
                Text(downloadText(for: state.progressFraction))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            if isActive {
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
            } else {
                Button {
                    transcriptionModelStore.activate(model)
                } label: {
                    Label(generalSettingsStore.text(.use), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
            }

        case .failed:
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Task {
                        await transcriptionModelStore.download(model)
                    }
                } label: {
                    Label(generalSettingsStore.text(.retry), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                if let errorMessage = state.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }
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
