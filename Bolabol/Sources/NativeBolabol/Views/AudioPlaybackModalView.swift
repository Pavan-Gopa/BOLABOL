import NativeBolabolCore
import AVFoundation
import Combine
import SwiftUI

@MainActor
struct AudioPlaybackModalView: View {
    let note: BolabolNote
    @ObservedObject var noteStore: NoteStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionEngineStore: TranscriptionEngineStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @Binding var isPresented: Bool

    @State private var avPlayer: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var volume: Double = 1.0
    @State private var isRetranscribing = false
    @State private var statusMessage = ""

    private var isV1Selected: Bool {
        hotkeySettingsStore.settings.target == .note
    }

    private var isV2Selected: Bool {
        hotkeySettingsStore.settings.target == .x2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? generalSettingsStore.text(.untitledNote)
                         : note.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(generalSettingsStore.text(.audioPlaybackModalTitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            if let audioRecording = note.audioRecording,
               FileManager.default.fileExists(atPath: audioRecording.fileURL.path) {

                VStack(spacing: 14) {
                    // Scrubber Slider
                    HStack(spacing: 10) {
                        Text(formatTime(currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { currentTime },
                                set: { newValue in
                                    currentTime = newValue
                                    seek(to: newValue)
                                }
                            ),
                            in: 0...max(duration, 0.1)
                        )

                        Text(formatTime(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                    }

                    // Volume Boost Control (Up to 300%)
                    HStack(spacing: 10) {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Slider(
                            value: Binding(
                                get: { volume },
                                set: { newValue in
                                    volume = newValue
                                    avPlayer?.volume = Float(newValue)
                                }
                            ),
                            in: 0.0...3.0
                        )

                        Text("\(Int(volume * 100))%")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(volume > 1.0 ? Color.accentColor : .secondary)
                            .frame(width: 44, alignment: .trailing)
                    }

                    // Playback Controls
                    HStack(spacing: 20) {
                        Button {
                            seek(by: -5)
                        } label: {
                            Image(systemName: "gobackward.5")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(avPlayer == nil)

                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(avPlayer == nil)
                        .keyboardShortcut(.space, modifiers: [])

                        Button {
                            seek(by: 5)
                        } label: {
                            Image(systemName: "goforward.5")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(avPlayer == nil)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))

                if !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        if isRetranscribing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    // Polishing Variant Selection (V1 / V2) synchronized with program Output Target
                    HStack(spacing: 6) {
                        Button {
                            if hotkeySettingsStore.settings.target == .note {
                                hotkeySettingsStore.settings.target = .raw
                            } else {
                                hotkeySettingsStore.settings.target = .note
                            }
                        } label: {
                            Text("V1")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isV1Selected ? Color.accentColor : Color.secondary.opacity(0.18))
                                )
                                .foregroundStyle(isV1Selected ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isV1Selected ? "Variant 1 active (Output Target: V1)" : "Set Output Target to V1")

                        Button {
                            if hotkeySettingsStore.settings.target == .x2 {
                                hotkeySettingsStore.settings.target = .raw
                            } else {
                                hotkeySettingsStore.settings.target = .x2
                            }
                        } label: {
                            Text("V2")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isV2Selected ? Color.accentColor : Color.secondary.opacity(0.18))
                                )
                                .foregroundStyle(isV2Selected ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isV2Selected ? "Variant 2 active (Output Target: V2)" : "Set Output Target to V2")
                    }

                    Spacer()

                    Button {
                        retranscribe()
                    } label: {
                        Label(
                            generalSettingsStore.text(.retranscribeNoteLabel),
                            systemImage: "arrow.clockwise.circle.fill"
                        )
                        .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetranscribing)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(generalSettingsStore.text(.audioFileNotFound))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanUpPlayer()
        }
    }

    private func setupPlayer() {
        guard let audioRecording = note.audioRecording else { return }

        let asset = AVURLAsset(url: audioRecording.fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.volume = Float(volume)

        self.avPlayer = player
        let durationSeconds = audioRecording.duration > 0 ? audioRecording.duration : CMTimeGetSeconds(asset.duration)
        self.duration = (durationSeconds.isNaN || durationSeconds.isInfinite) ? 0 : durationSeconds

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player else { return }
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                if !seconds.isNaN && !seconds.isInfinite {
                    self.currentTime = seconds
                }
                if player.timeControlStatus == .paused && self.isPlaying {
                    let maxDuration = self.duration
                    if maxDuration > 0 && self.currentTime >= maxDuration - 0.2 {
                        self.isPlaying = false
                        self.currentTime = 0
                        self.seek(to: 0)
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.isPlaying = false
                self.currentTime = 0
                self.seek(to: 0)
            }
        }
    }

    private func cleanUpPlayer() {
        if let token = timeObserverToken, let player = avPlayer {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        avPlayer?.pause()
        avPlayer = nil
    }

    private func togglePlayPause() {
        guard let player = avPlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(by seconds: Double) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    private func seek(to seconds: Double) {
        guard let player = avPlayer else { return }
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func retranscribe() {
        guard let audioRecording = note.audioRecording else { return }
        avPlayer?.pause()
        isPlaying = false

        isRetranscribing = true
        statusMessage = generalSettingsStore.text(.retranscribingStatus)

        let target = hotkeySettingsStore.settings.target
        let requestedVariants = target.requestedPolishingVariants

        // Close modal immediately so re-transcription runs persistently in the background
        isPresented = false

        Task { @MainActor in
            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: transcriptionEngineStore.activeEngine(modelStore: transcriptionModelStore),
                glossarySettingsProvider: { glossaryStore.settings }
            )

            let languageCode = transcriptionModelStore.resolvedLanguageCode
            let forcedLanguageCode = languageCode == "auto" ? nil : languageCode
            await workflow.retranscribeExistingNote(
                noteID: note.id,
                audioFileURL: audioRecording.fileURL,
                forcedLanguageCode: forcedLanguageCode
            )

            if !requestedVariants.isEmpty && polishingEngineStore.canAutoPolishAfterTranscription {
                let polishingWorkflow = PolishingWorkflow(
                    noteStore: noteStore,
                    engine: polishingEngineStore.activeEngine,
                    templateProvider: { variant in
                        promptTemplateStore.template(for: variant)
                    }
                )
                await polishingWorkflow.polishNote(note.id, variants: requestedVariants)
            }
        }
    }
}


