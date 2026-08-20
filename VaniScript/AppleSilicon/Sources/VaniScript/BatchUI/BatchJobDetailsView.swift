import SwiftUI
import VaniScriptCore

struct BatchJobDetailsView: View {
    @ObservedObject var store: BatchTranscriptionStore
    let job: BatchJob

    var body: some View {
        Form {
            Section("File") {
                LabeledContent("Source", value: job.relativeSourcePath)
                    .textSelection(.enabled)
                LabeledContent("Companion output", value: job.relativeOutputPath)
                    .textSelection(.enabled)
            }
            Section("Status") {
                LabeledContent("State") {
                    Label(stateLabel, systemImage: stateIcon)
                        .foregroundStyle(stateColor)
                }
                if job.state == .processing {
                    if job.isDeterminateProgress {
                        ProgressView(value: min(max(job.progress, 0), 1)) {
                            Text(job.progressStageText)
                        } currentValueLabel: {
                            Text(job.chunkProgressLabel)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Transcription progress")
                        .accessibilityValue(job.voiceOverProgressValue)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView {
                                Text(job.progressStageText)
                            }
                            Text(job.chunkProgressLabel)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Transcription progress")
                        .accessibilityValue(job.voiceOverProgressValue)
                    }
                } else {
                    LabeledContent("Progress", value: job.chunkProgressLabel)
                }
                LabeledContent("Attempts", value: String(job.attempt))
                if job.state == .processing, let startedAt = job.startedAt ?? Optional(job.createdAt) {
                    LabeledContent("Processing duration") {
                        Text(startedAt, style: .timer)
                            .monospacedDigit()
                    }
                } else if let duration = job.formattedDuration {
                    LabeledContent("Processing duration", value: duration)
                }
                LabeledContent("Generation", value: String(job.generation))
            }
            if let error = job.lastError {
                Section("Issue") {
                    Label {
                        Text(error)
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Issue: \(error)")
                }
            }
            Section("Configuration") {
                LabeledContent("Provider", value: providerName)
                LabeledContent("Source language", value: job.configuration.sourceLanguage)
            }
            Section("History") {
                LabeledContent("Created", value: job.createdAt.formatted())
                LabeledContent("Updated", value: job.updatedAt.formatted())
            }
            Section {
                HStack(spacing: 12) {
                    if job.state == .completed {
                        Button("Open Transcript") { store.openCompanion(for: job) }
                            .accessibilityLabel("Open companion transcript for \(job.relativeSourcePath)")
                    }
                    if job.state == .failed || job.state == .cancelled || job.state == .blockedOutputCollision {
                        Button("Retry") { Task { await store.retry(jobID: job.id) } }
                            .accessibilityLabel("Retry \(job.relativeSourcePath)")
                    }
                    if job.state == .pending || job.state == .processing {
                        Button("Cancel", role: .destructive) { Task { await store.cancel(jobID: job.id) } }
                            .accessibilityLabel("Cancel \(job.relativeSourcePath)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fileName)
    }

    private var fileName: String {
        URL(fileURLWithPath: job.relativeSourcePath).lastPathComponent
    }

    private var providerName: String {
        let identifier = job.configuration.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = identifier.split(separator: "|")
        // New pipe-separated format: planner|silence|provider|model|lang|chunk|slice|thresh|silence|canonical
        if parts.count >= 4 {
            let provider = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            let model = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
            let readable = provider == model ? provider : "\(provider) · \(model)"
            return Self.shortProviderName(readable)
        }
        // Legacy batch identifiers encode the full configuration as a long hex string.
        // Never allow that implementation detail to determine the Form's width.
        if identifier.hasPrefix("batch-id-v2-") || identifier.count > 96 {
            return "Local transcription"
        }
        return Self.shortProviderName(identifier)
    }

    private static func shortProviderName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 56 else { return normalized }
        return String(normalized.prefix(53)) + "…"
    }

    private var stateLabel: String {
        switch job.state {
        case .pending: "Pending"
        case .processing: "Processing"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .blockedOutputCollision: "Output conflict"
        }
    }

    private var stateIcon: String {
        switch job.state {
        case .pending: "clock"
        case .processing: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed, .blockedOutputCollision: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var stateColor: Color {
        switch job.state {
        case .completed: .green
        case .failed, .blockedOutputCollision: .red
        case .processing: .accentColor
        default: .secondary
        }
    }
}
