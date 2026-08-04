// Canary 1B v2 smdesai Core ML spike harness (Bolabol S4b P0).
//
// This is an offline, standalone probe for the smdesai KV-cache export. It is
// not a product target and must not be copied into Sources. The harness keeps
// the true audio, mel, and encoder lengths separate from fixed Core ML buffers.
//
// Usage:
//   CanarySmdesaiSpike <audio.wav> modelRoot=<dir> vocabPath=<file>
//                       [compute=cpu|ane|all] [maxTokens=50]
//
// The model requires macOS 15+ because the decoder uses MLState. Inference is
// native Core ML only. The vocabPath argument is an id-to-piece JSON map used
// for readable diagnostics; the downloaded candidate's canary_spe.model is
// retained in the model root for the eventual native SentencePiece adapter.

import Accelerate
import CoreML
import Foundation

struct SpikeError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct Config {
    let audioPath: String
    var modelRoot = "."
    var vocabPath = ""
    var compute = "cpu"
    var frontend = "coreml"
    var task = "asr"
    var srcLang = "en"
    var tgtLang = "en"
    var maxTokens = 50
}

func parseArgs(_ args: [String]) -> Config {
    var config = Config(audioPath: args.count > 1 ? args[1] : "")
    for argument in args.dropFirst(2) {
        let pair = argument.split(separator: "=", maxSplits: 1)
        guard pair.count == 2 else { continue }
        switch pair[0] {
        case "modelRoot": config.modelRoot = String(pair[1])
        case "vocabPath": config.vocabPath = String(pair[1])
        case "compute": config.compute = String(pair[1])
        case "frontend": config.frontend = String(pair[1])
        case "task": config.task = String(pair[1])
        case "src": config.srcLang = String(pair[1])
        case "tgt": config.tgtLang = String(pair[1])
        case "maxTokens": config.maxTokens = Int(pair[1]) ?? 50
        default: break
        }
    }
    return config
}

// MARK: - WAV reader

func readWav(path: String) throws -> (samples: [Float], sampleRate: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bytes = [UInt8](data)
    guard bytes.count > 44,
          String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
        throw SpikeError(message: "not a RIFF/WAVE file: \(path)")
    }

    var formatOffset = -1
    var dataOffset = -1
    var cursor = 12
    while cursor + 8 <= bytes.count {
        let identifier = String(bytes: bytes[cursor..<cursor + 4], encoding: .ascii) ?? ""
        let chunkSize = Int(bytes[cursor + 4])
            | (Int(bytes[cursor + 5]) << 8)
            | (Int(bytes[cursor + 6]) << 16)
            | (Int(bytes[cursor + 7]) << 24)
        if identifier == "fmt " { formatOffset = cursor }
        if identifier == "data" { dataOffset = cursor + 8 }
        cursor += 8 + chunkSize + (chunkSize % 2)
    }

    guard formatOffset >= 0, dataOffset >= 0 else {
        throw SpikeError(message: "WAV is missing fmt/data chunks: \(path)")
    }

    let format = bytes
    let audioFormat = Int(format[formatOffset + 8]) | (Int(format[formatOffset + 9]) << 8)
    let channels = Int(format[formatOffset + 10]) | (Int(format[formatOffset + 11]) << 8)
    let sampleRate = Int(format[formatOffset + 12])
        | (Int(format[formatOffset + 13]) << 8)
        | (Int(format[formatOffset + 14]) << 16)
        | (Int(format[formatOffset + 15]) << 24)
    let bits = Int(format[formatOffset + 22]) | (Int(format[formatOffset + 23]) << 8)
    guard channels > 0, (audioFormat == 1 || audioFormat == 3) else {
        throw SpikeError(message: "unsupported WAV format \(audioFormat) / channels \(channels)")
    }

    let raw = Array(bytes[dataOffset...])
    let frameBytes = channels * bits / 8
    guard frameBytes > 0 else { throw SpikeError(message: "invalid WAV frame size") }
    let frameCount = raw.count / frameBytes
    var samples = [Float](repeating: 0, count: frameCount)

    if audioFormat == 1, bits == 16 {
        for frame in 0..<frameCount {
            var sum: Int32 = 0
            for channel in 0..<channels {
                let index = frame * frameBytes + channel * 2
                let value = Int16(bitPattern: UInt16(raw[index]) | (UInt16(raw[index + 1]) << 8))
                sum += Int32(value)
            }
            samples[frame] = Float(sum) / Float(channels) / 32768.0
        }
    } else if audioFormat == 3, bits == 32 {
        raw.withUnsafeBytes { buffer in
            let floats = buffer.bindMemory(to: Float.self)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channels { sum += floats[frame * channels + channel] }
                samples[frame] = sum / Float(channels)
            }
        }
    } else {
        throw SpikeError(message: "unsupported WAV bits: \(bits)")
    }

    return (samples, sampleRate)
}

