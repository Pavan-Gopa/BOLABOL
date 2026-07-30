import NativeSmartScribeCore
import SwiftUI

@MainActor
struct PolishingSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Scan for local models button
                ScanForLocalModelsButton()

                // Catalog model cards
                ForEach(polishingEngineStore.models) { model in
                    PolishingModelRow(model: model)
                }

                // Custom (scanned) models section
                if !polishingEngineStore.customModels.isEmpty {
                    HStack {
                        Label(generalSettingsStore.text(.settingsLocalModels), systemImage: "folder.badge.gearshape")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 8)

                    ForEach(polishingEngineStore.customModels) { model in
                        PolishingModelRow(model: model)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 12)
        }
        .overlayScrollbar()
        .onAppear {
            polishingEngineStore.reconcileModelStates()
        }
    }

    private func engineTitle(for descriptor: PolishingEngineDescriptor) -> String {
        switch descriptor.id {
        case PolishingEngineStore.disabledEngineID:
            generalSettingsStore.text(.polishingDisabled)
        case "local-rule-based-polish":
            generalSettingsStore.text(.quickLocalCleanup)
        case PolishingEngineStore.mlxSwiftEngineID:
            generalSettingsStore.text(.localMLXModel)
        default:
            descriptor.displayName
        }
    }

    private func polishingEngineHint(for engineID: String) -> String {
        switch engineID {
        case PolishingEngineStore.disabledEngineID:
            generalSettingsStore.text(.polishingDisabledHint)
        case "local-rule-based-polish":
            generalSettingsStore.text(.quickLocalCleanupHint)
        case PolishingEngineStore.mlxSwiftEngineID:
            generalSettingsStore.text(.localMLXModelHint)
        default:
            generalSettingsStore.text(.apiPolishingHint)
        }
    }

}

private struct PolishingModelRow: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    let model: PolishingModelDescriptor

    var body: some View {
        let state = polishingEngineStore.installationState(for: model)
        let isActive = polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID
            && polishingEngineStore.settings.activeModelID == model.id

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
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
                            .background(
                                model.isCustom
                                    ? .purple.opacity(0.16)
                                    : .blue.opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(model.isCustom ? .purple : .blue)
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

                Text(model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isReasoningModel {
                    Label(
                        "Reasoning model: it may show its thinking in the result and is slower for polishing. A non-reasoning instruct model is recommended.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if !model.isCustom {
                        PolishingModelMetaPill(systemImage: "wand.and.stars", title: generalSettingsStore.text(.quality), rating: model.quality)
                        PolishingModelMetaPill(systemImage: "bolt", title: generalSettingsStore.text(.speed), rating: model.speed)
                    }
                    Label(model.downloadSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.isCustom, let localURL = model.localDirectoryURL {
                        Label {
                            Text(localURL.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(model.repositoryID, systemImage: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                actionView(state: state, isActive: isActive)

                if state.status == .downloaded || model.isCustom {
                    Button(role: .destructive) {
                        polishingEngineStore.remove(model)
                    } label: {
                        Label(
                            model.isCustom ? generalSettingsStore.text(.remove) : generalSettingsStore.text(.delete),
                            systemImage: model.isCustom ? "xmark.circle" : "trash"
                        )
                    }
                    .controlSize(.small)
                    .help(model.isCustom ? generalSettingsStore.text(.removeCustomModelHelp) : "")
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
        state: PolishingModelInstallationState,
        isActive: Bool
    ) -> some View {
        switch state.status {
        case .notDownloaded:
            Button {
                Task {
                    await polishingEngineStore.prepare(model)
                }
            } label: {
                Label(generalSettingsStore.text(.download), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(polishingEngineStore.isPreparingAnyModel)

        case .downloading:
            VStack(alignment: .trailing, spacing: 6) {
                if polishingEngineStore.isPreparing(model) {
                    ProgressView(value: state.progressFraction)
                        .frame(width: 120)
                    Text(downloadText(for: state.progressFraction))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task {
                            await polishingEngineStore.prepare(model)
                        }
                    } label: {
                        Label(generalSettingsStore.text(.retry), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(polishingEngineStore.isPreparingAnyModel)

                    Text(generalSettingsStore.text(.downloadInterrupted))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                    polishingEngineStore.activate(model)
                } label: {
                    Label(generalSettingsStore.text(.use), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
            }

        case .failed:
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Task {
                        await polishingEngineStore.prepare(model)
                    }
                } label: {
                    Label(generalSettingsStore.text(.retry), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(polishingEngineStore.isPreparingAnyModel)

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

        let percent = progress * 100
        if percent < 0.01 {
            return String(format: "\(generalSettingsStore.text(.downloading)) %.3f%%", percent)
        }
        if percent < 1 {
            return String(format: "\(generalSettingsStore.text(.downloading)) %.2f%%", percent)
        }
        return "\(generalSettingsStore.text(.downloading)) \(Int(percent))%"
    }
}

private struct PolishingModelMetaPill: View {
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

private extension ModelPreparationSnapshot {
    var statusText: String {
        switch phase {
        case .notReady:
            message ?? "Not ready"
        case .downloading:
            if let progressFraction {
                "Downloading \(Int(progressFraction * 100))%"
            } else {
                message ?? "Downloading"
            }
        case .loading:
            message ?? "Loading"
        case .ready:
            message ?? "Ready"
        case .failed:
            message ?? "Failed"
        }
    }
}

// MARK: - Scan for Local Models Button

private struct ScanForLocalModelsButton: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(generalSettingsStore.text(.scanForLocalModels))
                    .font(.subheadline.weight(.medium))
                Text(generalSettingsStore.text(.scanForLocalModelsBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 4) {
                if polishingEngineStore.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(generalSettingsStore.text(.scanning))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            await polishingEngineStore.scanForLocalModels()
                        }
                    } label: {
                        Label(generalSettingsStore.text(.scan), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }

                if let count = polishingEngineStore.lastScanResultCount {
                    Text(count == 0 ? generalSettingsStore.text(.noNewModelsFound) : generalSettingsStore.formattedText(.foundModelsCount, "\(count)"))
                        .font(.caption)
                        .foregroundStyle(count > 0 ? .green : .secondary)
                }

                if let skipped = polishingEngineStore.lastScanSkippedUnsupportedCount,
                   skipped > 0 {
                    Text(generalSettingsStore.formattedText(.skippedUnsupportedModels, "\(skipped)"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(generalSettingsStore.text(.localPolishingSupportHint))
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
}
