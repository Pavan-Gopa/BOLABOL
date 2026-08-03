import Foundation
import NativeBolabolCore
import Testing

@MainActor
@Suite("Glossary store")
struct GlossaryStoreTests {
    @Test("default glossary starts empty")
    func defaultGlossaryStartsEmpty() {
        #expect(GlossarySettings().entries.isEmpty)
        #expect(GlossarySettings().authorTranscriptionLanguage == "English")
        #expect(GlossarySettings().autoTranslationLanguage == "Russian")
    }

    @Test("decodes legacy glossary settings without language fields")
    func decodesLegacyGlossarySettingsWithoutLanguageFields() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "enabled": true,
          "entries": []
        }
        """.utf8)

        let settings = try JSONDecoder().decode(GlossarySettings.self, from: data)

        #expect(settings.authorTranscriptionLanguage == "English")
        #expect(settings.autoTranslationLanguage == "Russian")
        #expect(settings.entries.isEmpty)
    }

    @Test("decodes legacy basic language settings")
    func decodesLegacyBasicLanguageSettings() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "enabled": true,
          "basicLanguage": "russian",
          "entries": []
        }
        """.utf8)

        let settings = try JSONDecoder().decode(GlossarySettings.self, from: data)

        #expect(settings.authorTranscriptionLanguage == "Russian")
        #expect(settings.autoTranslationLanguage == "English")
        #expect(settings.entries.isEmpty)
    }

    @Test("author transcription language controls source and translation glossary targets")
    func authorTranscriptionLanguageControlsSourceAndTranslationTargets() {
        let entry = GlossaryEntry(
            id: "prabhupada",
            variants: ["Шрила Прабупада"],
            source: "Śrīla Prabhupāda",
            translation: "Шрила Прабхупада",
            category: "Teachers",
            translations: ["Default": "Шрила Прабхупада"],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: [entry]))

        store.setAuthorTranscriptionLanguage("Russian")

        #expect(store.settings.authorTranscriptionLanguage == "Russian")
        #expect(store.settings.autoTranslationLanguage == "English")
        #expect(store.settings.entries.first?.source == "Шрила Прабхупада")
        #expect(store.settings.entries.first?.translation == "Śrīla Prabhupāda")
        #expect(store.apply(to: "Шрила Прабупада пришёл.", target: .source).text == "Шрила Прабхупада пришёл.")
        #expect(store.apply(to: "Шрила Прабупада arrived.", target: .translation).text == "Śrīla Prabhupāda arrived.")
    }

    @Test("arbitrary glossary languages use named translations")
    func arbitraryGlossaryLanguagesUseNamedTranslations() {
        let entry = GlossaryEntry(
            id: "prabhupada",
            variants: ["Srila Prabupada"],
            source: "Śrīla Prabhupāda",
            translation: "Шрила Прабхупада",
            category: "Teachers",
            translations: [
                "Dutch": "Srila Prabhupada",
                "English": "Śrīla Prabhupāda",
                "German": "Srila Prabhupada (Deutsch)",
                "Russian": "Шрила Прабхупада"
            ],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(
            enabled: true,
            authorTranscriptionLanguage: "Dutch",
            autoTranslationLanguage: "German",
            entries: [entry]
        ))

        #expect(store.settings.entries.first?.source == "Srila Prabhupada")
        #expect(store.settings.entries.first?.translation == "Srila Prabhupada (Deutsch)")
        #expect(store.apply(to: "Srila Prabupada spoke.", target: .source).text == "Srila Prabhupada spoke.")
        #expect(store.apply(to: "Srila Prabupada spoke.", target: .translation).text == "Srila Prabhupada (Deutsch) spoke.")
        #expect(store.apply(to: "Srila Prabupada spoke.", target: .translation, language: "English").text == "Śrīla Prabhupāda spoke.")
    }

    @Test("missing auto translation language does not fall back to wrong language")
    func missingAutoTranslationLanguageDoesNotFallBackToWrongLanguage() {
        let entry = GlossaryEntry(
            id: "prabhupada",
            variants: ["Шрила Прабупада"],
            source: "Śrīla Prabhupāda",
            translation: "Шрила Прабхупада",
            category: "Teachers",
            translations: [
                "English": "Śrīla Prabhupāda",
                "Russian": "Шрила Прабхупада"
            ],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: [entry]))

        store.setAutoTranslationLanguage("German")

        #expect(store.settings.autoTranslationLanguage == "German")
        #expect(store.settings.entries.first?.translation == "")
        let result = store.apply(to: "Шрила Прабупада spoke.", target: .translation)
        #expect(result.text == "Шрила Прабупада spoke.")
        #expect(result.count == 0)
    }

    @Test("review entry stores selected misspelling as variant for author language")
    func reviewEntryStoresSelectedMisspellingAsVariantForAuthorLanguage() {
        let store = GlossaryStore(settings: GlossarySettings(
            enabled: true,
            authorTranscriptionLanguage: "Russian",
            autoTranslationLanguage: "English",
            entries: []
        ))

        _ = store.createGlossaryEntryFromReview(
            selectedText: "Прабу",
            source: "прабху",
            translation: "Prabhu",
            category: "Vaishnava",
            side: .source
        )

        #expect(store.settings.entries.first?.variants == ["Прабу"])
        #expect(store.settings.entries.first?.translations["Russian"] == "прабху")
        #expect(store.settings.entries.first?.translations["English"] == "Prabhu")
        #expect(store.apply(to: "Прабу сказал.", target: .source).text == "прабху сказал.")
        #expect(store.apply(to: "Прабу spoke.", target: .translation).text == "Prabhu spoke.")
    }

    @Test("creates review entries and applies source rewrite")
    func createsReviewEntriesAndAppliesSourceRewrite() {
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: []))

        let entry = store.createGlossaryEntryFromReview(
            selectedText: "Jipatake Maharaj",
            source: "Jayapataka Maharaja",
            translation: "Джаяпатака Махарадж",
            category: "Teachers",
            side: .source,
            now: Date(timeIntervalSince1970: 1_783_036_800)
        )

        #expect(store.settings.entries.count == 1)
        #expect(entry.variants == ["Jipatake Maharaj"])
        #expect(entry.source == "Jayapataka Maharaja")
        #expect(entry.translation == "Джаяпатака Махарадж")
        #expect(entry.category == "Teachers")

        let result = store.apply(to: "Jipatake Maharaj spoke.", target: .source)
        #expect(result.text == "Jayapataka Maharaja spoke.")
        #expect(result.count == 1)
    }

    @Test("adds variants without duplicates")
    func addsVariantsWithoutDuplicates() {
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: []))
        let entry = store.createGlossaryEntryFromReview(
            selectedText: "Jay Pataka",
            source: "Jayapataka Maharaja",
            translation: "",
            category: nil,
            side: .source
        )

        store.addGlossaryVariants(
            to: entry.id,
            variants: ["Jay Pataka", "Jipatake Maharaj", "jipatake maharaj", "  "]
        )

        #expect(store.settings.entries.first?.variants == ["Jay Pataka", "Jipatake Maharaj"])
    }

    @Test("disabled glossary leaves text unchanged")
    func disabledGlossaryLeavesTextUnchanged() {
        let entry = GlossaryEntry(
            id: "g1",
            variants: ["Krishna"],
            source: "Kṛṣṇa",
            translation: "Кришна",
            category: nil,
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(enabled: false, entries: [entry]))

        let result = store.apply(to: "Krishna", target: .source)

        #expect(result.text == "Krishna")
        #expect(result.count == 0)
    }

    @Test("merges entries into target entry")
    func mergesEntriesIntoTargetEntry() {
        let target = GlossaryEntry(
            id: "target",
            variants: ["Krishna"],
            source: "Kṛṣṇa",
            translation: "Кришна",
            category: "Names",
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let source = GlossaryEntry(
            id: "source",
            variants: ["Krsna"],
            source: "Krushna",
            translation: "Кришна",
            category: "Names",
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: [target, source]))

        store.mergeEntry(source.id, into: target.id)

        #expect(store.settings.entries.count == 1)
        #expect(store.settings.entries.first?.id == "target")
        #expect(store.settings.entries.first?.variants == ["Krishna", "Krsna", "Krushna"])
    }

    @Test("clears all glossary entries")
    func clearsAllGlossaryEntries() {
        let entry = GlossaryEntry(
            id: "g1",
            variants: ["Krishna"],
            source: "Kṛṣṇa",
            translation: "Кришна",
            category: "Names",
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: [entry]))

        store.clearEntries()

        #expect(store.settings.entries.isEmpty)
        #expect(store.settings.enabled)
    }

    @Test("category selection maps existing custom and empty values")
    func categorySelectionMapsExistingCustomAndEmptyValues() {
        let categories = ["Names", "Teachers"]

        #expect(GlossaryCategorySelection.selectionID(for: "Teachers", categories: categories) == "Teachers")
        #expect(GlossaryCategorySelection.selectionID(for: "New Topic", categories: categories) == GlossaryCategorySelection.customID)
        #expect(GlossaryCategorySelection.selectionID(for: "   ", categories: categories) == GlossaryCategorySelection.noneID)

        #expect(GlossaryCategorySelection.categoryValue(for: "Names") == "Names")
        #expect(GlossaryCategorySelection.categoryValue(for: GlossaryCategorySelection.noneID) == "")
        #expect(GlossaryCategorySelection.categoryValue(for: GlossaryCategorySelection.customID, currentCategory: "Teachers", categories: categories) == "")
        #expect(GlossaryCategorySelection.categoryValue(for: GlossaryCategorySelection.customID, currentCategory: "New Topic", categories: categories) == "New Topic")
    }

    @Test("entry search filters merge targets by visible fields")
    func entrySearchFiltersMergeTargetsByVisibleFields() {
        let krishna = GlossaryEntry(
            id: "krishna",
            variants: ["Krishna", "Krsna"],
            source: "Kṛṣṇa",
            translation: "Кришна",
            category: "Names",
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let teacher = GlossaryEntry(
            id: "teacher",
            variants: ["Srila Prabhupada"],
            source: "Śrīla Prabhupāda",
            translation: "Шрила Прабхупада",
            category: "Teachers",
            translations: [:],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )
        let entries = [krishna, teacher]

        #expect(GlossaryEntrySearch.filter(entries, query: "krs").map(\.id) == ["krishna"])
        #expect(GlossaryEntrySearch.filter(entries, query: "teacher").map(\.id) == ["teacher"])
        #expect(GlossaryEntrySearch.filter(entries, query: "  ").map(\.id) == ["krishna", "teacher"])
    }

    @Test("persists glossary JSON container")
    func persistsGlossaryJSONContainer() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-bolabol-glossary-\(UUID().uuidString)")
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(
            settings: GlossarySettings(enabled: true, entries: []),
            glossaryFileURL: url,
            isPersistenceEnabled: true
        )
        _ = store.createGlossaryEntryFromReview(
            selectedText: "Krishna",
            source: "Kṛṣṇa",
            translation: "Кришна",
            category: "Names"
        )

        let reloaded = GlossaryStore(glossaryFileURL: url, isPersistenceEnabled: true)

        #expect(reloaded.settings.enabled)
        #expect(reloaded.settings.entries.count == 1)
        #expect(reloaded.settings.entries.first?.source == "Kṛṣṇa")
    }

    @Test("imports and exports CSV")
    func importsAndExportsCSV() throws {
        let store = GlossaryStore(settings: GlossarySettings(enabled: true, entries: []))
        try store.importCSVData(
            Data("source,translation,category,variants\nKṛṣṇa,Кришна,Names,\"Krishna;Krsna\"\n".utf8)
        )

        #expect(store.settings.entries.first?.source == "Kṛṣṇa")
        #expect(store.settings.entries.first?.variants == ["Krishna", "Krsna"])

        let exported = String(data: try store.exportCSVData(), encoding: .utf8)
        #expect(exported?.contains("Kṛṣṇa") == true)
        #expect(exported?.contains("Krishna;Krsna") == true)
    }
}
