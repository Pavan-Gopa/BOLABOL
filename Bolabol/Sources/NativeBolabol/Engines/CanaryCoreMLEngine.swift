import Accelerate
import AVFoundation
import CoreML
import Foundation
import NativeBolabolCore

// MARK: - CanaryCoreMLEngine

/// Core ML engine for Canary-family ASR models.
///
/// Supports two model variants under the `.canaryCoreML` backend:
/// - **Flash** (`canary-180m-flash-coreml`): int8, macOS 14+, 10 s window,
///   NeMo mel frontend, EN/DE/FR/ES ASR + AST.
/// - **1B Path B** (`canary-1b-v2-coreml`): int4 ANE, macOS 15+ (MLState),
///   15 s window, native NeMo-style mel frontend, EN ASR + EN→FR AST.
///
/// Spike constraints (authoritative):
/// - `.cpuAndNeuralEngine` only — `.all` crashes MPSGraph on Flash.
/// - Explicit language from `capabilities.supportedLanguageCodes`; no auto-detect.
/// - Audio longer than `capabilities.maxChunkSeconds` is segmented; no
///   cross-window context.
/// - 1B Path B requires macOS 15+ (stateful `MLState` decoder).
actor CanaryCoreMLEngine: TranscriptionEngine {
    nonisolated let id: String
    nonisolated let displayName: String

    private let model: TranscriptionModelDescriptor
    private let modelFolderURL: URL
    private var flashState: FlashState?
    private var pathBState: Any?

    private enum ModelVariant {
        case flash
        case pathB
    }

    private let variant: ModelVariant

    // MARK: - Init

    init(model: TranscriptionModelDescriptor, modelFolderURL: URL) {
        self.model = model
        self.modelFolderURL = modelFolderURL
        self.id = "canary-\(model.id)"
        self.displayName = "Canary Core ML/ANE (\(model.displayName))"

        switch model.id {
        case "canary-180m-flash-coreml":
            self.variant = .flash
        case "canary-1b-v2-coreml":
            self.variant = .pathB
        default:
            self.variant = .flash
        }
    }

    // MARK: - TranscriptionEngine

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let audioFileURL = request.audioFileURL else {
            throw CanaryTranscriptionError.missingAudioFile
        }

        try await validateOSRequirement()
        try await ensureLoaded()

        let samples = try await loadAudioSamples(from: audioFileURL)
        guard !samples.isEmpty else {
            throw CanaryTranscriptionError.emptyAudio
        }

        let maxChunkSamples = Int(model.capabilities.maxChunkSeconds * 16_000.0)
        let chunks = Self.chunk(samples: samples, maxSamples: maxChunkSamples)

        var allText = ""
        let startedAt = Date()

        for chunkSamples in chunks {
            let text: String
            switch variant {
            case .flash:
                text = try await transcribeFlash(chunkSamples, request: request)
            case .pathB:
                if #available(macOS 15.0, *) {
                    text = try await transcribePathB(chunkSamples, request: request)
                } else {
                    throw CanaryTranscriptionError.unsupportedOS(
                        required: ASRModelCapabilities.OSVersion(majorVersion: 15, minorVersion: 0),
                        current: ASRModelCapabilities.OSVersion(
                            majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                            minorVersion: ProcessInfo.processInfo.operatingSystemVersion.minorVersion,
                            patchVersion: ProcessInfo.processInfo.operatingSystemVersion.patchVersion
                        )
                    )
                }
            }
            allText += (allText.isEmpty ? "" : " ") + text
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let text = allText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CanaryTranscriptionError.emptyResult
        }

        return TranscriptionResult(
            text: text,
            diagnostics: EngineDiagnostics(
                backendName: displayName
            )
        )
    }

    // MARK: - OS Requirement

    private func validateOSRequirement() throws {
        if let minVersion = model.capabilities.minOSVersion {
            let current = ProcessInfo.processInfo.operatingSystemVersion
            let currentVersion = ASRModelCapabilities.OSVersion(
                majorVersion: current.majorVersion,
                minorVersion: current.minorVersion,
                patchVersion: current.patchVersion
            )
            guard currentVersion >= minVersion else {
                throw CanaryTranscriptionError.unsupportedOS(
                    required: minVersion,
                    current: currentVersion
                )
            }
        }
    }

    // MARK: - Model Loading

    private func ensureLoaded() async throws {
        switch variant {
        case .flash:
            if flashState == nil {
                flashState = try await FlashState.load(from: modelFolderURL)
            }
        case .pathB:
            if pathBState == nil {
                if #available(macOS 15.0, *) {
                    pathBState = try await PathBState.load(from: modelFolderURL)
                } else {
                    throw CanaryTranscriptionError.unsupportedOS(
                        required: ASRModelCapabilities.OSVersion(majorVersion: 15, minorVersion: 0),
                        current: ASRModelCapabilities.OSVersion(
                            majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                            minorVersion: ProcessInfo.processInfo.operatingSystemVersion.minorVersion,
                            patchVersion: ProcessInfo.processInfo.operatingSystemVersion.patchVersion
                        )
                    )
                }
            }
        }
    }

    // MARK: - Audio Loading

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("bolabol-canary-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWAV) }

        do {
            try GeminiCloudDictationEngine.convertTo16kMonoWAV(
                source: url,
                destination: tempWAV
            )
        } catch {
            throw CanaryTranscriptionError.audioPreparationFailed(error.localizedDescription)
        }

        return try readFloat32WAV(at: tempWAV)
    }

    private func readFloat32WAV(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count > 44,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            throw CanaryTranscriptionError.invalidWAV
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
            throw CanaryTranscriptionError.invalidWAV
        }

        let channels = Int(bytes[fmtOffset + 10]) | (Int(bytes[fmtOffset + 11]) << 8)
        let sampleRate = Int(bytes[fmtOffset + 12])
            | (Int(bytes[fmtOffset + 13]) << 8)
            | (Int(bytes[fmtOffset + 14]) << 16)
            | (Int(bytes[fmtOffset + 15]) << 24)
        let bits = Int(bytes[fmtOffset + 22]) | (Int(bytes[fmtOffset + 23]) << 8)
        let audioFormat = Int(bytes[fmtOffset + 8]) | (Int(bytes[fmtOffset + 9]) << 8)

        guard channels > 0, sampleRate == 16_000 else {
            throw CanaryTranscriptionError.invalidWAV
        }
        guard audioFormat == 1 && bits == 16 else {
            throw CanaryTranscriptionError.invalidWAV
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

    // MARK: - Chunking

    // Internal seam for unit testing engine audio chunking contracts (BLOCK-S9-004)
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

    // MARK: - Language Resolution

    // Internal seam for language validation contract testing (BLOCK-S9-002)
    internal func resolveLanguage(_ request: TranscriptionRequest) throws -> String {
        let supported = model.capabilities.supportedLanguageCodes
        guard !supported.isEmpty else {
            throw CanaryTranscriptionError.noSupportedLanguages
        }

        // Explicit language required — no auto-detect (S9 contract).
        // nil forcedLanguageCode (e.g. HUD A route) is an error, not a fallback.
        guard let forced = request.forcedLanguageCode else {
            throw CanaryTranscriptionError.unsupportedLanguage("nil (explicit language required)")
        }

        guard supported.contains(forced) else {
            throw CanaryTranscriptionError.unsupportedLanguage(forced)
        }

        return forced
    }

    // MARK: - Flash Transcription

    private func transcribeFlash(_ samples: [Float], request: TranscriptionRequest) async throws -> String {
        guard let state = flashState else {
            throw CanaryTranscriptionError.modelNotLoaded
        }

        let language = try resolveLanguage(request)
        let targetLanguage: String
        if request.translateToEnglish && model.capabilities.supportsSpeechTranslation {
            targetLanguage = "en"
        } else {
            targetLanguage = language
        }

        guard state.languageTokenIds[language] != nil else {
            throw CanaryTranscriptionError.unsupportedLanguage(language)
        }

        // Frontend: NeMo mel
        let melFrontend = state.melFrontend
        let (mel, frames) = try melFrontend.extract(samples)
        guard frames > 0 else {
            throw CanaryTranscriptionError.emptyAudio
        }

        // Encoder
        let encOut = try state.runEncoder(mel: mel, length: frames)
        guard let embeddings = encOut.embeddings, let encMask = encOut.mask else {
            throw CanaryTranscriptionError.encoderFailed
        }

        // Prompt: [7, 4, 16, src, tgt, 5, 9, 11, 13]
        var prompt = state.promptTemplate
        guard let srcID = state.languageTokenIds[language],
              let tgtID = state.languageTokenIds[targetLanguage] else {
            throw CanaryTranscriptionError.unsupportedLanguage(language)
        }
        prompt[3] = srcID
        prompt[4] = tgtID

        // Prefill
        var output = try state.runPrefill(
            inputIDs: prompt,
            embeddings: embeddings,
            mask: encMask
        )

        // Greedy decode
        var tokens: [Int] = []
        for _ in 0..<256 {
            guard let logits = output["logits"]?.multiArrayValue,
                  let cache = output["decoder_hidden_states"]?.multiArrayValue else {
                break
            }
            let (best, _) = argmax(logits, vocab: 5248)
            if best == state.eosId { break }
            tokens.append(best)
            let cacheLength = cache.shape[2].intValue
            output = try state.runDecoderStep(
                token: best,
                cache: cache,
                embeddings: embeddings,
                mask: encMask,
                startPos: cacheLength
            )
        }

        return decodeFlash(tokens: tokens, vocab: state.vocab)
    }

    private func decodeFlash(tokens: [Int], vocab: [Int: String]) -> String {
        var text = ""
        for t in tokens {
            guard let piece = vocab[t], !piece.hasPrefix("<|") else { continue }
            text += piece
        }
        return text.replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Path B Transcription

    @available(macOS 15.0, *)
    private func transcribePathB(_ samples: [Float], request: TranscriptionRequest) async throws -> String {
        guard let state = pathBState as? PathBState else {
            throw CanaryTranscriptionError.modelNotLoaded
        }

        let language = try resolveLanguage(request)
        let targetLanguage: String
        if request.translateToEnglish && model.capabilities.supportsSpeechTranslation {
            targetLanguage = "en"
        } else {
            targetLanguage = language
        }

        guard state.languageTokenIds[language] != nil else {
            throw CanaryTranscriptionError.unsupportedLanguage(language)
        }

        // Frontend: native NeMo-style mel (Path B)
        let (mel, frames) = try state.melFrontend.extract(samples)
        guard frames > 0 else {
            throw CanaryTranscriptionError.emptyAudio
        }

        // Encoder
        let encOut = try state.runEncoder(mel: mel, length: frames)
        guard let encStates = encOut.states, let _ = encOut.length else {
            throw CanaryTranscriptionError.encoderFailed
        }

        // Cross-attention KV
        let crossOut = try state.runCrossKV(states: encStates)
        guard let encK = crossOut.k, let encV = crossOut.v else {
            throw CanaryTranscriptionError.encoderFailed
        }

        // Language IDs for Path B
        let seed = [16053, 7, 4, 16,
                    state.languageTokenIds[language] ?? 64,
                    state.languageTokenIds[targetLanguage] ?? 64,
                    5, 9, 11, 13]

        // Fresh MLState per segment (macOS 15+)
        let mlState = try state.makeState()
        var output: [String: MLFeatureValue] = [:]
        var position = 0

        for token in seed {
            output = try state.runDecoderStep(
                state: mlState,
                token: token,
                position: position,
                encK: encK,
                encV: encV
            )
            position += 1
        }

        // Greedy decode
        var tokens: [Int] = []
        var repeatedCount = 0
        var previousToken: Int?
        for _ in 0..<256 {
            guard let logits = output["log_probs"]?.multiArrayValue else { break }
            let token = argmax(logits)
            if token == 3 { break }  // EOS
            if token == previousToken {
                repeatedCount += 1
                if repeatedCount >= 4 { break }
            } else {
                repeatedCount = 0
            }
            previousToken = token
            tokens.append(token)
            output = try state.runDecoderStep(
                state: mlState,
                token: token,
                position: position,
                encK: encK,
                encV: encV
            )
            position += 1
        }

        return state.decode(tokens: tokens)
    }

    // MARK: - Helpers

    private func argmax(_ logits: MLMultiArray, vocab: Int) -> (index: Int, score: Float) {
        let count = logits.count
        let offset = count - vocab
        var best = 0
        var bestScore: Float = -Float.infinity

        switch logits.dataType {
        case .float16:
            let ptr = logits.dataPointer.assumingMemoryBound(to: Float16.self)
            for i in 0..<vocab {
                let score = Float(ptr[offset + i])
                if score > bestScore { bestScore = score; best = i }
            }
        case .float32:
            let ptr = logits.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<vocab {
                let score = ptr[offset + i]
                if score > bestScore { bestScore = score; best = i }
            }
        default:
            for i in 0..<vocab {
                let score = Float(logits[offset + i].floatValue)
                if score > bestScore { bestScore = score; best = i }
            }
        }
        return (best, bestScore)
    }

    private func argmax(_ logits: MLMultiArray) -> Int {
        var best = 0
        var bestScore: Float = -Float.infinity
        for i in 0..<logits.count {
            let score = Float(logits[i].floatValue)
            if score > bestScore { bestScore = score; best = i }
        }
        return best
    }
}

// MARK: - Flash State

private extension CanaryCoreMLEngine {
    final class FlashState {
        let encoder: MLModel
        let prefill: MLModel
        let decoder: MLModel
        let vocab: [Int: String]
        let languageTokenIds: [String: Int]
        let promptTemplate: [Int]
        let eosId: Int
        let melFrontend: FlashMelFrontend

        init(
            encoder: MLModel,
            prefill: MLModel,
            decoder: MLModel,
            vocab: [Int: String],
            languageTokenIds: [String: Int],
            promptTemplate: [Int],
            eosId: Int,
            melFrontend: FlashMelFrontend
        ) {
            self.encoder = encoder
            self.prefill = prefill
            self.decoder = decoder
            self.vocab = vocab
            self.languageTokenIds = languageTokenIds
            self.promptTemplate = promptTemplate
            self.eosId = eosId
            self.melFrontend = melFrontend
        }

        static func load(from root: URL) async throws -> FlashState {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            func load(_ name: String) throws -> MLModel {
                let url = root.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw CanaryTranscriptionError.missingModelFile(name + ".mlmodelc")
                }
                return try MLModel(contentsOf: url, configuration: config)
            }

            let encoder = try load("CanaryEncoder")
            let prefill = try load("CanaryPrefill")
            let decoder = try load("CanaryDecoder")

            // config.json
            let configURL = root.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                throw CanaryTranscriptionError.missingModelFile("config.json")
            }
            let configData = try Data(contentsOf: configURL)
            guard let cfg = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                throw CanaryTranscriptionError.invalidModelConfig
            }

            let langs = cfg["languageTokenIds"] as? [String: Int] ?? [:]
            let special = cfg["specialTokenIds"] as? [String: Int] ?? [:]
            let coreml = cfg["coreml"] as? [String: Any] ?? [:]
            let encoderMelFrames = (coreml["encoderMelFrames"] as? Int) ?? 1000
            let promptIds = cfg["promptIds"] as? [String: [Int]]
            let template: [Int]
            if let first = promptIds?.values.first {
                template = first
            } else {
                template = [7, 4, 16, 0, 0, 5, 9, 11, 13]
            }
            guard let eos = special["eos"] else {
                throw CanaryTranscriptionError.invalidModelConfig
            }

            // vocab.json
            let vocabURL = root.appendingPathComponent("vocab.json")
            guard FileManager.default.fileExists(atPath: vocabURL.path) else {
                throw CanaryTranscriptionError.missingModelFile("vocab.json")
            }
            let vocabData = try Data(contentsOf: vocabURL)
            let vocabObj = try JSONSerialization.jsonObject(with: vocabData)
            var vocab: [Int: String] = [:]
            if let dict = vocabObj as? [String: String] {
                for (k, v) in dict {
                    guard let id = Int(k) else { continue }
                    vocab[id] = v
                }
            }

            let melFrontend = try FlashMelFrontend(config: cfg, encoderMelFrames: encoderMelFrames)

            return FlashState(
                encoder: encoder,
                prefill: prefill,
                decoder: decoder,
                vocab: vocab,
                languageTokenIds: langs,
                promptTemplate: template,
                eosId: eos,
                melFrontend: melFrontend
            )
        }

        func runEncoder(mel: MLMultiArray, length: Int) throws -> (embeddings: MLMultiArray?, mask: MLMultiArray?) {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "audio_signal": MLFeatureValue(multiArray: mel),
                "length": MLFeatureValue(multiArray: makeI32Scalar(length)),
            ])
            let out = try encoder.prediction(from: provider)
            return (
                embeddings: out.featureValue(for: "encoder_embeddings")?.multiArrayValue,
                mask: out.featureValue(for: "encoder_mask")?.multiArrayValue
            )
        }

        func runPrefill(inputIDs: [Int], embeddings: MLMultiArray, mask: MLMultiArray) throws -> [String: MLFeatureValue] {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: try makeI32(inputIDs)),
                "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
                "encoder_mask": MLFeatureValue(multiArray: mask),
            ])
            let out = try prefill.prediction(from: provider)
            var result: [String: MLFeatureValue] = [:]
            for name in out.featureNames { result[name] = out.featureValue(for: name) }
            return result
        }

        func runDecoderStep(
            token: Int,
            cache: MLMultiArray,
            embeddings: MLMultiArray,
            mask: MLMultiArray,
            startPos: Int
        ) throws -> [String: MLFeatureValue] {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: try makeI32([token])),
                "decoder_mems": MLFeatureValue(multiArray: cache),
                "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
                "encoder_mask": MLFeatureValue(multiArray: mask),
                "start_pos": MLFeatureValue(multiArray: makeI32Scalar(startPos)),
            ])
            let out = try decoder.prediction(from: provider)
            var result: [String: MLFeatureValue] = [:]
            for name in out.featureNames { result[name] = out.featureValue(for: name) }
            return result
        }
    }
}

