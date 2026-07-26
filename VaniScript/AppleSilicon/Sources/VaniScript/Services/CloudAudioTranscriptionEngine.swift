import Foundation
import VaniScriptCore

struct ActiveCloudTranscriptionProvider: Equatable, Sendable {
    var id: String
    var label: String
    var model: String
    var apiKey: String

    static func resolve(settings: AppSettings, providerID: String) -> ActiveCloudTranscriptionProvider? {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "gemini-cloud":
            let key = settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ActiveCloudTranscriptionProvider(
                id: "gemini-cloud",
                label: "Gemini Cloud",
                // A4 (§9.2): Gemini transcription uses the user-selected text model
                // (same generateContent endpoint); hardcode fallback for empty settings.
                model: Self.resolvedModel(settings.geminiTextModel, fallback: "gemini-2.5-flash"),
                apiKey: key
            )
        case "gpt-cloud":
            let key = settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ActiveCloudTranscriptionProvider(
                id: "gpt-cloud",
                label: "GPT Cloud",
                // A4: OpenAI transcription is a dedicated audio model (whisper-1); it is
                // not the settings *text* model, so the audio hardcode stays until an
                // audio-model picker lands (A5).
                model: "whisper-1",
                apiKey: key
            )
        default:
            return nil
        }
    }

    // A4: trim the settings value and fall back to the engine's previous hardcode when
    // the user never picked a model (migration-safe: empty settings → old behavior).
    private static func resolvedModel(_ configured: String, fallback: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct CloudAudioTranscriptionResult: Sendable {
    var text: String
    var cues: [TranscriptCue]
    // A2 (§8.1): token counters parsed from the provider response, or nil when the
    // provider returned none (e.g. whisper without a usage block). Best-effort — the
    // transcription result is valid regardless of whether usage was captured.
    var usage: TokenUsage? = nil
}

actor CloudAudioTranscriptionEngine {
    enum CloudTranscriptionError: LocalizedError {
        case invalidEndpoint
        case cannotReadAudio(URL)
        case emptyResponse(provider: String)
        case unusableResponse(provider: String, detail: String)
        case requestFailed(provider: String, status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Cloud transcription endpoint is invalid."
            case let .cannotReadAudio(url):
                return "Could not read audio chunk for cloud transcription: \(url.lastPathComponent)."
            case let .emptyResponse(provider):
                return "\(provider) returned no usable transcription text."
            case let .unusableResponse(provider, detail):
                return "\(provider) returned no usable transcription text. \(detail)"
            case let .requestFailed(provider, status, body):
                let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty
                    ? "\(provider) transcription failed with HTTP \(status)."
                    : "\(provider) transcription failed with HTTP \(status): \(message)"
            }
        }
    }

    func transcribe(
        audioURL: URL,
        sourceLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        provider: ActiveCloudTranscriptionProvider,
        promptPresets: [String: PromptPresetSettings],
        chunkStartSec: Double,
        chunkEndSec: Double
    ) async throws -> CloudAudioTranscriptionResult {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.cannotReadAudio(audioURL)
        }

        let prompt = transcriptionPrompt(
            sourceLang: sourceLang,
            metadata: metadata,
            glossary: glossary,
            promptPresets: promptPresets,
            chunkStartSec: chunkStartSec,
            chunkEndSec: chunkEndSec
        )
        let raw: String
        // A2: usage is parsed alongside the transcript text and attached to the result.
        let usage: TokenUsage?
        switch provider.id {
        case "gemini-cloud":
            (raw, usage) = try await transcribeWithGemini(
                audioData: audioData,
                fileName: audioURL.lastPathComponent,
                mimeType: mimeType(for: audioURL),
                prompt: prompt,
                provider: provider
            )
        case "gpt-cloud":
            (raw, usage) = try await transcribeWithOpenAI(
                audioData: audioData,
                fileName: audioURL.lastPathComponent,
                mimeType: mimeType(for: audioURL),
                prompt: prompt,
                sourceLang: sourceLang,
                provider: provider
            )
        default:
            throw CloudTranscriptionError.emptyResponse(provider: provider.label)
        }

        return try parse(rawText: raw, provider: provider, usage: usage, chunkStartSec: chunkStartSec, chunkEndSec: chunkEndSec)
    }

    private func transcriptionPrompt(
        sourceLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings],
        chunkStartSec: Double,
        chunkEndSec: Double
    ) -> String {
        let targetLanguage = normalizedLanguageLabel(sourceLang)
        let metadataBlock = """
        Date: \(metadata.date.isEmpty ? "Unknown" : metadata.date)
        Location: \(metadata.location.isEmpty ? "Unknown" : metadata.location)
        Lecturer: \(metadata.lecturer.isEmpty ? "Unknown" : metadata.lecturer)
        Participants: \(metadata.participants.isEmpty ? "None" : metadata.participants)
        """
        let userPrompt = DefaultPrompts.render(
            id: "transcriptionUser",
            promptPresets: promptPresets,
            variables: [
                "translationInstruction": "Do not translate in this step.",
                "speakerHint": metadata.lecturer.isEmpty ? "Unknown" : metadata.lecturer,
                "metadataBlock": metadataBlock,
                "requestedFormats": "timestamped TXT",
                "translatedTxtExample": "",
            ]
        )
        let systemPrompt = DefaultPrompts.activeText(id: "transcriptionSystem", promptPresets: promptPresets)
        let glossaryText = glossaryBlock(glossary)

        return """
        \(systemPrompt)

        Prompt Settings guidance:
        \(userPrompt)

        Native VaniScript cloud transcription contract:
        - Transcribe only the attached audio chunk.
        - Return only the original-language transcript. Do not translate.
        - Source language: \(targetLanguage).
        - Output one cue per line, formatted exactly as "[MM:SS] text".
        - Timestamps must be relative to this chunk, starting at 00:00.
        - Keep cue length readable for karaoke review, usually 2-8 seconds per cue.
        - Do not output [ORIGINAL_TXT] tags, markdown, commentary, summaries, or explanations.
        - If the custom prompt above conflicts with this output format, this native contract wins.

        Chunk absolute time range: \(formatTimestamp(chunkStartSec))-\(formatTimestamp(chunkEndSec)).

        Metadata:
        \(metadataBlock)

        Glossary spellings to preserve:
        \(glossaryText.isEmpty ? "No glossary entries." : glossaryText)
        """
    }

    private func transcribeWithGemini(
        audioData: Data,
        fileName: String,
        mimeType: String,
        prompt: String,
        provider: ActiveCloudTranscriptionProvider
    ) async throws -> (text: String, usage: TokenUsage?) {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: provider.apiKey)]
        guard let url = components?.url else { throw CloudTranscriptionError.invalidEndpoint }

        let body = GeminiAudioGenerateContentRequest(
            contents: [
                GeminiAudioContent(
                    role: "user",
                    parts: [
                        GeminiAudioPart(text: prompt, inlineData: nil),
                        GeminiAudioPart(
                            text: nil,
                            inlineData: GeminiInlineAudioData(
                                mimeType: mimeType,
                                data: audioData.base64EncodedString()
                            )
                        ),
                    ]
                )
            ],
            generationConfig: GeminiAudioGenerationConfig(
                temperature: 0.0,
                maxOutputTokens: 8192,
                responseMimeType: "text/plain"
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, provider: provider.label)
        // A2: best-effort usage capture from the raw Gemini response. Never throws.
        let usage = UsageRecorder.parseGeminiUsage(from: data)
        let decoded = try JSONDecoder().decode(GeminiAudioGenerateContentResponse.self, from: data)
        let text = decoded.candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw CloudTranscriptionError.unusableResponse(
                provider: provider.label,
                detail: geminiEmptyResponseDetail(decoded, rawData: data)
            )
        }
        return (text, usage)
    }

    private func transcribeWithOpenAI(
        audioData: Data,
        fileName: String,
        mimeType: String,
        prompt: String,
        sourceLang: String,
        provider: ActiveCloudTranscriptionProvider
    ) async throws -> (text: String, usage: TokenUsage?) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw CloudTranscriptionError.invalidEndpoint
        }

        var fields = [
            "model": provider.model,
            "prompt": prompt,
            "response_format": "json",
            "temperature": "0",
        ]
        if let languageCode = isoLanguageCode(sourceLang) {
            fields["language"] = languageCode
        }

        let boundary = "VaniScript-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            fields: fields,
            fileFieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            fileData: audioData,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, provider: provider.label)
        // A2: some OpenAI-compatible transcription models return a `usage` block
        // (e.g. gpt-4o-transcribe); classic whisper-1 does not → nil. Never throws.
        let usage = UsageRecorder.parseOpenAIUsage(from: data)
        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudTranscriptionError.emptyResponse(provider: provider.label) }
        return (text, usage)
    }

    private func parse(
        rawText: String,
        provider: ActiveCloudTranscriptionProvider,
        usage: TokenUsage?,
        chunkStartSec: Double,
        chunkEndSec: Double
    ) throws -> CloudAudioTranscriptionResult {
        let cleaned = cleanTranscriptionText(rawText)
        guard !cleaned.isEmpty else {
            throw CloudTranscriptionError.unusableResponse(
                provider: provider.label,
                detail: "The model response was not accepted as transcript text. Response preview: \(preview(rawText))."
            )
        }

        let timestampedCues = SessionState.reconstructCuesFromTimestampedText(
            cleaned,
            startSec: chunkStartSec,
            endSec: chunkEndSec
        )
        if !timestampedCues.isEmpty {
            let text = timestampedCues.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return CloudAudioTranscriptionResult(text: text, cues: timestampedCues, usage: usage)
        }

        let text = SessionState
            .strippingInlineTimestampMarkers(cleaned)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CloudTranscriptionError.emptyResponse(provider: provider.label)
        }
        return CloudAudioTranscriptionResult(
            text: text,
            cues: SessionState.reconstructCuesFromRawText(text, startSec: chunkStartSec, endSec: chunkEndSec),
            usage: usage
        )
    }

    private func cleanTranscriptionText(_ rawText: String) -> String {
        var text = ModelOutputSanitizer.sanitizeTranscript(rawText)
        if let section = extractTaggedSection("ORIGINAL_TXT", from: text) {
            text = section
        }
        text = text.replacingOccurrences(of: #"(?is)\[/?(?:ORIGINAL|TRANSLATED)_[A-Z_]+\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?im)^\s*(?:original transcript|transcript|transcription)\s*:\s*"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTaggedSection(_ tag: String, from text: String) -> String? {
        let pattern = #"(?is)\[\#(tag)\]\s*([\s\S]*?)\s*\[/\#(tag)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudTranscriptionError.requestFailed(provider: provider, status: http.statusCode, body: body)
        }
    }

    private func geminiEmptyResponseDetail(_ response: GeminiAudioGenerateContentResponse, rawData: Data) -> String {
        var details: [String] = []
        if let blockReason = response.promptFeedback?.blockReason, !blockReason.isEmpty {
            details.append("Prompt blocked: \(blockReason).")
        }
        if let blockMessage = response.promptFeedback?.blockReasonMessage, !blockMessage.isEmpty {
            details.append(blockMessage)
        }
        if let candidates = response.candidates, !candidates.isEmpty {
            let finishReasons = candidates.compactMap(\.finishReason).filter { !$0.isEmpty }
            if !finishReasons.isEmpty {
                details.append("Finish reason: \(finishReasons.joined(separator: ", ")).")
            }
            let blockedSafety = candidates
                .flatMap { $0.safetyRatings ?? [] }
                .filter { $0.blocked == true }
                .compactMap(\.category)
            if !blockedSafety.isEmpty {
                details.append("Safety blocked categories: \(blockedSafety.joined(separator: ", ")).")
            }
        } else {
            details.append("Gemini returned no candidates.")
        }
        if let raw = String(data: rawData, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            details.append("Raw response preview: \(preview(raw)).")
        }
        return details.isEmpty ? "Gemini returned an empty response body." : details.joined(separator: " ")
    }

    private func preview(_ text: String, maxLength: Int = 260) -> String {
        let compact = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maxLength else { return "\"\(compact)\"" }
        return "\"\(String(compact.prefix(maxLength)))...\""
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "aac":
            return "audio/aac"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private func normalizedLanguageLabel(_ sourceLang: String) -> String {
        let trimmed = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "auto" ? "auto-detect" : trimmed
    }

    private func isoLanguageCode(_ sourceLang: String) -> String? {
        let trimmed = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.count == 2 { return trimmed }
        switch trimmed {
        case "english":
            return "en"
        case "russian":
            return "ru"
        case "spanish":
            return "es"
        case "french":
            return "fr"
        case "german":
            return "de"
        default:
            return nil
        }
    }

    private func glossaryBlock(_ glossary: [GlossaryEntry]) -> String {
        glossary
            .filter(\.remember)
            .prefix(80)
            .map { entry in
                let variants = entry.variants.isEmpty ? "" : " variants: \(entry.variants.joined(separator: ", "))"
                return "- \(entry.source)\(variants)"
            }
            .joined(separator: "\n")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func multipartBody(
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private struct GeminiAudioGenerateContentRequest: Encodable {
    var contents: [GeminiAudioContent]
    var generationConfig: GeminiAudioGenerationConfig
}

private struct GeminiAudioGenerationConfig: Encodable {
    var temperature: Double
    var maxOutputTokens: Int
    var responseMimeType: String
}

private struct GeminiAudioContent: Codable {
    var role: String?
    var parts: [GeminiAudioPart]
}

private struct GeminiAudioPart: Codable {
    var text: String?
    var inlineData: GeminiInlineAudioData?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiInlineAudioData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiAudioGenerateContentResponse: Decodable {
    var candidates: [GeminiAudioCandidate]?
    var promptFeedback: GeminiPromptFeedback?
}

private struct GeminiAudioCandidate: Decodable {
    var content: GeminiAudioContent?
    var finishReason: String?
    var safetyRatings: [GeminiSafetyRating]?
}

private struct GeminiPromptFeedback: Decodable {
    var blockReason: String?
    var blockReasonMessage: String?
    var safetyRatings: [GeminiSafetyRating]?
}

private struct GeminiSafetyRating: Decodable {
    var category: String?
    var probability: String?
    var blocked: Bool?
}

private struct OpenAITranscriptionResponse: Decodable {
    var text: String
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
