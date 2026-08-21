import SwiftUI
import VaniScriptCore

struct BatchJobRowView: View {
    let job: BatchJob
    var onOpenCompanion: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Fixed-size status slot: one compact indeterminate spinner while this
            // job is processing, state icons otherwise. The identical frame keeps
            // row geometry stable across state transitions.
            Group {
                if job.state == .processing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.relativeSourcePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = job.lastError,
                   job.state == .failed || job.state == .blockedOutputCollision {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if job.state == .processing, let startedAt = job.startedAt ?? Optional(job.createdAt) {
                Text(startedAt, style: .timer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let duration = job.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if job.state == .completed {
                onOpenCompanion?()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(job.state == .completed ? "Double-click to open companion transcript" : "")
    }
    private var accessibilityLabel: String {
        let progressInfo = job.state == .processing ? job.voiceOverProgressValue : job.chunkProgressLabel
        return [job.relativeSourcePath, stateLabel, progressInfo, "attempt \(job.attempt)", job.formattedDuration, job.lastError]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
    /// Compact visual summary: state first, chunk progress where meaningful,
    /// and the attempt count only when the job has actually been retried.
    /// VoiceOver keeps the full label via `accessibilityLabel`.
    private var metadataLine: String {
        if job.state == .processing {
            var parts = [job.progressStageText]
            if job.attempt > 1 {
                parts.append("attempt \(job.attempt)")
            }
            return parts.joined(separator: " · ")
        }
        var parts = [stateLabel]
        if job.state != .pending {
            parts.append(job.chunkProgressLabel)
        }
        if job.attempt > 1 {
            parts.append("attempt \(job.attempt)")
        }
        return parts.joined(separator: " · ")
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

    private var icon: String {
        switch job.state {
        case .pending: "clock"
        case .processing: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed, .blockedOutputCollision: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var color: Color {
        switch job.state {
        case .completed: .green
        case .failed, .blockedOutputCollision: .red
        case .processing: .accentColor
        default: .secondary
        }
    }
}
