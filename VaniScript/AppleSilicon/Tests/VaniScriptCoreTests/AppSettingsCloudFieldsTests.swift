import Testing
import Foundation
@testable import VaniScriptCore

// A1 (API_USAGE): verifies the data-model foundation is migration-safe.
//  - Old settings JSON (without the new cloud fields) decodes to sensible defaults.
//  - New AppSettings/ProviderUsage fields survive an encode → decode round-trip.
//  - CloudProviderCatalog preserves the Human-approved fixed provider order.
// These are pure data tests (no UI, no engines, no network) per the A1 scope.
@Suite("AppSettings cloud fields (A1)")
struct AppSettingsCloudFieldsTests {

    // MARK: - Migration: old settings without new fields → defaults

    @Test("decodes legacy settings (missing new cloud fields) into defaults")
    func decodesLegacySettingsToDefaults() throws {
        // Minimal legacy-style payload: none of the A1 fields are present. The decoder
        // must not throw and must apply migration-safe defaults.
        let legacyJSON = """
        {
            "geminiKey": "old-gemini",
            "openaiKey": "",
            "anthropicKey": "",
            "geminiBudgetUsd": 5,
            "openaiBudgetUsd": 0
        }
        """
        let data = Data(legacyJSON.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        // Existing field preserved.
        #expect(settings.geminiKey == "old-gemini")
        // New model fields fall back to the current engine hardcode (behavior unchanged).
        #expect(settings.geminiTextModel == "gemini-2.5-flash")
        #expect(settings.openaiTextModel == "gpt-4o-mini")
        // New cloud providers default to empty keys/models and zero budgets.
        #expect(settings.qwenApiKey.isEmpty)
        #expect(settings.qwenCloudModel.isEmpty)
        #expect(settings.qwenBudgetUsd == 0)
        #expect(settings.openrouterApiKey.isEmpty)
        #expect(settings.openrouterModel.isEmpty)
        #expect(settings.openrouterBudgetUsd == 0)
        #expect(settings.ollamaCloudApiKey.isEmpty)
        #expect(settings.ollamaCloudModel.isEmpty)
        #expect(settings.ollamaCloudBaseUrl == "https://ollama.com")
    }

    @Test("decodes legacy ProviderUsage (no lastModel/lastTransactionAt) into nil")
    func decodesLegacyProviderUsage() throws {
        let legacyUsageJSON = """
        {
            "sessions": 3,
            "inputTokens": 100,
            "outputTokens": 50,
            "audioMinutes": 1.5,
            "lastUsed": "2026-07-25"
        }
        """
        let usage = try JSONDecoder().decode(ProviderUsage.self, from: Data(legacyUsageJSON.utf8))
        #expect(usage.sessions == 3)
        #expect(usage.inputTokens == 100)
        // New optional fields default to nil for legacy records.
        #expect(usage.lastModel == nil)
        #expect(usage.lastTransactionAt == nil)
    }

    // MARK: - Round-trip: encode → decode preserves new fields

    @Test("round-trips AppSettings with new cloud fields set")
    func roundTripsAppSettingsWithNewFields() throws {
        var settings = AppSettings.defaults
        settings.geminiTextModel = "gemini-2.5-pro"
        settings.openaiTextModel = "gpt-4o"
        settings.qwenApiKey = "qwen-key"
        settings.qwenCloudModel = "qwen-plus"
        settings.qwenBudgetUsd = 12.5
        settings.openrouterApiKey = "or-key"
        settings.openrouterModel = "openai/gpt-4o-mini"
        settings.openrouterBudgetUsd = 20
        settings.ollamaCloudApiKey = "ollama-key"
        settings.ollamaCloudModel = "gpt-oss:120b"
        settings.ollamaCloudBaseUrl = "https://ollama.com"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded == settings)
        #expect(decoded.qwenCloudModel == "qwen-plus")
        #expect(decoded.openrouterBudgetUsd == 20)
        #expect(decoded.ollamaCloudModel == "gpt-oss:120b")
    }

    @Test("round-trips ProviderUsage with lastModel/lastTransactionAt")
    func roundTripsProviderUsage() throws {
        let usage = ProviderUsage(
            sessions: 2,
            inputTokens: 200,
            outputTokens: 80,
            audioMinutes: 3,
            lastUsed: "2026-07-25",
            lastInputTokens: 40,
            lastOutputTokens: 20,
            lastModel: "qwen:qwen-plus",
            lastTransactionAt: "2026-07-25T12:00:00Z"
        )
        let encoded = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ProviderUsage.self, from: encoded)

        #expect(decoded == usage)
        #expect(decoded.lastModel == "qwen:qwen-plus")
        #expect(decoded.lastTransactionAt == "2026-07-25T12:00:00Z")
    }

    // MARK: - CloudProviderCatalog

    @Test("catalog preserves the fixed Human-approved provider order")
    func catalogFixedOrder() {
        #expect(CloudProviderCatalog.providerOrder == [
            "gemini", "openai", "anthropic", "qwen", "openrouter", "ollama-cloud", "custom",
        ])
        #expect(CloudProviderCatalog.providers.map(\.id) == CloudProviderCatalog.providerOrder)
    }

    @Test("catalog exposes descriptor lookup + display names")
    func catalogLookup() {
        #expect(CloudProviderCatalog.providerDisplayName("gemini") == "Google Gemini")
        #expect(CloudProviderCatalog.providerDisplayName("ollama-cloud") == "Ollama Cloud")
        // Unknown id falls back to the raw id (legacy/custom safety).
        #expect(CloudProviderCatalog.providerDisplayName("unknown-x") == "unknown-x")

        let openrouter = CloudProviderCatalog.descriptor(for: "openrouter")
        #expect(openrouter?.balanceKind == .openrouterCredits)
        #expect(openrouter?.capabilities.supportsRealBalance == true)
    }
}
