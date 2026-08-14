import Foundation
import Testing
@testable import VaniScript

@Suite("Document cloud structured output")
struct DocumentCloudStructuredOutputTests {
    @Test("Gemini 3.x document requests use application/json, responseJsonSchema, low thinking, and 32,768 output tokens")
    func gemini3DocumentUsesResponseJsonSchemaAndLowThinkingAndOutputTokens() throws {
        // Test default tokens
        let bodyDefault = try CloudTextTranslationRequestBuilder.geminiBody(
            prompt: "translate this document chunk",
            model: "gemini-3.6-flash",
            maxOutputTokens: nil,
            responseMode: .documentJSON
        )
        let rootDefault = try jsonObject(bodyDefault)
        let configDefault = try #require(rootDefault["generationConfig"] as? [String: Any])

        #expect(configDefault["responseMimeType"] as? String == "application/json")
        #expect(configDefault["maxOutputTokens"] as? Int == 32_768)
        #expect(configDefault["responseSchema"] == nil)

        let thinking = try #require(configDefault["thinkingConfig"] as? [String: Any])
        #expect(thinking["thinkingLevel"] as? String == "LOW")

        let schema = try #require(configDefault["responseJsonSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        let required = try #require(schema["required"] as? [String])
        #expect(required.sorted() == ["blocks", "chunkId", "schema"])

        let properties = try #require(schema["properties"] as? [String: Any])
        let blocks = try #require(properties["blocks"] as? [String: Any])
        #expect(blocks["type"] as? String == "array")

        let blockItems = try #require(blocks["items"] as? [String: Any])
        #expect(blockItems["type"] as? String == "object")
        let blockRequired = try #require(blockItems["required"] as? [String])
        #expect(blockRequired.sorted() == ["id", "spans"])

        let blockProps = try #require(blockItems["properties"] as? [String: Any])
        let spans = try #require(blockProps["spans"] as? [String: Any])
        #expect(spans["type"] as? String == "array")

        let spanItems = try #require(spans["items"] as? [String: Any])
        #expect(spanItems["type"] as? String == "object")
        let spanRequired = try #require(spanItems["required"] as? [String])
        #expect(spanRequired.sorted() == ["style", "text"])

        let spanProps = try #require(spanItems["properties"] as? [String: Any])
        #expect(spanProps["id"] != nil)
        #expect(spanProps["style"] != nil)
        #expect(spanProps["text"] != nil)

        // Test that caller's smaller planner reservation (8,192) does not starve Gemini 3.x
        let bodyBounded = try CloudTextTranslationRequestBuilder.geminiBody(
            prompt: "translate this document chunk",
            model: "gemini-3.6-flash",
            maxOutputTokens: 8_192,
            responseMode: .documentJSON
        )
        let rootBounded = try jsonObject(bodyBounded)
        let configBounded = try #require(rootBounded["generationConfig"] as? [String: Any])
        #expect(configBounded["maxOutputTokens"] as? Int == 32_768)
        #expect(configBounded["responseSchema"] == nil)
        #expect(configBounded["responseJsonSchema"] != nil)
    }

