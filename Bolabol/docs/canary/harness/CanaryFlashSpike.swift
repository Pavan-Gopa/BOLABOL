// Canary Flash (~180M) Core ML spike harness (Bolabol S5 spike, pure Swift).
//
// Artifact under test: aufklarer/Canary-180M-Flash-CoreML — an int8 Core ML
// (mlprogram, macOS 14 / iOS 17) export of nvidia/canary-180m-flash.
//
// Graph contract (verified against model.mil at load time):
//   CanaryEncoder  audio_signal fp32 [1,128,1000] (log-mel, 10 s window),
//                  length int32 [1] (true mel-frame count, drives masking)
//                  -> encoder_embeddings fp32 [1,125,1024], encoder_mask fp32 [1,125]
//   CanaryPrefill  input_ids int32 [1,9] (prompt), encoder_embeddings,
//                  encoder_mask -> logits fp32 [1,1,5248],
//                  decoder_hidden_states fp32 [5,1,9,1024]
//   CanaryDecoder  input_ids int32 [1,1], decoder_mems fp32 [5,1,C,1024]
//                  (flexible C), encoder_embeddings, encoder_mask,
//                  start_pos int32 [1] -> logits fp32 [1,1,5248],
//                  decoder_hidden_states fp32 [5,1,C+1,1024]
//
// The encoder input is NOT raw audio: features are NeMo
// AudioToMelSpectrogramPreprocessor-style log-mel (pre-emphasis 0.97, centred
// constant-padded STFT, symmetric Hann 400/512, Slaney 128-band mel bank,
// log(x + 2^-24), per-feature normalisation over the sample (N-1) variance).
// The frontend in this file is adapted from soniqo/speech-swift
// Sources/CanaryASR/MelPreprocessor.swift (Apache-2.0) — the reference
// implementation for this exact export; contract constants are also published
// in the artifact's config.json.
//
// Valid-length semantics (S4 lesson): `length` is the TRUE mel-frame count for
// the real audio (floor(samples / 160)), never the padded buffer size. Mel
// columns beyond the valid frames are exact zeros and are masked inside the
// encoder from `length`.
//
// Prompt: [7, 4, 16, <src>, <tgt>, 5, 9, 11, 13], language ids from
// config.json languageTokenIds (en=62, de=76, fr=69, es=169). Greedy argmax
// decode: prefill on the prompt, then one decoder step per token feeding
// decoder_hidden_states back as decoder_mems with start_pos = cache length.
// Stop at EOS id (3, <|endoftext|>). logits are log probabilities; the
// confidence is exp(mean log p) over emitted tokens.
//
// No Python, no NeMo, no external tokenizer. Audio > 10 s is truncated to the
// window (matches the reference SDK: segment with VAD before inference).

import Accelerate
import CoreML
import Foundation

// MARK: - Config

struct Config {
    var audioPath: String
    var task = "asr"
    var srcLang = "en"
    var tgtLang = "en"
    var modelRoot = "."
    var compute = "all"
    var maxTokens = 256
}

func parseArgs(_ args: [String]) -> Config {
    var cfg = Config(audioPath: args.count > 1 ? args[1] : "")
    for arg in args.dropFirst(2) {
        let kv = arg.split(separator: "=", maxSplits: 1)
        guard kv.count == 2 else { continue }
        switch kv[0] {
        case "task": cfg.task = String(kv[1])
        case "src": cfg.srcLang = String(kv[1])
        case "tgt": cfg.tgtLang = String(kv[1])
        case "modelRoot": cfg.modelRoot = String(kv[1])
        case "compute": cfg.compute = String(kv[1])
        case "maxTokens": cfg.maxTokens = Int(kv[1]) ?? 256
        default: break
        }
    }
    return cfg
}

// MARK: - WAV reader (16-bit PCM or Float32, mono/stereo downmix)

