import AVFoundation
import Foundation

final class MicrophoneAudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let levelQueue = DispatchQueue(label: "com.vaniscript.microphone-audio-recorder.levels")
    private var session: AVCaptureSession?
    private var dataOutput: AVCaptureAudioDataOutput?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var outputURL: URL?
    private var cancelRequested = false
    private var didStartSession = false
    private var appendedSamples = 0
    private var onLevels: (@Sendable ([Double]) -> Void)?
    private var lastLevelUpdateNanos: UInt64 = 0
    private let levelUpdateIntervalNanos: UInt64 = 66_000_000

    var isRecording: Bool {
        session?.isRunning == true
    }

    func start(
        deviceUniqueID: String?,
        onLevels: (@Sendable ([Double]) -> Void)? = nil
    ) async throws -> URL {
        guard session == nil else {
            throw MicrophoneAudioRecorderError.alreadyRecording
        }
        try await ensureAudioPermission()

        guard let device = Self.audioDevice(uniqueID: deviceUniqueID) else {
            throw MicrophoneAudioRecorderError.noInputDevice
        }

        let outputURL = try makeRecordingURL()
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw MicrophoneAudioRecorderError.cannotCreateOutput
        }
        writer.add(input)

        let sessionInput = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let dataOutput = AVCaptureAudioDataOutput()

        session.beginConfiguration()
        if session.canAddInput(sessionInput) {
            session.addInput(sessionInput)
        } else {
            session.commitConfiguration()
            throw MicrophoneAudioRecorderError.cannotCreateInput
        }
        if session.canAddOutput(dataOutput) {
            dataOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            dataOutput.setSampleBufferDelegate(self, queue: levelQueue)
            session.addOutput(dataOutput)
        } else {
            session.commitConfiguration()
            throw MicrophoneAudioRecorderError.cannotCreateOutput
        }
        session.commitConfiguration()

        self.session = session
        self.dataOutput = dataOutput
        self.writer = writer
        self.input = input
        self.outputURL = outputURL
        self.cancelRequested = false
        self.didStartSession = false
        self.appendedSamples = 0
        self.onLevels = onLevels
        self.lastLevelUpdateNanos = 0

        session.startRunning()
        return outputURL
    }

    func stop() async throws -> URL {
        guard let session, let writer, let input, let outputURL else {
            throw MicrophoneAudioRecorderError.notRecording
        }

        session.stopRunning()

        let sampleCount = levelQueue.sync { appendedSamples }
        guard sampleCount > 0 else {
            writer.cancelWriting()
            cleanupRecordingState()
            try? FileManager.default.removeItem(at: outputURL)
            throw MicrophoneAudioRecorderError.noAudioSamples
        }

        levelQueue.sync {
            input.markAsFinished()
        }

        try await finishWriting(writer)
        cleanupRecordingState()
        return outputURL
    }

    func cancel() async {
        session?.stopRunning()
        writer?.cancelWriting()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        cleanupRecordingState()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let writer, let input else { return }

        if !didStartSession {
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            didStartSession = true
        }

        if input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) {
                appendedSamples += sampleBuffer.numSamples
            }
        }

        emitLevelsIfNeeded(from: sampleBuffer)
    }

    private func makeRecordingURL() throws -> URL {
        let directory = AppStoragePaths.recordingsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return directory
            .appendingPathComponent("VaniScript_Microphone_Recording_\(formatter.string(from: Date()))")
            .appendingPathExtension("m4a")
    }

    private func cleanupRecordingState() {
        session = nil
        dataOutput = nil
        writer = nil
        input = nil
        outputURL = nil
        cancelRequested = false
        didStartSession = false
        appendedSamples = 0
        onLevels = nil
        lastLevelUpdateNanos = 0
    }

    private func emitLevelsIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let onLevels else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastLevelUpdateNanos >= levelUpdateIntervalNanos else { return }
        lastLevelUpdateNanos = now
        guard let levels = AudioSampleBufferLevels.levels(from: sampleBuffer) else { return }
        onLevels(levels)
    }

    private static func audioDevice(uniqueID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        if let uniqueID,
           !uniqueID.isEmpty,
           let selected = devices.first(where: { $0.uniqueID == uniqueID }) {
            return selected
        }
        return AVCaptureDevice.default(for: .audio) ?? devices.first
    }

    private func ensureAudioPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                return
            }
            throw MicrophoneAudioRecorderError.permissionDenied
        case .denied, .restricted:
            throw MicrophoneAudioRecorderError.permissionDenied
        @unknown default:
            throw MicrophoneAudioRecorderError.permissionDenied
        }
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let writerBox = AssetWriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerBox.writer.finishWriting {
                if writerBox.writer.status == .failed || writerBox.writer.status == .cancelled {
                    continuation.resume(throwing: writerBox.writer.error ?? MicrophoneAudioRecorderError.noAudioSamples)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

enum MicrophoneAudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noInputDevice
    case permissionDenied
    case cannotCreateInput
    case cannotCreateOutput
    case noAudioSamples
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Microphone recording is already running."
        case .notRecording:
            "No microphone recording is running."
        case .noInputDevice:
            "No microphone or virtual audio input is available."
        case .permissionDenied:
            "Microphone permission is required to record this source."
        case .cannotCreateInput:
            "Could not connect the selected audio input."
        case .cannotCreateOutput:
            "Could not create the microphone recording output."
        case .noAudioSamples:
            "Recording produced no microphone audio."
        case .cancelled:
            "Microphone recording cancelled."
        }
    }
}