// MARK: - Path B State

@available(macOS 15.0, *)
private extension CanaryCoreMLEngine {
    final class PathBState {
        let encoder: MLModel
        let crossKV: MLModel
        let decoderKV: MLModel
        let vocab: [Int: String]
        let languageTokenIds: [String: Int]
        let eosId: Int
        let melFrontend: PathBMelFrontend

        init(
            encoder: MLModel,
            crossKV: MLModel,
            decoderKV: MLModel,
            vocab: [Int: String],
            languageTokenIds: [String: Int],
            eosId: Int,
            melFrontend: PathBMelFrontend
        ) {
            self.encoder = encoder
            self.crossKV = crossKV
            self.decoderKV = decoderKV
            self.vocab = vocab
            self.languageTokenIds = languageTokenIds
            self.eosId = eosId
            self.melFrontend = melFrontend
        }

        static func load(from root: URL) async throws -> PathBState {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            func load(_ name: String) throws -> MLModel {
                let url = root.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw CanaryTranscriptionError.missingModelFile(name + ".mlmodelc")
                }
                return try MLModel(contentsOf: url, configuration: config)
            }

            let encoder = try load("canary_encoder")
            let crossKV = try load("canary_cross_kv")
            let decoderKV = try load("canary_decoder_kv")

            // Parse SentencePiece model for vocabulary
            let speURL = root.appendingPathComponent("canary_spe.model")
            guard FileManager.default.fileExists(atPath: speURL.path) else {
                throw CanaryTranscriptionError.missingModelFile("canary_spe.model")
            }
            let spePieces = try SentencePieceModel(url: speURL).pieces

