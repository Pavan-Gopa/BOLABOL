import Foundation
import Testing
@testable import VaniScriptCore

// A5: request-routing coverage for CloudChatRouter (endpoints, headers, model
// fallbacks, error/nil mapping). Pure functions — no network, no real keys (§14).
@Suite("CloudChatRouter — A5 routing")
struct CloudProviderRoutingTests {
    @Test("qwen routes to DashScope compatible-mode with Bearer auth")
    func qwenRoute() {
        var settings = AppSettings.defaults
        settings.qwenApiKey = "  qwen-test-key  " // must be trimmed
        let route = CloudChatRouter.route(providerID: CloudProviderCatalog.qwenID, settings: settings)

        #expect(route?.endpoint.absoluteString == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
        #expect(route?.headers["Authorization"] == "Bearer qwen-test-key")
        #expect(route?.apiKey == "qwen-test-key")
        // Empty settings model → catalog default (migration-safe fallback, §9.2).
        #expect(route?.model == "qwen-plus")
        #expect(route?.label == "Qwen")
    }

    @Test("openrouter routes to /api/v1/chat/completions")
    func openrouterRoute() {
        var settings = AppSettings.defaults
        settings.openrouterApiKey = "or-key"
        settings.openrouterModel = "anthropic/claude-3.5-sonnet"
        let route = CloudChatRouter.route(providerID: CloudProviderCatalog.openrouterID, settings: settings)

        #expect(route?.endpoint.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(route?.headers["Authorization"] == "Bearer or-key")
        // User-selected model wins over the catalog default.
        #expect(route?.model == "anthropic/claude-3.5-sonnet")
    }

    @Test("ollama cloud uses OpenAI-compatible /v1 on the configured base URL")
    func ollamaRouteDefaultBase() {
        var settings = AppSettings.defaults
        settings.ollamaCloudApiKey = "ollama-key"
        let route = CloudChatRouter.route(providerID: CloudProviderCatalog.ollamaCloudID, settings: settings)

        #expect(route?.endpoint.absoluteString == "https://ollama.com/v1/chat/completions")
        #expect(route?.headers["Authorization"] == "Bearer ollama-key")
        #expect(route?.model == "gpt-oss:120b") // catalog default
    }

    @Test("ollama base URL: trailing slashes stripped, empty falls back to default")
    func ollamaBaseNormalization() {
        var settings = AppSettings.defaults
        settings.ollamaCloudApiKey = "k"

        settings.ollamaCloudBaseUrl = "https://my-ollama.example.com//"
        #expect(
            CloudChatRouter.route(providerID: CloudProviderCatalog.ollamaCloudID, settings: settings)?
                .endpoint.absoluteString == "https://my-ollama.example.com/v1/chat/completions"
        )

        settings.ollamaCloudBaseUrl = "   "
        #expect(
            CloudChatRouter.route(providerID: CloudProviderCatalog.ollamaCloudID, settings: settings)?
                .endpoint.absoluteString == "https://ollama.com/v1/chat/completions"
        )
    }

    @Test("missing or blank key resolves to nil (error mapping: no route, no request)")
    func missingKeyReturnsNil() {
        var settings = AppSettings.defaults
        #expect(CloudChatRouter.route(providerID: CloudProviderCatalog.qwenID, settings: settings) == nil)

        settings.openrouterApiKey = "  \n "
        #expect(CloudChatRouter.route(providerID: CloudProviderCatalog.openrouterID, settings: settings) == nil)
    }

    @Test("unknown / legacy provider ids are not routed here")
    func unknownIdsReturnNil() {
        var settings = AppSettings.defaults
        settings.geminiKey = "g"
        settings.openaiKey = "o"
        // Legacy providers keep their dedicated engine paths (gemini-cloud/gpt-cloud);
        // the router only owns the three new OpenAI-compatible providers.
        #expect(CloudChatRouter.route(providerID: "gemini-cloud", settings: settings) == nil)
        #expect(CloudChatRouter.route(providerID: "gpt-cloud", settings: settings) == nil)
        #expect(CloudChatRouter.route(providerID: "custom", settings: settings) == nil)
        #expect(CloudChatRouter.route(providerID: "", settings: settings) == nil)
    }

    @Test("settings model overrides catalog default for qwen")
    func qwenModelOverride() {
        var settings = AppSettings.defaults
        settings.qwenApiKey = "k"
        settings.qwenCloudModel = " qwen-max "
        let route = CloudChatRouter.route(providerID: CloudProviderCatalog.qwenID, settings: settings)
        #expect(route?.model == "qwen-max") // trimmed
    }
}
