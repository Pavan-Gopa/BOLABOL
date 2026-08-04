// GigaAM v3 Core ML spike harness (Bolabol S6, pure Swift).
//
// Artifact under test: huggingfinger0/gigaam-v3-coreml, revision
// db44a79c2244cb9eb8178e383bd1ee92ec7fea25.
//
// The bundle is a native three-part RNN-T graph:
//   Encoder       audio_signal fp32 [1,64,3000] -> encoded fp16 [1,768,750]
//   Predictor     x int32 [1,1], hi/ci fp32 [1,1,320] -> dec/ho/co
//   JointDecision enc fp32 [1,768,1], dec fp32 [1,320,1] -> token_id int32
//
// The feature extractor follows the upstream v3_e2e_rnnt contract: 16 kHz
// mono, 64 HTK mel bins, n_fft=win_length=320, hop=160, center=false,
// no mel normalization, log(clamp(mel, 1e-9, 1e9)). The fixed Core ML input
// is filled from a roughly 30 s zero-padded window. Since this export has no
// length input, the harness computes the true valid mel/encoder lengths and
// never decodes the padded encoder tail.
//
// This file is a spike harness only. It is not a Bolabol product target and
// has no external runtime or process invocation path.

import Accelerate
import CoreML
import Darwin
import Foundation

// MARK: - Errors and configuration

struct SpikeError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct Config {
    var audioPath: String
    var modelRoot = "."
    var compute = "ane"
    var maxSymbols = 10
    var maxTokens = 512
}

func parseArgs(_ args: [String]) -> Config {
    var config = Config(audioPath: args.count > 1 ? args[1] : "")
    for argument in args.dropFirst(2) {
        let parts = argument.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        switch parts[0] {
        case "modelRoot": config.modelRoot = String(parts[1])
        case "compute": config.compute = String(parts[1])
        case "maxSymbols": config.maxSymbols = Int(parts[1]) ?? 10
        case "maxTokens": config.maxTokens = Int(parts[1]) ?? 512
        default: break
        }
    }
    return config
}

// MARK: - WAV input

func readWav(path: String) throws -> (samples: [Float], sampleRate: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bytes = [UInt8](data)
    guard bytes.count > 44,
          String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
        throw SpikeError(message: "not a RIFF/WAVE file: \(path)")
    }

    var fmtOffset = -1
    var dataOffset = -1
    var offset = 12
    while offset + 8 <= bytes.count {
        let chunkID = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
        let chunkSize = Int(bytes[offset + 4]) |
            (Int(bytes[offset + 5]) << 8) |
            (Int(bytes[offset + 6]) << 16) |
            (Int(bytes[offset + 7]) << 24)
        if chunkID == "fmt " { fmtOffset = offset }
        if chunkID == "data" { dataOffset = offset + 8 }
        offset += 8 + chunkSize + (chunkSize % 2)
    }

    guard fmtOffset >= 0, dataOffset >= 0, fmtOffset + 24 <= bytes.count else {
        throw SpikeError(message: "WAV is missing fmt/data chunks")
    }

    let audioFormat = Int(bytes[fmtOffset + 8]) | (Int(bytes[fmtOffset + 9]) << 8)
    let channels = Int(bytes[fmtOffset + 10]) | (Int(bytes[fmtOffset + 11]) << 8)
    let sampleRate = Int(bytes[fmtOffset + 12]) |
        (Int(bytes[fmtOffset + 13]) << 8) |
        (Int(bytes[fmtOffset + 14]) << 16) |
        (Int(bytes[fmtOffset + 15]) << 24)
    let bitsPerSample = Int(bytes[fmtOffset + 22]) | (Int(bytes[fmtOffset + 23]) << 8)
    guard channels > 0 else { throw SpikeError(message: "WAV has no channels") }
    guard audioFormat == 1 || audioFormat == 3 else {
        throw SpikeError(message: "unsupported WAV format \(audioFormat); need PCM or Float32")
    }

    let raw = Array(bytes[dataOffset...])
    let bytesPerFrame = channels * bitsPerSample / 8
    guard bytesPerFrame > 0 else { throw SpikeError(message: "invalid WAV frame size") }
    let frames = raw.count / bytesPerFrame
    var samples = [Float](repeating: 0, count: frames)

    if audioFormat == 1 && bitsPerSample == 16 {
        for frame in 0..<frames {
            var sum: Int32 = 0
            for channel in 0..<channels {
                let index = frame * bytesPerFrame + channel * 2
                let sample = Int16(bitPattern: UInt16(raw[index]) | (UInt16(raw[index + 1]) << 8))
                sum += Int32(sample)
            }
            samples[frame] = Float(sum) / Float(channels) / 32768.0
        }
    } else if audioFormat == 3 && bitsPerSample == 32 {
        raw.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += floatBuffer[frame * channels + channel]
                }
                samples[frame] = sum / Float(channels)
            }
        }
    } else {
        throw SpikeError(message: "unsupported WAV sample width \(bitsPerSample)")
    }

    return (samples, sampleRate)
}