// MARK: - Core ML helpers

func computeUnits(_ name: String) -> MLComputeUnits {
    switch name {
    case "ane": return .cpuAndNeuralEngine
    case "all": return .all
    default: return .cpuOnly
    }
}

func makeFloatArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
    _ = values.withUnsafeBufferPointer { buffer in
        memcpy(array.dataPointer, buffer.baseAddress!, values.count * MemoryLayout<Float>.stride)
    }
    return array
}

func makeIntArray(_ values: [Int], shape: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
    for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
    return array
}

func run(_ model: MLModel, _ features: [String: MLFeatureValue]) throws -> [String: MLFeatureValue] {
    let provider = try MLDictionaryFeatureProvider(dictionary: features)
    let output = try model.prediction(from: provider)
    var values: [String: MLFeatureValue] = [:]
    for name in output.featureNames { values[name] = output.featureValue(for: name) }
    return values
}

func floatValues(_ array: MLMultiArray) -> [Float] {
    let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
    return Array(UnsafeBufferPointer(start: pointer, count: array.count))
}

func scalarInt(_ array: MLMultiArray) -> Int {
    array[0].intValue
}

func modelPath(_ root: String, _ name: String) -> URL {
    URL(fileURLWithPath: root).appendingPathComponent(name + ".mlmodelc")
}

struct Models {
    let preprocessor: MLModel
    let encoder: MLModel
    let crossKV: MLModel
    let decoderKV: MLModel
    let vocab: [Int: String]

    static func load(root: String, vocabPath: String, compute: String) throws -> Models {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits(compute)

        let preprocessor = try MLModel(
            contentsOf: modelPath(root, "canary_preprocessor"),
            configuration: configuration
        )
        let encoder = try MLModel(
            contentsOf: modelPath(root, "canary_encoder"),
            configuration: configuration
        )
        let crossKV = try MLModel(
            contentsOf: modelPath(root, "canary_cross_kv"),
            configuration: configuration
        )
        let decoderKV = try MLModel(
            contentsOf: modelPath(root, "canary_decoder_kv"),
            configuration: configuration
        )

        let data = try Data(contentsOf: URL(fileURLWithPath: vocabPath))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw SpikeError(message: "vocabPath must contain an id-to-piece JSON object")
        }
        var vocab: [Int: String] = [:]
        for (key, value) in object {
            if let id = Int(key) { vocab[id] = value }
        }

