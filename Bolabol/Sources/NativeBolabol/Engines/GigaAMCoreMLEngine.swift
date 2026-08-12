import Accelerate
import AVFoundation
import CoreML
import Foundation
import NativeBolabolCore

// MARK: - GigaAMCoreMLEngine

/// Core ML engine for GigaAM v3 RNNT Russian ASR.
///
/// Spike constraints (authoritative):
/// - RU only; HTK log-mel frontend; 16 kHz mono
/// - VAD/chunks ≤ 30 s; reset RNNT state per chunk
/// - Decode only true valid encoder frames; blank id 1024
/// - No claims about WER/confidence/EN/multilingual/auto-detect
actor GigaAMCoreMLEngine: TranscriptionEngine {
    nonisolated let id: String
    nonisolated let displayName: String

    private let model: TranscriptionModelDescriptor
    private let modelFolderURL: URL
    private var state: GigaAMState?

    init(model: TranscriptionModelDescriptor, modelFolderURL: URL) {
        self.model = model
        self.modelFolderURL = modelFolderURL
        self.id = "gigaam-\(model.id)"
        self.displayName = "GigaAM Core ML/ANE (\(model.displayName))"
    }

    // MARK: - TranscriptionEngine

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let audioFileURL = request.audioFileURL else {
            throw GigaAMTranscriptionError.missingAudioFile
        }

        _ = try resolveLanguage(request)

        try await ensureLoaded()

        let samples = try await loadAudioSamples(from: audioFileURL)
        guard !samples.isEmpty else {
            throw GigaAMTranscriptionError.emptyAudio
        }

        let maxChunkSamples = Int(model.capabilities.maxChunkSeconds * 16_000.0)
        let chunks = Self.chunk(samples: samples, maxSamples: maxChunkSamples)

        var allTokens: [Int] = []
        let startedAt = Date()

        for chunkSamples in chunks {
            let tokens = try await decodeChunk(chunkSamples)
            allTokens.append(contentsOf: tokens)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let text = state?.decode(tokens: allTokens) ?? ""
        guard !text.isEmpty else {
            throw GigaAMTranscriptionError.emptyResult
        }

        return TranscriptionResult(
            text: text,
            diagnostics: EngineDiagnostics(
                backendName: displayName,
                tokensPerSecond: Double(allTokens.count) / max(elapsed, 0.001)
            )
        )
    }

    // MARK: - Model Loading

    private func ensureLoaded() async throws {
        if state == nil {
            state = try await GigaAMState.load(from: modelFolderURL)
        }
    }

    // MARK: - Audio Loading

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("bolabol-gigaam-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWAV) }

        do {
            try GeminiCloudDictationEngine.convertTo16kMonoWAV(
                source: url,
                destination: tempWAV
            )
        } catch {
            throw GigaAMTranscriptionError.audioPreparationFailed(error.localizedDescription)
        }

        return try readFloat32WAV(at: tempWAV)
    }

    private func readFloat32WAV(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count > 44,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            throw GigaAMTranscriptionError.invalidWAV
        }

        var fmtOffset = -1
        var dataOffset = -1
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize = Int(bytes[offset + 4])
                | (Int(bytes[offset + 5]) << 8)
                | (Int(bytes[offset + 6]) << 16)
                | (Int(bytes[offset + 7]) << 24)
            if chunkID == "fmt " { fmtOffset = offset }
            if chunkID == "data" { dataOffset = offset + 8 }
            offset += 8 + chunkSize + (chunkSize % 2)
        }

        guard fmtOffset >= 0, dataOffset >= 0, fmtOffset + 24 <= bytes.count else {
            throw GigaAMTranscriptionError.invalidWAV
        }

        let channels = Int(bytes[fmtOffset + 10]) | (Int(bytes[fmtOffset + 11]) << 8)
        let sampleRate = Int(bytes[fmtOffset + 12])
            | (Int(bytes[fmtOffset + 13]) << 8)
            | (Int(bytes[fmtOffset + 14]) << 16)
            | (Int(bytes[fmtOffset + 15]) << 24)
        let bits = Int(bytes[fmtOffset + 22]) | (Int(bytes[fmtOffset + 23]) << 8)
        let audioFormat = Int(bytes[fmtOffset + 8]) | (Int(bytes[fmtOffset + 9]) << 8)

        guard channels > 0, sampleRate == 16_000 else {
            throw GigaAMTranscriptionError.invalidWAV
        }
        guard audioFormat == 1 && bits == 16 else {
            throw GigaAMTranscriptionError.invalidWAV
        }

        let raw = Array(bytes[dataOffset...])
        let frameBytes = channels * bits / 8
        let frames = raw.count / frameBytes
        var samples = [Float](repeating: 0, count: frames)

        for f in 0..<frames {
            var acc: Int32 = 0
            for c in 0..<channels {
                let i = f * frameBytes + c * 2
                let s = Int16(bitPattern: UInt16(raw[i]) | (UInt16(raw[i + 1]) << 8))
                acc += Int32(s)
            }
            samples[f] = Float(acc) / Float(channels) / 32768.0
        }

        return samples
    }

    // MARK: - Language Resolution

    // Keep language validation isolated so explicit-source requirements remain testable.
    internal func resolveLanguage(_ request: TranscriptionRequest) throws -> String {
        let supported = model.capabilities.supportedLanguageCodes
        guard !supported.isEmpty else {
            throw GigaAMTranscriptionError.unsupportedLanguage("none configured")
        }
        guard let language = request.forcedLanguageCode else {
            throw GigaAMTranscriptionError.unsupportedLanguage("nil (explicit language required)")
        }
        guard supported.contains(language) else {
            throw GigaAMTranscriptionError.unsupportedLanguage(language)
        }
        // ADR-022 keeps GigaAM transcription-only; translation is a separate
        // post-transcription text operation.
        guard !request.translateToEnglish else {
            throw GigaAMTranscriptionError.translationUnsupported
        }
        return language
    }

    // MARK: - Chunking

    // Keep chunking as a pure seam so audio-window boundaries remain testable.
    nonisolated internal static func chunk(samples: [Float], maxSamples: Int) -> [[Float]] {
        guard samples.count > maxSamples else { return [samples] }
        var chunks: [[Float]] = []
        var start = 0
        while start < samples.count {
            let end = min(start + maxSamples, samples.count)
            chunks.append(Array(samples[start..<end]))
            start = end
        }
        return chunks
    }

    // MARK: - RNNT Decode

    private func decodeChunk(_ samples: [Float]) async throws -> [Int] {
        guard let state = state else {
            throw GigaAMTranscriptionError.modelNotLoaded
        }

        // HTK log-mel frontend
        let extracted = try state.frontend.extract(samples)
        guard extracted.validFrames > 0 else {
            throw GigaAMTranscriptionError.emptyAudio
        }

        // Encoder
        guard let encoded = try state.runEncoder(features: extracted.features) else {
            throw GigaAMTranscriptionError.encoderFailed
        }

        // RNNT decode (fresh state per chunk)
        let validEncoderFrames = max(1, (extracted.validFrames + 3) / 4)
        let tokens = try state.decodeRNNT(
            encoded: encoded,
            validFrames: validEncoderFrames,
            maxSymbols: 10,
            maxTokens: 512
        )

        return tokens
    }
}

