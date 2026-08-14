import Foundation
import VaniScriptCore

struct ActiveCloudTranslationProvider: Equatable, Sendable {
    var id: String
    var label: String
    var model: String
    var apiKey: String
    var apiKeys: [String] = []
    // A5: OpenAI-compatible routing for the new providers (Qwen/OpenRouter/Ollama
    // Cloud). `nil` endpoint = legacy hardcoded providers (gemini-cloud/gpt-cloud),
    // whose URLs stay inside the engine — behavior 1:1 with pre-A5.
    var endpoint: URL? = nil
    var headers: [String: String] = [:]

    var rotationKeys: [String] {
        let keys = apiKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !keys.isEmpty { return keys }
        let primary = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return primary.isEmpty ? [] : [primary]
    }

    static func resolve(settings: AppSettings, providerID: String) -> ActiveCloudTranslationProvider? {
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ProviderRegistry.isBudgetExceeded(providerID: trimmedProvider, settings: settings) else {
            return nil
        }
        switch trimmedProvider {
        case "gemini-cloud":
            let bank = settings.geminiKeyBank
            let keys = bank.enabledKeys
            guard let key = keys.first else { return nil }
            return ActiveCloudTranslationProvider(
                id: "gemini-cloud",
                label: "Gemini Cloud",
                // A4 (§9.2): use the user-selected model; fall back to the previous
                // hardcode when settings is empty so legacy behavior is unchanged.
                model: Self.resolvedModel(settings.geminiTextModel, fallback: "gemini-2.5-flash"),
                apiKey: key,
                apiKeys: keys
            )
        case "gpt-cloud":
            let key = settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ActiveCloudTranslationProvider(
                id: "gpt-cloud",
                label: "GPT Cloud",
                // A4 (§9.2): user-selected OpenAI model, hardcode fallback.
                model: Self.resolvedModel(settings.openaiTextModel, fallback: "gpt-4o-mini"),
                apiKey: key
            )
        default:
            // A5: Qwen / OpenRouter / Ollama Cloud resolve through the core
            // CloudChatRouter (base URL + settings model + key). Unknown ids or a
            // missing key still return nil, exactly like the legacy cases above.
            guard let route = CloudChatRouter.route(providerID: trimmedProvider, settings: settings) else {
                return nil
            }
            return ActiveCloudTranslationProvider(
                id: route.providerID,
                label: route.label,
                model: route.model,
                apiKey: route.apiKey,
                endpoint: route.endpoint,
                headers: route.headers
            )
        }
    }

    // A4: trim the settings value and fall back to the engine's previous hardcode when
    // the user never picked a model (migration-safe: empty settings → old behavior).
    private static func resolvedModel(_ configured: String, fallback: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum CloudTextTranslationResponseMode: Equatable, Sendable {
    case text
    case documentJSON
}

/// Pure request-body construction keeps provider contracts testable without
/// opening a network connection. The default `.text` mode deliberately omits
/// structured-output fields so media/chat/Shorts requests retain their former
/// payload shape.
enum CloudTextTranslationRequestBuilder {
    static func isGemini3(model: String?) -> Bool {
        guard let model = model?.lowercased() else { return false }
        return model.contains("gemini-3") || model.contains("gemini-v3")
    }

    static func geminiBody(
        prompt: String,
        model: String? = nil,
        maxOutputTokens: Int? = nil,
        responseMode: CloudTextTranslationResponseMode = .text
    ) throws -> Data {
        let isDoc = responseMode == .documentJSON
        let isG3 = isGemini3(model: model)

        let resolvedTokens: Int?
        if isDoc {
            if isG3 {
                resolvedTokens = max(maxOutputTokens ?? 32_768, 32_768)
            } else {
                resolvedTokens = maxOutputTokens ?? 8_192
            }
        } else {
            resolvedTokens = maxOutputTokens
        }

        let thinkingConfig = (isDoc && isG3) ? GeminiThinkingConfig(thinkingLevel: "LOW") : nil

        let body = GeminiGenerateContentRequest(
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: prompt)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.2,
                maxOutputTokens: resolvedTokens,
                responseMimeType: isDoc ? "application/json" : "text/plain",
                responseJsonSchema: isDoc ? GeminiSchema.documentTranslationSchema : nil,
                thinkingConfig: thinkingConfig
            )
        )
        return try JSONEncoder().encode(body)
    }