            // Language token IDs (Path B uses the same Canary convention)
            let languageTokenIds: [String: Int] = [
                "en": 64, "fr": 71, "de": 78, "es": 171, "ru": 157
            ]
            let eosId = 3

            let melFrontend = try PathBMelFrontend()

            return PathBState(
                encoder: encoder,
                crossKV: crossKV,
                decoderKV: decoderKV,
                vocab: Dictionary(uniqueKeysWithValues: spePieces.enumerated().map { ($0.offset, $0.element) }),
                languageTokenIds: languageTokenIds,
                eosId: eosId,
                melFrontend: melFrontend
            )
        }

        func makeState() -> MLState {
            try! decoderKV.makeState()
        }

        func runEncoder(mel: MLMultiArray, length: Int) throws -> (states: MLMultiArray?, length: Int?) {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "mel": MLFeatureValue(multiArray: mel),
                "mel_length": MLFeatureValue(multiArray: makeI32Scalar(length)),
            ])
            let out = try encoder.prediction(from: provider)
            return (
                states: out.featureValue(for: "enc_states")?.multiArrayValue,
                length: out.featureValue(for: "encoder_length")?.multiArrayValue.map { Int($0[0].intValue) }
            )
        }

        func runCrossKV(states: MLMultiArray) throws -> (k: MLMultiArray?, v: MLMultiArray?) {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "enc_states": MLFeatureValue(multiArray: states),
            ])
            let out = try crossKV.prediction(from: provider)
            return (
                k: out.featureValue(for: "enc_k")?.multiArrayValue,
                v: out.featureValue(for: "enc_v")?.multiArrayValue
            )
        }

        func runDecoderStep(
            state: MLState,
            token: Int,
            position: Int,
            encK: MLMultiArray,
            encV: MLMultiArray
        ) throws -> [String: MLFeatureValue] {
            let selfMask = try makeSelfMask(position: position)
            let features: [String: MLFeatureValue] = [
                "enc_k": MLFeatureValue(multiArray: encK),
                "enc_v": MLFeatureValue(multiArray: encV),
                "pos": MLFeatureValue(multiArray: try CanaryCoreMLEngine.pathBDecoderPositionArray(position: position)),
                "self_mask": MLFeatureValue(multiArray: selfMask),
                "token": MLFeatureValue(multiArray: try makeI32([token])),
            ]
            let provider = try MLDictionaryFeatureProvider(dictionary: features)
            let out = try decoderKV.prediction(from: provider, using: state)
            var result: [String: MLFeatureValue] = [:]
            for name in out.featureNames { result[name] = out.featureValue(for: name) }
            return result
        }

        func decode(tokens: [Int]) -> String {
            let pieces = tokens.compactMap { vocab[$0] }.filter { !$0.hasPrefix("<|") }
            return pieces.joined()
                .replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func makeSelfMask(position: Int, capacity: Int = 238) throws -> MLMultiArray {
            let clamped = min(max(position, 0), capacity - 1)
            var mask = [Float](repeating: -10_000, count: capacity)
            for i in 0...clamped { mask[i] = 0 }
            return try makeFloatArray(mask, shape: [1, 1, 1, capacity])
        }
    }
}

