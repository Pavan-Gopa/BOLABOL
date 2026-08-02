import AVFoundation
import Combine
import CoreAudio
import Foundation
import NativeBlaboomCore

@MainActor
final class AudioRecorder: ObservableObject {
    enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    struct InputDeviceStatus: Equatable {
        enum Availability: Equatable {
            case unknown
            case available
            case unavailable
        }

        var availability: Availability
        var deviceName: String?
        var message: String?

        var isAvailable: Bool {
            availability == .available
        }

        static let unknown = InputDeviceStatus(
            availability: .unknown,
            deviceName: nil,
            message: nil
        )
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var frequencyBands: [Float] = Array(repeating: 0.08, count: 40)
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var inputDeviceStatus: InputDeviceStatus = .unknown
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private var textProvider: (AppTextKey) -> String
    private let fileManager: FileManager
    private let recordingsDirectory: URL
    private var currentFileURL: URL?
    private var currentFormat: AVAudioFormat?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var inputDeviceMonitorTimer: Timer?
    private var smoothedFrequencyBands = Array(repeating: Float(0.08), count: 40)
    private var didInstallInputTap = false

    init(
        textProvider: @escaping (AppTextKey) -> String = {
            AppText.localized($0, language: .english)
        },
        fileManager: FileManager = .default
    ) {
        self.textProvider = textProvider
        self.fileManager = fileManager
        self.recordingsDirectory = Self.defaultRecordingsDirectory(fileManager: fileManager)
        refreshInputDeviceStatus()
        startInputDeviceMonitor()
    }

    func setTextProvider(_ provider: @escaping (AppTextKey) -> String) {
        textProvider = provider
    }

    @discardableResult
    func refreshInputDeviceStatus() -> InputDeviceStatus {
        let status = Self.currentInputDeviceStatus(textProvider: textProvider)
        inputDeviceStatus = status
        if status.isAvailable,
           errorMessage == textProvider(.audioInputNoDevice) {
            errorMessage = nil
        }
        return status
    }

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil

        let inputStatus = refreshInputDeviceStatus()
        guard inputStatus.isAvailable else {
            errorMessage = inputStatus.message ?? textProvider(.audioInputNoDevice)
            return
        }

        guard await requestMicrophonePermission() else {
            errorMessage = textProvider(.microphoneAccessDisabled)
            return
        }

        do {
            let refreshedInputStatus = refreshInputDeviceStatus()
            guard refreshedInputStatus.isAvailable else {
                errorMessage = refreshedInputStatus.message ?? textProvider(.audioInputNoDevice)
                return
            }

            try fileManager.createDirectory(
                at: recordingsDirectory,
                withIntermediateDirectories: true
            )

            let fileURL = Self.makeRecordingURL(in: recordingsDirectory)
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: 1,
                interleaved: false
            ) ?? format

            let monoSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: monoFormat.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]

            let audioFile = try AVAudioFile(forWriting: fileURL, settings: monoSettings)
            let startDate = Date()

            currentFileURL = fileURL
            currentFormat = monoFormat
            startedAt = startDate
            elapsedTime = 0
            inputLevel = 0
            frequencyBands = Array(repeating: 0.08, count: 40)
            smoothedFrequencyBands = Array(repeating: 0.08, count: 40)

