import AVFoundation
import Foundation

/// Errors produced while creating the canonical local-ASR input file.
enum LocalASRAudioPreprocessorError: LocalizedError, Equatable, Sendable {
    case sourceUnavailable(URL)
    case sourceFormatInvalid
    case destinationIsSource
    case formatCreationFailed(String)
    case bufferAllocationFailed
    case converterUnavailable
    case sourceReadFailed(String)
    case conversionFailed(String)
    case outputInvalid(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let url):
            return "Could not open audio source \(url.lastPathComponent)."
        case .sourceFormatInvalid:
            return "The audio source has no usable sample rate or channels."
        case .destinationIsSource:
            return "The normalized audio destination must differ from the source."
        case .formatCreationFailed(let detail):
            return "Could not create an audio format: \(detail)"
        case .bufferAllocationFailed:
            return "Could not allocate an audio conversion buffer."
        case .converterUnavailable:
            return "The system audio converter is unavailable for this recording."
        case .sourceReadFailed(let detail):
            return "Could not read the audio source: \(detail)"
        case .conversionFailed(let detail):
            return "Audio conversion failed: \(detail)"
        case .outputInvalid(let detail):
            return "The normalized WAV is invalid: \(detail)"
        }
    }
}

/// Converts arbitrary readable audio into the 16 kHz mono PCM WAV required by
/// local ASR models. Multichannel sources are never downmixed: the physical
/// channel with the greatest measured energy is copied into the mono signal.
struct LocalASRAudioPreprocessor: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Writes and validates a normalized WAV at `destination`, returning that URL.
    /// Existing output at the destination is replaced. A failed or cancelled
    /// conversion removes any partial output so callers never observe a stale file.
    @discardableResult
    func convertTo16kMonoWAV(source: URL, destination: URL) throws -> URL {
        try Task.checkCancellation()

        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw LocalASRAudioPreprocessorError.destinationIsSource
        }

        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: source)
        } catch {
            throw LocalASRAudioPreprocessorError.sourceUnavailable(source)
        }

        let processingFormat = inputFile.processingFormat
        let sampleRate = processingFormat.sampleRate
        let channelCount = Int(processingFormat.channelCount)
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0 else {
            throw LocalASRAudioPreprocessorError.sourceFormatInvalid
        }

        guard let floatSourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw LocalASRAudioPreprocessorError.formatCreationFailed("mono analysis format")
        }

        let sourceChannel = try loudestSourceChannel(in: source, format: floatSourceFormat)

        guard let monoSourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw LocalASRAudioPreprocessorError.formatCreationFailed("mono source format")
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw LocalASRAudioPreprocessorError.formatCreationFailed("16 kHz output format")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        try prepareDestination(destination)

        do {
            try Task.checkCancellation()
            guard let converter = AVAudioConverter(from: monoSourceFormat, to: outputFormat) else {
                throw LocalASRAudioPreprocessorError.converterUnavailable
            }

            do {
                let outputFile = try AVAudioFile(
                    forWriting: destination,
                    settings: settings,
                    commonFormat: .pcmFormatInt16,
                    interleaved: true
                )
                try convertFileLoop(
                    inputFile: inputFile,
                    outputFile: outputFile,
                    converter: converter,
                    sourceFormat: floatSourceFormat,
                    monoSourceFormat: monoSourceFormat,
                    outputFormat: outputFormat,
                    sourceChannel: sourceChannel
                )
            }

            try Task.checkCancellation()
            try validateOutput(at: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            if error is CancellationError {
                throw error
            }
            if let error = error as? LocalASRAudioPreprocessorError {
                throw error
            }
            throw LocalASRAudioPreprocessorError.conversionFailed(error.localizedDescription)
        }
    }

    private func prepareDestination(_ destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        } catch {
            throw LocalASRAudioPreprocessorError.conversionFailed(error.localizedDescription)
        }
    }

    /// Scans at most eight seconds and returns the first channel with the highest
    /// sum-of-squares energy. Strict comparison makes ties deterministic.
    private func loudestSourceChannel(in source: URL, format: AVAudioFormat) throws -> Int {
        let channelCount = Int(format.channelCount)
        guard channelCount > 1 else { return 0 }

        let scanner: AVAudioFile
        do {
            scanner = try AVAudioFile(forReading: source)
        } catch {
            throw LocalASRAudioPreprocessorError.sourceUnavailable(source)
        }

        let scanLimit = AVAudioFramePosition((format.sampleRate * 8).rounded(.down))
        let totalFrames = min(scanner.length, scanLimit)
        guard totalFrames > 0 else { return 0 }

        let chunk: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw LocalASRAudioPreprocessorError.bufferAllocationFailed
        }
        guard let channelData = buffer.floatChannelData else {
            throw LocalASRAudioPreprocessorError.formatCreationFailed("non-interleaved scan buffer")
        }

        var energy = [Double](repeating: 0, count: channelCount)
        var scanned: AVAudioFramePosition = 0
        while scanned < totalFrames {
            try Task.checkCancellation()
            let remaining = totalFrames - scanned
            let toRead = AVAudioFrameCount(
                min(AVAudioFramePosition(chunk), remaining)
            )
            do {
                try scanner.read(into: buffer, frameCount: toRead)
            } catch {
                throw LocalASRAudioPreprocessorError.sourceReadFailed(error.localizedDescription)
            }

            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                var sum = energy[channel]
                for frame in 0..<frames {
                    let value = Double(samples[frame])
                    sum += value * value
                }
                energy[channel] = sum
            }
            scanned += AVAudioFramePosition(frames)
        }

        var loudest = 0
        for channel in 1..<channelCount where energy[channel] > energy[loudest] {
            loudest = channel
        }
        return loudest
    }

    private func convertFileLoop(
        inputFile: AVAudioFile,
        outputFile: AVAudioFile,
        converter: AVAudioConverter,
        sourceFormat: AVAudioFormat,
        monoSourceFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        sourceChannel: Int
    ) throws {
        let capacity: AVAudioFrameCount = 8_192
        let channelCount = Int(sourceFormat.channelCount)

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoSourceFormat,
            frameCapacity: capacity
        ) else {
            throw LocalASRAudioPreprocessorError.bufferAllocationFailed
        }

        var multichannelBuffer: AVAudioPCMBuffer?
        if channelCount > 1 {
            guard let multi = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: capacity
            ) else {
                throw LocalASRAudioPreprocessorError.bufferAllocationFailed
            }
            multichannelBuffer = multi
        } else {
            multichannelBuffer = nil
        }

        let ratio = outputFormat.sampleRate / max(monoSourceFormat.sampleRate, 1)
        let outputCapacity = AVAudioFrameCount(Double(capacity) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw LocalASRAudioPreprocessorError.bufferAllocationFailed
        }

        final class ConversionState: @unchecked Sendable {
            var isAtEnd = false
            var wasCancelled = false
            var readError: Error?
        }

        let state = ConversionState()
        nonisolated(unsafe) let monoForCallback = monoBuffer
        nonisolated(unsafe) let multiForCallback = multichannelBuffer
        let selectedChannel = min(max(sourceChannel, 0), max(channelCount - 1, 0))

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.isAtEnd {
                outStatus.pointee = .noDataNow
                return nil
            }
            if Task.isCancelled {
                state.wasCancelled = true
                state.isAtEnd = true
                outStatus.pointee = .endOfStream
                return nil
            }

            let remaining = AVAudioFrameCount(
                max(0, inputFile.length - inputFile.framePosition)
            )
            if remaining == 0 {
                state.isAtEnd = true
                outStatus.pointee = .endOfStream
                return nil
            }

            let toRead = min(capacity, remaining)
            do {
                if let multi = multiForCallback,
                   let multiData = multi.floatChannelData,
                   let monoData = monoForCallback.floatChannelData {
                    try inputFile.read(into: multi, frameCount: toRead)
                    let frames = multi.frameLength
                    if frames == 0 {
                        state.isAtEnd = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    let source = multiData[selectedChannel]
                    let target = monoData[0]
                    for frame in 0..<Int(frames) {
                        target[frame] = source[frame]
                    }
                    monoForCallback.frameLength = frames
                } else {
                    try inputFile.read(into: monoForCallback, frameCount: toRead)
                    if monoForCallback.frameLength == 0 {
                        state.isAtEnd = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }
                outStatus.pointee = .haveData
                return monoForCallback
            } catch {
                state.readError = error
                state.isAtEnd = true
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        while !state.isAtEnd {
            try Task.checkCancellation()
            outputBuffer.frameLength = 0
            var converterError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &converterError,
                withInputFrom: inputBlock
            )
            if let converterError {
                throw LocalASRAudioPreprocessorError.conversionFailed(
                    converterError.localizedDescription
                )
            }
            if status == .error {
                throw LocalASRAudioPreprocessorError.conversionFailed("system converter error")
            }
            if outputBuffer.frameLength > 0 {
                do {
                    try outputFile.write(from: outputBuffer)
                } catch {
                    throw LocalASRAudioPreprocessorError.conversionFailed(
                        error.localizedDescription
                    )
                }
            }
            if status == .endOfStream {
                break
            }
        }

        if state.wasCancelled || Task.isCancelled {
            throw CancellationError()
        }
        if let readError = state.readError {
            throw LocalASRAudioPreprocessorError.sourceReadFailed(
                readError.localizedDescription
            )
        }
    }

    private func validateOutput(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size >= 44
        else {
            throw LocalASRAudioPreprocessorError.outputInvalid("missing WAV data")
        }

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forReading: url)
        } catch {
            throw LocalASRAudioPreprocessorError.outputInvalid(error.localizedDescription)
        }

        let format = outputFile.fileFormat
        guard outputFile.length > 0,
              abs(format.sampleRate - 16_000) < 0.5,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16,
              format.isInterleaved
        else {
            throw LocalASRAudioPreprocessorError.outputInvalid(
                "expected 16 kHz mono interleaved 16-bit PCM"
            )
        }
    }
}