    static func openAIBody(
        prompt: String,
        model: String,
        providerID: String,
        responseMode: CloudTextTranslationResponseMode = .text
    ) throws -> Data {
        let responseFormat = responseMode == .documentJSON
            && supportsStructuredJSON(providerID: providerID)
            ? OpenAIResponseFormat(type: "json_object")
            : nil
        let body = OpenAIChatCompletionRequest(
            model: model,
            temperature: 0.2,
            messages: [
                OpenAIMessage(
                    role: "system",
                    content: "You are VaniScript's translation engine. Return only the requested translation output, with no commentary."
                ),
                OpenAIMessage(role: "user", content: prompt),
            ],
            responseFormat: responseFormat
        )
        return try JSONEncoder().encode(body)
    }

    static func supportsStructuredJSON(providerID: String) -> Bool {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gpt-cloud", "openai", "qwen", "openrouter":
            return true
        default:
            // Ollama Cloud and unknown/custom routes are not known to accept the
            // OpenAI `response_format` field, so leave the field out.
            return false
        }
    }
}


actor CloudTextTranslationEngine {
    public typealias HTTPHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let httpHandler: HTTPHandler?

    private static let defaultNetworkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600 // 10 minutes request timeout for long LLM translations
        config.timeoutIntervalForResource = 1800 // 30 minutes resource timeout
        return URLSession(configuration: config)
    }()

    init(httpHandler: HTTPHandler? = nil) {
        self.httpHandler = httpHandler
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let httpHandler {
            return try await httpHandler(request)
        }
        return try await Self.defaultNetworkSession.data(for: request)
    }
    // A2 (§8.1): usage accumulator. Each low-level `generate*` call adds the token
    // counters it parsed out of the API response here; a high-level operation may
    // fan out into several HTTP calls (e.g. batched cue translation), so we SUM.
    // The store calls `takeLastUsage()` once, immediately after a high-level call
    // returns, to read and reset the accumulated delta. Actor isolation serializes
    // these mutations; recording is best-effort (invariant §14.4) so a shared engine
    // instance interleaving two operations at worst mis-attributes a delta — it never
    // fails or corrupts the translation itself.
    private var accumulatedUsage: TokenUsage?

    /// Fold one call's parsed usage into the accumulator (nil deltas are ignored).
    private func accumulate(_ delta: TokenUsage?) {
        guard let delta, !delta.isEmpty else { return }
        accumulatedUsage = (accumulatedUsage ?? TokenUsage(inputTokens: 0, outputTokens: 0)) + delta
    }

    /// Return and clear the usage accumulated since the last read. Returns `nil` when
    /// no provider usage was seen (so the store records nothing — best-effort).
    func takeLastUsage() -> TokenUsage? {
        defer { accumulatedUsage = nil }
        return accumulatedUsage
    }

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
            case let .unusableResponse(provider, _):
                return "\(provider) returned no usable translation text."
            case let .requestFailed(provider, status, _):
                return "\(provider) translation failed with HTTP \(status)."
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

    /// Generates one strict document-translation response while preserving the
    /// existing provider routing, key rotation, and usage accounting path.
    func translateDocument(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = nil
    ) async throws -> String {
        let defaultTokens = CloudTextTranslationRequestBuilder.isGemini3(model: provider.model) ? 32_768 : 8_192
        let raw = try await generate(
            prompt: prompt,
            provider: provider,
            maxOutputTokens: maxOutputTokens ?? defaultTokens,
            responseMode: .documentJSON
        )
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranslationError.emptyResponse(provider: provider.label)
        }
        return raw
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
            do {
                translated += try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(raw, sourceCues: batch)
                continue
            } catch {
                // Cloud models (Gemini / OpenRouter / etc.) often ignore the MLX cue-XML
                // contract and return plain or timestamped text. Accept those shapes
                // before failing the whole segment.
                AppLogger.shared.info(
                    "\(provider.label) cue-XML parse missed (\(error.localizedDescription)). Trying freeform/timestamped fallback."
                )
            }

            if let freeform = try? NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput(
                raw,
                sourceCues: batch,
                targetLang: targetLang
            ), !freeform.isEmpty {
                translated += freeform
                continue
            }

            // Last resort: translate the batch as one blob, then realign to source cues.
            let joined = batch
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let blobRaw = try await generate(
                prompt: NativeLLMPromptBuilder.translationPrompt(
                    text: joined,
                    targetLang: targetLang,
                    metadata: metadata,
                    glossary: glossary,
                    promptPresets: promptPresets
                ),
                provider: provider
            )
            let blobTranslated = try NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput(
                blobRaw,
                sourceCues: batch,
                targetLang: targetLang
            )
            translated += blobTranslated
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

    func translateShortsPlan(
        _ plan: ShortsClipPlan,
        targetLanguage: String,
        provider: ActiveCloudTranslationProvider
    ) async throws -> ShortsClipTranslation {
        let prompt = ShortsPlanner.buildTranslationPrompt(plan: plan, targetLanguage: targetLanguage)
        let raw = try await generate(prompt: prompt, provider: provider, maxOutputTokens: 2_048)
        return try ShortsPlanner.parseTranslationResponse(
            raw,
            language: targetLanguage,
            provider: provider.id,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func generate(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = nil,
        responseMode: CloudTextTranslationResponseMode = .text
    ) async throws -> String {
        switch provider.id {
        case "gemini-cloud":
            return try await generateGemini(
                prompt: prompt,
                provider: provider,
                maxOutputTokens: maxOutputTokens,
                responseMode: responseMode
            )
        case "gpt-cloud":
            return try await generateOpenAI(
                prompt: prompt,
                provider: provider,
                responseMode: responseMode
            )
        default:
            // A5: routed providers (Qwen/OpenRouter/Ollama Cloud) carry their own
            // OpenAI-compatible endpoint + auth headers, resolved by CloudChatRouter.
            if let endpoint = provider.endpoint {
                return try await generateOpenAICompatible(
                    prompt: prompt,
                    provider: provider,
                    url: endpoint,
                    headers: provider.headers,
                    responseMode: responseMode
                )
            }
            throw CloudTranslationError.emptyResponse(provider: provider.label)
        }
    }

    private func generateGemini(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = nil,
        responseMode: CloudTextTranslationResponseMode = .text
    ) async throws -> String {
        let keys = provider.rotationKeys
        guard !keys.isEmpty else { throw CloudTranslationError.invalidEndpoint }

        var lastError: Error?
        let totalStartTime = DispatchTime.now()

        for (index, apiKey) in keys.enumerated() {
            var activeProvider = provider
            activeProvider.apiKey = apiKey
            do {
                return try await executeGeminiGeneration(
                    prompt: prompt,
                    provider: activeProvider,
                    maxOutputTokens: maxOutputTokens,
                    responseMode: responseMode,
                    keyIndex: index,
                    keyCount: keys.count
                )
            } catch let error as CloudTranslationError {
                lastError = error
                switch error {
                case .requestFailed(_, let status, let body):
                    if GeminiAPIKeyBank.isRotatableFailure(status: status, body: body) {
                        let hasMoreKeys = index < keys.count - 1
                        if hasMoreKeys {
                            if let delay = GeminiAPIKeyBank.retryDelayNanoseconds(
                                status: status,
                                body: body,
                                attempt: index
                            ) {
                                try? await Task.sleep(nanoseconds: delay)
                            }
                            continue
                        } else {
                            let totalElapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - totalStartTime.uptimeNanoseconds) / 1_000_000)
                            let failureClass = GeminiAPIKeyBank.isQuotaFailure(status: status, body: body)
                                ? "quota-exhausted (HTTP \(status))"
                                : "capacity-exhausted (HTTP \(status))"
                            AppLogger.shared.warn(
                                "Gemini terminal failure [attempted \(keys.count)/\(keys.count) keys] model: \(provider.model) elapsedMs: \(totalElapsedMs) failureClass: \(failureClass)"
                            )
                        }
                    }
                    // Non-rotatable HTTP error or exhausted all keys
                    throw error
                case .emptyResponse, .unusableResponse, .invalidEndpoint:
                    // Output contract / model response failures stop immediately and are not misclassified as key exhaustion.
                    throw error
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? CloudTranslationError.invalidEndpoint
    }

    private func executeGeminiGeneration(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        maxOutputTokens: Int? = nil,
        responseMode: CloudTextTranslationResponseMode = .text,
        keyIndex: Int = 0,
        keyCount: Int = 1
    ) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: provider.apiKey)]
        guard let url = components?.url else { throw CloudTranslationError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CloudTextTranslationRequestBuilder.geminiBody(
            prompt: prompt,
            model: provider.model,
            maxOutputTokens: maxOutputTokens,
            responseMode: responseMode
        )

        let startTime = DispatchTime.now()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await performRequest(request)
        } catch {
            let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)
            AppLogger.shared.warn(
                "Gemini attempt [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) status: network-error elapsedMs: \(elapsedMs) responseChars: 0"
            )
            throw error
        }
        let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            let isRotatable = GeminiAPIKeyBank.isRotatableFailure(status: http.statusCode, body: body)
            let statusLabel: String
            if isRotatable {
                statusLabel = GeminiAPIKeyBank.isQuotaFailure(status: http.statusCode, body: body)
                    ? "quota (HTTP \(http.statusCode))"
                    : "capacity (HTTP \(http.statusCode))"
            } else {
                statusLabel = "HTTP \(http.statusCode)"
            }
            AppLogger.shared.info(
                "Gemini attempt [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) status: \(statusLabel) elapsedMs: \(elapsedMs) responseChars: 0"
            )
            if !isRotatable {
                AppLogger.shared.warn(
                    "Gemini terminal failure [attempted key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) failureClass: non-rotatable (HTTP \(http.statusCode))"
                )
            }
            throw CloudTranslationError.requestFailed(provider: provider.label, status: http.statusCode, body: body)
        }

        // Best-effort usage capture
        accumulate(UsageRecorder.parseGeminiUsage(from: data))
        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let finishReason = decoded.candidates?.first?.finishReason ?? "NONE"
        let normalizedFinishReason = finishReason.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let text = decoded.candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        AppLogger.shared.info(
            "Gemini attempt [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) status: HTTP 200 elapsedMs: \(elapsedMs) responseChars: \(text.count) finishReason: \(finishReason)"
        )

        guard let candidates = decoded.candidates, !candidates.isEmpty else {
            AppLogger.shared.warn(
                "Gemini terminal failure [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) failureClass: empty-candidates"
            )
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: geminiEmptyResponseDetail(decoded, rawData: data)
            )
        }

        if normalizedFinishReason == "MAX_TOKENS" {
            AppLogger.shared.warn(
                "Gemini terminal failure [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) failureClass: max-tokens (\(finishReason))"
            )
            let detail = "Gemini reached maximum output token limit (\(finishReason)) and produced incomplete output. \(geminiEmptyResponseDetail(decoded, rawData: data))"
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: detail
            )
        }

        if normalizedFinishReason != "STOP" && normalizedFinishReason != "NONE" && normalizedFinishReason != "FINISH_REASON_UNSPECIFIED" && !normalizedFinishReason.isEmpty {
            AppLogger.shared.warn(
                "Gemini terminal failure [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) failureClass: finish-reason-\(normalizedFinishReason.lowercased()) (\(finishReason))"
            )
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: geminiEmptyResponseDetail(decoded, rawData: data)
            )
        }

        guard !text.isEmpty else {
            AppLogger.shared.warn(
                "Gemini terminal failure [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) failureClass: empty-output (\(finishReason))"
            )
            throw CloudTranslationError.unusableResponse(
                provider: provider.label,
                detail: geminiEmptyResponseDetail(decoded, rawData: data)
            )
        }

        AppLogger.shared.info(
            "Gemini completed successfully [key \(keyIndex + 1)/\(keyCount)] model: \(provider.model) elapsedMs: \(elapsedMs) responseChars: \(text.count) finishReason: \(finishReason)"
        )
        return text
    }

    private func generateOpenAI(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        responseMode: CloudTextTranslationResponseMode = .text
    ) async throws -> String {
        // Legacy gpt-cloud path: fixed OpenAI URL + Bearer, now delegating to the
        // shared OpenAI-compatible builder (A5 refactor — behavior unchanged).
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw CloudTranslationError.invalidEndpoint
        }
        return try await generateOpenAICompatible(
            prompt: prompt,
            provider: provider,
            url: url,
            headers: ["Authorization": "Bearer \(provider.apiKey)"],
            responseMode: responseMode
        )
    }

    // A5: one request/response path for every OpenAI-compatible chat provider
    // (OpenAI, Qwen DashScope compatible-mode, OpenRouter, Ollama Cloud /v1). The
    // caller supplies the endpoint + auth headers; body shape and usage parsing
    // (§8.1, best-effort) are identical across providers.
    private func generateOpenAICompatible(
        prompt: String,
        provider: ActiveCloudTranslationProvider,
        url: URL,
        headers: [String: String],
        responseMode: CloudTextTranslationResponseMode = .text
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Auth comes from the caller (Bearer for all current providers); the key is
        // only ever placed in the header — never logged (invariant §14.3).
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CloudTextTranslationRequestBuilder.openAIBody(
            prompt: prompt,
            model: provider.model,
            providerID: provider.id,
            responseMode: responseMode
        )

        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data, provider: provider.label)
        // A2: best-effort usage capture (OpenAI-compatible `usage` block). Never throws.
        accumulate(UsageRecorder.parseOpenAIUsage(from: data))
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