// Internal product seam for the Path B decoder input contract. The verified
// S4b model requires `pos` as int32 shape [1], unlike the token's [1, 1].
extension CanaryCoreMLEngine {
    nonisolated internal static func pathBDecoderPositionArray(position: Int) throws -> MLMultiArray {
        try makeI32Scalar(position)
    }
}

// MARK: - Flash Mel Frontend (NeMo contract)

private struct FlashMelFrontend {
    let sampleRate: Int
    let numMelBins: Int
    let nFFT = 512
    let hopLength = 160
    let winLength = 400
    let preEmphasis = Float(0.97)
    let logGuard = Float(5.960464477539063e-08)
    let normEpsilon = Float(1e-5)
    let encoderMelFrames: Int

    private let log2FFT: vDSP_Length = 9
    private let nBins = 257
    private let centrePad = 256
    private let windowOffset = 56
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float]

    init(config: [String: Any], encoderMelFrames: Int) throws {
        guard let sr = config["sampleRate"] as? Int ?? (config["sampleRate"] as? Double).map({ Int($0) }),
              let bins = config["numMelBins"] as? Int ?? (config["numMelBins"] as? Double).map({ Int($0) }) else {
            throw CanaryTranscriptionError.invalidModelConfig
        }
        self.sampleRate = sr
        self.numMelBins = bins
        self.encoderMelFrames = encoderMelFrames
        guard let setup = vDSP_create_fftsetup(log2FFT, FFTRadix(kFFTRadix2)) else {
            throw CanaryTranscriptionError.frontendFailed("FFT setup failed")
        }
        self.fftSetup = setup
        var window = [Float](repeating: 0, count: winLength)
        for i in 0..<winLength {
            window[i] = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(winLength - 1)))
        }
        self.hannWindow = window
        self.melFilterbank = FlashMelFrontend.buildMelFilterbank(nMels: bins, nBins: nBins, sampleRate: sr)
    }

    func extract(_ audio: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        guard !audio.isEmpty else {
            throw CanaryTranscriptionError.emptyAudio
        }

        // Pre-emphasis
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

        // Centre padding
        var padded = [Float](repeating: 0, count: centrePad + emphasized.count + centrePad)
        for i in 0..<emphasized.count { padded[centrePad + i] = emphasized[i] }

        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        let frames = min(stftFrames, audio.count / hopLength)
        guard frames > 0 else {
            throw CanaryTranscriptionError.emptyAudio
        }
        let usable = min(frames, encoderMelFrames)

        let mel = try MLMultiArray(
            shape: [1, NSNumber(value: numMelBins), NSNumber(value: encoderMelFrames)],
            dataType: .float32
        )
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
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
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
                if hz >= left && hz <= centre {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre && hz <= right {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + m] = Float(weight * enorm)
            }
        }
        return bank
    }
}