// MARK: - Core ML helpers

func makeShape(_ values: [Int]) -> [NSNumber] {
    values.map { NSNumber(value: $0) }
}

func makeFloatArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
    let expected = shape.reduce(1, *)
    guard values.count == expected else {
        throw SpikeError(message: "float array has \(values.count) values, expected \(expected)")
    }
    let array = try MLMultiArray(shape: makeShape(shape), dataType: .float32)
    let destination = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
    for index in values.indices { destination[index] = values[index] }
    return array
}

func makeIntArray(shape: [Int], values: [Int]) throws -> MLMultiArray {
    let expected = shape.reduce(1, *)
    guard values.count == expected else {
        throw SpikeError(message: "integer array has \(values.count) values, expected \(expected)")
    }
    let array = try MLMultiArray(shape: makeShape(shape), dataType: .int32)
    let destination = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
    for index in values.indices { destination[index] = Int32(values[index]) }
    return array
}

func makeIntScalar(_ value: Int) throws -> MLMultiArray {
    try makeIntArray(shape: [1, 1], values: [value])
}

func run(_ model: MLModel, _ features: [String: MLFeatureValue]) throws -> [String: MLFeatureValue] {
    let provider = try MLDictionaryFeatureProvider(dictionary: features)
    let output = try model.prediction(from: provider)
    var result: [String: MLFeatureValue] = [:]
    for name in output.featureNames {
        result[name] = output.featureValue(for: name)
    }
    return result
}

func elementOffset(_ array: MLMultiArray, indices: [Int]) -> Int {
    zip(indices, array.strides).reduce(0) { partial, item in
        partial + item.0 * item.1.intValue
    }
}

func floatValue(_ array: MLMultiArray, offset: Int) -> Float {
    switch array.dataType {
    case .float16:
        return Float(array.dataPointer.assumingMemoryBound(to: Float16.self)[offset])
    case .float32:
        return array.dataPointer.assumingMemoryBound(to: Float.self)[offset]
    case .double:
        return Float(array.dataPointer.assumingMemoryBound(to: Double.self)[offset])
    default:
        return array[offset].floatValue
    }
}

func floatValue(_ array: MLMultiArray, indices: [Int]) -> Float {
    floatValue(array, offset: elementOffset(array, indices: indices))
}

func copyFloatArray(_ source: MLMultiArray, shape: [Int], sourceIndices: ([Int]) -> [Int]) throws -> MLMultiArray {
    let count = shape.reduce(1, *)
    let destination = try MLMultiArray(shape: makeShape(shape), dataType: .float32)
    let pointer = destination.dataPointer.bindMemory(to: Float.self, capacity: count)
    for flatIndex in 0..<count {
        var remaining = flatIndex
        var destinationIndices = [Int](repeating: 0, count: shape.count)
        for dimension in stride(from: shape.count - 1, through: 0, by: -1) {
            destinationIndices[dimension] = remaining % shape[dimension]
            remaining /= shape[dimension]
        }
        pointer[flatIndex] = floatValue(source, indices: sourceIndices(destinationIndices))
    }
    return destination
}

func encoderFrame(_ encoded: MLMultiArray, dimension: Int, time: Int) throws -> MLMultiArray {
    try copyFloatArray(encoded, shape: [1, dimension, 1]) { indices in
        [indices[0], indices[1], time]
    }
}