// MARK: - GigaAM State

private final class GigaAMState {
    let encoder: MLModel
    let predictor: MLModel
    let joint: MLModel
    let vocab: [Int: String]
    let frontend: GigaAMMelFrontend
    let blankID = 1024

    init(
        encoder: MLModel,
        predictor: MLModel,
        joint: MLModel,
        vocab: [Int: String],
        frontend: GigaAMMelFrontend
    ) {
        self.encoder = encoder
        self.predictor = predictor
        self.joint = joint
        self.vocab = vocab
        self.frontend = frontend
    }

    static func load(from root: URL) async throws -> GigaAMState {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        func load(_ name: String) throws -> MLModel {
            let url = root.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw GigaAMTranscriptionError.missingModelFile(name + ".mlmodelc")
            }
            return try MLModel(contentsOf: url, configuration: config)
        }

        let encoder = try load("Encoder")
        let predictor = try load("Predictor")
        let joint = try load("JointDecision")

        // vocab.txt
        let vocabURL = root.appendingPathComponent("vocab.txt")
        guard FileManager.default.fileExists(atPath: vocabURL.path) else {
            throw GigaAMTranscriptionError.missingModelFile("vocab.txt")
        }
        let vocabData = try Data(contentsOf: vocabURL)
        guard let vocabText = String(data: vocabData, encoding: .utf8) else {
            throw GigaAMTranscriptionError.invalidModelConfig
        }

        var vocab: [Int: String] = [:]
        for line in vocabText.components(separatedBy: .newlines) where !line.isEmpty {
            guard let separator = line.lastIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let piece = String(line[..<separator])
            if let id = Int(line[line.index(after: separator)...]) {
                vocab[id] = piece
            }
        }

        let frontend = try GigaAMMelFrontend()