// MARK: - Path B Mel Frontend (Native NeMo-style)

private struct PathBMelFrontend {
    private let sampleRate = 16_000
    private let numMelBins = 128
    private let nFFT = 512
    private let hopLength = 160
    private let winLength = 400
    private let centrePad = 256
    private let windowOffset = 56
    private let maxFrames = 1_501
    private let preEmphasis = Float(0.97)
    private let logGuard = Float(5.960464477539063e-08)
    private let normEpsilon = Float(1e-5)
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float]

    init() throws {
        guard let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else {
            throw CanaryTranscriptionError.frontendFailed("FFT setup failed")
        }
        fftSetup = setup
        hannWindow = (0..<400).map {
            0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / 399.0))
        }
        melFilterbank = PathBMelFrontend.buildMelFilterbank(
            nMels: numMelBins, nBins: nFFT / 2 + 1, sampleRate: sampleRate
        )
    }

    func extract(_ source: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        let audio = Array(source.prefix(240_000))
        guard !audio.isEmpty else { throw CanaryTranscriptionError.emptyAudio }

        var emphasized = [Float](repeating: 0, count: audio.count)
        emphasized[0] = audio[0]
        if audio.count > 1 {
            for i in 1..<audio.count {
                emphasized[i] = audio[i] - preEmphasis * audio[i - 1]
            }
        }

        // Reflect padding for Path B
        var padded = [Float](repeating: 0, count: audio.count + centrePad * 2)
        for i in 0..<audio.count { padded[centrePad + i] = emphasized[i] }
        if audio.count > centrePad + 1 {
            for i in 0..<centrePad {
                padded[centrePad - 1 - i] = emphasized[i + 1]
                padded[centrePad + audio.count + i] = emphasized[audio.count - 2 - i]
            }
        }

        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        let frames = min(stftFrames, maxFrames)
        guard frames > 0 else { throw CanaryTranscriptionError.emptyAudio }

        let mel = try MLMultiArray(
            shape: [1, NSNumber(value: numMelBins), NSNumber(value: maxFrames)],
            dataType: .float32
        )
        let melPointer = mel.dataPointer.bindMemory(to: Float.self, capacity: mel.count)
        for i in 0..<mel.count { melPointer[i] = 0 }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nFFT / 2 + 1)
        var melFrame = [Float](repeating: 0, count: numMelBins)

        for t in 0..<frames {
            for i in 0..<nFFT { frame[i] = 0 }
            let start = t * hopLength
            for i in 0..<winLength {
                frame[windowOffset + i] = padded[start + windowOffset + i] * hannWindow[i]
            }
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imagBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                    frame.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(nFFT / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, 9, FFTDirection(FFT_FORWARD))
                    let dc = split.realp[0] * 0.5
                    let nyquist = split.imagp[0] * 0.5
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
                                  out.baseAddress!, 1, 1, vDSP_Length(numMelBins),
                                  vDSP_Length(nFFT / 2 + 1))
                    }
                }
            }
            for bin in 0..<numMelBins {
                melPointer[bin * maxFrames + t] = log(melFrame[bin] + logGuard)
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
            for f in 0..<frames { mean += row[f] }
            mean /= Float(frames)
            var squaredDeviation: Float = 0
            for f in 0..<frames {
                let d = row[f] - mean
                squaredDeviation += d * d
            }
            let variance = squaredDeviation / Float(frames - 1)
            let scale = 1 / ((variance > 0 ? sqrt(variance) : 0) + normEpsilon)
            for f in 0..<frames { row[f] = (row[f] - mean) * scale }
        }
    }

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
            let enorm = right > left ? 2.0 / (right - left) : 0
            for bin in 0..<nBins {
                let hz = Double(bin) * binHz
                var weight = 0.0
                if hz >= left && hz <= centre {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre && hz <= right {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + m] = Float(weight * enorm)
            }
        }
        return bank
    }
}

