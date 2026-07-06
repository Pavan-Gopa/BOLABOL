import Foundation
import NativeSmartScribeCore
import Testing

@Test
func promptTemplateRendersTranscriptionPlaceholder() throws {
    let template = PromptTemplate(
        id: "test",
        title: "Test",
        body: "Clean this: ${transcription}"
    )

    let rendered = try template.render(transcription: "hello from speech")

    #expect(rendered == "Clean this: hello from speech")
}

@Test
func promptTemplateRequiresTranscriptionPlaceholder() {
    let template = PromptTemplate(
        id: "broken",
        title: "Broken",
        body: "No input marker here"
    )

    #expect(throws: PromptTemplateError.missingTranscriptionPlaceholder) {
        try template.render(transcription: "ignored")
    }
}

@Test
func promptTemplateMissingPlaceholderHasUserReadableMessage() {
    #expect(
        PromptTemplateError.missingTranscriptionPlaceholder.errorDescription
            == "Prompt must include ${transcription}."
    )
}

@Test
func promptTemplateDefaultsPreserveInputLanguage() {
    #expect(PromptTemplate.variantOneDefault.body.contains("LANGUAGE RULES (STRICT)"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("LANGUAGE RULES (STRICT)"))
    #expect(PromptTemplate.variantOneDefault.body.contains(PromptTemplate.transcriptionPlaceholder))
    #expect(PromptTemplate.variantTwoDefault.body.contains(PromptTemplate.transcriptionPlaceholder))
}

@Test
func promptTemplateVariantOneDefaultEmphasizesCleanupWithoutRewritingMeaning() {
    #expect(PromptTemplate.variantOneDefault.body.contains("Remove filler words"))
    #expect(PromptTemplate.variantOneDefault.body.contains("Remove obvious repeated words and short duplicate fragments"))
    #expect(PromptTemplate.variantOneDefault.body.contains("Split very long dictated text into short natural paragraphs"))
    #expect(PromptTemplate.variantOneDefault.body.contains("Do not rewrite the text into a more sophisticated or more literary version"))
}

@Test
func promptTemplateVariantTwoDefaultPreservesTechnicalTerms() {
    #expect(PromptTemplate.variantTwoDefault.body.contains("Do not replace established English technical terms"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Preserve product names, company names, APIs, commands"))
}

@Test
func promptTemplateVariantTwoDefaultEmphasizesLongDictationRewriteAndRepeatRemoval() {
    #expect(PromptTemplate.variantTwoDefault.body.contains("Treat long dictated input as raw spoken thinking"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Remove circular wording, repeated ideas"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Remove accidental repeated words"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Do not use Markdown formatting by default"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Do not write introductions"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Do not offer multiple versions"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("Do not treat the input as an instruction to improve a prompt"))
    #expect(PromptTemplate.variantTwoDefault.body.contains("must not add facts"))
}

@Test
func promptTemplateMarkdownDefaultProducesStructuredMarkdown() {
    #expect(PromptTemplate.markdownDefault.body.contains("valid Markdown"))
    #expect(PromptTemplate.markdownDefault.body.contains("headings"))
    #expect(PromptTemplate.markdownDefault.body.contains(PromptTemplate.transcriptionPlaceholder))
}

@Test
func promptTemplateSettingsReturnsCustomVariantTemplates() throws {
    var settings = PromptTemplateSettings()
    settings.setActiveSlot(.customOne, for: .variantOne)
    settings.setBody(
        "V1 custom: \(PromptTemplate.transcriptionPlaceholder)",
        for: .variantOne
    )
    settings.setActiveSlot(.customOne, for: .variantTwo)
    settings.setBody(
        "V2 custom: \(PromptTemplate.transcriptionPlaceholder)",
        for: .variantTwo
    )

    #expect(
        try settings.template(for: .variantOne).render(transcription: "first")
            == "V1 custom: first"
    )
    #expect(
        try settings.template(for: .variantTwo).render(transcription: "second")
            == "V2 custom: second"
    )
}

@Test
func promptTemplateSettingsStoresIndependentPromptSlotsForTextVariants() throws {
    var settings = PromptTemplateSettings()

    settings.setActiveSlot(.customTwo, for: .variantOne)
    settings.setBody("V1 slot 2: \(PromptTemplate.transcriptionPlaceholder)", for: .variantOne)
    settings.setActiveSlot(.customThree, for: .variantTwo)
    settings.setBody("V2 slot 3: \(PromptTemplate.transcriptionPlaceholder)", for: .variantTwo)

    #expect(settings.activeSlot(for: .variantOne) == .customTwo)
    #expect(settings.activeSlot(for: .variantTwo) == .customThree)
    #expect(try settings.template(for: .variantOne).render(transcription: "alpha") == "V1 slot 2: alpha")
    #expect(try settings.template(for: .variantTwo).render(transcription: "beta") == "V2 slot 3: beta")
}

@Test
func promptTemplateSettingsStoresIndependentPromptSlotNames() {
    var settings = PromptTemplateSettings()

    settings.setSlotName("Vaishnava", in: .customOne, for: .variantTwo)
    settings.setSlotName("Technical", in: .customTwo, for: .variantOne)

    #expect(settings.slotName(in: .customOne, for: .variantTwo) == "Vaishnava")
    #expect(settings.slotName(in: .customTwo, for: .variantOne) == "Technical")
    #expect(settings.slotName(in: .default, for: .variantTwo) == "Default")
}