fileprivate struct GeminiGenerateContentRequest: Encodable {
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

/// An immutable JSON Schema model for Gemini structured output (`responseJsonSchema`).
/// Declared as a final reference type to allow recursive nesting (`items` and `properties`) without infinite value-type layout.
/// All stored properties are immutable `let` values, ensuring safe cross-actor usage.
fileprivate final class GeminiSchema: Encodable, @unchecked Sendable {
    let type: String
    let properties: [String: GeminiSchema]?
    let required: [String]?
    let items: GeminiSchema?

    init(
        type: String,
        properties: [String: GeminiSchema]? = nil,
        required: [String]? = nil,
        items: GeminiSchema? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
    }

    static let documentTranslationSchema = GeminiSchema(
        type: "object",
        properties: [
            "schema": GeminiSchema(type: "string"),
            "chunkId": GeminiSchema(type: "string"),
            "blocks": GeminiSchema(
                type: "array",
                items: GeminiSchema(
                    type: "object",
                    properties: [
                        "id": GeminiSchema(type: "string"),
                        "spans": GeminiSchema(
                            type: "array",
                            items: GeminiSchema(
                                type: "object",
                                properties: [
                                    "id": GeminiSchema(type: "string"),
                                    "style": GeminiSchema(type: "string"),
                                    "text": GeminiSchema(type: "string")
                                ],
                                required: ["style", "text"]
                            )
                        )
                    ],
                    required: ["id", "spans"]
                )
            )
        ],
        required: ["schema", "chunkId", "blocks"]
    )
}

fileprivate struct GeminiThinkingConfig: Encodable {
    var thinkingLevel: String?
}

fileprivate struct GeminiGenerationConfig: Encodable {
    var temperature: Double
    var maxOutputTokens: Int?
    var responseMimeType: String
    var responseJsonSchema: GeminiSchema?
    var thinkingConfig: GeminiThinkingConfig?
}

fileprivate struct GeminiContent: Codable {
    var role: String?
    var parts: [GeminiPart]
}

fileprivate struct GeminiPart: Codable {
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

fileprivate struct OpenAIChatCompletionRequest: Encodable {
    var model: String
    var temperature: Double
    var messages: [OpenAIMessage]
    var responseFormat: OpenAIResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case responseFormat = "response_format"
    }
}

fileprivate struct OpenAIResponseFormat: Encodable {
    var type: String
}

fileprivate struct OpenAIMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    var message: OpenAIMessage
}
