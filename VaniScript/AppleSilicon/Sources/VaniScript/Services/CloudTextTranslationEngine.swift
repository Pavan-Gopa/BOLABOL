import Foundation
import VaniScriptCore

struct ActiveCloudTranslationProvider: Equatable, Sendable {
    var id: String
    var label: String
    var model: String
    var apiKey: String

    static func resolve(settings: AppSettings, providerID: String) -> ActiveCloudTranslationProvider? {
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmedProvider {
        case "gemini-cloud":
            let key = settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ActiveCloudTranslationProvider(
                id: "gemini-cloud",
                label: "Gemini Cloud",
                model: "gemini-2.5-flash",
                apiKey: key
            )
        case "gpt-cloud":
            let key = settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ActiveCloudTranslationProvider(
                id: "gpt-cloud",
                label: "GPT Cloud",
                model: "gpt-4o-mini",
                apiKey: key
            )
        default:
            return nil
        }
    }
}

actor CloudTextTranslationEngine {
    enum CloudTranslationError: LocalizedError {
        case invalidEndpoint
        case emptyResponse(provider: String)
        case unusableResponse(provider: String, detail: String)
        case requestFailed(provider: String, status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Cloud translation endpoint is invalid."
            case let .emptyResponse(provider):
                return "\(provider) returned no usable translation text."
            case let .unusableResponse(provider, detail):
                return "\(provider) returned no usable translation text. \(detail)"
            case let .requestFailed(provider, status, body):
                let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty
                    ? "\(provider) translation failed with HTTP \(status)."
                    : "\(provider) translation failed with HTTP \(status): \(message)"
            }
        }
    }

    func translate(
        text: String,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        provider: ActiveCloudTranslationProvider,
        promptPresets: [String: PromptPresetSettings] = [:]
    ) async throws -> String {
        let prompt = NativeLLMPromptBuilder.translationPrompt(
            text: text,
            targetLang: targetLang,
            metadata: metadata,
            glossary: glossary,
            promptPresets: promptPresets
        )
        let raw = try await generate(prompt: prompt, provider: provider)
        let cleaned = ModelOutputSanitizer.sanitizeTranslation(raw, targetLang: targetLang)
        guard !cleaned.isEmpty else {
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: "The model response was not accepted as translation text. Response preview: \(preview(raw))."
            )
        }
        return cleaned
    }

    func translateCues(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        provider: ActiveCloudTranslationProvider,
        promptPresets: [String: PromptPresetSettings] = [:]
    ) async throws -> [TranscriptCue] {
        guard !cues.isEmpty else { return [] }

        var translated: [TranscriptCue] = []
        let batches = NativeLLMPromptBuilder.cueTranslationBatches(cues, maxSourceCharacters: 2_200)
        for batch in batches {
            let prompt = NativeLLMPromptBuilder.cueBatchTranslationPrompt(
                cues: batch,
                targetLang: targetLang,
                metadata: metadata,
                glossary: glossary,
                promptPresets: promptPresets
            )
            let raw = try await generate(prompt: prompt, provider: provider)
            translated += try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(raw, sourceCues: batch)
        }
        return translated
    }

    func planShorts(
        transcript: String,
        count: Int,
        minDurationSec: Int,
        maxDurationSec: Int,
        outputLanguage: String,
        speakerName: String?,
        mode: ShortsPlanLanguageMode,
        existingClips: [ShortsClipPlan] = [],
        provider: ActiveCloudTranslationProvider
    ) async throws -> [ShortsClipPlan] {
        let prompt = ShortsPlanner.buildPrompt(
            transcript: transcript,
            count: count,
            minDurationSec: minDurationSec,
            maxDurationSec: maxDurationSec,
            outputLanguage: outputLanguage,
            speakerName: speakerName,
            mode: mode,
            existingClips: existingClips
        )
        // Pass nil so Gemini uses the model default output budget (matching the
        // Electron build), because dense multi-clip caption plans can exceed 8k tokens.
        let raw = try await generate(prompt: prompt, provider: provider, maxOutputTokens: nil)
        return try ShortsPlanner.parsePlanResponse(raw)
    }

    private func generate(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = 8192
    ) async throws -> String {
        switch provider.id {
        case "gemini-cloud":
            return try await generateGemini(prompt: prompt, provider: provider, maxOutputTokens: maxOutputTokens)
        case "gpt-cloud":
            return try await generateOpenAI(prompt: prompt, provider: provider)
        default:
            throw CloudTranslationError.emptyResponse(provider: provider.label)
        }
    }

    private func generateGemini(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = 8192
    ) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: provider.apiKey)]
        guard let url = components?.url else { throw CloudTranslationError.invalidEndpoint }

        let body = GeminiGenerateContentRequest(
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: prompt)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.2,
                maxOutputTokens: maxOutputTokens,
                responseMimeType: "text/plain"
            )
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, provider: provider.label)
        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let text = decoded.candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: geminiEmptyResponseDetail(decoded, rawData: data)
            )
        }
        return text
    }

    private func generateOpenAI(prompt: String, provider: ActiveCloudTranslationProvider) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw CloudTranslationError.invalidEndpoint
        }
        let body = OpenAIChatCompletionRequest(
            model: provider.model,
            temperature: 0.2,
            messages: [
                OpenAIMessage(
                    role: "system",
                    content: "You are VaniScript's translation engine. Return only the requested translation output, with no commentary."
                ),
                OpenAIMessage(role: "user", content: prompt),
            ]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, provider: provider.label)
        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let text = decoded.choices
            .map(\.message.content)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudTranslationError.emptyResponse(provider: provider.label) }
        return text
    }

    private func validate(response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudTranslationError.requestFailed(provider: provider, status: http.statusCode, body: body)
        }
    }

    private func geminiEmptyResponseDetail(_ response: GeminiGenerateContentResponse, rawData: Data) -> String {
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
}

private struct GeminiGenerateContentRequest: Encodable {
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

private struct GeminiGenerationConfig: Encodable {
    var temperature: Double
    var maxOutputTokens: Int?
    var responseMimeType: String
}

private struct GeminiContent: Codable {
    var role: String?
    var parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    var text: String?
}

private struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]?
    var promptFeedback: GeminiPromptFeedback?
}

private struct GeminiCandidate: Decodable {
    var content: GeminiContent?
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

private struct OpenAIChatCompletionRequest: Encodable {
    var model: String
    var temperature: Double
    var messages: [OpenAIMessage]
}

private struct OpenAIMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    var message: OpenAIMessage
}