// MARK: - SentencePiece Model Parser

private struct SentencePieceModel {
    let pieces: [String]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self.pieces = SentencePieceModel.parsePieces(from: data)
    }

    private static func parsePieces(from data: Data) -> [String] {
        var pieces: [String] = []
        var offset = 0
        let bytes = [UInt8](data)

        while offset < bytes.count {
            guard offset < bytes.count else { break }
            let (tag, afterTag) = readVarint(bytes, offset)
            guard afterTag > offset else { break }
            offset = afterTag

            let fieldNumber = tag >> 3
            let wireType = tag & 0x7

            if fieldNumber == 1 && wireType == 2 {
                // Length-delimited (Piece message)
                guard offset < bytes.count else { break }
                let (length, afterLength) = readVarint(bytes, offset)
                offset = afterLength
                let messageEnd = offset + length
                guard messageEnd <= bytes.count else { break }

                var pieceOffset = offset
                var piece: String?
                while pieceOffset < messageEnd {
                    guard pieceOffset < bytes.count else { break }
                    let (pTag, afterPTag) = readVarint(bytes, pieceOffset)
                    guard afterPTag > pieceOffset else { break }
                    pieceOffset = afterPTag

                    let pField = pTag >> 3
                    let pWire = pTag & 0x7

                    if pField == 1 && pWire == 2 {
                        guard pieceOffset < bytes.count else { break }
                        let (strLen, afterStrLen) = readVarint(bytes, pieceOffset)
                        pieceOffset = afterStrLen
                        guard pieceOffset + strLen <= bytes.count else { break }
                        piece = String(bytes: bytes[pieceOffset..<(pieceOffset + strLen)], encoding: .utf8)
                        pieceOffset += strLen
                    } else if pField == 2 && pWire == 5 {
                        pieceOffset += 4  // float
                    } else if pField == 3 && pWire == 0 {
                        let (_, afterVI) = readVarint(bytes, pieceOffset)
                        pieceOffset = afterVI
                    } else {
                        break
                    }
                }
                pieces.append(piece ?? "")
                offset = messageEnd
            } else if wireType == 0 {
                let (_, afterVI) = readVarint(bytes, offset)
                offset = afterVI
            } else if wireType == 2 {
                guard offset < bytes.count else { break }
                let (len, afterLen) = readVarint(bytes, offset)
                offset = afterLen + len
            } else if wireType == 5 {
                offset += 4
            } else {
                break
            }
        }
        return pieces
    }

    private static func readVarint(_ bytes: [UInt8], _ offset: Int) -> (Int, Int) {
        var result = 0
        var shift = 0
        var off = offset
        while off < bytes.count {
            let byte = Int(bytes[off])
            off += 1
            result |= (byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return (result, off) }
            shift += 7
        }
        return (result, off)
    }
}