        return GigaAMState(
            encoder: encoder,
            predictor: predictor,
            joint: joint,
            vocab: vocab,
            frontend: frontend
        )
    }

    func runEncoder(features: MLMultiArray) throws -> MLMultiArray? {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": MLFeatureValue(multiArray: features),
        ])
        let out = try encoder.prediction(from: provider)
        return out.featureValue(for: "encoded")?.multiArrayValue
    }

    func decodeRNNT(
        encoded: MLMultiArray,
        validFrames: Int,
        maxSymbols: Int,
        maxTokens: Int
    ) throws -> [Int] {
        let encoderDimension = encoded.shape[1].intValue
        let totalEncoderFrames = encoded.shape[2].intValue
        let validEncoderFrames = min(totalEncoderFrames, max(1, validFrames))

        var tokens: [Int] = []
        var lastToken = blankID
        var hidden = try makeFloatArray(shape: [1, 1, 320], values: Array(repeating: 0, count: 320))
        var cell = try makeFloatArray(shape: [1, 1, 320], values: Array(repeating: 0, count: 320))
        var hasState = false

        for time in 0..<validEncoderFrames {
            var emittedAtFrame = 0
            while emittedAtFrame < maxSymbols && tokens.count < maxTokens {
                let predictorInput = try makeIntArray(shape: [1, 1], values: [hasState ? lastToken : blankID])
                let predictorOutput = try runPredictor(
                    token: predictorInput,
                    hidden: hidden,
                    cell: cell
                )
                guard let decoder = predictorOutput["dec"]?.multiArrayValue,
                      let nextHidden = predictorOutput["ho"]?.multiArrayValue,
                      let nextCell = predictorOutput["co"]?.multiArrayValue else {
                    break
                }

                let encoderSlice = try encoderFrame(encoded, dimension: encoderDimension, time: time)
                let decoderSlice = try predictorOutputForJoint(decoder, hiddenSize: 320)
                let jointOutput = try runJoint(enc: encoderSlice, dec: decoderSlice)
                guard let tokenArray = jointOutput["token_id"]?.multiArrayValue else { break }
                let token = tokenArray[0].intValue

                if token == blankID { break }

                tokens.append(token)
                lastToken = token
                hidden = try predictorState(nextHidden, hiddenSize: 320)
                cell = try predictorState(nextCell, hiddenSize: 320)
                hasState = true
                emittedAtFrame += 1
            }
        }

        return tokens
    }

    private func runPredictor(token: MLMultiArray, hidden: MLMultiArray, cell: MLMultiArray) throws -> [String: MLFeatureValue] {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "x": MLFeatureValue(multiArray: token),
            "hi": MLFeatureValue(multiArray: hidden),
            "ci": MLFeatureValue(multiArray: cell),
        ])
        let out = try predictor.prediction(from: provider)
        var result: [String: MLFeatureValue] = [:]
        for name in out.featureNames { result[name] = out.featureValue(for: name) }
        return result
    }

    private func runJoint(enc: MLMultiArray, dec: MLMultiArray) throws -> [String: MLFeatureValue] {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "enc": MLFeatureValue(multiArray: enc),
            "dec": MLFeatureValue(multiArray: dec),
        ])
        let out = try joint.prediction(from: provider)
        var result: [String: MLFeatureValue] = [:]
        for name in out.featureNames { result[name] = out.featureValue(for: name) }
        return result
    }

    func decode(tokens: [Int]) -> String {
        let pieces = tokens.compactMap { vocab[$0] }.filter { !$0.hasPrefix("<") }
        return pieces.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - GigaAM Mel Frontend (HTK contract)

private final class GigaAMMelFrontend {
    let sampleRate = 16_000
    let nFFT = 320
    let hopLength = 160
    let melBins = 64
    let windowFrames = 3_000
    let windowSamples = 480_000

    private let dftSetup: vDSP_DFT_Setup
    private let hannWindow: [Float]
    private let filterbank: [Float]

    init() throws {
        guard let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(320), vDSP_DFT_Direction(rawValue: 1)!) else {
            throw GigaAMTranscriptionError.frontendFailed("FFT setup failed")
        }
        dftSetup = setup

        hannWindow = (0..<320).map { index in
            0.5 * (1.0 - cos(2.0 * Float.pi * Float(index) / Float(320)))
        }
        filterbank = GigaAMMelFrontend.makeHTKFilterbank(
            melBins: 64,
            frequencyBins: 161,
            sampleRate: 16_000,
            fftSize: 320
        )
    }

    deinit {
        vDSP_DFT_DestroySetup(dftSetup)
    }

    func extract(_ samples: [Float]) throws -> (features: MLMultiArray, validFrames: Int, processedSamples: Int) {
        guard !samples.isEmpty else { throw GigaAMTranscriptionError.emptyAudio }

        let processedSamples = min(samples.count, windowSamples)
        guard processedSamples >= nFFT else {
            throw GigaAMTranscriptionError.emptyAudio
        }

        let featureSamples = (windowFrames - 1) * hopLength + nFFT
        var padded = [Float](repeating: 0, count: featureSamples)
        padded.replaceSubrange(0..<processedSamples, with: samples[0..<processedSamples])

        let validFrames = min(windowFrames, ((processedSamples - nFFT) / hopLength) + 1)
        let features = try MLMultiArray(
            shape: [1, NSNumber(value: melBins), NSNumber(value: windowFrames)],
            dataType: .float32
        )
        let output = features.dataPointer.bindMemory(to: Float.self, capacity: melBins * windowFrames)
        let paddedMelValue = log(1e-9 as Float)
        for index in 0..<(melBins * windowFrames) {
            output[index] = paddedMelValue
        }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var outputReal = [Float](repeating: 0, count: nFFT / 2)
        var outputImaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nFFT / 2 + 1)
        var mel = [Float](repeating: 0, count: melBins)

        // The encoder input is fixed at 3000 columns, but only valid frames
        // need frontend work. The remaining columns retain the log-floor value
        // produced by the contract's zero-padded audio.
        for time in 0..<validFrames {
            let start = time * hopLength
            for index in 0..<nFFT {
                frame[index] = padded[start + index] * hannWindow[index]
            }

            for pair in 0..<(nFFT / 2) {
                real[pair] = frame[pair * 2]
                imaginary[pair] = frame[pair * 2 + 1]
            }
            real.withUnsafeBufferPointer { realBuffer in
                imaginary.withUnsafeBufferPointer { imagBuffer in
                    outputReal.withUnsafeMutableBufferPointer { outReal in
                        outputImaginary.withUnsafeMutableBufferPointer { outImag in
                            vDSP_DFT_Execute(
                                dftSetup,
                                realBuffer.baseAddress!,
                                imagBuffer.baseAddress!,
                                outReal.baseAddress!,
                                outImag.baseAddress!
                            )
                        }
                    }
                }
            }

            let dc = outputReal[0] * 0.5
            let nyquist = outputImaginary[0] * 0.5
            power[0] = dc * dc
            for bin in 1..<(nFFT / 2) {
                let re = outputReal[bin] * 0.5
                let im = outputImaginary[bin] * 0.5
                power[bin] = re * re + im * im
            }
            power[nFFT / 2] = nyquist * nyquist

            for melBin in 0..<melBins {
                let bankStart = melBin * (nFFT / 2 + 1)
                var total: Float = 0
                for bin in 0...(nFFT / 2) {
                    total += power[bin] * filterbank[bankStart + bin]
                }
                mel[melBin] = log(min(max(total, 1e-9), 1e9))
                output[melBin * windowFrames + time] = mel[melBin]
            }
        }

        return (features, validFrames, processedSamples)
    }

    private static func makeHTKFilterbank(
        melBins: Int,
        frequencyBins: Int,
        sampleRate: Int,
        fftSize: Int
    ) -> [Float] {
        func hzToMel(_ hz: Double) -> Double {
            2595.0 * log10(1.0 + hz / 700.0)
        }
        func melToHz(_ mel: Double) -> Double {
            700.0 * (pow(10.0, mel / 2595.0) - 1.0)
        }

        let lowerMel = hzToMel(0)
        let upperMel = hzToMel(Double(sampleRate) / 2.0)
        let points = (0..<(melBins + 2)).map { index in
            melToHz(lowerMel + (upperMel - lowerMel) * Double(index) / Double(melBins + 1))
        }
        let frequencies = (0..<frequencyBins).map {
            Double($0) * Double(sampleRate) / Double(fftSize)
        }

        var bank = [Float](repeating: 0, count: melBins * frequencyBins)
        for melBin in 0..<melBins {
            let left = points[melBin]
            let center = points[melBin + 1]
            let right = points[melBin + 2]
            for bin in 0..<frequencyBins {
                let frequency = frequencies[bin]
                let rising = center > left ? (frequency - left) / (center - left) : 0
                let falling = right > center ? (right - frequency) / (right - center) : 0
                bank[melBin * frequencyBins + bin] = Float(max(0, min(rising, falling)))
            }
        }
        return bank
    }
}

