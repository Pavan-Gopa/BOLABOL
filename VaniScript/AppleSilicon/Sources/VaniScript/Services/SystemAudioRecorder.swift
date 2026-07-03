import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sampleQueue = DispatchQueue(label: "com.vaniscript.system-audio-recorder.samples")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var outputURL: URL?
    private var didStartSession = false
    private var appendedSamples = 0
    private var onLevels: (@Sendable ([Double]) -> Void)?
    private var lastLevelUpdateNanos: UInt64 = 0
    private let levelUpdateIntervalNanos: UInt64 = 66_000_000

    var isRecording: Bool {
        stream != nil
    }

    func start(onLevels: (@Sendable ([Double]) -> Void)? = nil) async throws -> URL {
        guard stream == nil else {
            throw SystemAudioRecorderError.alreadyRecording
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplay
        }

        let outputURL = try makeRecordingURL()
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw SystemAudioRecorderError.cannotCreateWriter
        }
        writer.add(input)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        self.stream = stream
        self.writer = writer
        self.input = input
        self.outputURL = outputURL
        self.didStartSession = false
        self.appendedSamples = 0
        self.onLevels = onLevels
        self.lastLevelUpdateNanos = 0

        try await startCapture(stream)
        return outputURL
    }

    func stop() async throws -> URL {
        guard let stream, let writer, let input, let outputURL else {
            throw SystemAudioRecorderError.notRecording
        }

        try await stopCapture(stream)

        let sampleCount = sampleQueue.sync { appendedSamples }
        guard sampleCount > 0 else {
            writer.cancelWriting()
            cleanupRecordingState()
            try? FileManager.default.removeItem(at: outputURL)
            throw SystemAudioRecorderError.noAudioSamples
        }

        sampleQueue.sync {
            input.markAsFinished()
        }
        try await finishWriting(writer)

        cleanupRecordingState()
        return outputURL
    }

    func cancel() async {
        guard let stream else { return }
        try? await stopCapture(stream)
        writer?.cancelWriting()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        cleanupRecordingState()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let writer, let input else { return }

        if !didStartSession {
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            didStartSession = true
        }

        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            appendedSamples += sampleBuffer.numSamples
        }
        emitLevelsIfNeeded(from: sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        writer?.cancelWriting()
    }

    private func makeRecordingURL() throws -> URL {
        let directory = AppStoragePaths.recordingsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return directory
            .appendingPathComponent("VaniScript_Recording_\(formatter.string(from: Date()))")
            .appendingPathExtension("m4a")
    }

    private func cleanupRecordingState() {
        self.stream = nil
        self.writer = nil
        self.input = nil
        self.outputURL = nil
        self.didStartSession = false
        self.appendedSamples = 0
        self.onLevels = nil
        self.lastLevelUpdateNanos = 0
    }

    private func emitLevelsIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let onLevels else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastLevelUpdateNanos >= levelUpdateIntervalNanos else { return }
        lastLevelUpdateNanos = now
        guard let levels = AudioSampleBufferLevels.levels(from: sampleBuffer) else { return }
        onLevels(levels)
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let writerBox = AssetWriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerBox.writer.finishWriting {
                if writerBox.writer.status == .failed || writerBox.writer.status == .cancelled {
                    continuation.resume(throwing: writerBox.writer.error ?? SystemAudioRecorderError.cannotFinishRecording)
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

enum SystemAudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noDisplay
    case cannotCreateWriter
    case cannotFinishRecording
    case noAudioSamples

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "System audio recording is already running."
        case .notRecording:
            "No system audio recording is running."
        case .noDisplay:
            "No display is available for ScreenCaptureKit audio capture."
        case .cannotCreateWriter:
            "Could not create the native audio recording writer."
        case .cannotFinishRecording:
            "Could not finish the native audio recording."
        case .noAudioSamples:
            "Recording produced no system audio. Make sure audio is playing and Screen Recording permission is granted."
        }
    }
}