// MARK: - MLMultiArray Helpers

private func makeI32(_ values: [Int]) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
    for (i, v) in values.enumerated() { a[i] = NSNumber(value: v) }
    return a
}

private func makeI32Scalar(_ v: Int) throws -> MLMultiArray {
    let a = try MLMultiArray(shape: [1], dataType: .int32)
    a[0] = NSNumber(value: v)
    return a
}

private func makeFloatArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
    _ = values.withUnsafeBufferPointer { buffer in
        memcpy(array.dataPointer, buffer.baseAddress!, values.count * MemoryLayout<Float>.stride)
    }
    return array
}

// MARK: - Errors

// Internal seam for unit testing engine error contracts (BLOCK-S9-004)
internal enum CanaryTranscriptionError: LocalizedError, Equatable {
    case missingAudioFile
    case emptyAudio
    case invalidWAV
    case audioPreparationFailed(String)
    case emptyResult
    case modelNotLoaded
    case missingModelFile(String)
    case invalidModelConfig
    case unsupportedOS(required: ASRModelCapabilities.OSVersion, current: ASRModelCapabilities.OSVersion)
    case unsupportedLanguage(String)
    case noSupportedLanguages
    case encoderFailed
    case frontendFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "Canary needs a recorded or imported audio file."
        case .emptyAudio:
            "The audio file contains no usable samples."
        case .invalidWAV:
            "The audio file is not a valid 16 kHz mono WAV."
        case .audioPreparationFailed(let detail):
            "Could not prepare audio for Canary: \(detail)"
        case .emptyResult:
            "Canary returned an empty transcription."
        case .modelNotLoaded:
            "The Canary model is not loaded. Please try again."
        case .missingModelFile(let name):
            "Canary model file missing: \(name). Download the model in Settings → Local Models."
        case .invalidModelConfig:
            "The Canary model configuration is invalid. Re-download the model."
        case .unsupportedOS(let required, let current):
            "Canary 1B requires macOS \(required.majorVersion).\(required.minorVersion) or later (current: \(current.majorVersion).\(current.minorVersion))."
        case .unsupportedLanguage(let code):
            "Language '\(code)' is not supported by this Canary model."
        case .noSupportedLanguages:
            "This Canary model has no supported languages configured."
        case .encoderFailed:
            "Canary encoder failed. Check that the model is complete."
        case .frontendFailed(let detail):
            "Canary audio frontend failed: \(detail)"
        }
    }
}