        print("compute units: \(compute) -> \(computeUnits(compute).rawValue)")
        print("preprocessor in: \(preprocessor.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("preprocessor out: \(preprocessor.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("encoder in: \(encoder.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("encoder out: \(encoder.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("cross KV in/out: \(crossKV.modelDescription.inputDescriptionsByName.keys.sorted()) / \(crossKV.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("decoder KV in/out: \(decoderKV.modelDescription.inputDescriptionsByName.keys.sorted()) / \(decoderKV.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("vocab entries: \(vocab.count)")

        return Models(preprocessor: preprocessor, encoder: encoder, crossKV: crossKV,
                      decoderKV: decoderKV, vocab: vocab)
    }
}

// MARK: - Native NeMo-style mel frontend (Path B)

struct NativeMelFrontend {
    private let sampleRate = 16_000
    private let numMelBins = 128
    private let nFFT = 512
    private let hopLength = 160
    private let winLength = 400
    private let centrePad = 256
    private let windowOffset = 56
    private let maxFrames = 1_501
    private let preEmphasis = Float(0.97)
    private let logGuard = Float(5.960464477539063e-08) // 2^-24
    private let normEpsilon = Float(1e-5)
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float]

    init() throws {
        let windowLength = 400
        guard let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else {
            throw SpikeError(message: "native mel FFT setup failed")
        }
        fftSetup = setup
        hannWindow = (0..<windowLength).map {
            0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / Float(windowLength - 1)))
        }
        melFilterbank = NativeMelFrontend.buildMelFilterbank(
            nMels: numMelBins, nBins: nFFT / 2 + 1, sampleRate: sampleRate
        )
    }

    func extract(_ source: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        let audio = Array(source.prefix(240_000))
        guard !audio.isEmpty else { throw SpikeError(message: "native mel received empty audio") }

        var emphasized = [Float](repeating: 0, count: audio.count)
        emphasized[0] = audio[0]
        if audio.count > 1 {
            for index in 1..<audio.count {
                emphasized[index] = audio[index] - preEmphasis * audio[index - 1]
            }
        }

        // Core ML smdesai's MIL declares reflect padding, unlike the old S4
        // preprocessor export. The native path mirrors centered STFT framing.
        var padded = [Float](repeating: 0, count: audio.count + centrePad * 2)
        for index in 0..<audio.count { padded[centrePad + index] = emphasized[index] }
        if audio.count > centrePad + 1 {
            for index in 0..<centrePad {
                padded[centrePad - 1 - index] = emphasized[index + 1]
                padded[centrePad + audio.count + index] = emphasized[audio.count - 2 - index]
            }
        }

        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        let frames = min(stftFrames, maxFrames)
        guard frames > 0 else { throw SpikeError(message: "native mel produced no frames") }

        let mel = try MLMultiArray(
            shape: [1, NSNumber(value: numMelBins), NSNumber(value: maxFrames)],
            dataType: .float32
        )
        let melPointer = mel.dataPointer.bindMemory(to: Float.self, capacity: mel.count)
        for index in 0..<mel.count { melPointer[index] = 0 }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nFFT / 2 + 1)
        var melFrame = [Float](repeating: 0, count: numMelBins)

        for time in 0..<frames {
            for index in 0..<nFFT { frame[index] = 0 }
            let start = time * hopLength
            for index in 0..<winLength {
                frame[windowOffset + index] = padded[start + windowOffset + index] * hannWindow[index]
            }

            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                    frame.withUnsafeBufferPointer { sourceBuffer in
                        sourceBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(nFFT / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, 9, FFTDirection(FFT_FORWARD))
                    let dc = split.realp[0] * 0.5
                    let nyquist = split.imagp[0] * 0.5
                    split.imagp[0] = 0
                    power[0] = dc * dc
                    for bin in 1..<(nFFT / 2) {
                        let realPart = split.realp[bin] * 0.5
                        let imaginaryPart = split.imagp[bin] * 0.5
                        power[bin] = realPart * realPart + imaginaryPart * imaginaryPart
                    }
                    power[nFFT / 2] = nyquist * nyquist
                }
            }

            melFilterbank.withUnsafeBufferPointer { bank in
                power.withUnsafeBufferPointer { spectrum in
                    melFrame.withUnsafeMutableBufferPointer { output in
                        vDSP_mmul(spectrum.baseAddress!, 1, bank.baseAddress!, 1,
                                  output.baseAddress!, 1, 1, vDSP_Length(numMelBins),
                                  vDSP_Length(nFFT / 2 + 1))
                    }
                }
            }
            for bin in 0..<numMelBins {
                melPointer[bin * maxFrames + time] = log(melFrame[bin] + logGuard)
            }
        }

        normalize(melPointer, frames: frames)
        return (mel, frames)
    }

