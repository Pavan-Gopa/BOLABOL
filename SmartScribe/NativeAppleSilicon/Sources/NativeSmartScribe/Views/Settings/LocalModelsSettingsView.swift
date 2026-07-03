import NativeSmartScribeCore
import SwiftUI

struct LocalModelsSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top config block — fixed height, no scrolling inside
            VStack(spacing: 0) {
                Form {
                    Section(generalSettingsStore.text(.transcriptionModel)) {
                        LabeledContent(generalSettingsStore.text(.activeModelLabel)) {
                            Text(transcriptionModelStore.activeModel?.displayName ?? generalSettingsStore.text(.noLocalModelSelected))
                                .foregroundStyle(transcriptionModelStore.activeModel == nil ? .secondary : .primary)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(height: 70)
                // Disable the inner NSScrollView of the Form so it doesn't scroll
                .allowsHitTesting(true)
                .scrollDisabled(true)
            }

            // Models list — only this scrolls
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(transcriptionModelStore.models) { model in
                        TranscriptionModelRow(model: model)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 12)
            }
            .overlayScrollbar()
        }
        .onAppear {
            transcriptionModelStore.reconcileModelStates()
        }
    }
}

private struct TranscriptionModelRow: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    let model: TranscriptionModelDescriptor

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
                Task {
                    await transcriptionModelStore.download(model)
                }
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
