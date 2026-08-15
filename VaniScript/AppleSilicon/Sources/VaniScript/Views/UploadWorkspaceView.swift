import SwiftUI
import AVKit

struct UploadWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            LogoHeader()
                .padding(.bottom, 36)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 220), spacing: 16), count: 3),
                spacing: 16
            ) {
                UploadOptionCard(
                    title: "Upload Media / Document",
                    detail: "Import audio, video, DOCX, TXT, MD, RTF, or PDF.",
                    systemImage: "tray.and.arrow.up",
                    dashed: true,
                    action: store.chooseSourceFile,
                    onDrop: store.handleDroppedSources
                )
                .onboardingTarget("workspace-dropzone")

                UploadOptionCard(
                    title: "Record Audio Source",
                    detail: "Capture system audio or a connected microphone.",
                    systemImage: "mic",
                    action: store.presentRecordingWorkspace
                )
                .onboardingTarget("workspace-record-card")

                UploadOptionCard(
                    title: "Import Link",
                    detail: "Download media directly from the internet, e.g. YouTube or SoundCloud.",
                    systemImage: "link",
                    action: store.presentLinkImporter
                )
                .onboardingTarget("workspace-link-card")
            }
            .frame(maxWidth: 1020)

            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .padding(.top, 18)
            }

            if !store.recordingMessage.isEmpty {
                Text(store.recordingMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.isRecordingSystemAudio ? Color.red.opacity(0.9) : VaniScriptTheme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer(minLength: 22)

            AppFooter()
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .sheet(isPresented: $store.isLinkImporterPresented) {
            LinkImportSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isRecordingWorkspacePresented) {
            RecordingWorkspaceSheet()
                .environmentObject(store)
        }
    }
}

