import NativeSmartScribeCore
import SwiftUI

struct AudioInputDeviceStatusPill: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @ObservedObject var audioRecorder: AudioRecorder
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            SoundActivityDot(
                isActive: audioRecorder.isRecording && audioRecorder.inputLevel > 0.025,
                level: audioRecorder.inputLevel,
                tint: tint
            )

            if !compact {
                Button {
                    audioRecorder.refreshInputDeviceStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(generalSettingsStore.text(.refreshAudioInput))
            }
        }
        .smartScribeFont(.caption, weight: .medium)
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.75))
        .help(helpText)
    }

    private var status: AudioRecorder.InputDeviceStatus {
        audioRecorder.inputDeviceStatus
    }

    private var title: String {
        switch status.availability {
        case .available:
            return String(
                format: generalSettingsStore.text(.audioInputReady),
                status.deviceName ?? "Microphone"
            )
        case .unavailable:
            return generalSettingsStore.text(.audioInputNoDevice)
        case .unknown:
            return generalSettingsStore.text(.audioInputChecking)
        }
    }

    private var subtitle: String {
        if audioRecorder.isRecording {
            return audioRecorder.inputLevel > 0.025
                ? generalSettingsStore.text(.audioSignalActive)
                : generalSettingsStore.text(.audioListening)
        }
        return generalSettingsStore.text(.refreshAudioInput)
    }

    private var iconName: String {
        switch status.availability {
        case .available:
            return "mic.fill"
        case .unavailable:
            return "mic.slash.fill"
        case .unknown:
            return "mic"
        }
    }

    private var tint: Color {
        switch status.availability {
        case .available:
            return audioRecorder.isRecording ? .red : .green
        case .unavailable:
            return compact ? .red : .orange
        case .unknown:
            return .secondary
        }
    }

    private var helpText: String {
        status.message ?? title
    }
}

private struct SoundActivityDot: View {
    let isActive: Bool
    let level: Float
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isActive ? 0.22 : 0.08))
                .frame(width: 12, height: 12)
            Circle()
                .fill(tint.opacity(isActive ? 0.95 : 0.35))
                .frame(
                    width: max(4, CGFloat(level) * 12),
                    height: max(4, CGFloat(level) * 12)
                )
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