            removeInputTapIfNeeded()
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: format,
                block: makeAudioRecorderTap(audioFile: audioFile, monoFormat: monoFormat, recorder: self)
            )
            didInstallInputTap = true

            engine.prepare()
            try engine.start()
            isRecording = true
            startElapsedTimer(from: startDate)
        } catch {
            resetCaptureState()
            errorMessage = String(
                format: textProvider(.couldNotStartRecording),
                error.localizedDescription
            )
        }
    }

    @discardableResult
    func stop() -> AudioRecording? {
        guard isRecording else { return nil }

        let endDate = Date()
        removeInputTapIfNeeded()
        engine.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false
        inputLevel = 0
        frequencyBands = Array(repeating: 0.08, count: 40)
        smoothedFrequencyBands = Array(repeating: 0.08, count: 40)

        guard let fileURL = currentFileURL else {
            resetCaptureState()
            return nil
        }

        let startDate = startedAt ?? endDate
        let format = currentFormat
        let fileSize = fileSize(at: fileURL)
        let recording = AudioRecording(
            fileURL: fileURL,
            createdAt: startDate,
            duration: max(0, endDate.timeIntervalSince(startDate)),
            sampleRate: format?.sampleRate ?? 0,
            channelCount: Int(format?.channelCount ?? 0),
            fileSizeBytes: fileSize,
            suggestedTitle: Self.suggestedTitle(for: startDate, textProvider: textProvider),
            source: .microphone
        )

        resetCaptureState(keepError: true)
        return recording
    }

    fileprivate func stopAfterWriteFailure(message: String) {
        errorMessage = String(format: textProvider(.recordingStopped), message)
        _ = stop()
    }

    fileprivate func updateInputLevel(_ level: Float) {
        inputLevel = level
    }

    fileprivate func updateSpectrumBands(_ bands: [Float]) {
        guard smoothedFrequencyBands.count == bands.count else {
            smoothedFrequencyBands = bands
            frequencyBands = bands
            return
        }

        smoothedFrequencyBands = zip(smoothedFrequencyBands, bands).map { previous, next in
            let factor: Float = next > previous ? 0.72 : 0.38
            return previous * (1 - factor) + next * factor
        }
        frequencyBands = smoothedFrequencyBands
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionState = .granted
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            permissionState = granted ? .granted : .denied
            return granted
        case .denied, .restricted:
            permissionState = .denied
            return false
        @unknown default:
            permissionState = .denied
            return false
        }
    }

    private func startElapsedTimer(from startDate: Date) {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func startInputDeviceMonitor() {
        inputDeviceMonitorTimer?.invalidate()
        inputDeviceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInputDeviceStatus()
            }
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard
            let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    private func resetCaptureState(keepError: Bool = false) {
        removeInputTapIfNeeded()
        engine.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        currentFileURL = nil
        currentFormat = nil
        startedAt = nil
        elapsedTime = 0
        inputLevel = 0
        frequencyBands = Array(repeating: 0.08, count: 40)
        smoothedFrequencyBands = Array(repeating: 0.08, count: 40)
        isRecording = false

        if !keepError {
            errorMessage = nil
        }
    }

    private func removeInputTapIfNeeded() {
        guard didInstallInputTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        didInstallInputTap = false
    }

    private static func currentInputDeviceStatus(
        textProvider: (AppTextKey) -> String
    ) -> InputDeviceStatus {
        if let coreAudioDevice = currentCoreAudioInputDevice(),
           coreAudioDevice.hasInputStreams {
            return InputDeviceStatus(
                availability: .available,
                deviceName: AVCaptureDevice.default(for: .audio)?.localizedName ?? coreAudioDevice.fallbackName,
                message: nil
            )
        }

        if let captureDevice = AVCaptureDevice.default(for: .audio) {
            return InputDeviceStatus(
                availability: .available,
                deviceName: captureDevice.localizedName,
                message: nil
            )
        }

        return InputDeviceStatus(
            availability: .unavailable,
            deviceName: nil,
            message: textProvider(.audioInputNoDevice)
        )
    }

    private struct CoreAudioInputDevice {
        var id: AudioDeviceID
        var fallbackName: String
        var hasInputStreams: Bool
    }

    private static func currentCoreAudioInputDevice() -> CoreAudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr,
              deviceID != kAudioObjectUnknown
        else {
            return nil
        }

        return CoreAudioInputDevice(
            id: deviceID,
            fallbackName: "Microphone",
            hasInputStreams: coreAudioDeviceHasInputStreams(deviceID)
        )
    }

    private static func coreAudioDeviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        )

        guard status == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func defaultRecordingsDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("NativeBlaboom", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private static func makeRecordingURL(in directory: URL) -> URL {
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("recording-\(timestamp).caf")
    }

    private static func suggestedTitle(
        for date: Date,
        textProvider: (AppTextKey) -> String
    ) -> String {
        "\(textProvider(.voiceNote)) \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

}

private func makeAudioRecorderTap(
    audioFile: AVAudioFile,
    monoFormat: AVAudioFormat,
    recorder: AudioRecorder
) -> AVAudioNodeTapBlock {
    { [weak recorder, audioFile, monoFormat] buffer, _ in
        if let monoBuffer = downmixToMono(buffer: buffer, targetFormat: monoFormat) {
            do {
                try audioFile.write(from: monoBuffer)
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak recorder] in
                    recorder?.stopAfterWriteFailure(message: message)
                }
                return
            }
        }

        let level = inputLevel(for: buffer)
        let bands = frequencyBands(for: buffer)
        Task { @MainActor [weak recorder] in
            recorder?.updateInputLevel(level)
            recorder?.updateSpectrumBands(bands)
        }
    }
}

private func downmixToMono(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let floatChannelData = buffer.floatChannelData else { return nil }
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0 else { return nil }

    if channelCount == 1 {
        return buffer
    }

    guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
        return nil
    }
    monoBuffer.frameLength = AVAudioFrameCount(frameCount)

    guard let monoChannelData = monoBuffer.floatChannelData?[0] else { return nil }

    let scale = 1.0 / Float(max(1, channelCount))
    for frame in 0..<frameCount {
        var sum: Float = 0
        for channel in 0..<channelCount {
            sum += floatChannelData[channel][frame]
        }
        monoChannelData[frame] = sum * scale
    }

    return monoBuffer
}

