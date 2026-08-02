import NativeBlaboomCore
import Testing

@Test
func usageStatisticsRecordTracksLastTransactionAndTotals() {
    var settings = UsageStatisticsSettings()

    settings.record(
        modelID: "openai:gpt-4o-mini",
        modelName: "OpenAI GPT-4o mini",
        promptTokens: 12,
        completionTokens: 8
    )
    settings.record(
        modelID: "openai:gpt-4o-mini",
        modelName: "OpenAI GPT-4o mini",
        promptTokens: 3,
        completionTokens: 2
    )

    #expect(settings.lastTransaction.promptTokens == 3)
    #expect(settings.lastTransaction.completionTokens == 2)
    #expect(settings.lastTransaction.totalTokens == 5)
    #expect(settings.totals["openai:gpt-4o-mini"]?.promptTokens == 15)
    #expect(settings.totals["openai:gpt-4o-mini"]?.completionTokens == 10)
    #expect(settings.totals["openai:gpt-4o-mini"]?.totalTokens == 25)
    #expect(settings.modelNames["openai:gpt-4o-mini"] == "OpenAI GPT-4o mini")
}

@Test
func usageStatisticsResetClearsSelectedModelOnly() {
    var settings = UsageStatisticsSettings()
    settings.record(modelID: "a", modelName: "A", promptTokens: 10, completionTokens: 1)
    settings.record(modelID: "b", modelName: "B", promptTokens: 20, completionTokens: 2)

    settings.reset(modelID: "a")

    #expect(settings.totals["a"] == UsageTokenCount())
    #expect(settings.totals["b"]?.totalTokens == 22)
}

@Test
func usageStatisticsResetClearsMultipleModels() {
    var settings = UsageStatisticsSettings()
    settings.record(modelID: "google:gemini-2.5-flash", modelName: "Gemini Flash", promptTokens: 10, completionTokens: 5)
    settings.record(modelID: "google:gemini-2.5-pro", modelName: "Gemini Pro", promptTokens: 20, completionTokens: 10)
    settings.record(modelID: "openai:gpt-4o-mini", modelName: "GPT-4o mini", promptTokens: 50, completionTokens: 25)

    settings.reset(modelIDs: ["google:gemini-2.5-flash", "google:gemini-2.5-pro"])

    #expect(settings.totals["google:gemini-2.5-flash"] == UsageTokenCount())
    #expect(settings.totals["google:gemini-2.5-pro"] == UsageTokenCount())
    #expect(settings.totals["openai:gpt-4o-mini"]?.totalTokens == 75)
}