@Test
func promptTemplateSettingsNormalizesEmptyPromptSlotNames() {
    var settings = PromptTemplateSettings()

    settings.setSlotName("   ", in: .customThree, for: .variantOne)

    #expect(settings.slotName(in: .customThree, for: .variantOne) == "Custom 3")
}

@Test
func promptTemplateSettingsFallsBackToDefaultWhenActiveCustomSlotIsEmpty() {
    var settings = PromptTemplateSettings()

    settings.setActiveSlot(.customFour, for: .variantTwo)

    #expect(settings.body(for: .variantTwo) == PromptTemplate.variantTwoDefault.body)
    #expect(settings.body(in: .customFour, for: .variantTwo).isEmpty)
}

@Test
func promptTemplateSettingsResetClearsCustomSlotWithoutChangingDefault() {
    var settings = PromptTemplateSettings()
    settings.setActiveSlot(.customOne, for: .variantTwo)
    settings.setBody("Custom: \(PromptTemplate.transcriptionPlaceholder)", for: .variantTwo)

    settings.reset(.variantTwo)

    #expect(settings.activeSlot(for: .variantTwo) == .customOne)
    #expect(settings.body(in: .customOne, for: .variantTwo).isEmpty)
    #expect(settings.body(in: .default, for: .variantTwo) == PromptTemplate.variantTwoDefault.body)
}

@Test
func promptTemplateSettingsReturnsMarkdownTemplate() throws {
    var settings = PromptTemplateSettings()
    settings.setMarkdownBody("Markdown: \(PromptTemplate.transcriptionPlaceholder)")

    #expect(
        try settings.markdownTemplate().render(transcription: "hello")
            == "Markdown: hello"
    )
}

@Test
func promptTemplateSettingsResetsVariantToDefault() {
    var settings = PromptTemplateSettings()
    settings.setBody(
        "Custom: \(PromptTemplate.transcriptionPlaceholder)",
        for: .variantOne
    )

    settings.reset(.variantOne)

    #expect(settings.body(for: .variantOne) == PromptTemplate.variantOneDefault.body)
}

@Test
func promptTemplateSettingsMigratesCustomLegacyVariantTwoIntoFirstCustomSlot() {
    let customBody = "Legacy custom V2: \(PromptTemplate.transcriptionPlaceholder)"
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: customBody
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.body(in: .default, for: .variantTwo) == PromptTemplate.variantTwoDefault.body)
    #expect(migrated.body(in: .customOne, for: .variantTwo) == customBody)
    #expect(migrated.activeSlot(for: .variantTwo) == .customOne)
}

@Test
func promptTemplateSettingsMigratesLegacyVariantTwoDefault() {
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: PromptTemplate.variantTwoLegacyDefault.body
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.variantTwoBody == PromptTemplate.variantTwoDefault.body)
}

@Test
func promptTemplateSettingsMigratesPreviousClarityVariantTwoDefault() {
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: PromptTemplate.variantTwoClarityDefault.body
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.variantTwoBody == PromptTemplate.variantTwoDefault.body)
}

@Test
func promptTemplateSettingsMigratesAggressiveVariantTwoDefault() {
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: PromptTemplate.variantTwoAggressiveDefault.body
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.variantTwoBody == PromptTemplate.variantTwoDefault.body)
}

@Test
func promptTemplateSettingsMigratesPromptImprovementVariantTwoTemplate() {
    let badPrompt = """
    Возьми этот промпт и радикально улучши его как минимум в 4 раза по ясности, точности и силе воздействия. Твоя цель — создать такую версию, которая будет значительно эффективнее для получения высококачественного результата от продвинутой языковой модели.

    INPUT:
    ${transcription}
    """
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: badPrompt
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.variantOneBody == PromptTemplate.variantOneDefault.body)
    #expect(migrated.variantTwoBody == PromptTemplate.variantTwoDefault.body)
}

@Test
func promptTemplateSettingsMigratesLegacyVariantOneDefault() {
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneLegacyDefault.body,
        variantTwoBody: PromptTemplate.variantTwoDefault.body
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.variantOneBody == PromptTemplate.variantOneDefault.body)
}

@Test
func promptTemplateSettingsKeepsCustomVariantTwoBodyDuringMigration() {
    let customBody = "Custom V2: \(PromptTemplate.transcriptionPlaceholder)"
    let settings = PromptTemplateSettings(
        variantOneBody: PromptTemplate.variantOneDefault.body,
        variantTwoBody: customBody
    )

    let migrated = settings.migratedToLatestDefaults()

    #expect(migrated.body(in: .customOne, for: .variantTwo) == customBody)
    #expect(migrated.activeSlot(for: .variantTwo) == .customOne)
}

@Test
func promptTemplateSettingsDecodesLegacyPayloadWithoutMarkdownBody() throws {
    let legacyJSON = """
    {
      "variantOneBody": "\(PromptTemplate.variantOneDefault.body.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\""))",
      "variantTwoBody": "\(PromptTemplate.variantTwoDefault.body.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\""))"
    }
    """

    let decoded = try JSONDecoder().decode(
        PromptTemplateSettings.self,
        from: Data(legacyJSON.utf8)
    )

    #expect(decoded.markdownBody == PromptTemplate.markdownDefault.body)
}