// MARK: - MLMultiArray Helpers

private func makeFloatArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
    let expected = shape.reduce(1, *)
    guard values.count == expected else {
        throw GigaAMTranscriptionError.arrayShapeMismatch
    }
    let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
    let destination = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
    for index in values.indices { destination[index] = values[index] }
    return array
}

private func makeIntArray(shape: [Int], values: [Int]) throws -> MLMultiArray {
    let expected = shape.reduce(1, *)
    guard values.count == expected else {
        throw GigaAMTranscriptionError.arrayShapeMismatch
    }
    let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
    let destination = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
    for index in values.indices { destination[index] = Int32(values[index]) }
    return array
}

// Encoder outputs may use Float16, Float32, or Double; keep scalar conversion
// in one seam so decoding does not assume a single storage type.
internal func floatValue(from array: MLMultiArray, at offset: Int) -> Float {
    switch array.dataType {
    case .float16:
        return Float(array.dataPointer.assumingMemoryBound(to: Float16.self)[offset])
    case .float32:
        return array.dataPointer.assumingMemoryBound(to: Float.self)[offset]
    case .double:
        return Float(array.dataPointer.assumingMemoryBound(to: Double.self)[offset])
    default:
        return Float(array[offset].floatValue)
    }
}

// Keep stride conversion in a small seam so tensor layout remains testable.
internal func elementOffset(_ array: MLMultiArray, indices: [Int]) -> Int {
    zip(indices, array.strides).reduce(0) { $0 + $1.0 * $1.1.intValue }
}

