// Canary-1B-v2 Core ML spike harness (Bolabol B6 spike, pure Swift, no Python).
//
// Usage:
//   CanarySpike <audio.wav> [task=asr|ast] [src=en] [tgt=fr] [modelRoot=dir]
//
// NOTE: the alexwengg/canary-1b-v2-coreml .mlmodelc bundles are internally
// inconsistent: metadata.json describes an fp32 spec-8 export (1501 mel frames,
// 188 encoder frames, 256 decoder seq) while model.mil/coremldata.bin are the
// fp16 iOS-17 export (1401 mel frames, 176 encoder frames, 128 decoder seq).
// This harness follows the EXECUTABLE contract (model.mil):
//
//   preprocessor: (audio_signal fp16 [1,224000], length fp16 [1])
//                 -> (audio_features fp16 [1,128,1401], audio_features_length int32 [1])
//   encoder:      (audio_features fp16 [1,128,1401], audio_lengths fp16 [1])
//                 -> (encoder_output fp16 [1,1024,176], encoded_lengths int32 [1])
//   decoder:      (input_ids int32 [1,128], decoder_mask int32 [1,128],
//                  encoder_embeddings fp16 [1,176,1024], encoder_mask int32 [1,176])
//                 -> (hidden_states fp16 [1,128,1024])
//
// 14 s window (224000 samples @ 16 kHz), 128 decoder steps, EOS=3, PAD=0.
// Prompt: [7, 4, 16, src, tgt, 5, 9, 11, 13].

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
    let projectionWeights: [Float]
    let projectionBias: [Float]
    let vocab: [Int: String]

    static func load(root: String) throws -> CanaryModels {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let pre = try MLModel(contentsOf: URL(fileURLWithPath: "\(root)/canary_preprocessor.mlmodelc"), configuration: config)
        let enc = try MLModel(contentsOf: URL(fileURLWithPath: "\(root)/canary_encoder.mlmodelc"), configuration: config)
        let dec = try MLModel(contentsOf: URL(fileURLWithPath: "\(root)/canary_decoder.mlmodelc"), configuration: config)
        print("preprocessor in: \(pre.modelDescription.inputDescriptionsByName.keys)")
        print("preprocessor out: \(pre.modelDescription.outputDescriptionsByName.keys)")
        print("encoder in: \(enc.modelDescription.inputDescriptionsByName.keys)")
        print("encoder out: \(enc.modelDescription.outputDescriptionsByName.keys)")
        print("decoder in: \(dec.modelDescription.inputDescriptionsByName.keys)")
        print("decoder out: \(dec.modelDescription.outputDescriptionsByName.keys)")

        let wData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/assets/projection_weights.bin"))
        let bData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/assets/projection_bias.bin"))
        let weights = wData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let bias = bData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        print("projection weights: \(weights.count) (expect 16777216), bias: \(bias.count) (expect 16384)")

        let vocabData = try Data(contentsOf: URL(fileURLWithPath: "\(root)/assets/vocab.json"))
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
                            projectionWeights: weights, projectionBias: bias,
                            vocab: vocab)
    }
}

// MARK: - MLMultiArray helpers

func makeF16(_ values: [Float16]) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .float16)
    let u = values.map { $0.bitPattern }
    memcpy(a.dataPointer, u, u.count * MemoryLayout<UInt16>.stride)
    return a
}

func makeF16Scalar(_ v: Float) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1], dataType: .float16)
    var u = Float16(v).bitPattern
    memcpy(a.dataPointer, &u, MemoryLayout<UInt16>.stride)
    return a
}

func makeInt32(_ values: [Int]) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
    for (i, v) in values.enumerated() { a[i] = NSNumber(value: v) }
    return a
}

