import Foundation
import Testing
@testable import VaniScriptCore

struct GeminiAPIKeyBankTests {
    @Test func primaryKeyMirrorsFirstEnabledEntry() {
        var bank = GeminiAPIKeyBank(entries: [
            "\(GeminiAPIKeyBank.disabledPrefix)disabled-key",
            "active-key",
            "second-active"
        ])

        #expect(bank.primaryKey == "active-key")
        #expect(bank.enabledKeys == ["active-key", "second-active"])
        #expect(bank.hasEnabledKey)
        #expect(bank.configuredCount == 3)

        bank.primaryKey = "rotated-primary"
        #expect(bank.enabledKeys.first == "rotated-primary")
        #expect(bank.entries[0].hasPrefix(GeminiAPIKeyBank.disabledPrefix))
    }

    @Test func disableAndEnableControlsRotationSet() {
        var bank = GeminiAPIKeyBank(entries: ["key-a", "key-b", "key-c"])
        bank.disableAllExcept(at: 1)

        #expect(bank.enabledKeys == ["key-b"])
        #expect(bank.isDisabled(at: 0))
        #expect(!bank.isDisabled(at: 1))
        #expect(bank.isDisabled(at: 2))

        bank.enableAll()
        #expect(bank.enabledKeys == ["key-a", "key-b", "key-c"])
    }

    @Test func addRemoveRespectMaxKeysAndDisablePrefix() {
        var bank = GeminiAPIKeyBank()
        for index in 1...GeminiAPIKeyBank.maxKeys {
            bank.addKey("key-\(index)")
        }
        #expect(bank.entries.count == GeminiAPIKeyBank.maxKeys)

        bank.addKey("overflow")
        #expect(bank.entries.count == GeminiAPIKeyBank.maxKeys)
        #expect(!bank.entries.contains("overflow"))

        bank.toggleDisabled(at: 0)
        #expect(bank.isDisabled(at: 0))
        #expect(bank.cleanKey(at: 0) == "key-1")

        bank.removeKey(at: 0)
        #expect(bank.entries.count == GeminiAPIKeyBank.maxKeys - 1)
        #expect(bank.primaryKey == "key-2")
    }

    @Test func quotaFailureDetectionMatchesGeminiSignals() {
        #expect(GeminiAPIKeyBank.isQuotaFailure(status: 429, body: "anything"))
        #expect(GeminiAPIKeyBank.isQuotaFailure(status: 403, body: #"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#))
        #expect(GeminiAPIKeyBank.isQuotaFailure(status: 400, body: "Quota exceeded for metric"))
        #expect(GeminiAPIKeyBank.isQuotaFailure(status: 503, body: "rate limit reached"))
        #expect(!GeminiAPIKeyBank.isQuotaFailure(status: 401, body: "API key not valid"))
        #expect(!GeminiAPIKeyBank.isQuotaFailure(status: 500, body: "internal"))
    }

    @Test func capacityAndRotatableFailureDetectionMatchesGeminiHighDemand() {
        let highDemandBody = """
        {"error":{"code":503,"message":"This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.","status":"UNAVAILABLE"}}
        """
        #expect(GeminiAPIKeyBank.isCapacityFailure(status: 503, body: highDemandBody))
        #expect(GeminiAPIKeyBank.isRotatableFailure(status: 503, body: highDemandBody))
        #expect(!GeminiAPIKeyBank.isQuotaFailure(status: 503, body: highDemandBody))

        #expect(GeminiAPIKeyBank.isCapacityFailure(status: 502, body: "bad gateway"))
        #expect(GeminiAPIKeyBank.isCapacityFailure(status: 504, body: "gateway timeout"))
        #expect(GeminiAPIKeyBank.isCapacityFailure(status: 500, body: "model overloaded, try again later"))
        #expect(!GeminiAPIKeyBank.isCapacityFailure(status: 401, body: "API key not valid"))
        #expect(!GeminiAPIKeyBank.isRotatableFailure(status: 401, body: "API key not valid"))

        // Quota remains rotatable via the shared gate.
        #expect(GeminiAPIKeyBank.isRotatableFailure(status: 429, body: "too many requests"))

        #expect(GeminiAPIKeyBank.retryDelayNanoseconds(status: 503, body: highDemandBody, attempt: 0) == 400_000_000)
        #expect(GeminiAPIKeyBank.retryDelayNanoseconds(status: 429, body: "quota", attempt: 0) == nil)
    }

    @Test func quota503PrecedenceAndAuthFailuresStayNonRotatable() {
        // A 503 whose body signals quota must be treated as quota (no backoff
        // delay), not as plain capacity — quota classification wins.
        let quota503 = #"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#
        #expect(GeminiAPIKeyBank.isQuotaFailure(status: 503, body: quota503))
        #expect(GeminiAPIKeyBank.isCapacityFailure(status: 503, body: quota503))
        #expect(GeminiAPIKeyBank.isRotatableFailure(status: 503, body: quota503))
        #expect(GeminiAPIKeyBank.retryDelayNanoseconds(status: 503, body: quota503, attempt: 0) == 400_000_000)

        // Auth failures never rotate, regardless of wording in the body.
        #expect(!GeminiAPIKeyBank.isRotatableFailure(status: 400, body: "API key not valid. Please pass a valid API key."))
        #expect(!GeminiAPIKeyBank.isRotatableFailure(status: 403, body: #"{"error":{"status":"PERMISSION_DENIED"}}"#))
        #expect(!GeminiAPIKeyBank.isRotatableFailure(status: 404, body: "model not found"))
        #expect(GeminiAPIKeyBank.retryDelayNanoseconds(status: 401, body: "unauthorized", attempt: 0) == nil)
    }