private func encoderFrame(_ encoded: MLMultiArray, dimension: Int, time: Int) throws -> MLMultiArray {
    let destination = try MLMultiArray(shape: [1, NSNumber(value: dimension), NSNumber(value: 1)], dataType: .float32)
    let pointer = destination.dataPointer.bindMemory(to: Float.self, capacity: dimension)
    for d in 0..<dimension {
        let offset = elementOffset(encoded, indices: [0, d, time])
        pointer[d] = floatValue(from: encoded, at: offset)
    }
    return destination
}

private func predictorOutputForJoint(_ decoder: MLMultiArray, hiddenSize: Int) throws -> MLMultiArray {
    let destination = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize), NSNumber(value: 1)], dataType: .float32)
    let destPtr = destination.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize)
    for h in 0..<hiddenSize {
        // decoder shape is [1, 1, hiddenSize] — indices [0, h, 0] in the spike
        // use [0, 0, h] but the spike harness uses [indices[0], indices[2], indices[1]]
        // which maps [batch, hidden, seq] -> [batch, seq, hidden]
        let offset = elementOffset(decoder, indices: [0, 0, h])
        destPtr[h] = floatValue(from: decoder, at: offset)
    }
    return destination
}

private func predictorState(_ state: MLMultiArray, hiddenSize: Int) throws -> MLMultiArray {
    let destination = try MLMultiArray(shape: [1, NSNumber(value: 1), NSNumber(value: hiddenSize)], dataType: .float32)
    let destPtr = destination.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize)
    for h in 0..<hiddenSize {
        let offset = elementOffset(state, indices: [0, 0, h])
        destPtr[h] = floatValue(from: state, at: offset)
    }
    return destination
}

// MARK: - Errors

// Keep engine errors stable for the transcription failure contract.
internal enum GigaAMTranscriptionError: LocalizedError, Equatable {
    case missingAudioFile
    case emptyAudio
    case invalidWAV
    case audioPreparationFailed(String)
    case emptyResult
    case modelNotLoaded
    case missingModelFile(String)
    case invalidModelConfig
    case unsupportedLanguage(String)
    case translationUnsupported
    case encoderFailed
    case frontendFailed(String)
    case arrayShapeMismatch

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "GigaAM needs a recorded or imported audio file."
        case .emptyAudio:
            "The audio file contains no usable samples."
        case .invalidWAV:
            "The audio file is not a valid 16 kHz mono WAV."
        case .audioPreparationFailed(let detail):
            "Could not prepare audio for GigaAM: \(detail)"
        case .emptyResult:
            "GigaAM returned an empty transcription."
        case .modelNotLoaded:
            "The GigaAM model is not loaded. Please try again."
        case .missingModelFile(let name):
            "GigaAM model file missing: \(name). Download the model in Settings → Local Models."
        case .invalidModelConfig:
            "The GigaAM model configuration is invalid. Re-download the model."
        case .unsupportedLanguage(let code):
            "GigaAM supports Russian only. '\(code)' is not supported."
        case .translationUnsupported:
            "GigaAM transcribes Russian speech only and cannot translate to English."
        case .encoderFailed:
            "GigaAM encoder failed. Check that the model is complete."
        case .frontendFailed(let detail):
            "GigaAM audio frontend failed: \(detail)"
        case .arrayShapeMismatch:
            "Internal error: MLMultiArray shape mismatch."
        }
    }
}