func makeInt32Scalar(_ v: Int) throws -> MLMultiArray {
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

/// Transpose fp16 [1, D, T] -> fp16 [1, T, D] via raw buffer copies.
func transposeF16(_ src: MLMultiArray, D: Int, T: Int) throws -> MLMultiArray {
    let out = try MLMultiArray(shape: [1, NSNumber(value: T), NSNumber(value: D)], dataType: .float16)
    let s = src.dataPointer.bindMemory(to: UInt16.self, capacity: D * T)
    let d = out.dataPointer.bindMemory(to: UInt16.self, capacity: T * D)
    for t in 0..<T {
        for dim in 0..<D {
            d[t * D + dim] = s[dim * T + t]
        }
    }
    return out
}

/// Read one fp16 row [D] as [Float].
func rowF16(_ arr: MLMultiArray, index: Int, count: Int) -> [Float] {
    let s = arr.dataPointer.bindMemory(to: UInt16.self, capacity: arr.count)
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        out[i] = Float(Float16(bitPattern: s[index * count + i]))
    }
    return out
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
struct CanarySpike {
    static func main() async throws {
        let cfg = parseArgs(CommandLine.arguments)
        guard !cfg.audioPath.isEmpty else {
            print("usage: CanarySpike <audio.wav> [task=asr|ast] [src=en] [tgt=fr] [modelRoot=dir]")
            exit(1)
        }
        let t0 = Date()
        let models = try CanaryModels.load(root: cfg.modelRoot)
        let loadSec = Date().timeIntervalSince(t0)

        let wav = try readWav(path: cfg.audioPath)
        guard wav.sampleRate == 16000 else {
            print("FATAL: sample rate \(wav.sampleRate) != 16000")
            exit(2)
        }
        let audio = Array(wav.samples.prefix(224_000))
        let durationSec = Double(audio.count) / 16000.0
        print("audio: \(audio.count) samples, \(String(format: "%.2f", durationSec)) s @16 kHz mono")

        // 1) Preprocessor: pad/truncate to the fixed 14 s window [1,224000]
        let t1 = Date()
        let padded = audio + Array(repeating: Float(0), count: max(0, 224_000 - audio.count))
        let audioF16 = padded.map { Float16($0) }
        let preOut = try run(models.preprocessor, [
            "audio_signal": MLFeatureValue(multiArray: try makeF16(audioF16)),
            "length": MLFeatureValue(multiArray: try makeF16Scalar(Float(audio.count))),
        ])
        guard let features = preOut["audio_features"]?.multiArrayValue,
              let featuresLen = preOut["audio_features_length"]?.multiArrayValue else {
            print("FATAL: missing preprocessor outputs: \(preOut.keys)"); exit(3)
        }
        let preSec = Date().timeIntervalSince(t1)
        print("preprocessor out: \(features.shape) length=\(featuresLen[0].intValue) (\(String(format: "%.3f", preSec)) s)")

        // 2) Encoder
        let t2 = Date()
        let encOut = try run(models.encoder, [
            "audio_features": MLFeatureValue(multiArray: features),
            "audio_lengths": MLFeatureValue(multiArray: try makeF16Scalar(Float(audio.count))),
        ])
        guard let encFeat = encOut["encoder_output"]?.multiArrayValue else {
            print("FATAL: missing encoder output: \(encOut.keys)"); exit(4)
        }
        let encSec = Date().timeIntervalSince(t2)
        // encoded_lengths output is broken in this export (raw fp16 bits, e.g.
        // 4992 for 250 mel frames). Derive the valid encoder frames from the
        // (correct) preprocessor length instead: mel/8.
        let encLen = max(1, (featuresLen[0].intValue + 7) / 8)
        print("encoder out: \(encFeat.shape) encoded_lengths_out=\(encOut["encoded_lengths"]?.multiArrayValue?[0].intValue ?? -1) derived=\(encLen) (\(String(format: "%.3f", encSec)) s)")

        let T = encFeat.shape[2].intValue
        let encEmb = try transposeF16(encFeat, D: encFeat.shape[1].intValue, T: T)
        print("encoder_embeddings transposed: \(encEmb.shape)")

        // 3) Decoder greedy loop (real ids from canary-1b-v2 vocab.json)
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
        var tokens: [Int] = [7, 4, 16, src, tgt, 5, 9, 11, 13]
        print("prompt: \(tokens.map { models.vocab[$0] ?? "?" }.joined(separator: " "))")

        let seqLen = 128
        let validEncFrames = min(max(encLen, 0), T)
        let encMask = try MLMultiArray(shape: [1, NSNumber(value: T)], dataType: .int32)
        for i in 0..<T { encMask[i] = i < validEncFrames ? 1 : 0 }

        let t3 = Date()
        var stepTimes: [Double] = []
        var generated: [Int] = []
        var stoppedByEOS = false
        for _ in 0..<(seqLen - tokens.count) {
            let st = Date()
            var padded = tokens
            var mask = [Int](repeating: 1, count: tokens.count)
            if padded.count < seqLen {
                padded.append(contentsOf: Array(repeating: 0, count: seqLen - padded.count))
                mask.append(contentsOf: Array(repeating: 0, count: seqLen - tokens.count))
            }
            let decOut = try run(models.decoder, [
                "input_ids": MLFeatureValue(multiArray: try makeInt32(padded)),
                "decoder_mask": MLFeatureValue(multiArray: try makeInt32(mask)),
                "encoder_embeddings": MLFeatureValue(multiArray: encEmb),
                "encoder_mask": MLFeatureValue(multiArray: encMask),
            ])
            guard let hidden = decOut["hidden_states"]?.multiArrayValue else {
                print("FATAL: missing decoder output: \(decOut.keys)"); exit(6)
            }
            let readIdx = tokens.count - 1
            let lastHidden = rowF16(hidden, index: readIdx, count: 1024)
            var logits = models.projectionBias
            models.projectionWeights.withUnsafeBufferPointer { w in
                lastHidden.withUnsafeBufferPointer { h in
                    // W is row-major [1024,16384]; y[o] = sum_i W[i][o] * x[i]
                    cblas_sgemv(CblasRowMajor, CblasTrans,
                                Int32(1024), Int32(16384),
                                1.0, w.baseAddress!, Int32(16384),
                                h.baseAddress!, 1,
                                1.0, &logits, 1)
                }
            }
            var best = 0
            var bestVal = -Float.infinity
            for i in 0..<16384 where logits[i] > bestVal {
                bestVal = logits[i]; best = i
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

        print("\n=== RESULT (task=\(cfg.task), src=\(cfg.srcLang) tgt=\(cfg.tgtLang)) ===")
        print("transcript: \(text)")
        print("tokens generated: \(generated.count), EOS: \(stoppedByEOS)")
        print("timing: load=\(String(format: "%.2f", loadSec))s pre=\(String(format: "%.3f", preSec))s enc=\(String(format: "%.3f", encSec))s decode=\(String(format: "%.2f", decSec))s")
        print("decoder step: avg=\(String(format: "%.3f", avgStep))s max=\(String(format: "%.3f", maxStep))s (full 128-seq recompute per step, no KV cache)")
        print("RTFx decode: \(String(format: "%.1f", durationSec / decSec))x")
        print("footprint: \(footprintBytes() / 1024 / 1024) MiB")
    }
}