func readWav(path: String) throws -> (samples: [Float], sampleRate: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bytes = [UInt8](data)
    guard bytes.count > 44, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
        throw NSError(domain: "wav", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a RIFF/WAVE file"])
    }
    var fmtChunk = -1, dataChunk = -1
    var offset = 12
    while offset + 8 <= bytes.count {
        let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
        let size = Int(bytes[offset + 4]) | (Int(bytes[offset + 5]) << 8) | (Int(bytes[offset + 6]) << 16) | (Int(bytes[offset + 7]) << 24)
        if id == "fmt " { fmtChunk = offset }
        if id == "data" { dataChunk = offset + 8 }
        offset += 8 + size + (size % 2)
    }
    guard fmtChunk >= 0, dataChunk >= 0 else {
        throw NSError(domain: "wav", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing fmt/data chunk"])
    }
    let fmt = bytes
    let audioFormat = Int(fmt[fmtChunk + 8]) | (Int(fmt[fmtChunk + 9]) << 8)
    let channels = Int(fmt[fmtChunk + 10]) | (Int(fmt[fmtChunk + 11]) << 8)
    let sampleRate = Int(fmt[fmtChunk + 12]) | (Int(fmt[fmtChunk + 13]) << 8) | (Int(fmt[fmtChunk + 14]) << 16) | (Int(fmt[fmtChunk + 15]) << 24)
    let bits = Int(fmt[fmtChunk + 22]) | (Int(fmt[fmtChunk + 23]) << 8)
    guard audioFormat == 1 || audioFormat == 3 else {
        throw NSError(domain: "wav", code: 3, userInfo: [NSLocalizedDescriptionKey: "unsupported format \(audioFormat)"])
    }
    let raw = Array(bytes[dataChunk...])
    let frameBytes = channels * bits / 8
    let frames = raw.count / frameBytes
    var samples = [Float](repeating: 0, count: frames)
    if audioFormat == 1 && bits == 16 {
        for f in 0..<frames {
            var acc: Int32 = 0
            for c in 0..<channels {
                let i = f * frameBytes + c * 2
                let s = Int16(bitPattern: UInt16(raw[i]) | (UInt16(raw[i + 1]) << 8))
                acc += Int32(s)
            }
            samples[f] = Float(acc) / Float(channels) / 32768.0
        }
    } else if audioFormat == 3 && bits == 32 {
        raw.withUnsafeBytes { buf in
            let floats = buf.bindMemory(to: Float.self)
            for f in 0..<frames {
                var acc: Float = 0
                for c in 0..<channels { acc += floats[f * channels + c] }
                samples[f] = acc / Float(channels)
            }
        }
    } else {
        throw NSError(domain: "wav", code: 4, userInfo: [NSLocalizedDescriptionKey: "unsupported bits \(bits)"])
    }
    return (samples, sampleRate)
}

// MARK: - Memory footprint

func footprintBytes() -> UInt64 {
    var info = task_vm_info()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

// MARK: - Log-mel frontend (NeMo AudioToMelSpectrogramPreprocessor contract)
//
// Adapted from soniqo/speech-swift Sources/CanaryASR/MelPreprocessor.swift
// (Apache-2.0); constants cross-checked against the artifact's config.json.

struct MelFrontend {
    let sampleRate: Int
    let numMelBins: Int
    let nFFT = 512
    let hopLength = 160
    let winLength = 400
    let preEmphasis = Float(0.97)
    let logGuard = Float(5.960464477539063e-08) // 2^-24
    let normEpsilon = Float(1e-5)
    let encoderMelFrames: Int

    private let log2FFT: vDSP_Length = 9
    private let nBins = 257
    private let centrePad = 256
    private let windowOffset = 56 // (512 - 400) / 2
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float] // [nBins, nMels] bin-major

    init(config: [String: Any], encoderMelFrames: Int) throws {
        guard let sr = config["sampleRate"] as? Int ?? (config["sampleRate"] as? Double).map({ Int($0) }),
              let bins = config["numMelBins"] as? Int ?? (config["numMelBins"] as? Double).map({ Int($0) }) else {
            throw NSError(domain: "frontend", code: 1, userInfo: [NSLocalizedDescriptionKey: "config missing sampleRate/numMelBins"])
        }
        self.sampleRate = sr
        self.numMelBins = bins
        self.encoderMelFrames = encoderMelFrames
        guard let setup = vDSP_create_fftsetup(log2FFT, FFTRadix(kFFTRadix2)) else {
            throw NSError(domain: "frontend", code: 2, userInfo: [NSLocalizedDescriptionKey: "vDSP FFT setup failed"])
        }
        self.fftSetup = setup
        var window = [Float](repeating: 0, count: winLength)
        for i in 0..<winLength {
            window[i] = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(winLength - 1)))
        }
        self.hannWindow = window
        self.melFilterbank = MelFrontend.buildMelFilterbank(nMels: bins, nBins: nBins, sampleRate: sr)
    }

    /// Log-mel for `audio`, zero-padded to the fixed encoder window.
    /// Returns the mel [1,128,window] (float32) and the true frame count to
    /// pass as the encoder `length`.
    func extract(_ audio: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        guard !audio.isEmpty else {
            throw NSError(domain: "frontend", code: 3, userInfo: [NSLocalizedDescriptionKey: "empty audio"])
        }
        // Pre-emphasis: x[n] - 0.97 * x[n-1]
        var emphasized = [Float](repeating: 0, count: audio.count)
        emphasized[0] = audio[0]
        if audio.count > 1 {
            audio.withUnsafeBufferPointer { src in
                emphasized.withUnsafeMutableBufferPointer { dst in
                    var negative = -preEmphasis
                    vDSP_vsma(src.baseAddress!, 1, &negative,
                              src.baseAddress! + 1, 1,
                              dst.baseAddress! + 1, 1,
                              vDSP_Length(audio.count - 1))
                }
            }
        }
        // Centre padding with zeros — torch.stft(center: true, pad_mode: "constant").
        var padded = [Float](repeating: 0, count: centrePad + emphasized.count + centrePad)
        for i in 0..<emphasized.count { padded[centrePad + i] = emphasized[i] }

        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        // NeMo reports floor(samples / hop) as the valid length, one less than
        // the centred STFT produces. Normalising over the extra frame shifts
        // every bin's statistics, so the reference keeps floor(samples / hop).
        let frames = min(stftFrames, audio.count / hopLength)
        guard frames > 0 else {
            throw NSError(domain: "frontend", code: 4, userInfo: [NSLocalizedDescriptionKey: "audio shorter than one frame"])
        }
        let usable = min(frames, encoderMelFrames)

        let mel = try MLMultiArray(shape: [1, NSNumber(value: numMelBins), NSNumber(value: encoderMelFrames)],
                                   dataType: .float32)
        let melPointer = UnsafeMutablePointer<Float>(OpaquePointer(mel.dataPointer))
        for i in 0..<(numMelBins * encoderMelFrames) { melPointer[i] = 0 }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nBins)
        var melFrame = [Float](repeating: 0, count: numMelBins)

        for t in 0..<usable {
            for i in 0..<nFFT { frame[i] = 0 }
            let start = t * hopLength
            for i in 0..<winLength {
                frame[windowOffset + i] = padded[start + windowOffset + i] * hannWindow[i]
            }
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imagBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!,
                                                imagp: imagBuffer.baseAddress!)
                    frame.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(nFFT / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2FFT, FFTDirection(FFT_FORWARD))
                    let nyquist = split.imagp[0] * 0.5
                    let dc = split.realp[0] * 0.5
                    split.imagp[0] = 0
                    power[0] = dc * dc
                    for bin in 1..<(nFFT / 2) {
                        let re = split.realp[bin] * 0.5
                        let im = split.imagp[bin] * 0.5
                        power[bin] = re * re + im * im
                    }
                    power[nFFT / 2] = nyquist * nyquist
                }
            }
            melFilterbank.withUnsafeBufferPointer { bank in
                power.withUnsafeBufferPointer { spectrum in
                    melFrame.withUnsafeMutableBufferPointer { out in
                        vDSP_mmul(spectrum.baseAddress!, 1, bank.baseAddress!, 1,
                                  out.baseAddress!, 1, 1, vDSP_Length(numMelBins), vDSP_Length(nBins))
                    }
                }
            }
            for m in 0..<numMelBins {
                melPointer[m * encoderMelFrames + t] = log(melFrame[m] + logGuard)
            }
        }
        normalizePerFeature(melPointer, frames: usable)
        return (mel, usable)
    }

    /// Per-feature normalisation over the frames that hold audio: sample (N-1)
    /// variance, 1e-5 epsilon on the deviation.
    private func normalizePerFeature(_ mel: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 1 else { return }
        for m in 0..<numMelBins {
            let row = mel + m * encoderMelFrames
            var sum: Float = 0
            vDSP_sve(row, 1, &sum, vDSP_Length(frames))
            let mean = sum / Float(frames)
            var squaredDeviation: Float = 0
            for t in 0..<frames {
                let d = row[t] - mean
                squaredDeviation += d * d
            }
            let variance = squaredDeviation / Float(frames - 1)
            let deviation = (variance > 0 ? sqrt(variance) : 0) + normEpsilon
            var negativeMean = -mean
            var scale = 1 / deviation
            vDSP_vsadd(row, 1, &negativeMean, row, 1, vDSP_Length(frames))
            vDSP_vsmul(row, 1, &scale, row, 1, vDSP_Length(frames))
        }
    }

    /// Slaney-scale mel filterbank, area-normalised, built in double precision
    /// in Hz space exactly as librosa does.
    private static func buildMelFilterbank(nMels: Int, nBins: Int, sampleRate: Int) -> [Float] {
        func hzToMel(_ hz: Double) -> Double {
            let fMin = 0.0, fSp = 200.0 / 3.0
            let minLogHz = 1000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return hz < minLogHz ? (hz - fMin) / fSp : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Double) -> Double {
            let fMin = 0.0, fSp = 200.0 / 3.0
            let minLogHz = 1000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return mel < minLogMel ? fMin + fSp * mel : minLogHz * exp(logStep * (mel - minLogMel))
        }
        let melMin = hzToMel(0)
        let melMax = hzToMel(Double(sampleRate) / 2)
        var edges = [Double](repeating: 0, count: nMels + 2)
        for i in 0...(nMels + 1) {
            edges[i] = melToHz(melMin + (melMax - melMin) * Double(i) / Double(nMels + 1))
        }
        let binHz = Double(sampleRate) / 512.0
        var bank = [Float](repeating: 0, count: nBins * nMels)
        for m in 0..<nMels {
            let left = edges[m], centre = edges[m + 1], right = edges[m + 2]
            let enorm = right > left ? 2.0 / (right - left) : 0.0
            for bin in 0..<nBins {
                let hz = Double(bin) * binHz
                var weight = 0.0
                if hz >= left && hz <= centre && centre > left {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre && hz <= right && right > centre {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + m] = Float(weight * enorm)
            }
        }
        return bank
    }
}

