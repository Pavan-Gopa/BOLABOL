// Canary-1B-v2 FluidInference Core ML spike harness (Bolabol S4 spike, pure Swift).
//
// Usage:
//   CanaryFluidSpike <audio.wav> [task=asr|ast] [src=en] [tgt=fr]
//                    [modelRoot=dir] [compute=all|ane|cpu] [maxTokens=120]
//
// Artifact under test: FluidInference/canary-1b-v2-coreml (int4 ANE export).
// Contracts verified at load time (MIL, model.mil headers):
//
//   Preprocessor (ios17, CPU): audio_signal fp32 [1,240000], audio_length int32 [1]
//                              -> processed fp32 [1,128,1501], processed_length int32 [1]
//   EncoderInt4   (ios18, ANE): features fp32 [1,128,1501], features_length int32 [1]
//                              -> encoder fp32 [1,1024,188], encoder_length int32 [1]
//   DecoderInt4   (ios18, ANE): input_ids int32 [1,256], decoder_mask fp32 [1,256],
//                              encoder_embeddings fp32 [1,188,1024], encoder_mask fp32 [1,188]
//                              -> decoder fp32 [1,256,1024]
//   Projection    (ios17, ANE): hidden fp32 [1,1024] -> logits fp32 [1,16384]
//
// 15 s window (240000 samples @ 16 kHz), 256 decoder steps, eos=3, pad=2, bos=4.
// Window/valid-length semantics: `audio_length` is the TRUE valid sample count
// for the current window (min(remaining source samples, window) after offset),
// never the padded buffer size. offset>=0: leading-silence chunk (clip starts at
// offset); offset<0: mid-clip chunk (skip |offset| source samples first). Padded
// zero samples beyond the valid count are filler only and never counted as valid.
// Prompt: [7, 4, 16, src, tgt, 5, 9, 11, 13]. Greedy argmax decode.
// No Python, no NeMo, no external tokenizer — vocab.json (id -> piece) only.

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
    var maxTokens = 120
    var encMaskMode = "derived"
    var offsetSamples = 0
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
        case "maxTokens": cfg.maxTokens = Int(kv[1]) ?? 120
        case "encMask": cfg.encMaskMode = String(kv[1])
        case "offset": cfg.offsetSamples = Int(kv[1]) ?? 0
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
        throw NSError(domain: "wav", code: 3, userInfo: [NSLocalizedDescriptionKey: "unsupported format \(audioFormat) (need PCM or IEEE float)"])
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

// MARK: - Model bundle

struct CanaryModels {
    let preprocessor: MLModel
    let encoder: MLModel
    let decoder: MLModel
    let projection: MLModel
    let vocab: [Int: String]

    static func computeUnits(_ name: String) -> MLComputeUnits {
        switch name {
        case "ane": return .cpuAndNeuralEngine
        case "cpu": return .cpuOnly
        default: return .all
        }
    }