private func inputLevel(for buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0 }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else { return 0 }

    var sum: Float = 0
    for channel in 0..<channelCount {
        let samples = channelData[channel]
        for frame in 0..<frameCount {
            sum += samples[frame] * samples[frame]
        }
    }

    return min(1, sqrt(sum / Float(frameCount * channelCount)))
}

private func frequencyBands(for buffer: AVAudioPCMBuffer, bandCount: Int = 40) -> [Float] {
    guard let channelData = buffer.floatChannelData else {
        return Array(repeating: 0.08, count: bandCount)
    }

    let sampleRate = Float(buffer.format.sampleRate)
    let frameCount = min(Int(buffer.frameLength), 768)
    guard sampleRate > 0, frameCount >= 64 else {
        return Array(repeating: 0.08, count: bandCount)
    }

    let channelCount = Int(buffer.format.channelCount)
    var monoSamples = Array(repeating: Float(0), count: frameCount)
    for index in 0..<frameCount {
        var averagedSample: Float = 0
        for channel in 0..<channelCount {
            averagedSample += channelData[channel][index]
        }
        monoSamples[index] = averagedSample / Float(max(1, channelCount))
    }

    // Remove the DC component before the transform. Built-in and USB
    // microphones often carry a tiny offset or low-frequency rumble which
    // otherwise keeps the left side of a relative spectrum permanently raised.
    let mean = monoSamples.reduce(0, +) / Float(frameCount)
    var squareSum: Float = 0
    var windowedSamples = Array(repeating: Float(0), count: frameCount)
    for index in 0..<frameCount {
        let centeredSample = monoSamples[index] - mean
        squareSum += centeredSample * centeredSample
        let phase = 2 * Float.pi * Float(index) / Float(max(1, frameCount - 1))
        let window = 0.5 - 0.5 * cos(phase)
        windowedSamples[index] = centeredSample * window
    }
    let rootMeanSquare = sqrt(squareSum / Float(frameCount))

    let binCount = min(frameCount / 2, 196)
    var magnitudes = Array(repeating: Float(0), count: binCount)
    for index in 0..<binCount {
        let omega = 2 * Float.pi * Float(index) / Float(frameCount)
        var real: Float = 0
        var imaginary: Float = 0

        for frame in 0..<frameCount {
            let sample = windowedSamples[frame]
            let phase = omega * Float(frame)
            real += sample * cos(phase)
            imaginary -= sample * sin(phase)
        }

        magnitudes[index] = sqrt(real * real + imaginary * imaginary) / Float(frameCount)
    }

    let nyquist = sampleRate / 2
    let minFrequency: Float = 60
    let maxFrequency = min(10_000, nyquist)
    let logMin = log10(minFrequency)
    let logMax = log10(maxFrequency)
    let binWidth = sampleRate / Float(frameCount)

    let rawBands: [Float] = (0..<bandCount).map { band in
        let startPosition = Float(band) / Float(bandCount)
        let endPosition = Float(band + 1) / Float(bandCount)
        let startFrequency = pow(10, logMin + (logMax - logMin) * startPosition)
        let endFrequency = pow(10, logMin + (logMax - logMin) * endPosition)
        let startBin = max(1, Int(startFrequency / binWidth))
        let endBin = min(binCount - 1, max(startBin + 1, Int(endFrequency / binWidth)))
        let slice = magnitudes[startBin..<endBin]
        return slice.reduce(0, +) / Float(max(1, slice.count))
    }

    let activityInput = min(1, max(0, (rootMeanSquare - 0.0035) / 0.035))
    let activitySmooth = activityInput * activityInput * (3 - 2 * activityInput)
    let activityGate = pow(activitySmooth, 0.70)

    return rawBands.enumerated().map { index, magnitude in
        let progress = Float(index) / Float(max(1, bandCount - 1))
        let highGain: Float = progress > 0.50 ? (1.0 + 1.35 * (progress - 0.50) / 0.50) : 1.0
        let absolute = min(1, log1p(magnitude * 150 * highGain) / log1p(18))
        
        let frequencyWeight: Float
        if progress < 0.25 {
            frequencyWeight = 0.85 + 0.15 * (progress / 0.25)
        } else if progress <= 0.55 {
            frequencyWeight = 1.0
        } else {
            let highProgress = (progress - 0.55) / 0.45
            frequencyWeight = 1.0 + 1.85 * highProgress
        }

        let emphasized = absolute * frequencyWeight * activityGate
        return max(0.02, min(1, emphasized))
    }
}
