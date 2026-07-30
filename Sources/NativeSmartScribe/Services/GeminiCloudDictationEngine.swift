import AVFoundation
import Foundation
import NativeSmartScribeCore

/// First stage of cloud dictation: record → convert to 16 kHz mono WAV → Gemini
/// → faithful, lightly cleaned Raw text.
///
/// Variant 1/2 are intentionally performed later as a separate text-only request.
/// Uses inline audio for ordinary dictation and the Files API for larger recordings.
/// Model id is taken from Settings → API Providers → Google (never overridden to an older Flash).
struct GeminiCloudDictationEngine: Sendable {
    let apiKey: String
    let modelID: String

    /// Only used when the Google text-model field is empty.
    static let preferredDefaultModel = APIProviderKind.google.defaultTextModel

    /// Uses the user-selected Google model as-is, stripping any provider prefix.
    static func resolvedModelID(_ configured: String) -> String {
        var trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slashIndex = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[trimmed.index(after: slashIndex)...])
        }
        return trimmed.isEmpty ? preferredDefaultModel : trimmed
    }

    struct DictationRequest: Sendable {
        var audioFileURL: URL
        var forceTargetLanguage: Bool
        var targetLanguageName: String
    }

    struct DictationResult: Sendable {
        var text: String
        var diagnostics: EngineDiagnostics
    }

    enum DictationError: LocalizedError {
        case missingAPIKey
        case cannotReadAudio
        case exportFailed(String)
        case emptyResponse
        case audioNotUnderstood(String)
        case apiError(status: Int, message: String)
        case invalidEndpoint
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Google API key is missing. Settings → API Providers → Google Gemini."
            case .cannotReadAudio:
                "Could not read the recorded audio file."
            case .exportFailed(let detail):
                "Could not prepare audio for Gemini: \(detail)"
            case .emptyResponse:
                "Gemini returned an empty result."
            case .audioNotUnderstood(let sample):
                "Gemini did not use the audio (placeholder reply). Pick a current Flash model in API Providers → Google. Sample: \(sample)"
            case .apiError(let status, let message):
                message.isEmpty
                    ? "Gemini failed (HTTP \(status))."
                    : "Gemini failed (HTTP \(status)): \(message)"
            case .invalidEndpoint:
                "Invalid Gemini endpoint."
            case .uploadFailed(let detail):
                "Gemini file upload failed: \(detail)"
            }
        }
    }

    func dictate(_ request: DictationRequest) async throws -> DictationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DictationError.missingAPIKey }

        let model = Self.resolvedModelID(modelID)
        let startedAt = Date()

        // 1) Convert CAF → 16 kHz mono PCM WAV (what Gemini STT-style paths handle best).
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartscribe-gemini-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try Self.convertToGeminiWAV(source: request.audioFileURL, destination: wavURL)
        let audioData = try Data(contentsOf: wavURL)
        guard audioData.count > 1000 else {
            throw DictationError.cannotReadAudio
        }

        NativeSmartScribeLog.transcription.info(
            "Gemini dictation prepare model=\(model, privacy: .public) wavBytes=\(audioData.count) source=\(request.audioFileURL.lastPathComponent, privacy: .public)"
        )

        let instruction = CloudRawTranscriptionPrompt.instruction(
            forceTargetLanguage: request.forceTargetLanguage,
            targetLanguageName: request.targetLanguageName
        )

        let response: GeminiResponse

        // For audio <= 12 MB (almost all dictation clips), use direct inlineData (fast & 100% reliable)
        if audioData.count <= 12 * 1024 * 1024 {
            let base64 = audioData.base64EncodedString()
            response = try await generateWithInlineData(
                apiKey: key,
                model: model,
                base64Audio: base64,
                mimeType: "audio/wav",
                instruction: instruction
            )
        } else {
            // For large files > 12 MB, upload via Files API
            let uploaded = try await uploadFile(
                apiKey: key,
                data: audioData,
                mimeType: "audio/wav",
                displayName: "smartscribe-dictation.wav"
            )

            response = try await generateWithFile(
                apiKey: key,
                model: model,
                fileURI: uploaded.uri,
                mimeType: "audio/wav",
                instruction: instruction
            )

            Task {
                try? await self.deleteFile(apiKey: key, name: uploaded.name)
            }
        }

        var cleaned = ModelOutputSanitizer.sanitize(response.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = Self.stripLeadingHallucinatedIntro(cleaned)
        if cleaned.hasPrefix("[NO_SPEECH]") || cleaned == "[NO_SPEECH]" {
            cleaned = ""
        }
        if !cleaned.isEmpty {
            // Flash Lite can return a faithful transcript while ignoring individual cleanup
            // instructions. Keep Raw fast and deterministic by applying the existing local,
            // rule-based light cleanup instead of spending another cloud request.
            cleaned = SpeechCleanupNormalizer.normalize(cleaned, mode: .lightCleanup)
        }
        guard !cleaned.isEmpty else { throw DictationError.emptyResponse }

        if Self.looksLikeAudioNotReceived(cleaned) {
            throw DictationError.audioNotUnderstood(String(cleaned.prefix(200)))
        }

        return DictationResult(
            text: cleaned,
            diagnostics: EngineDiagnostics(
                backendName: "Google Gemini \(model)",
                loadTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                promptTokens: response.promptTokens,
                completionTokens: response.completionTokens
            )
        )
    }

    static func looksLikeAudioNotReceived(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "please provide an audio",
            "please provide audio",
            "provide an audio recording",
            "no audio was",
            "no audio provided",
            "attach an audio",
            "upload an audio",
            "i cannot hear",
            "i can't hear",
            "i did not receive",
            "didn't receive any audio",
            "quick brown fox jumps over the lazy dog",
            "lorem ipsum"
        ]
        return needles.contains { lower.contains($0) }
    }

    /// Models sometimes invent an English “YouTube intro” before the real transcript
    /// Drop leading Latin-only sentences when the rest of the result is mostly Cyrillic.
    static func stripLeadingHallucinatedIntro(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let hasCyrillic = trimmed.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        guard hasCyrillic else { return trimmed }

        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return trimmed }

        var dropCount = 0
        for part in parts {
            let cyr = part.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
            let lat = part.range(of: "[A-Za-z]", options: .regularExpression) != nil
            if lat && !cyr {
                dropCount += 1
                continue
            }
            break
        }
        guard dropCount > 0, dropCount < parts.count else { return trimmed }

        let keepStart = parts[dropCount]
        if let range = trimmed.range(of: keepStart) {
            return String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // MARK: - Files API upload

    private struct UploadedFile {
        var name: String
        var uri: String
    }

    /// Resumable upload (simple single-request path for files under ~20 MB).
    private func uploadFile(
        apiKey: String,
        data: Data,
        mimeType: String,
        displayName: String
    ) async throws -> UploadedFile {
        guard let startURL = URL(
            string: "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)"
        ) else {
            throw DictationError.invalidEndpoint
        }

        var start = URLRequest(url: startURL)
        start.httpMethod = "POST"
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: [
            "file": ["display_name": displayName]
        ])

        let (_, startResponse) = try await URLSession.shared.data(for: start)
        guard let http = startResponse as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let uploadURLString = http.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString)
        else {
            throw DictationError.uploadFailed("Could not start resumable upload.")
        }

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        upload.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        upload.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        upload.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        upload.httpBody = data
        upload.timeoutInterval = 45

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: upload)
        let status = (uploadResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let msg = String(data: uploadData, encoding: .utf8) ?? ""
            throw DictationError.uploadFailed("HTTP \(status) \(msg)")
        }

        guard let object = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any] else {
            throw DictationError.uploadFailed("Unexpected upload response (not JSON).")
        }
        let fileObj = object["file"] as? [String: Any]
        let uri = fileObj?["uri"] as? String ?? object["uri"] as? String
        let name = fileObj?["name"] as? String ?? object["name"] as? String
        guard let uri, let name else {
            let snippet = String(data: uploadData, encoding: .utf8) ?? ""
            throw DictationError.uploadFailed("Unexpected upload response: \(snippet.prefix(300))")
        }

        try await waitUntilFileActive(apiKey: apiKey, name: name)
        return UploadedFile(name: name, uri: uri)
    }

    private func waitUntilFileActive(apiKey: String, name: String) async throws {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/\(name)?key=\(apiKey)"
        ) else { return }

        for _ in 0..<30 {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(status),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let state = (object["state"] as? String) ?? ""
                if state == "ACTIVE" || state.isEmpty {
                    return
                }
                if state == "FAILED" {
                    throw DictationError.uploadFailed("File processing failed on Google side.")
                }
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func deleteFile(apiKey: String, name: String) async throws {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/\(name)?key=\(apiKey)"
        ) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - generateContent (inlineData & fileData)

    private struct GeminiResponse {
        var text: String
        var promptTokens: Int?
        var completionTokens: Int?
    }

    private func generateWithInlineData(
        apiKey: String,
        model: String,
        base64Audio: String,
        mimeType: String,
        instruction: String
    ) async throws -> GeminiResponse {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw DictationError.invalidEndpoint }

        // VaniScript native contract: text prompt first, then inline_data (snake_case), temperature 0.0
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": instruction
                        ],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Audio
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let message = Self.errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            NativeSmartScribeLog.transcription.error(
                "Gemini generateContent (inline) HTTP \(status) model=\(model, privacy: .public) \(message, privacy: .public)"
            )
            throw DictationError.apiError(status: status, message: message)
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictationError.emptyResponse
        }

        if let feedback = object["promptFeedback"] as? [String: Any],
           let block = feedback["blockReason"] as? String,
           !block.isEmpty {
            throw DictationError.apiError(
                status: status,
                message: "Blocked (\(block)): \(feedback["blockReasonMessage"] as? String ?? "")"
            )
        }

        let text = Self.extractText(from: object)
        let usage = object["usageMetadata"] as? [String: Any]
        return GeminiResponse(
            text: text,
            promptTokens: usage?["promptTokenCount"] as? Int,
            completionTokens: usage?["candidatesTokenCount"] as? Int
        )
    }

    private func generateWithFile(
        apiKey: String,
        model: String,
        fileURI: String,
        mimeType: String,
        instruction: String
    ) async throws -> GeminiResponse {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw DictationError.invalidEndpoint }

        // VaniScript native contract: text prompt first, then file_data (snake_case), temperature 0.0
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": instruction
                        ],
                        [
                            "file_data": [
                                "mime_type": mimeType,
                                "file_uri": fileURI
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let message = Self.errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            NativeSmartScribeLog.transcription.error(
                "Gemini generateContent (file) HTTP \(status) model=\(model, privacy: .public) \(message, privacy: .public)"
            )
            throw DictationError.apiError(status: status, message: message)
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictationError.emptyResponse
        }

        if let feedback = object["promptFeedback"] as? [String: Any],
           let block = feedback["blockReason"] as? String,
           !block.isEmpty {
            throw DictationError.apiError(
                status: status,
                message: "Blocked (\(block)): \(feedback["blockReasonMessage"] as? String ?? "")"
            )
        }

        let text = Self.extractText(from: object)
        let usage = object["usageMetadata"] as? [String: Any]
        return GeminiResponse(
            text: text,
            promptTokens: usage?["promptTokenCount"] as? Int,
            completionTokens: usage?["candidatesTokenCount"] as? Int
        )
    }

    private static func extractText(from object: [String: Any]) -> String {
        guard let candidates = object["candidates"] as? [[String: Any]] else { return "" }
        var chunks: [String] = []
        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let text = part["text"] as? String {
                    chunks.append(text)
                }
            }
        }
        return chunks.joined(separator: "\n")
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    // MARK: - CAF / any → 16 kHz mono 16-bit WAV

    /// Convert app recordings to a small 16 kHz mono 16-bit WAV that Gemini handles well.
    ///
    /// Recordings can be multichannel (e.g. a 4-channel aggregate input where only some
    /// channels carry the microphone signal). Letting CoreAudio downmix such a discrete
    /// layout to mono can cancel the signal to digital silence, which makes Gemini
    /// hallucinate filler ("the, the, the…"). To stay robust we pick the single loudest
    /// source channel and convert only that channel — no CoreAudio channel downmix runs.
    static func convertToGeminiWAV(source: URL, destination: URL) throws {
        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: source)
        } catch {
            throw DictationError.exportFailed(
                "Cannot open recording (\(error.localizedDescription))."
            )
        }

        let sourceFormat = inputFile.processingFormat
        let sourceChannel = loudestSourceChannel(in: source, format: sourceFormat)

        guard let monoSourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DictationError.exportFailed("Could not create mono source format.")
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw DictationError.exportFailed("Could not create 16 kHz mono format.")
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

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let outputFile = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // Mono float @ source rate → Int16 mono @ 16 kHz. This converter only resamples
        // and changes the sample format; it never changes channel count, so no downmix
        // cancellation can occur.
        guard let converter = AVAudioConverter(from: monoSourceFormat, to: outputFormat) else {
            throw DictationError.exportFailed("AVAudioConverter unavailable for this recording.")
        }

        try convertFileLoop(
            inputFile: inputFile,
            outputFile: outputFile,
            converter: converter,
            sourceFormat: sourceFormat,
            monoSourceFormat: monoSourceFormat,
            outputFormat: outputFormat,
            sourceChannel: sourceChannel
        )

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 1000 else {
            throw DictationError.exportFailed("WAV too small after conversion (\(size) bytes).")
        }

        NativeSmartScribeLog.transcription.info(
            "Gemini WAV conversion complete: sourceFrames=\(inputFile.length) sourceChannels=\(Int(sourceFormat.channelCount)) usedChannel=\(sourceChannel) wavBytes=\(size)"
        )
    }

    /// Index of the source channel with the most energy. Multichannel mic inputs often
    /// carry speech on only one or two channels; scanning keeps the audible one instead
    /// of averaging in silent (or out-of-phase) channels that would cancel the signal.
    private static func loudestSourceChannel(in source: URL, format: AVAudioFormat) -> Int {
        let channelCount = Int(format.channelCount)
        guard channelCount > 1 else { return 0 }

        guard let scanner = try? AVAudioFile(forReading: source) else { return 0 }

        // Scan at most ~8 seconds to keep this cheap even for long recordings.
        let scanLimit = AVAudioFramePosition(format.sampleRate * 8)
        let totalFrames = min(scanner.length, scanLimit)
        guard totalFrames > 0 else { return 0 }

        let chunk: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return 0 }

        var energy = [Float](repeating: 0, count: channelCount)
        var scanned: AVAudioFramePosition = 0
        while scanned < totalFrames {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunk), totalFrames - scanned))
            guard (try? scanner.read(into: buffer, frameCount: toRead)) != nil else { break }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channelData = buffer.floatChannelData else { break }
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                var sum: Float = 0
                for frame in 0..<frames {
                    let value = samples[frame]
                    sum += value * value
                }
                energy[channel] += sum
            }
            scanned += AVAudioFramePosition(frames)
        }

        var best = 0
        for channel in 1..<channelCount where energy[channel] > energy[best] {
            best = channel
        }
        return best
    }

    private static func convertFileLoop(
        inputFile: AVAudioFile,
        outputFile: AVAudioFile,
        converter: AVAudioConverter,
        sourceFormat: AVAudioFormat,
        monoSourceFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        sourceChannel: Int
    ) throws {
        let capacity: AVAudioFrameCount = 8192
        let channelCount = Int(sourceFormat.channelCount)

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoSourceFormat, frameCapacity: capacity) else {
            throw DictationError.exportFailed("Input buffer alloc failed.")
        }

        // Only needed when the source has more than one channel; we copy the chosen
        // channel into `monoBuffer` ourselves instead of letting CoreAudio downmix.
        var multichannelBuffer: AVAudioPCMBuffer?
        if channelCount > 1 {
            guard let multi = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else {
                throw DictationError.exportFailed("Input buffer alloc failed.")
            }
            multichannelBuffer = multi
        }

        let ratio = outputFormat.sampleRate / max(monoSourceFormat.sampleRate, 1)
        let outputCapacity = AVAudioFrameCount(Double(capacity) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw DictationError.exportFailed("Output buffer alloc failed.")
        }

        final class ConversionState: @unchecked Sendable {
            var isAtEnd = false
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
            let remaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
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
                state.isAtEnd = true
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        while !state.isAtEnd {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                throw DictationError.exportFailed(error.localizedDescription)
            }
            if status == .error {
                throw DictationError.exportFailed("Audio conversion error.")
            }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            if status == .endOfStream {
                break
            }
        }
    }
}