// MARK: - Model bundle

struct FlashModels {
    let encoder: MLModel
    let prefill: MLModel
    let step: MLModel
    let vocab: [Int: String]
    let languageTokenIds: [String: Int]
    let promptTemplate: [Int] // [7, 4, 16, src, tgt, 5, 9, 11, 13]
    let eosId: Int
    let encoderMelFrames: Int
    let encodedFrames: Int

    static func computeUnits(_ name: String) -> MLComputeUnits {
        switch name {
        case "ane": return .cpuAndNeuralEngine
        case "cpu": return .cpuOnly
        default: return .all
        }
    }

    static func load(root: String, compute: String) throws -> FlashModels {
        let units = computeUnits(compute)
        let config = MLModelConfiguration()
        config.computeUnits = units
        func load(_ name: String) throws -> MLModel {
            try MLModel(contentsOf: URL(fileURLWithPath: "\(root)/\(name).mlmodelc"), configuration: config)
        }
        let enc = try load("CanaryEncoder")
        let pre = try load("CanaryPrefill")
        let dec = try load("CanaryDecoder")
        print("compute units: \(compute) -> \(units.rawValue)")
        print("encoder in: \(enc.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("encoder out: \(enc.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("prefill in: \(pre.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("prefill out: \(pre.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("step in: \(dec.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("step out: \(dec.modelDescription.outputDescriptionsByName.keys.sorted())")

        let cfgData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/config.json"))
        guard let cfg = try JSONSerialization.jsonObject(with: cfgData) as? [String: Any] else {
            throw NSError(domain: "load", code: 1, userInfo: [NSLocalizedDescriptionKey: "config.json not a dict"])
        }
        let langs = cfg["languageTokenIds"] as? [String: Int] ?? [:]
        let special = cfg["specialTokenIds"] as? [String: Int] ?? [:]
        let coreml = cfg["coreml"] as? [String: Any] ?? [:]
        let encoderMelFrames = (coreml["encoderMelFrames"] as? Int) ?? 1000
        let encodedFrames = (coreml["encodedFrames"] as? Int) ?? 125
        let promptIds = cfg["promptIds"] as? [String: [Int]]
        let template: [Int]
        if let first = promptIds?.values.first {
            template = first
        } else {
            template = [7, 4, 16, 0, 0, 5, 9, 11, 13]
        }
        guard let eos = special["eos"] else {
            throw NSError(domain: "load", code: 2, userInfo: [NSLocalizedDescriptionKey: "no eos id"])
        }

        let vocabData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/vocab.json"))
        let obj = try JSONSerialization.jsonObject(with: vocabData)
        var vocab: [Int: String] = [:]
        if let dict = obj as? [String: String] {
            for (k, v) in dict {
                guard let id = Int(k) else { continue }
                vocab[id] = v
            }
        }
        print("vocab entries: \(vocab.count), encoder window \(encoderMelFrames) mel frames -> \(encodedFrames) encoded frames")
        return FlashModels(encoder: enc, prefill: pre, step: dec, vocab: vocab,
                           languageTokenIds: langs, promptTemplate: template,
                           eosId: eos, encoderMelFrames: encoderMelFrames,
                           encodedFrames: encodedFrames)
    }
}

// MARK: - MLMultiArray helpers

func makeI32(_ values: [Int]) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
    for (i, v) in values.enumerated() { a[i] = NSNumber(value: v) }
    return a
}

func makeI32Scalar(_ v: Int) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1], dataType: .int32)
    a[0] = NSNumber(value: v)
    return a
}

func run(_ model: MLModel, _ dict: [String: MLFeatureValue]) throws -> [String: MLFeatureValue] {
    let provider = try MLDictionaryFeatureProvider(dictionary: dict)
    let out = try model.prediction(from: provider)
    var result: [String: MLFeatureValue] = [:]
    for name in out.featureNames { result[name] = out.featureValue(for: name) }
    return result
}

/// Greedy argmax over the LAST `vocab` values of a [1,1,vocab] logits array,
/// reading at the array's own precision (fp16 models must not be read as fp32).
func argmax(_ logits: MLMultiArray, vocab: Int) -> (index: Int, score: Float) {
    let count = logits.count
    let offset = count - vocab
    func scan<T: BinaryFloatingPoint>(_ pointer: UnsafeMutablePointer<T>) -> (Int, Float) {
        var best = 0
        var bestScore = pointer[offset]
        for i in 1..<vocab where pointer[offset + i] > bestScore {
            bestScore = pointer[offset + i]
            best = i
        }
        return (best, Float(bestScore))
    }
    switch logits.dataType {
    case .float16: return scan(logits.dataPointer.assumingMemoryBound(to: Float16.self))
    case .double: return scan(logits.dataPointer.assumingMemoryBound(to: Float64.self))
    default: return scan(logits.dataPointer.assumingMemoryBound(to: Float32.self))
    }
}

// MARK: - Decode

func decode(vocab: [Int: String], tokens: [Int]) -> String {
    var text = ""
    for t in tokens {
        guard let piece = vocab[t], !piece.hasPrefix("<|") else { continue }
        text += piece
    }
    return text.replacingOccurrences(of: "\u{2581}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Main

@main
struct CanaryFlashSpike {
    static func main() async throws {
        let cfg = parseArgs(CommandLine.arguments)
        guard !cfg.audioPath.isEmpty else {
            print("usage: CanaryFlashSpike <audio.wav> [task=asr|ast] [src=en] [tgt=de] [modelRoot=dir] [compute=all|ane|cpu] [maxTokens=n]")
            exit(1)
        }
        let t0 = Date()
        let models = try FlashModels.load(root: cfg.modelRoot, compute: cfg.compute)
        let loadSec = Date().timeIntervalSince(t0)

        let wav = try readWav(path: cfg.audioPath)
        guard wav.sampleRate == 16000 else {
            print("FATAL: sample rate \(wav.sampleRate) != 16000")
            exit(2)
        }
        let rawCount = wav.samples.count
        let durationSec = Double(rawCount) / 16000.0
        print("audio: \(rawCount) samples on disk (\(String(format: "%.2f", durationSec)) s), \(wav.sampleRate) Hz")

        // Frontend: log-mel over the raw valid audio, zero-padded to the
        // encoder's fixed 10 s window; `length` = true frame count.
        let cfgData = try Data(contentsOf: URL(fileURLWithPath: "\(cfg.modelRoot)/config.json"))
        let cfgObj = try JSONSerialization.jsonObject(with: cfgData) as! [String: Any]
        let frontend = try MelFrontend(config: cfgObj, encoderMelFrames: models.encoderMelFrames)
        let t1 = Date()
        let (mel, frames) = try frontend.extract(wav.samples)
        let melSec = Date().timeIntervalSince(t1)
        print("mel: \(mel.shape), length(valid frames)=\(frames) = \(String(format: "%.2f", Double(frames) * 160 / 16000.0)) s (window \(models.encoderMelFrames) frames = \(models.encoderMelFrames * 160 / 16000) s) (\(String(format: "%.3f", melSec)) s)")

        // Encoder — mask is computed INSIDE the graph from `length`.
        let t2 = Date()
        let encOut = try run(models.encoder, [
            "audio_signal": MLFeatureValue(multiArray: mel),
            "length": MLFeatureValue(multiArray: try makeI32Scalar(frames)),
        ])
        guard let embeddings = encOut["encoder_embeddings"]?.multiArrayValue,
              let encMask = encOut["encoder_mask"]?.multiArrayValue else {
            print("FATAL: missing encoder outputs: \(encOut.keys)"); exit(3)
        }
        let encSec = Date().timeIntervalSince(t2)
        print("encoder out: \(embeddings.shape) mask \(encMask.shape) (valid \(frames) mel frames -> \(Int((Double(frames) / 8).rounded(.up))) encoded frames) (\(String(format: "%.3f", encSec)) s)")

        // Prompt from config: [7, 4, 16, src, tgt, 5, 9, 11, 13]
        guard let src = models.languageTokenIds[cfg.srcLang],
              let tgt = models.languageTokenIds[cfg.tgtLang] else {
            print("FATAL: unsupported lang \(cfg.srcLang)/\(cfg.tgtLang); known: \(models.languageTokenIds.keys.sorted())")
            exit(4)
        }
        var prompt = models.promptTemplate
        prompt[3] = src
        prompt[4] = tgt
        print("prompt(\(cfg.task) \(cfg.srcLang)->\(cfg.tgtLang)): \(prompt.map { models.vocab[$0] ?? "?" }.joined(separator: " "))")

        // Prefill: whole prompt against an empty cache.
        let t3 = Date()
        var output = try run(models.prefill, [
            "input_ids": MLFeatureValue(multiArray: try makeI32(prompt)),
            "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
            "encoder_mask": MLFeatureValue(multiArray: encMask),
        ])
        guard output["logits"]?.multiArrayValue != nil else {
            print("FATAL: missing prefill logits: \(output.keys)"); exit(5)
        }
        let prefillSec = Date().timeIntervalSince(t3)

        // Greedy decode loop.
        var stepTimes: [Double] = []
        var tokens: [Int] = []
        var scoreSum: Double = 0
        var stoppedByEOS = false
        let t4 = Date()
        for _ in 0..<cfg.maxTokens {
            guard let logits = output["logits"]?.multiArrayValue,
                  let cache = output["decoder_hidden_states"]?.multiArrayValue else {
                print("FATAL: missing decode outputs: \(output.keys)"); exit(6)
            }
            let (best, score) = argmax(logits, vocab: 5248)
            scoreSum += Double(score)
            if best == models.eosId { stoppedByEOS = true; break }
            tokens.append(best)
            let cacheLength = cache.shape[2].intValue
            let st = Date()
            output = try run(models.step, [
                "input_ids": MLFeatureValue(multiArray: try makeI32([best])),
                "decoder_mems": MLFeatureValue(multiArray: cache),
                "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
                "encoder_mask": MLFeatureValue(multiArray: encMask),
                "start_pos": MLFeatureValue(multiArray: try makeI32Scalar(cacheLength)),
            ])
            stepTimes.append(Date().timeIntervalSince(st))
        }
        let decodeSec = Date().timeIntervalSince(t4)

        let text = decode(vocab: models.vocab, tokens: tokens)
        let confidence: Float = tokens.isEmpty ? 0 : Float(exp(scoreSum / Double(tokens.count)))
        let avgStep = stepTimes.isEmpty ? 0 : stepTimes.reduce(0, +) / Double(stepTimes.count)
        let maxStep = stepTimes.max() ?? 0

        print("\n=== RESULT (task=\(cfg.task), src=\(cfg.srcLang) tgt=\(cfg.tgtLang), compute=\(cfg.compute)) ===")
        print("transcript: \(text)")
        print("tokens generated: \(tokens.count), EOS: \(stoppedByEOS), confidence: \(String(format: "%.3f", confidence))")
        print("timing: load=\(String(format: "%.2f", loadSec))s mel=\(String(format: "%.3f", melSec))s enc=\(String(format: "%.3f", encSec))s prefill=\(String(format: "%.3f", prefillSec))s decode=\(String(format: "%.2f", decodeSec))s")
        print("decoder step: avg=\(String(format: "%.3f", avgStep))s max=\(String(format: "%.3f", maxStep))s (\(tokens.count + 1) calls incl. prefill)")
        print("RTFx (decode only, \(String(format: "%.2f", durationSec)) s audio): \(String(format: "%.1f", durationSec / decodeSec))x")
        print("footprint: \(footprintBytes() / 1024 / 1024) MiB")
    }
}