func predictorOutputForJoint(_ decoder: MLMultiArray, hiddenSize: Int) throws -> MLMultiArray {
    try copyFloatArray(decoder, shape: [1, hiddenSize, 1]) { indices in
        [indices[0], indices[2], indices[1]]
    }
}

func predictorState(_ state: MLMultiArray, hiddenSize: Int) throws -> MLMultiArray {
    try copyFloatArray(state, shape: [1, 1, hiddenSize]) { indices in
        [indices[0], indices[1], indices[2]]
    }
}

func memoryFootprintBytes() -> UInt64 {
    var info = task_vm_info()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

// MARK: - Log-mel frontend

final class GigaAMMelFrontend {
    let sampleRate = 16_000
    let nFFT = 320
    let hopLength = 160
    let melBins = 64
    let windowFrames = 3_000
    let windowSamples = 480_000

    private let dftSetup: vDSP_DFT_Setup
    private let hannWindow: [Float]
    private let filterbank: [Float] // [melBin, frequencyBin]

    init() throws {
        let fftSize = 320
        let sampleRate = 16_000
        let melCount = 64
        guard let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction(rawValue: 1)!) else {
            throw SpikeError(message: "failed to create 320-point FFT setup")
        }
        dftSetup = setup

        // torchaudio's default Hann window is periodic (period=n), not symmetric.
        hannWindow = (0..<fftSize).map { index in
            0.5 * (1.0 - cos(2.0 * Float.pi * Float(index) / Float(fftSize)))
        }
        filterbank = GigaAMMelFrontend.makeHTKFilterbank(
            melBins: melCount,
            frequencyBins: fftSize / 2 + 1,
            sampleRate: sampleRate,
            fftSize: fftSize
        )
    }

    deinit {
        vDSP_DFT_DestroySetup(dftSetup)
    }

    func extract(_ samples: [Float]) throws -> (features: MLMultiArray, validFrames: Int, processedSamples: Int) {
        guard !samples.isEmpty else { throw SpikeError(message: "audio is empty") }

        let processedSamples = min(samples.count, windowSamples)
        guard processedSamples >= nFFT else {
            throw SpikeError(message: "audio is shorter than one 20 ms mel frame")
        }

        // One extra hop is a feature-only right pad required to produce the
        // export's fixed 3000 columns while keeping the advertised 30 s audio window.
        let featureSamples = (windowFrames - 1) * hopLength + nFFT
        var padded = [Float](repeating: 0, count: featureSamples)
        padded.replaceSubrange(0..<processedSamples, with: samples[0..<processedSamples])

        let validFrames = min(windowFrames, ((processedSamples - nFFT) / hopLength) + 1)
        let features = try MLMultiArray(
            shape: makeShape([1, melBins, windowFrames]),
            dataType: .float32
        )
        let output = features.dataPointer.bindMemory(to: Float.self, capacity: melBins * windowFrames)

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var outputReal = [Float](repeating: 0, count: nFFT / 2)
        var outputImaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nFFT / 2 + 1)
        var mel = [Float](repeating: 0, count: melBins)

        for time in 0..<windowFrames {
            let start = time * hopLength
            for index in 0..<nFFT {
                frame[index] = padded[start + index] * hannWindow[index]
            }

            for pair in 0..<(nFFT / 2) {
                real[pair] = frame[pair * 2]
                imaginary[pair] = frame[pair * 2 + 1]
            }
            real.withUnsafeBufferPointer { realBuffer in
                imaginary.withUnsafeBufferPointer { imaginaryBuffer in
                    outputReal.withUnsafeMutableBufferPointer { outputRealBuffer in
                        outputImaginary.withUnsafeMutableBufferPointer { outputImaginaryBuffer in
                            vDSP_DFT_Execute(
                                dftSetup,
                                realBuffer.baseAddress!,
                                imaginaryBuffer.baseAddress!,
                                outputRealBuffer.baseAddress!,
                                outputImaginaryBuffer.baseAddress!
                            )
                        }
                    }
                }
            }

            // vDSP's real DFT forward transform stores amplitudes doubled.
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

// MARK: - Models and vocabulary

struct GigaAMModels {
    let encoder: MLModel
    let predictor: MLModel
    let joint: MLModel
    let vocab: [Int: String]

    static func computeUnits(_ name: String) throws -> MLComputeUnits {
        switch name {
        case "ane": return .cpuAndNeuralEngine
        case "cpu": return .cpuOnly
        case "all": return .all
        default:
            throw SpikeError(message: "compute must be ane, cpu, or all")
        }
    }

    static func load(root: String, compute: String) throws -> GigaAMModels {
        let units = try computeUnits(compute)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units

        func loadModel(_ name: String) throws -> MLModel {
            let url = URL(fileURLWithPath: "\(root)/\(name).mlmodelc", isDirectory: true)
            return try MLModel(contentsOf: url, configuration: configuration)
        }

        let encoder = try loadModel("Encoder")
        let predictor = try loadModel("Predictor")
        let joint = try loadModel("JointDecision")
        let vocabURL = URL(fileURLWithPath: "\(root)/vocab.txt")
        let vocabData = try Data(contentsOf: vocabURL)
        guard let vocabText = String(data: vocabData, encoding: .utf8) else {
            throw SpikeError(message: "vocab.txt is not UTF-8")
        }

        var vocab: [Int: String] = [:]
        for line in vocabText.components(separatedBy: .newlines) where !line.isEmpty {
            guard let separator = line.lastIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let piece = String(line[..<separator])
            let id = Int(line[line.index(after: separator)...])
            if let id { vocab[id] = piece }
        }

        print("compute units: \(compute)")
        print("encoder in: \(encoder.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("encoder out: \(encoder.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("predictor in: \(predictor.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("predictor out: \(predictor.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("joint in: \(joint.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("joint out: \(joint.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("vocab entries: \(vocab.count), blank id: 1024")

        return GigaAMModels(encoder: encoder, predictor: predictor, joint: joint, vocab: vocab)
    }
}

func decode(vocab: [Int: String], tokens: [Int]) -> String {
    let pieces = tokens.compactMap { vocab[$0] }.filter {
        !$0.hasPrefix("<")
    }
    return pieces.joined()
        .replacingOccurrences(of: "\u{2581}", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Native RNN-T inference

struct DecodeResult {
    let tokens: [Int]
    let frames: [Int]
    let blankTerminatedFrames: Int
    let symbolsCapped: Int
    let duration: TimeInterval
}

func decodeRNNT(
    models: GigaAMModels,
    encoded: MLMultiArray,
    validFrames: Int,
    maxSymbols: Int,
    maxTokens: Int
) throws -> DecodeResult {
    let encoderDimension = encoded.shape[1].intValue
    let totalEncoderFrames = encoded.shape[2].intValue
    let validEncoderFrames = min(totalEncoderFrames, max(1, (validFrames + 3) / 4))
    let blankID = 1024

    var tokens: [Int] = []
    var tokenFrames: [Int] = []
    var lastToken = blankID
    var hidden = try makeFloatArray(shape: [1, 1, 320], values: Array(repeating: 0, count: 320))
    var cell = try makeFloatArray(shape: [1, 1, 320], values: Array(repeating: 0, count: 320))
    var hasState = false
    var blankTerminatedFrames = 0
    var cappedFrames = 0

    let started = Date()
    for time in 0..<validEncoderFrames {
        var emittedAtFrame = 0
        var stoppedByBlank = false
        while emittedAtFrame < maxSymbols && tokens.count < maxTokens {
            let predictorInput = try makeIntArray(shape: [1, 1], values: [hasState ? lastToken : blankID])
            let predictorOutput = try run(models.predictor, [
                "x": MLFeatureValue(multiArray: predictorInput),
                "hi": MLFeatureValue(multiArray: hidden),
                "ci": MLFeatureValue(multiArray: cell),
            ])
            guard let decoder = predictorOutput["dec"]?.multiArrayValue,
                  let nextHidden = predictorOutput["ho"]?.multiArrayValue,
                  let nextCell = predictorOutput["co"]?.multiArrayValue else {
                throw SpikeError(message: "predictor outputs are incomplete: \(predictorOutput.keys)")
            }

            let encoderSlice = try encoderFrame(encoded, dimension: encoderDimension, time: time)
            let decoderSlice = try predictorOutputForJoint(decoder, hiddenSize: 320)
            let jointOutput = try run(models.joint, [
                "enc": MLFeatureValue(multiArray: encoderSlice),
                "dec": MLFeatureValue(multiArray: decoderSlice),
            ])
            guard let tokenArray = jointOutput["token_id"]?.multiArrayValue else {
                throw SpikeError(message: "joint output is missing token_id: \(jointOutput.keys)")
            }
            let token = tokenArray[0].intValue

            if token == blankID {
                stoppedByBlank = true
                break
            }

            tokens.append(token)
            tokenFrames.append(time)
            lastToken = token
            hidden = try predictorState(nextHidden, hiddenSize: 320)
            cell = try predictorState(nextCell, hiddenSize: 320)
            hasState = true
            emittedAtFrame += 1
        }

        if stoppedByBlank { blankTerminatedFrames += 1 }
        if emittedAtFrame == maxSymbols { cappedFrames += 1 }
        if tokens.count >= maxTokens { break }
    }

    return DecodeResult(
        tokens: tokens,
        frames: tokenFrames,
        blankTerminatedFrames: blankTerminatedFrames,
        symbolsCapped: cappedFrames,
        duration: Date().timeIntervalSince(started)
    )
}

// MARK: - Entry point

@main
struct GigaAMCoreMLSpike {
    static func main() throws {
        let config = parseArgs(CommandLine.arguments)
        guard !config.audioPath.isEmpty else {
            print("usage: GigaAMCoreMLSpike <audio.wav> [modelRoot=dir] [compute=ane|cpu|all] [maxSymbols=10] [maxTokens=512]")
            return
        }

        let loadStart = Date()
        let models = try GigaAMModels.load(root: config.modelRoot, compute: config.compute)
        let loadDuration = Date().timeIntervalSince(loadStart)
        let wav = try readWav(path: config.audioPath)
        guard wav.sampleRate == 16_000 else {
            throw SpikeError(message: "sample rate \(wav.sampleRate) != 16000")
        }

        let duration = Double(wav.samples.count) / 16_000.0
        let frontend = try GigaAMMelFrontend()
        let featureStart = Date()
        let extracted = try frontend.extract(wav.samples)
        let featureDuration = Date().timeIntervalSince(featureStart)
        let validEncoderFrames = max(1, (extracted.validFrames + 3) / 4)
        print("audio: \(wav.samples.count) samples (\(String(format: "%.2f", duration)) s), processed: \(extracted.processedSamples) samples")
        print("features: \(extracted.features.shape), valid mel frames: \(extracted.validFrames)/3000, valid encoder frames: \(validEncoderFrames)/750")
        print("frontend: \(String(format: "%.3f", featureDuration)) s, window: 30 s, chunking: <= 30 s")

        let encoderStart = Date()
        let encoderOutput = try run(models.encoder, [
            "audio_signal": MLFeatureValue(multiArray: extracted.features),
        ])
        guard let encoded = encoderOutput["encoded"]?.multiArrayValue else {
            throw SpikeError(message: "encoder output is missing encoded: \(encoderOutput.keys)")
        }
        let encoderDuration = Date().timeIntervalSince(encoderStart)
        print("encoder: \(encoded.shape) dataType=Float16, elapsed: \(String(format: "%.3f", encoderDuration)) s")

        let decoded = try decodeRNNT(
            models: models,
            encoded: encoded,
            validFrames: extracted.validFrames,
            maxSymbols: config.maxSymbols,
            maxTokens: config.maxTokens
        )
        let transcript = decode(vocab: models.vocab, tokens: decoded.tokens)
        let rtf = decoded.duration > 0 ? Double(extracted.processedSamples) / 16_000.0 / decoded.duration : 0

        print("\n=== RESULT (compute=\(config.compute)) ===")
        print("transcript: \(transcript)")
        print("tokens: \(decoded.tokens.count), blank-terminated frames: \(decoded.blankTerminatedFrames), symbol-cap frames: \(decoded.symbolsCapped)")
        print("timing: load=\(String(format: "%.2f", loadDuration))s frontend=\(String(format: "%.3f", featureDuration))s encoder=\(String(format: "%.3f", encoderDuration))s rnnt=\(String(format: "%.3f", decoded.duration))s")
        print("RTFx (RNNT loop, valid audio): \(String(format: "%.1f", rtf))x")
        print("footprint: \(memoryFootprintBytes() / 1024 / 1024) MiB")
    }
}