private struct RecordingWorkspaceSheet: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VaniScriptLogoMark(size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.recordingPreviewURL == nil ? "Record Audio Source" : "Review Recording")
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(VaniScriptTheme.text0)
                        Text(sheetSubtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                    Spacer()
                    Button {
                        store.dismissRecordingWorkspace()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(RecordingIconButtonStyle())
                    .disabled(store.isRecordingSystemAudio || store.isPreparingRecordingPreview || store.isSavingRecording)
                    .help("Close")
                }

                if store.recordingPreviewURL != nil {
                    recordingReview
                } else if store.isRecordingSystemAudio {
                    recordingInProgress
                } else if store.isPreparingRecordingPreview || store.isSavingRecording {
                    recordingPending
                } else {
                    recordingSetup
                }
            }
            .padding(24)
            .frame(width: 560)
            .glassPanel()
            .padding(22)
        }
        .frame(width: 620, height: 460)
        .preferredColorScheme(store.settings.theme == .dark ? .dark : .light)
        .onAppear {
            store.refreshRecordingDevices()
        }
    }

    private var sheetSubtitle: String {
        if store.recordingPreviewURL != nil {
            return store.recordingMode == .system
                ? "Listen to the captured system/browser audio before sending it to transcription."
                : "Listen to the microphone recording before sending it to transcription."
        }
        if store.isRecordingSystemAudio {
            return store.recordingMode == .system
                ? "Capturing the shared source audio."
                : "Capturing the selected audio input."
        }
        return "Choose a source, record, review the audio, then continue to transcription."
    }

    private var recordingSetup: some View {
        VStack(spacing: 16) {
            recordingSourceTabs
            VStack(alignment: .leading, spacing: 8) {
                Text("Input Device")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .textCase(.uppercase)
                if store.recordingMode == .microphone {
                    HStack(spacing: 8) {
                        Picker("", selection: $store.selectedRecordingDeviceID) {
                            Text("Default input").tag("")
                            ForEach(store.recordingDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Button {
                            store.refreshRecordingDevices()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(RecordingIconButtonStyle())
                        .help("Refresh audio inputs")
                    }
                } else {
                    Text("System audio uses native ScreenCaptureKit. If macOS does not expose the app audio, switch to Mic / Virtual and choose a physical microphone or a virtual input such as BlackHole or Loopback.")
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(VaniScriptTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if !store.recordingErrorMessage.isEmpty {
                Text(store.recordingErrorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    store.openRecordingsFolder()
                } label: {
                    Label("Recordings", systemImage: "folder")
                }
                .buttonStyle(RecordingSecondaryButtonStyle())

                Button {
                    store.startAudioRecording()
                } label: {
                    Label("Start Recording", systemImage: "mic")
                }
                .buttonStyle(RecordingPrimaryButtonStyle())
            }
        }
    }

    private var recordingSourceTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording source")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
                .textCase(.uppercase)
            HStack(spacing: 6) {
                ForEach(RecordingMode.allCases) { mode in
                    Button {
                        store.recordingMode = mode
                    } label: {
                        Text(mode.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RecordingModeButtonStyle(active: store.recordingMode == mode))
                }
            }
        }
    }

    private var recordingInProgress: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(VaniScriptTheme.red)
                    .frame(width: 9, height: 9)
                Text("Recording \(WorkflowStore.formatRecordingTime(store.recordingElapsedSec))")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text0)
            }
            recordingMeter(active: true)
            if !store.recordingMessage.isEmpty {
                Text(store.recordingMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    store.cancelSystemAudioRecording()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(RecordingSecondaryButtonStyle())

                Button {
                    store.stopAndPreviewRecording()
                } label: {
                    Label("Stop & Review", systemImage: "stop.fill")
                }
                .buttonStyle(RecordingPrimaryButtonStyle())
            }
        }
    }

    private var recordingPending: some View {
        VStack(spacing: 16) {
            Text(store.isSavingRecording ? "Saving recording..." : "Preparing preview...")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text0)
            Text(store.isSavingRecording ? "Loading this capture into the normal transcription workflow." : "Loading the captured audio for review.")
                .font(.system(size: 12))
                .foregroundStyle(VaniScriptTheme.text2)
            recordingMeter(active: false)
        }
        .frame(minHeight: 220)
    }

    private var recordingReview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    store.toggleRecordingPreviewPlayback()
                } label: {
                    Image(systemName: store.isRecordingPreviewPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(RecordingPlayButtonStyle())
                VStack(spacing: 4) {
                    Slider(value: recordingPreviewSeek, in: 0...max(store.recordingPreviewDurationSec, 1))
                        .tint(VaniScriptTheme.accent)
                    HStack {
                        Text(WorkflowStore.formatRecordingTime(store.recordingPreviewTime))
                        Spacer()
                        Text(WorkflowStore.formatRecordingTime(store.recordingPreviewDurationSec))
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text2)
                }
            }
            .padding(14)
            .background(VaniScriptTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !store.recordingErrorMessage.isEmpty {
                Text(store.recordingErrorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    store.discardRecordingPreview()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(RecordingSecondaryButtonStyle())

                Button {
                    store.useRecordingPreview()
                } label: {
                    Label(store.isSavingRecording ? "Saving..." : "Save & Continue", systemImage: "checkmark")
                }
                .buttonStyle(RecordingPrimaryButtonStyle())
                .disabled(store.isSavingRecording)
            }
        }
    }

    private var recordingPreviewSeek: Binding<Double> {
        Binding {
            store.recordingPreviewTime
        } set: { value in
            store.seekRecordingPreview(to: value)
        }
    }

    private func recordingMeter(active: Bool) -> some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(store.recordingAudioLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? VaniScriptTheme.accent : VaniScriptTheme.text2.opacity(0.28))
                    .frame(width: 5, height: meterHeight(level: level, active: active))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 66)
        .padding(.horizontal, 10)
        .background(VaniScriptTheme.input)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func meterHeight(level: Double, active: Bool) -> CGFloat {
        let clamped = max(0.08, min(1, active ? level : 0.12))
        return CGFloat(10 + clamped * 54)
    }
}