    @Test("earlier Gemini document requests omit thinkingConfig and preserve standard tokens")
    func earlierGeminiDocumentOmitsThinkingConfigAndUsesStandardTokens() throws {
        let body = try CloudTextTranslationRequestBuilder.geminiBody(
            prompt: "translate this document chunk",
            model: "gemini-2.5-flash",
            maxOutputTokens: nil,
            responseMode: .documentJSON
        )
        let root = try jsonObject(body)
        let config = try #require(root["generationConfig"] as? [String: Any])

        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["maxOutputTokens"] as? Int == 8_192)
        #expect(config["responseSchema"] == nil)
        #expect(config["responseJsonSchema"] != nil)
        #expect(config["thinkingConfig"] == nil)
    }
    @Test("supported OpenAI-compatible document requests use json_object")
    func supportedOpenAIDocumentUsesJSONResponseFormat() throws {
        for providerID in ["gpt-cloud", "openai", "qwen", "openrouter"] {
            let body = try CloudTextTranslationRequestBuilder.openAIBody(
                prompt: "translate this document chunk",
                model: "test-model",
                providerID: providerID,
                responseMode: .documentJSON
            )
            let root = try jsonObject(body)
            let responseFormat = try #require(root["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_object")
        }
    }

    @Test("unsupported OpenAI-compatible document requests omit response_format")
    func unsupportedOpenAIDocumentOmitsResponseFormat() throws {
        let body = try CloudTextTranslationRequestBuilder.openAIBody(
            prompt: "translate this document chunk",
            model: "test-model",
            providerID: "ollama-cloud",
            responseMode: .documentJSON
        )
        let root = try jsonObject(body)

        #expect(root["response_format"] == nil)
    }

    @Test("media OpenAI request mode remains the prior freeform payload")
    func mediaOpenAIPayloadRemainsUnchanged() throws {
        let body = try CloudTextTranslationRequestBuilder.openAIBody(
            prompt: "translate media text",
            model: "gpt-4o-mini",
            providerID: "gpt-cloud",
            responseMode: .text
        )
        let root = try jsonObject(body)
        let messages = try #require(root["messages"] as? [[String: Any]])

        #expect(root["model"] as? String == "gpt-4o-mini")
        #expect(root["temperature"] as? Double == 0.2)
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["role"] as? String == "user")
        #expect(root["response_format"] == nil)
    }

    @Test("media Gemini request mode remains text/plain without schema or thinkingConfig")
    func mediaGeminiPayloadRemainsFreeform() throws {
        let body = try CloudTextTranslationRequestBuilder.geminiBody(
            prompt: "translate media text",
            model: "gemini-3.6-flash",
            maxOutputTokens: 8_192,
            responseMode: .text
        )
        let root = try jsonObject(body)
        let config = try #require(root["generationConfig"] as? [String: Any])

        #expect(config["responseMimeType"] as? String == "text/plain")
        #expect(config["maxOutputTokens"] as? Int == 8_192)
        #expect(config["responseSchema"] == nil)
        #expect(config["responseJsonSchema"] == nil)
        #expect(config["thinkingConfig"] == nil)
    }

    @Test("five-key rotation succeeds on key 5 after rotatable quota and capacity failures")
    func fiveKeyRotationSucceedsOnLastKey() async throws {
        actor RequestRecorder {
            var count = 0
            func record() -> Int {
                count += 1
                return count
            }
            func total() -> Int { count }
        }

        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            let attempt = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            switch attempt {
            case 1:
                // Key 1: HTTP 429 Quota
                let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (Data("{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"Quota exceeded\"}}".utf8), response)
            case 2:
                // Key 2: HTTP 503 Capacity / High demand
                let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (Data("{\"error\":{\"code\":503,\"status\":\"UNAVAILABLE\",\"message\":\"high demand\"}}".utf8), response)
            case 3:
                // Key 3: HTTP 502 Bad Gateway
                let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 502, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (Data("{\"error\":{\"code\":502,\"message\":\"Bad Gateway\"}}".utf8), response)
            case 4:
                // Key 4: HTTP 504 Gateway Timeout
                let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 504, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (Data("{\"error\":{\"code\":504,\"message\":\"Gateway Timeout\"}}".utf8), response)
            case 5:
                // Key 5: HTTP 200 Success
                let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                let body = """
                {
                  "candidates": [
                    {
                      "content": {
                        "parts": [
                          { "text": "{\\"schema\\":\\"vaniscript.document.translation.v1\\",\\"chunkId\\":\\"c1\\",\\"blocks\\":[{\\"id\\":\\"b1\\",\\"spans\\":[{\\"style\\":\\"plain\\",\\"text\\":\\"Success\\"}]}]}" }
                        ]
                      },
                      "finishReason": "STOP"
                    }
                  ]
                }
                """
                return (Data(body.utf8), response)
            default:
                fatalError("Unexpected attempt \(attempt)")
            }
        })

        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-2.5-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        let output = try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        #expect(await recorder.total() == 5)
        #expect(output.contains("Success"))
    }

    @Test("all keys fail with rotatable errors attempts every key once")
    func allKeysFailRotatable() async {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data("{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\"}}".utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-2.5-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        await #expect(throws: Error.self) {
            try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        }
        #expect(await recorder.total() == 5)
    }

    @Test("non-rotatable auth failure stops immediately on key 1")
    func nonRotatableAuthStopsImmediately() async {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data("{\"error\":{\"code\":400,\"message\":\"API key not valid. Please pass a valid API key.\",\"status\":\"INVALID_ARGUMENT\"}}".utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-2.5-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        await #expect(throws: Error.self) {
            try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        }
        #expect(await recorder.total() == 1)
    }

    @Test("malformed HTTP-success stops immediately and is classified honestly")
    func malformedSuccessStopsImmediately() async {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "" }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """
            return (Data(body.utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-2.5-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        await #expect(throws: Error.self) {
            try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        }
        #expect(await recorder.total() == 1)
    }
    @Test("MAX_TOKENS finishReason terminates honestly after one request without key rotation")
    func geminiMaxTokensThrowsImmediatelyWithoutRotating() async {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "{\\"schema\\":\\"vaniscript.document.translation.v1\\",\\"chunkId\\":\\"c1\\",\\"blocks\\":[{\\"id\\":\\"b1\\"" }
                    ]
                  },
                  "finishReason": "MAX_TOKENS"
                }
              ]
            }
            """
            return (Data(body.utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-3.6-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        await #expect(throws: Error.self) {
            try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        }
        #expect(await recorder.total() == 1)
    }

    @Test("case-insensitive finishReason stop succeeds on key 1")
    func geminiStopCaseInsensitiveSucceeds() async throws {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "{\\"schema\\":\\"vaniscript.document.translation.v1\\",\\"chunkId\\":\\"c1\\",\\"blocks\\":[{\\"id\\":\\"b1\\",\\"spans\\":[{\\"style\\":\\"plain\\",\\"text\\":\\"Translated\\"}]}]}" }
                    ]
                  },
                  "finishReason": "stop"
                }
              ]
            }
            """
            return (Data(body.utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-3.6-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        let result = try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        #expect(await recorder.total() == 1)
        #expect(result.contains("Translated"))
    }

    @Test("SAFETY finishReason terminates honestly after one request without key rotation")
    func geminiSafetyTerminationThrowsImmediatelyWithoutRotating() async {
        actor RequestRecorder {
            var count = 0
            func record() -> Int { count += 1; return count }
            func total() -> Int { count }
        }
        let recorder = RequestRecorder()
        let engine = CloudTextTranslationEngine(httpHandler: { request in
            _ = await recorder.record()
            let url = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = """
            {
              "candidates": [
                {
                  "finishReason": "SAFETY",
                  "safetyRatings": [
                    { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "blocked": true }
                  ]
                }
              ]
            }
            """
            return (Data(body.utf8), response)
        })
        let provider = ActiveCloudTranslationProvider(
            id: "gemini-cloud",
            label: "Gemini Cloud",
            model: "gemini-3.6-flash",
            apiKey: "key-1",
            apiKeys: ["key-1", "key-2", "key-3", "key-4", "key-5"]
        )

        await #expect(throws: Error.self) {
            try await engine.translateDocument(prompt: "translate chunk", provider: provider)
        }
        #expect(await recorder.total() == 1)
    }

    private func jsonObject(_ body: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