    private func normalize(_ mel: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 1 else { return }
        for bin in 0..<numMelBins {
            let row = mel + bin * maxFrames
            var mean: Float = 0
            for frame in 0..<frames { mean += row[frame] }
            mean /= Float(frames)
            var squaredDeviation: Float = 0
            for frame in 0..<frames {
                let difference = row[frame] - mean
                squaredDeviation += difference * difference
            }
            let variance = squaredDeviation / Float(frames - 1)
            let scale = 1 / ((variance > 0 ? sqrt(variance) : 0) + normEpsilon)
            for frame in 0..<frames { row[frame] = (row[frame] - mean) * scale }
        }
    }

    private static func buildMelFilterbank(nMels: Int, nBins: Int, sampleRate: Int) -> [Float] {
        func hzToMel(_ hz: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return hz < minLogHz ? (hz - fMin) / fSp : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return mel < minLogMel ? fMin + fSp * mel : minLogHz * exp(logStep * (mel - minLogMel))
        }

        let melMin = hzToMel(0)
        let melMax = hzToMel(Double(sampleRate) / 2)
        var edges = [Double](repeating: 0, count: nMels + 2)
        for index in 0...(nMels + 1) {
            edges[index] = melToHz(melMin + (melMax - melMin) * Double(index) / Double(nMels + 1))
        }

        let binHz = Double(sampleRate) / 512.0
        var bank = [Float](repeating: 0, count: nBins * nMels)
        for mel in 0..<nMels {
            let left = edges[mel]
            let centre = edges[mel + 1]
            let right = edges[mel + 2]
            let areaNormalization = right > left ? 2.0 / (right - left) : 0
            for bin in 0..<nBins {
                let hz = Double(bin) * binHz
                var weight = 0.0
                if hz >= left, hz <= centre, centre > left {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre, hz <= right, right > centre {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + mel] = Float(weight * areaNormalization)
            }
        }
        return bank
    }
}

// MARK: - Mel preflight

func makeSine(frequency: Double, samples: Int, sampleRate: Double = 16_000) -> [Float] {
    (0..<samples).map { index in
        Float(sin(2.0 * Double.pi * frequency * Double(index) / sampleRate) * 0.5)
    }
}

func paddedWindow(_ samples: [Float], windowSize: Int = 240_000) -> [Float] {
    var window = [Float](repeating: 0, count: windowSize)
    let count = min(samples.count, windowSize)
    window.replaceSubrange(0..<count, with: samples[0..<count])
    return window
}

func preprocess(_ model: MLModel, samples: [Float]) throws -> (mel: MLMultiArray, length: Int) {
    let validSamples = min(samples.count, 240_000)
    let window = paddedWindow(Array(samples.prefix(validSamples)))
    let output = try run(model, [
        "audio_signal": MLFeatureValue(multiArray: try makeFloatArray(window, shape: [1, 240_000])),
        "audio_length": MLFeatureValue(multiArray: try makeIntArray([validSamples], shape: [1])),
    ])
    guard let mel = output["mel"]?.multiArrayValue,
          let length = output["mel_length"]?.multiArrayValue else {
        throw SpikeError(message: "preprocessor output missing mel/mel_length: \(output.keys.sorted())")
    }
    return (mel, scalarInt(length))
}

func pearson(_ lhs: [Float], _ rhs: [Float]) -> Double {
    guard lhs.count == rhs.count, lhs.count > 1 else { return 0 }
    let leftMean = lhs.reduce(0, +) / Float(lhs.count)
    let rightMean = rhs.reduce(0, +) / Float(rhs.count)
    var numerator: Double = 0
    var leftSquared: Double = 0
    var rightSquared: Double = 0
    for index in lhs.indices {
        let left = Double(lhs[index] - leftMean)
        let right = Double(rhs[index] - rightMean)
        numerator += left * right
        leftSquared += left * left
        rightSquared += right * right
    }
    let denominator = sqrt(leftSquared * rightSquared)
    return denominator > 0 ? numerator / denominator : 0
}

func channelScores(_ mel: MLMultiArray, frames: Int) -> [Float] {
    let values = floatValues(mel)
    let bins = mel.shape[1].intValue
    let capacity = mel.shape[2].intValue
    let usable = min(max(frames, 1), capacity)
    return (0..<bins).map { bin in
        var total: Float = 0
        for frame in 0..<usable { total += abs(values[bin * capacity + frame]) }
        return total / Float(usable)
    }
}

func topChannels(_ scores: [Float], count: Int = 3) -> [Int] {
    scores.indices.sorted { scores[$0] > scores[$1] }.prefix(count).map { $0 }
}

func melEnergy(_ mel: MLMultiArray, frames: Int) -> [Float] {
    let values = floatValues(mel)
    let bins = mel.shape[1].intValue
    let capacity = mel.shape[2].intValue
    let usable = min(max(frames, 1), capacity)
    return (0..<usable).map { frame in
        var total: Float = 0
        for bin in 0..<bins { total += values[bin * capacity + frame] }
        return total
    }
}

func frameEnvelope(_ samples: [Float], frames: Int, hop: Int = 160) -> [Float] {
    (0..<frames).map { frame in
        let start = frame * hop
        let end = min(start + hop, samples.count)
        guard start < end else { return 0 }
        return samples[start..<end].reduce(0) { $0 + abs($1) } / Float(end - start)
    }
}

typealias MelExtractor = ([Float]) throws -> (mel: MLMultiArray, length: Int)

func runMelPreflight(label: String, extractor: MelExtractor, referenceAudio: [Float]) throws {
    let oneK = try extractor(makeSine(frequency: 1_000, samples: 40_000))
    let fourK = try extractor(makeSine(frequency: 4_000, samples: 40_000))
    let oneKTop = topChannels(channelScores(oneK.mel, frames: oneK.length))
    let fourKTop = topChannels(channelScores(fourK.mel, frames: fourK.length))
    let overlap = Set(oneKTop).intersection(fourKTop).count

    let speech = try extractor(referenceAudio)
    let energy = melEnergy(speech.mel, frames: speech.length)
    let envelope = frameEnvelope(Array(referenceAudio.prefix(min(referenceAudio.count, 240_000))), frames: energy.count)
    let correlation = pearson(energy, envelope)
    let values = floatValues(speech.mel)
    let bins = speech.mel.shape[1].intValue
    let capacity = speech.mel.shape[2].intValue
    var zeroCount = 0
    let validCount = bins * min(speech.length, capacity)
    for bin in 0..<bins {
        for frame in 0..<min(speech.length, capacity) {
            if values[bin * capacity + frame] == 0 { zeroCount += 1 }
        }
    }
    let zeroFraction = validCount > 0 ? Double(zeroCount) / Double(validCount) : 1
    let frequencySeparated = overlap <= 1 && oneKTop.first.map { abs($0 - (fourKTop.first ?? $0)) >= 5 } == true
    let pass = frequencySeparated && correlation > 0.5 && zeroFraction < 0.2
    let correlationText = String(format: "%.3f", correlation)
    let zeroFractionText = String(format: "%.3f", zeroFraction)

    print("\n=== MEL PREFLIGHT (\(label)) ===")
    print("1kHz: mel_length=\(oneK.length), top_channels=\(oneKTop)")
    print("4kHz: mel_length=\(fourK.length), top_channels=\(fourKTop)")
    print("frequency_top3_overlap=\(overlap), frequency_discrimination=\(frequencySeparated)")
    print("speech: mel_length=\(speech.length), pearson_mel_energy_envelope=\(correlationText)")
    print("valid_region_exact_zero_fraction=\(zeroFractionText)")
    print("MEL_PREFLIGHT: \(pass ? "PASS" : "FAIL")")
}

// MARK: - KV decode

func transposeEncoder(_ encoder: MLMultiArray) throws -> MLMultiArray {
    // smdesai already exports [1, 188, 1024]; this guard prevents silently
    // accepting a FluidInference-style [1, 1024, 188] tensor.
    guard encoder.shape.count == 3,
          encoder.shape[1].intValue == 188,
          encoder.shape[2].intValue == 1024 else {
        throw SpikeError(message: "unexpected encoder shape: \(encoder.shape)")
    }
    return encoder
}

func makeSelfMask(position: Int, capacity: Int = 238) throws -> MLMultiArray {
    let clamped = min(max(position, 0), capacity - 1)
    var mask = [Float](repeating: -10_000, count: capacity)
    for index in 0...clamped { mask[index] = 0 }
    return try makeFloatArray(mask, shape: [1, 1, 1, capacity])
}

func argmax(_ logits: MLMultiArray) -> Int {
    let values = floatValues(logits)
    var best = 0
    var bestValue = -Float.infinity
    for (index, value) in values.enumerated() where value > bestValue {
        best = index
        bestValue = value
    }
    return best
}

func decode(vocab: [Int: String], tokens: [Int]) -> String {
    let pieces = tokens.compactMap { vocab[$0] }.filter { !$0.hasPrefix("<|") }
    return pieces.joined().replacingOccurrences(of: "\u{2581}", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func runASR(models: Models, samples: [Float], maxTokens: Int, task: String,
            srcLang: String, tgtLang: String, extractor: MelExtractor) throws {
    let validSamples = min(samples.count, 240_000)
    let processed = try extractor(samples)
    let encoderOutput = try run(models.encoder, [
        "mel": MLFeatureValue(multiArray: processed.mel),
        "mel_length": MLFeatureValue(multiArray: try makeIntArray([processed.length], shape: [1])),
    ])
    guard let encoderStates = encoderOutput["enc_states"]?.multiArrayValue,
          let encoderLengthArray = encoderOutput["encoder_length"]?.multiArrayValue else {
        throw SpikeError(message: "encoder output missing enc_states/encoder_length: \(encoderOutput.keys.sorted())")
    }
    let encoderLength = scalarInt(encoderLengthArray)
    let states = try transposeEncoder(encoderStates)
    let crossOutput = try run(models.crossKV, [
        "enc_states": MLFeatureValue(multiArray: states),
    ])
    guard let encK = crossOutput["enc_k"]?.multiArrayValue,
          let encV = crossOutput["enc_v"]?.multiArrayValue else {
        throw SpikeError(message: "cross KV output missing enc_k/enc_v: \(crossOutput.keys.sorted())")
    }

    let languageIDs: [String: Int] = ["en": 64, "fr": 71, "de": 78, "es": 171, "ru": 157]
    guard let sourceID = languageIDs[srcLang], let targetID = languageIDs[tgtLang] else {
        throw SpikeError(message: "unsupported language pair \(srcLang)->\(tgtLang)")
    }
    let seed = [16053, 7, 4, 16, sourceID, targetID, 5, 9, 11, 13]
    let state = models.decoderKV.makeState()
    var output: [String: MLFeatureValue] = [:]
    var position = 0
    for token in seed {
        output = try runStatefulDecoder(models.decoderKV, state: state, token: token,
                                        position: position, encK: encK, encV: encV)
        position += 1
    }

    var generated: [Int] = []
    var stoppedByEOS = false
    var repeatedTokenCount = 0
    var previousToken: Int?
    for _ in 0..<maxTokens {
        guard let logits = output["log_probs"]?.multiArrayValue else {
            throw SpikeError(message: "decoder output missing log_probs: \(output.keys.sorted())")
        }
        let token = argmax(logits)
        if token == 3 {
            stoppedByEOS = true
            break
        }
        if token == previousToken { repeatedTokenCount += 1 } else { repeatedTokenCount = 0 }
        previousToken = token
        generated.append(token)
        output = try runStatefulDecoder(models.decoderKV, state: state, token: token,
                                        position: position, encK: encK, encV: encV)
        position += 1
    }

    let transcript = decode(vocab: models.vocab, tokens: generated)
    let loop = repeatedTokenCount >= 4
    print("\n=== ASR RESULT (smdesai KV, task=\(task), \(srcLang)->\(tgtLang)) ===")
    print("audio_length(valid)=\(validSamples), mel_length=\(processed.length), encoder_length=\(encoderLength)/188")
    print("prompt_length=\(seed.count), generated_tokens=\(generated.count), EOS=\(stoppedByEOS), repeated_tail=\(loop)")
    print("token_ids: \(generated)")
    print("transcript: \(transcript)")
    print("ASR_PREFLIGHT: \(stoppedByEOS && !transcript.isEmpty && !loop ? "PASS" : "FAIL")")
}

func runStatefulDecoder(_ model: MLModel, state: MLState, token: Int, position: Int,
                        encK: MLMultiArray, encV: MLMultiArray) throws -> [String: MLFeatureValue] {
    let features: [String: MLFeatureValue] = [
        "enc_k": MLFeatureValue(multiArray: encK),
        "enc_v": MLFeatureValue(multiArray: encV),
        "pos": MLFeatureValue(multiArray: try makeIntArray([position], shape: [1])),
        "self_mask": MLFeatureValue(multiArray: try makeSelfMask(position: position)),
        "token": MLFeatureValue(multiArray: try makeIntArray([token], shape: [1, 1])),
    ]
    let provider = try MLDictionaryFeatureProvider(dictionary: features)
    let output = try model.prediction(from: provider, using: state)
    var values: [String: MLFeatureValue] = [:]
    for name in output.featureNames { values[name] = output.featureValue(for: name) }
    return values
}

@main
struct CanarySmdesaiSpike {
    static func main() throws {
        let config = parseArgs(CommandLine.arguments)
        guard !config.audioPath.isEmpty, !config.vocabPath.isEmpty else {
            print("usage: CanarySmdesaiSpike <audio.wav> modelRoot=<dir> vocabPath=<file> [frontend=coreml|native] [task=asr|ast] [src=en] [tgt=en] [compute=cpu|ane|all] [maxTokens=50]")
            exit(1)
        }

        let models = try Models.load(root: config.modelRoot, vocabPath: config.vocabPath,
                                     compute: config.compute)
        let wav = try readWav(path: config.audioPath)
        guard wav.sampleRate == 16_000 else {
            throw SpikeError(message: "sample rate \(wav.sampleRate) != 16000")
        }
        let durationText = String(format: "%.2f", Double(wav.samples.count) / 16_000.0)
        print("audio: \(wav.samples.count) samples (\(durationText) s)")

        let coreMLExtractor: MelExtractor = { samples in
            try preprocess(models.preprocessor, samples: samples)
        }
        try runMelPreflight(label: "smdesai Core ML preprocessor",
                            extractor: coreMLExtractor, referenceAudio: wav.samples)

        let selectedExtractor: MelExtractor
        if config.frontend == "native" {
            let nativeFrontend = try NativeMelFrontend()
            selectedExtractor = { samples in
                let extracted = try nativeFrontend.extract(samples)
                return (mel: extracted.mel, length: extracted.frames)
            }
            try runMelPreflight(label: "Path B native NeMo-style mel",
                                extractor: selectedExtractor, referenceAudio: wav.samples)
        } else {
            selectedExtractor = coreMLExtractor
        }

        print("selected frontend: \(config.frontend)")
        try runASR(models: models, samples: wav.samples, maxTokens: config.maxTokens,
                   task: config.task, srcLang: config.srcLang, tgtLang: config.tgtLang,
                   extractor: selectedExtractor)
    }
}