private struct LinkImportSheet: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 16) {
                VaniScriptLogoMark(size: 32)
                Text("Import from Link")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)

                Text("Download media you have permission to use, then continue through the usual VaniScript workflow.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                TextField("Paste YouTube, SoundCloud, or direct media URL", text: $store.linkImportURL)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(VaniScriptTheme.input)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(store.isImportingLink || store.isLinkImportCompleted)

                // Segment Selector
                HStack(spacing: 0) {
                    Button(action: { store.linkImportAudioOnly = false }) {
                        Text("Video + audio")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(!store.linkImportAudioOnly ? VaniScriptTheme.onAccent : VaniScriptTheme.text2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(!store.linkImportAudioOnly ? VaniScriptTheme.accent : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isImportingLink || store.isLinkImportCompleted)

                    Button(action: { store.linkImportAudioOnly = true }) {
                        Text("Audio only")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(store.linkImportAudioOnly ? VaniScriptTheme.onAccent : VaniScriptTheme.text2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(store.linkImportAudioOnly ? VaniScriptTheme.accent : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isImportingLink || store.isLinkImportCompleted)
                }
                .padding(3)
                .background(VaniScriptTheme.control)
                .clipShape(Capsule())
                // Progress Bar
                if store.isImportingLink || store.isLinkImportCompleted {
                    VStack(spacing: 6) {
                        ProgressView(value: store.linkImportProgress ?? 0.0, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(VaniScriptTheme.accent)
                            .frame(width: 320)

                        if !store.linkImportMessage.isEmpty {
                            Text(store.linkImportMessage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VaniScriptTheme.accent)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 4)
                } else if !store.linkImportMessage.isEmpty {
                    Text(store.linkImportMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                }

                // Video/Audio Preview Player
                if store.isLinkImportCompleted, let url = store.linkImportedURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaniScriptTheme.border, lineWidth: 1))
                        .padding(.vertical, 4)
                }

                // Action Buttons
                HStack(spacing: 10) {
                    Button(store.isLinkImportCompleted ? "Imports" : "Cancel") {
                        store.dismissLinkImporter()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(store.isImportingLink)

                    if store.isLinkImportCompleted {
                        Button("Continue") {
                            store.continueAfterLinkImport()
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                    } else {
                        Button(store.isImportingLink ? "Importing..." : "Import") {
                            store.importDirectMediaLink()
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(store.isImportingLink || store.linkImportURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(24)
            .frame(width: 480)
            .glassPanel()
            .padding(20)
        }
        .frame(width: 540, height: store.isLinkImportCompleted ? 580 : 330)
        .preferredColorScheme(store.settings.theme == .dark ? .dark : .light)
    }
}

private struct UploadOptionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let dashed: Bool
    let status: String?
    let action: () -> Void
    let onDrop: (([URL]) -> Bool)?

    init(
        title: String,
        detail: String,
        systemImage: String,
        dashed: Bool = false,
        status: String? = nil,
        action: @escaping () -> Void,
        onDrop: (([URL]) -> Bool)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.dashed = dashed
        self.status = status
        self.action = action
        self.onDrop = onDrop
    }

    @ViewBuilder
    var body: some View {
        if let onDrop {
            cardContent
                .dropDestination(for: URL.self) { urls, _ in
                    onDrop(urls)
                }
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(VaniScriptTheme.accent.opacity(0.12))
                        .overlay(Circle().stroke(VaniScriptTheme.accent.opacity(0.32), lineWidth: 1.5))
                    Image(systemName: systemImage)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.accent)
                }
                .frame(width: 48, height: 48)

                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 260)

                if let status {
                    Text(status)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(VaniScriptTheme.accent.opacity(0.12))
                        .overlay(Capsule().stroke(VaniScriptTheme.accent.opacity(0.28), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .padding(28)
            .background(VaniScriptTheme.card)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                dashed ? VaniScriptTheme.border.opacity(1.3) : VaniScriptTheme.border,
                style: StrokeStyle(lineWidth: dashed ? 1.5 : 1, dash: dashed ? [6, 5] : [])
            )
    }
}

private struct RecordingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RecordingSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RecordingIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .frame(width: 30, height: 30)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RecordingModeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(isEnabled ? (active ? VaniScriptTheme.onAccent : VaniScriptTheme.text2) : VaniScriptTheme.disabledText)
            .padding(.vertical, 9)
            .background(
                isEnabled
                    ? (active ? VaniScriptTheme.accent : (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control))
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isEnabled ? (active ? VaniScriptTheme.accent.opacity(0.55) : VaniScriptTheme.controlBorder) : VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RecordingPlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .frame(width: 38, height: 38)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                Circle()
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(Circle())
    }
}