    @Test func retryDelayBackoffGrowsPerAttemptAndCaps() {
        let capacity503 = #"{"error":{"code":503,"status":"UNAVAILABLE","message":"high demand"}}"#
        let delays = (0...6).map {
            GeminiAPIKeyBank.retryDelayNanoseconds(status: 503, body: capacity503, attempt: $0)
        }
        #expect(delays == [
            400_000_000,    // attempt 0 → 0.4s
            800_000_000,    // attempt 1 → 0.8s
            1_200_000_000,  // attempt 2 → 1.2s
            1_600_000_000,  // attempt 3 → 1.6s
            2_000_000_000,  // attempt 4 → 2.0s
            2_000_000_000,  // capped
            2_000_000_000   // capped
        ])

        // Non-capacity failures never schedule a backoff delay.
        #expect(GeminiAPIKeyBank.retryDelayNanoseconds(status: 500, body: "internal", attempt: 0) == nil)
    }

    @Test func normalizeStripsEmptySlotsSoRotationNeverSeesEmptyKeys() {
        // Whitespace/blank entries must not become phantom rotation keys.
        // Empty slots are preserved positionally (Settings per-row editing) but
        // enabledKeys never surfaces them, so runtime rotation never sends "".
        var bank = GeminiAPIKeyBank(entries: ["real-key", "", "   "])
        #expect(bank.enabledKeys == ["real-key"])
        #expect(bank.configuredCount == 1)

        // addKey appends a slot only under maxKeys; a blank slot still cannot rotate.
        bank.addKey("")
        bank.addKey("second-key")
        #expect(bank.enabledKeys == ["real-key", "second-key"])
        #expect(bank.configuredCount == 2)

        // updateKey on a disabled slot preserves the disable marker on the new key.
        var disabledBank = GeminiAPIKeyBank(entries: ["\(GeminiAPIKeyBank.disabledPrefix)old"])
        disabledBank.updateKey("new-key", at: 0)
        #expect(disabledBank.isDisabled(at: 0))
        #expect(disabledBank.cleanKey(at: 0) == "new-key")
        #expect(disabledBank.enabledKeys.isEmpty)
    }

    @Test func appSettingLegacyDecodesWhenOnlyGeminiKeysBankIsStored() throws {
        // Forward-compatibility: settings written by a build storing only the
        // multi-key array must decode with the bank intact and primary synced.
        let json = """
        {
          "geminiKeys": ["first-key", "#DISABLED#second-key"],
          "openaiKey": "",
          "anthropicKey": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(decoded.geminiKey == "first-key")
        #expect(decoded.geminiKeys == ["first-key", "#DISABLED#second-key"])
        #expect(decoded.geminiKeyBank.enabledKeys == ["first-key"])
        #expect(decoded.geminiKeyBank.configuredCount == 2)

        // Toggling the second key on via the bank syncs the legacy array and
        // leaves the primary untouched (first enabled stays primary).
        var settings = decoded
        var bank = settings.geminiKeyBank
        bank.toggleDisabled(at: 1)
        settings.geminiKeyBank = bank
        #expect(settings.geminiKeyBank.enabledKeys == ["first-key", "second-key"])
        #expect(settings.geminiKey == "first-key")
        #expect(settings.geminiKeys == ["first-key", "second-key"])
    }

    @Test func appSettingsMigratesLegacySingleKeyAndKeepsPrimaryInSync() throws {
        let legacyJSON = """
        {
          "geminiKey": "legacy-key",
          "openaiKey": "",
          "anthropicKey": "",
          "geminiBudgetUsd": 0,
          "openaiBudgetUsd": 0,
          "theme": "dark",
          "fontSize": "md",
          "fontScale": 1,
          "fontFamily": "mono",
          "chunkDurationMin": 10,
          "sliceMode": "silence",
          "silenceThreshDb": -40,
          "minSilenceMs": 700,
          "defaultSourceLang": "auto",
          "transcriptionProvider": "whisperkit",
          "translationProvider": "none",
          "defaultTargetLang": "en",
          "localAsrModels": {},
          "localTranslationModels": {},
          "promptPresets": {},
          "usage": {},
          "glossary": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        #expect(decoded.geminiKey == "legacy-key")
        #expect(decoded.geminiKeys == ["legacy-key"])
        #expect(decoded.geminiKeyBank.enabledKeys == ["legacy-key"])

        var settings = AppSettings.defaults
        settings.geminiKey = "single"
        #expect(settings.geminiKeys == ["single"])
        #expect(settings.geminiKeyBank.primaryKey == "single")

        settings.geminiKeyBank = GeminiAPIKeyBank(entries: ["first", "second"])
        #expect(settings.geminiKey == "first")
        #expect(settings.geminiKeys == ["first", "second"])

        let encoded = try JSONEncoder().encode(settings)
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(roundTrip.geminiKey == "first")
        #expect(roundTrip.geminiKeys == ["first", "second"])
    }

    @Test func providerRegistryExposesGeminiWhenAnyEnabledKeyExists() {
        var settings = AppSettings.defaults
        settings.geminiKeyBank = GeminiAPIKeyBank(entries: [
            "\(GeminiAPIKeyBank.disabledPrefix)dead",
            "live-key"
        ])

        let transcription = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        #expect(transcription.contains(where: { $0.id == "gemini-cloud" }))

        let translation = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: "en")
        #expect(translation.providers.contains(where: { $0.id == "gemini-cloud" }))

        settings.geminiKeyBank = GeminiAPIKeyBank(entries: [
            "\(GeminiAPIKeyBank.disabledPrefix)dead"
        ])
        let emptyTranscription = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        #expect(!emptyTranscription.contains(where: { $0.id == "gemini-cloud" }))
    }
}
