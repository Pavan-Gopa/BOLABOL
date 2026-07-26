import Testing
import Foundation
@testable import VaniScriptCore

// A4 (API_USAGE §9.2): unit tests for CloudModelCatalog's response parsers and its
// per-provider "list models" request builder. Network is mocked — these tests only
// feed canned JSON through the pure parsers and inspect the URLRequests, so they run
// offline and deterministically (invariant §14: no real network, no keys in source).
@Suite("CloudModelCatalog parsers (A4)")
struct CloudModelCatalogTests {

    // MARK: - OpenAI-compatible /v1/models → data[].id

    @Test("parses OpenAI /v1/models data[].id list")
    func parsesOpenAIModels() throws {
        let json = """
        { "object": "list", "data": [
            { "id": "gpt-4o-mini", "object": "model" },
            { "id": "gpt-4o", "object": "model" }
        ] }
        """
        let models = try CloudModelCatalog.parse(data: Data(json.utf8), endpoint: .openAICompatible, provider: "OpenAI")
        #expect(models == [CloudModel(id: "gpt-4o-mini"), CloudModel(id: "gpt-4o")])
    }

    // MARK: - Gemini /v1beta/models → models[].name (strip models/)

    @Test("parses Gemini /v1beta/models and strips the models/ prefix")
    func parsesGeminiModels() throws {
        let json = """
        { "models": [
            { "name": "models/gemini-2.5-flash" },
            { "name": "models/gemini-2.5-pro" },
            { "name": "gemini-bare" }
        ] }
        """
        let models = try CloudModelCatalog.parse(data: Data(json.utf8), endpoint: .gemini, provider: "Gemini")
        #expect(models.map(\.id) == ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-bare"])
    }

    // MARK: - Ollama /api/tags → models[].name

    @Test("parses Ollama /api/tags models[].name list")
    func parsesOllamaTags() throws {
        let json = """
        { "models": [
            { "name": "gpt-oss:120b" },
            { "name": "llama3.1:8b" }
        ] }
        """
        let models = try CloudModelCatalog.parse(data: Data(json.utf8), endpoint: .ollamaTags, provider: "Ollama Cloud")
        #expect(models.map(\.id) == ["gpt-oss:120b", "llama3.1:8b"])
    }

    // MARK: - De-duplication + empty filtering (shared post-processing)

    @Test("de-dupes ids and drops empties preserving first-seen order")
    func dedupesAndDropsEmpties() throws {
        let json = """
        { "data": [
            { "id": "a" }, { "id": "a" }, { "id": "  " }, { "id": "b" }, { "id": "a" }
        ] }
        """
        let models = try CloudModelCatalog.parse(data: Data(json.utf8), endpoint: .openAICompatible, provider: "OpenAI")
        #expect(models.map(\.id) == ["a", "b"])
    }

    // MARK: - Error cases

    @Test("throws unparsableResponse on malformed body")
    func throwsOnMalformedBody() {
        let bad = Data("not json".utf8)
        #expect(throws: CloudModelCatalogError.self) {
            try CloudModelCatalog.parse(data: bad, endpoint: .openAICompatible, provider: "OpenAI")
        }
    }

    @Test("custom/none endpoints do not support listing")
    func customEndpointUnsupported() {
        let empty = Data("{}".utf8)
        #expect(throws: CloudModelCatalogError.self) {
            try CloudModelCatalog.parse(data: empty, endpoint: .custom, provider: "Custom")
        }
        #expect(throws: CloudModelCatalogError.self) {
            try CloudModelCatalog.parse(data: empty, endpoint: .none, provider: "None")
        }
    }

    // MARK: - Request builder (auth per provider, no keys leaked into paths)

    @Test("builds Gemini request with ?key= query param")
    func buildsGeminiRequest() throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.geminiID))
        let request = try #require(CloudModelCatalog.listRequest(descriptor: descriptor, apiKey: "SECRET"))
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("generativelanguage.googleapis.com/v1beta/models"))
        #expect(url.contains("key=SECRET"))
    }

    @Test("builds OpenAI request with Bearer auth header")
    func buildsOpenAIRequest() throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let request = try #require(CloudModelCatalog.listRequest(descriptor: descriptor, apiKey: "SECRET"))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SECRET")
    }

    @Test("builds Ollama request against configurable base URL")
    func buildsOllamaRequest() throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.ollamaCloudID))
        let request = try #require(CloudModelCatalog.listRequest(descriptor: descriptor, apiKey: "SECRET", baseURL: "https://ollama.com"))
        #expect(request.url?.absoluteString == "https://ollama.com/api/tags")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SECRET")
    }

    @Test("custom provider yields no list request")
    func customProviderNoRequest() throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.customID))
        #expect(CloudModelCatalog.listRequest(descriptor: descriptor, apiKey: "SECRET") == nil)
    }

    // MARK: - Actor listModels with a mocked fetcher (end-to-end, no network)

    @Test("listModels uses injected fetcher and caches the result")
    func listModelsWithMockFetcher() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let counter = CallCounter()
        let json = Data(#"{ "data": [ { "id": "gpt-4o-mini" } ] }"#.utf8)
        let catalog = CloudModelCatalog(fetcher: { request in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json, response)
        })

        let first = try await catalog.listModels(descriptor: descriptor, apiKey: "SECRET")
        let second = try await catalog.listModels(descriptor: descriptor, apiKey: "SECRET")
        #expect(first == [CloudModel(id: "gpt-4o-mini")])
        #expect(second == first)
        // Cache hit → fetcher called only once for the same key.
        #expect(await counter.value == 1)
    }

    @Test("listModels throws requestFailed on non-2xx")
    func listModelsNon2xx() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let catalog = CloudModelCatalog(fetcher: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
        await #expect(throws: CloudModelCatalogError.self) {
            _ = try await catalog.listModels(descriptor: descriptor, apiKey: "BAD")
        }
    }
}

// Small actor to count fetcher invocations from concurrency-safe test closures.
private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