    static func load(root: String, compute: String) throws -> CanaryModels {
        let units = computeUnits(compute)
        let config = MLModelConfiguration()
        config.computeUnits = units
        func load(_ name: String) throws -> MLModel {
            try MLModel(contentsOf: URL(fileURLWithPath: "\(root)/\(name).mlmodelc"), configuration: config)
        }
        let pre = try load("Preprocessor")
        let enc = try load("EncoderInt4")
        let dec = try load("DecoderInt4")
        let proj = try load("Projection")
        print("compute units: \(compute) -> \(units.rawValue)")
        print("preprocessor in: \(pre.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("preprocessor out: \(pre.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("encoder in: \(enc.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("encoder out: \(enc.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("decoder in: \(dec.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("decoder out: \(dec.modelDescription.outputDescriptionsByName.keys.sorted())")
        print("projection in: \(proj.modelDescription.inputDescriptionsByName.keys.sorted())")
        print("projection out: \(proj.modelDescription.outputDescriptionsByName.keys.sorted())")

        let vocabData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/vocab.json"))
        let obj = try JSONSerialization.jsonObject(with: vocabData)
        var vocab: [Int: String] = [:]
        if let dict = obj as? [String: String] {
            for (k, v) in dict {
                guard let id = Int(k) else { continue }
                vocab[id] = v
            }
        }
        print("vocab entries: \(vocab.count)")
        return CanaryModels(preprocessor: pre, encoder: enc, decoder: dec,
                            projection: proj, vocab: vocab)
    }
}

// MARK: - MLMultiArray helpers

func makeF32(_ values: [Float]) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .float32)
    memcpy(a.dataPointer, values, values.count * MemoryLayout<Float>.stride)
    return a
}

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

/// Transpose fp32 [1, D, T] -> fp32 [1, T, D].
func transposeF32(_ src: MLMultiArray, D: Int, T: Int) throws -> MLMultiArray {
    let out = try MLMultiArray(shape: [1, NSNumber(value: T), NSNumber(value: D)], dataType: .float32)
    let s = src.dataPointer.bindMemory(to: Float.self, capacity: D * T)
    let d = out.dataPointer.bindMemory(to: Float.self, capacity: T * D)
    for t in 0..<T {
        for dim in 0..<D {
            d[t * D + dim] = s[dim * T + t]
        }
    }
    return out
}

/// Read one fp32 row [count] at index.
func rowF32(_ arr: MLMultiArray, index: Int, count: Int) -> [Float] {
    let s = UnsafeBufferPointer<Float>(start: arr.dataPointer.bindMemory(to: Float.self, capacity: arr.count), count: arr.count)
    let start = index * count
    return Array(s[start..<(start + count)])
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
struct CanaryFluidSpike {
    static func main() async throws {
        let cfg = parseArgs(CommandLine.arguments)
        guard !cfg.audioPath.isEmpty else {
            print("usage: CanaryFluidSpike <audio.wav> [task=asr|ast] [src=en] [tgt=fr] [modelRoot=dir] [compute=all|ane|cpu] [maxTokens=n] [encMask=derived|all] [offset=n]")
            exit(1)
        }
        let t0 = Date()
        let models = try CanaryModels.load(root: cfg.modelRoot, compute: cfg.compute)
        let loadSec = Date().timeIntervalSince(t0)

        let wav = try readWav(path: cfg.audioPath)
        guard wav.sampleRate == 16000 else {
            print("FATAL: sample rate \(wav.sampleRate) != 16000")
            exit(2)
        }
        let rawCount = wav.samples.count
        // Window semantics (chunking/offset simulation):
        //   offset >= 0: clip samples are placed starting at `offset` in the
        //                15 s window (leading-silence chunk). Valid audio =
        //                min(remaining clip samples, window - offset).
        //   offset < 0:  the first |offset| clip samples are skipped (mid-clip
        //                chunk). Valid audio = min(remaining clip samples, window).
        // Zero-padding beyond validSamples is only filler to satisfy the fixed
        // [1,240000] input shape and is NEVER counted as valid audio.
        let windowSize = 240_000
        var audio = [Float](repeating: 0, count: windowSize)
        let validSamples: Int
        if cfg.offsetSamples >= 0 {
            validSamples = min(max(0, rawCount), max(0, windowSize - cfg.offsetSamples))
            if validSamples > 0 {
                audio.replaceSubrange(cfg.offsetSamples..<(cfg.offsetSamples + validSamples),
                                      with: wav.samples[0..<validSamples])
            }
        } else {
            let skip = min(-cfg.offsetSamples, rawCount)
            let remain = rawCount - skip
            validSamples = min(max(0, remain), windowSize)
            if validSamples > 0 {
                audio.replaceSubrange(0..<validSamples, with: wav.samples[skip..<(skip + validSamples)])
            }
        }
        let durationSec = Double(rawCount) / 16000.0
        print("audio: \(rawCount) samples on disk, audio_length(valid)=\(validSamples) fed into \(windowSize)-sample window at offset \(cfg.offsetSamples) (\(String(format: "%.2f", durationSec)) s on disk, \(String(format: "%.2f", Double(validSamples) / 16000.0)) s valid)")

        // 1) Preprocessor: pad/truncate to the fixed 15 s window [1,240000]
        let t1 = Date()
        let preOut = try run(models.preprocessor, [
            "audio_signal": MLFeatureValue(multiArray: try makeF32(audio)),
            "audio_length": MLFeatureValue(multiArray: try makeI32Scalar(validSamples)),
        ])
        guard let features = preOut["processed"]?.multiArrayValue,
              let featuresLen = preOut["processed_length"]?.multiArrayValue else {
            print("FATAL: missing preprocessor outputs: \(preOut.keys)"); exit(3)
        }
        let preSec = Date().timeIntervalSince(t1)
        print("preprocessor out: \(features.shape) processed_length=\(featuresLen[0].intValue) (audio_length=\(validSamples) -> \(String(format: "%.2f", Double(validSamples) / 16000.0)) s valid) (\(String(format: "%.3f", preSec)) s)")

        // 2) Encoder
        let t2 = Date()
        let encOut = try run(models.encoder, [
            "features": MLFeatureValue(multiArray: features),
            "features_length": MLFeatureValue(multiArray: featuresLen),
        ])
        guard let encFeat = encOut["encoder"]?.multiArrayValue else {
            print("FATAL: missing encoder output: \(encOut.keys)"); exit(4)
        }
        let encLenOut = encOut["encoder_length"]?.multiArrayValue?[0].intValue ?? -1
        let encSec = Date().timeIntervalSince(t2)
        let T = encFeat.shape[2].intValue
        print("encoder out: \(encFeat.shape) encoder_length=\(encLenOut) (mel/8 ceil: \((featuresLen[0].intValue + 7) / 8), valid=\(validSamples)) (\(String(format: "%.3f", encSec)) s)")

        let encEmb = try transposeF32(encFeat, D: encFeat.shape[1].intValue, T: T)
        print("encoder_embeddings transposed: \(encEmb.shape)")

        // 3) Decoder greedy loop + Projection head
        // Language ids from vocab.json (ISO-639-1 tokens at ids 24..206).
        let langIds: [String: Int] = [
            "en": 64, "fr": 71, "de": 78, "es": 171,
            "bg": 46, "hr": 58, "cs": 59, "da": 60, "nl": 62, "et": 66, "fi": 70,
            "el": 79, "hu": 89, "it": 99, "lv": 117, "lt": 120, "mt": 127, "pl": 150,
            "pt": 151, "ro": 154, "sk": 167, "sl": 168, "sv": 175, "ru": 157, "uk": 192,
        ]
        guard let src = langIds[cfg.srcLang], let tgt = langIds[cfg.tgtLang] else {
            print("FATAL: unsupported lang code \(cfg.srcLang)/\(cfg.tgtLang); known: \(langIds.keys.sorted())")
            exit(5)
        }
        let seqLen = 256
        var tokens: [Int] = [7, 4, 16, src, tgt, 5, 9, 11, 13]
        print("prompt: \(tokens.map { models.vocab[$0] ?? "?" }.joined(separator: " "))")

        let validEncFrames = max(1, min(encLenOut, T))
        let encMask = try MLMultiArray(shape: [1, NSNumber(value: T)], dataType: .float32)
        for i in 0..<T { encMask[i] = cfg.encMaskMode == "all" ? 1.0 : (i < validEncFrames ? 1.0 : 0.0) }
        print("encoder mask: \(cfg.encMaskMode) (valid \(validEncFrames)/\(T) frames, zeroed \(T - validEncFrames))")

        let t3 = Date()
        var stepTimes: [Double] = []
        var generated: [Int] = []
        var stoppedByEOS = false
        let cap = min(cfg.maxTokens, seqLen - tokens.count)
        for _ in 0..<cap {
            let st = Date()
            var padded = tokens
            var mask = [Float](repeating: 1.0, count: tokens.count)
            if padded.count < seqLen {
                padded.append(contentsOf: Array(repeating: 2, count: seqLen - padded.count)) // pad id 2
                mask.append(contentsOf: Array(repeating: 0.0, count: seqLen - tokens.count))
            }
            let decOut = try run(models.decoder, [
                "input_ids": MLFeatureValue(multiArray: try makeI32(padded)),
                "decoder_mask": MLFeatureValue(multiArray: try makeF32(mask)),
                "encoder_embeddings": MLFeatureValue(multiArray: encEmb),
                "encoder_mask": MLFeatureValue(multiArray: encMask),
            ])
            guard let hidden = decOut["decoder"]?.multiArrayValue else {
                print("FATAL: missing decoder output: \(decOut.keys)"); exit(6)
            }
            let readIdx = tokens.count - 1
            let lastHidden = rowF32(hidden, index: readIdx, count: 1024)
            let projOut = try run(models.projection, [
                "hidden": MLFeatureValue(multiArray: try makeF32(lastHidden)),
            ])
            guard let logits = projOut["logits"]?.multiArrayValue else {
                print("FATAL: missing projection output: \(projOut.keys)"); exit(7)
            }
            var best = 0
            var bestVal = -Float.infinity
            let lp = logits.dataPointer.bindMemory(to: Float.self, capacity: 16384)
            for i in 0..<16384 where lp[i] > bestVal {
                bestVal = lp[i]; best = i
            }
            stepTimes.append(Date().timeIntervalSince(st))
            if best == 3 { stoppedByEOS = true; break }
            tokens.append(best)
            generated.append(best)
        }
        let decSec = Date().timeIntervalSince(t3)

        let text = decode(vocab: models.vocab, tokens: generated)
        let avgStep = stepTimes.isEmpty ? 0 : stepTimes.reduce(0, +) / Double(stepTimes.count)
        let maxStep = stepTimes.max() ?? 0

        print("\n=== RESULT (task=\(cfg.task), src=\(cfg.srcLang) tgt=\(cfg.tgtLang), compute=\(cfg.compute)) ===")
        print("transcript: \(text)")
        print("tokens generated: \(generated.count), EOS: \(stoppedByEOS)")
        print("timing: load=\(String(format: "%.2f", loadSec))s pre=\(String(format: "%.3f", preSec))s enc=\(String(format: "%.3f", encSec))s decode=\(String(format: "%.2f", decSec))s")
        print("decoder step: avg=\(String(format: "%.3f", avgStep))s max=\(String(format: "%.3f", maxStep))s (full 256-seq recompute per step, no KV cache)")
        print("RTFx decode: \(String(format: "%.1f", durationSec / decSec))x")
        print("footprint: \(footprintBytes() / 1024 / 1024) MiB")
    }
}
