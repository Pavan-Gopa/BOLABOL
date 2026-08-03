import Combine
import Foundation

public enum GlossaryDraftSide: String, Codable, Equatable, Sendable {
    case source
    case translation
}

public enum GlossaryStoreError: LocalizedError, Equatable, Sendable {
    case invalidCSV
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .invalidCSV:
            "The glossary CSV file is invalid."
        case .invalidJSON:
            "The glossary JSON file is invalid."
        }
    }
}

@MainActor
public final class GlossaryStore: ObservableObject {
    @Published public private(set) var settings: GlossarySettings {
        didSet {
            saveSettings()
        }
    }

    private let fileManager: FileManager
    private let glossaryFileURL: URL
    private let isPersistenceEnabled: Bool
    private var isSavingEnabled = false

    public init(
        settings: GlossarySettings? = nil,
        fileManager: FileManager = .default,
        glossaryFileURL: URL? = nil,
        isPersistenceEnabled: Bool = false
    ) {
        self.fileManager = fileManager
        self.glossaryFileURL = glossaryFileURL ?? Self.defaultGlossaryFileURL(fileManager: fileManager)
        self.isPersistenceEnabled = isPersistenceEnabled

        if let settings {
            self.settings = Self.preparedSettings(settings)
        } else if isPersistenceEnabled,
                  let loadedSettings = Self.loadSettings(from: self.glossaryFileURL, fileManager: fileManager) {
            self.settings = Self.preparedSettings(loadedSettings)
        } else {
            self.settings = GlossarySettings()
        }

        self.isSavingEnabled = true
    }

    public static func live() -> GlossaryStore {
        GlossaryStore(isPersistenceEnabled: true)
    }

    public var categories: [String] {
        settings.entries
            .compactMap { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
    }

    public func setAuthorTranscriptionLanguage(_ language: String, now: Date = .now) {
        let oldAuthorLanguage = settings.authorTranscriptionLanguage
        let oldAutoTranslationLanguage = settings.autoTranslationLanguage
        let nextAuthorLanguage = GlossaryLanguageCatalog.normalizedName(
            language,
            fallback: oldAuthorLanguage
        )
        guard oldAuthorLanguage.localizedCaseInsensitiveCompare(nextAuthorLanguage) != .orderedSame else {
            return
        }

        let nextAutoTranslationLanguage = nextAuthorLanguage.localizedCaseInsensitiveCompare(oldAutoTranslationLanguage) == .orderedSame
            ? oldAuthorLanguage
            : oldAutoTranslationLanguage

        var nextSettings = settings
        nextSettings.authorTranscriptionLanguage = nextAuthorLanguage
        nextSettings.autoTranslationLanguage = nextAutoTranslationLanguage
        nextSettings.entries = settings.entries.map { entry in
            let recorded = Self.recordedLanguageForms(
                entry,
                authorLanguage: oldAuthorLanguage,
                autoTranslationLanguage: oldAutoTranslationLanguage,
                now: nil
            )
            return Self.localizedEntry(
                recorded,
                authorLanguage: nextAuthorLanguage,
                autoTranslationLanguage: nextAutoTranslationLanguage,
                now: now
            )
        }
        settings = nextSettings
    }

    public func setAutoTranslationLanguage(_ language: String, now: Date = .now) {
        let oldAuthorLanguage = settings.authorTranscriptionLanguage
        let oldAutoTranslationLanguage = settings.autoTranslationLanguage
        let nextAutoTranslationLanguage = GlossaryLanguageCatalog.normalizedName(
            language,
            fallback: oldAutoTranslationLanguage
        )
        guard oldAutoTranslationLanguage.localizedCaseInsensitiveCompare(nextAutoTranslationLanguage) != .orderedSame else {
            return
        }

        var nextSettings = settings
        nextSettings.autoTranslationLanguage = nextAutoTranslationLanguage
        nextSettings.entries = settings.entries.map { entry in
            let recorded = Self.recordedLanguageForms(
                entry,
                authorLanguage: oldAuthorLanguage,
                autoTranslationLanguage: oldAutoTranslationLanguage,
                now: nil
            )
            return Self.localizedEntry(
                recorded,
                authorLanguage: oldAuthorLanguage,
                autoTranslationLanguage: nextAutoTranslationLanguage,
                now: now
            )
        }
        settings = nextSettings
    }

    public func replaceEntries(_ entries: [GlossaryEntry]) {
        settings.entries = entries.map {
            Self.preparedEntry(
                $0,
                authorLanguage: settings.authorTranscriptionLanguage,
                autoTranslationLanguage: settings.autoTranslationLanguage,
                now: nil
            )
        }
    }

    public func clearEntries() {
        settings.entries = []
    }

    public func resetToStarterGlossary() {
        replaceEntries(StarterGlossary.entries)
    }

    public func mergeStarterGlossary() {
        replaceEntries(StarterGlossary.mergeStarterGlossary(settings.entries))
    }

    public func upsert(_ entry: GlossaryEntry) {
        let prepared = Self.preparedEntry(
            Self.recordedLanguageForms(
                entry,
                authorLanguage: settings.authorTranscriptionLanguage,
                autoTranslationLanguage: settings.autoTranslationLanguage,
                now: nil
            ),
            authorLanguage: settings.authorTranscriptionLanguage,
            autoTranslationLanguage: settings.autoTranslationLanguage,
            now: nil
        )
        if let index = settings.entries.firstIndex(where: { $0.id == entry.id }) {
            settings.entries[index] = prepared
        } else {
            settings.entries.append(prepared)
        }
    }

    public func delete(_ entryID: GlossaryEntry.ID) {
        settings.entries.removeAll { $0.id == entryID }
    }

    public func addGlossaryVariants(
        to entryID: GlossaryEntry.ID,
        variants: [String],
        now: Date = .now
    ) {
        guard let index = settings.entries.firstIndex(where: { $0.id == entryID }) else { return }

        var entry = settings.entries[index]
        entry.variants = (entry.variants + variants)
            .cleanedGlossaryValues(excluding: Self.correctForms(for: entry))
        entry.updatedAt = Self.isoString(from: now)
        settings.entries[index] = entry
    }

    public func mergeEntry(
        _ sourceEntryID: GlossaryEntry.ID,
        into targetEntryID: GlossaryEntry.ID,
        now: Date = .now
    ) {
        guard sourceEntryID != targetEntryID,
              let sourceIndex = settings.entries.firstIndex(where: { $0.id == sourceEntryID }),
              let targetIndex = settings.entries.firstIndex(where: { $0.id == targetEntryID })
        else {
            return
        }

        let source = settings.entries[sourceIndex]
        var target = settings.entries[targetIndex]
        target.variants = (
            target.variants
                + source.variants
                + [source.source, source.translation]
                + Array(source.translations.values)
        )
        .cleanedGlossaryValues(excluding: Self.correctForms(for: target))
        target.updatedAt = Self.isoString(from: now)

        settings.entries[targetIndex] = target
        settings.entries.removeAll { $0.id == sourceEntryID }
    }

    @discardableResult
    public func createGlossaryEntryFromReview(
        selectedText: String,
        source: String,
        translation: String,
        category: String?,
        side: GlossaryDraftSide = .source,
        now: Date = .now
    ) -> GlossaryEntry {
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = Self.isoString(from: now)
        let variants = [selectedText].cleanedGlossaryValues(
            excluding: [cleanSource, cleanTranslation]
        )
        let fallbackSource = side == .source ? selectedText.trimmingCharacters(in: .whitespacesAndNewlines) : cleanSource
        let fallbackTranslation = side == .translation ? selectedText.trimmingCharacters(in: .whitespacesAndNewlines) : cleanTranslation
        let finalSource = cleanSource.isEmpty ? fallbackSource : cleanSource
        let finalTranslation = cleanTranslation.isEmpty ? fallbackTranslation : cleanTranslation
        var translations: [String: String] = [:]
        Self.setLanguageForm(finalSource, for: settings.authorTranscriptionLanguage, in: &translations)
        Self.setLanguageForm(finalTranslation, for: settings.autoTranslationLanguage, in: &translations)
        Self.setLanguageForm(finalTranslation, for: "Default", in: &translations)

        let entry = GlossaryEntry(
            id: UUID().uuidString,
            variants: variants,
            source: finalSource,
            translation: finalTranslation,
            category: cleanCategory?.isEmpty == true ? nil : cleanCategory,
            translations: translations,
            remember: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        settings.entries.append(entry)
        return entry
    }

    public func apply(
        to text: String,
        target: GlossaryTextRewriter.Target,
        language: String? = nil
    ) -> GlossaryTextRewriter.Result {
        guard settings.enabled else {
            return GlossaryTextRewriter.Result(text: text, count: 0)
        }
        let translationLanguage = target == .translation
            ? GlossaryLanguageCatalog.normalizedName(
                language ?? settings.autoTranslationLanguage,
                fallback: settings.autoTranslationLanguage
            )
            : nil
        return GlossaryTextRewriter.apply(
            to: text,
            entries: settings.entries,
            target: target,
            translationLanguage: translationLanguage
        )
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    public func importJSONData(_ data: Data) throws {
        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(GlossarySettings.self, from: data) {
            self.settings = Self.preparedSettings(settings)
            return
        }
        if let entries = try? decoder.decode([GlossaryEntry].self, from: data) {
            replaceEntries(entries)
            return
        }
        throw GlossaryStoreError.invalidJSON
    }

    public func exportCSVData() throws -> Data {
        let rows = [["source", "translation", "category", "variants"]]
            + settings.entries.map { entry in
                [
                    entry.source,
                    entry.translation,
                    entry.category ?? "",
                    entry.variants.joined(separator: ";")
                ]
            }
        let csv = rows
            .map { $0.map(Self.csvEscapedField).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    public func importCSVData(_ data: Data, now: Date = .now) throws {
        guard let csv = String(data: data, encoding: .utf8) else {
            throw GlossaryStoreError.invalidCSV
        }

        let rows = try Self.parseCSV(csv)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
              header.contains("source")
        else {
            throw GlossaryStoreError.invalidCSV
        }

        let sourceIndex = header.firstIndex(of: "source")
        let translationIndex = header.firstIndex(of: "translation")
        let categoryIndex = header.firstIndex(of: "category")
        let variantsIndex = header.firstIndex(of: "variants")
        let timestamp = Self.isoString(from: now)

        let entries = rows.dropFirst().compactMap { row -> GlossaryEntry? in
            let source = sourceIndex.flatMap { row[safe: $0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !source.isEmpty else { return nil }

            let translation = translationIndex.flatMap { row[safe: $0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let category = categoryIndex.flatMap { row[safe: $0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let variants = variantsIndex.flatMap { row[safe: $0] }?
                .split(separator: ";")
                .map(String.init)
                .cleanedGlossaryValues(excluding: [source, translation]) ?? []

            return GlossaryEntry(
                id: UUID().uuidString,
                variants: variants,
                source: source,
                translation: translation,
                category: category?.isEmpty == true ? nil : category,
                translations: Self.translations(
                    source: source,
                    translation: translation,
                    authorLanguage: settings.authorTranscriptionLanguage,
                    autoTranslationLanguage: settings.autoTranslationLanguage
                ),
                remember: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        replaceEntries(entries)
    }

    private func saveSettings() {
        guard isSavingEnabled, isPersistenceEnabled else { return }
        do {
            let directory = glossaryFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try exportJSONData()
            try data.write(to: glossaryFileURL, options: .atomic)
        } catch {
            // Persistence should not interrupt transcription or UI editing.
        }
    }

    private static func loadSettings(
        from url: URL,
        fileManager: FileManager
    ) -> GlossarySettings? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(GlossarySettings.self, from: data) {
            return Self.preparedSettings(settings)
        }
        if let entries = try? decoder.decode([GlossaryEntry].self, from: data) {
            return Self.preparedSettings(GlossarySettings(entries: entries))
        }
        return nil
    }

    private static func defaultGlossaryFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("NativeBolabol", isDirectory: true)
            .appendingPathComponent("glossary.json", isDirectory: false)
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func preparedSettings(_ settings: GlossarySettings) -> GlossarySettings {
        var prepared = settings
        prepared.authorTranscriptionLanguage = GlossaryLanguageCatalog.normalizedName(
            prepared.authorTranscriptionLanguage,
            fallback: GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage
        )
        prepared.autoTranslationLanguage = GlossaryLanguageCatalog.normalizedName(
            prepared.autoTranslationLanguage,
            fallback: GlossaryLanguageCatalog.defaultAutoTranslationLanguage(
                for: prepared.authorTranscriptionLanguage
            )
        )
        prepared.entries = prepared.entries.map {
            preparedEntry(
                $0,
                authorLanguage: prepared.authorTranscriptionLanguage,
                autoTranslationLanguage: prepared.autoTranslationLanguage,
                now: nil
            )
        }
        return prepared
    }

    private static func preparedEntry(
        _ entry: GlossaryEntry,
        authorLanguage: String,
        autoTranslationLanguage: String,
        now: Date?
    ) -> GlossaryEntry {
        let normalizedAuthorLanguage = GlossaryLanguageCatalog.normalizedName(
            authorLanguage,
            fallback: GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage
        )
        let normalizedAutoTranslationLanguage = GlossaryLanguageCatalog.normalizedName(
            autoTranslationLanguage,
            fallback: GlossaryLanguageCatalog.defaultAutoTranslationLanguage(
                for: normalizedAuthorLanguage
            )
        )
        var prepared = entry
        prepared.source = prepared.source.trimmingCharacters(in: .whitespacesAndNewlines)
        prepared.translation = prepared.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        prepared.translations = normalizedTranslations(prepared.translations)

        if languageForm(in: prepared.translations, for: normalizedAuthorLanguage) == nil {
            setLanguageForm(prepared.source, for: normalizedAuthorLanguage, in: &prepared.translations)
        }
        if languageForm(in: prepared.translations, for: normalizedAutoTranslationLanguage) == nil {
            setLanguageForm(prepared.translation, for: normalizedAutoTranslationLanguage, in: &prepared.translations)
        }
        if languageForm(in: prepared.translations, for: "Default") == nil {
            setLanguageForm(prepared.translation, for: "Default", in: &prepared.translations)
        }

        return localizedEntry(
            prepared,
            authorLanguage: normalizedAuthorLanguage,
            autoTranslationLanguage: normalizedAutoTranslationLanguage,
            now: now
        )
    }

    private static func recordedLanguageForms(
        _ entry: GlossaryEntry,
        authorLanguage: String,
        autoTranslationLanguage: String,
        now: Date?
    ) -> GlossaryEntry {
        var recorded = entry
        recorded.source = recorded.source.trimmingCharacters(in: .whitespacesAndNewlines)
        recorded.translation = recorded.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        recorded.translations = normalizedTranslations(recorded.translations)
        setLanguageForm(recorded.source, for: authorLanguage, in: &recorded.translations)
        setLanguageForm(recorded.translation, for: autoTranslationLanguage, in: &recorded.translations)
        setLanguageForm(recorded.translation, for: "Default", in: &recorded.translations)
        if let now {
            recorded.updatedAt = isoString(from: now)
        }
        return recorded
    }

    private static func localizedEntry(
        _ entry: GlossaryEntry,
        authorLanguage: String,
        autoTranslationLanguage: String,
        now: Date?
    ) -> GlossaryEntry {
        var localized = entry
        localized.translations = normalizedTranslations(localized.translations)

        let source = languageForm(in: localized.translations, for: authorLanguage)
            ?? localized.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = languageForm(in: localized.translations, for: autoTranslationLanguage)
            ?? (sameLanguage(authorLanguage, autoTranslationLanguage) ? source : "")

        localized.source = source
        localized.translation = translation
        if let now {
            localized.updatedAt = isoString(from: now)
        }
        return localized
    }

    private static func translations(
        source: String,
        translation: String,
        authorLanguage: String,
        autoTranslationLanguage: String
    ) -> [String: String] {
        var translations: [String: String] = [:]
        setLanguageForm(source, for: authorLanguage, in: &translations)
        setLanguageForm(translation, for: autoTranslationLanguage, in: &translations)
        setLanguageForm(translation, for: "Default", in: &translations)
        return translations
    }

    private static func normalizedTranslations(_ translations: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (language, value) in translations {
            setLanguageForm(value, for: language, in: &normalized)
        }
        return normalized
    }

    private static func languageForm(in translations: [String: String], for language: String) -> String? {
        let normalizedLanguage = normalizedLanguageKey(language)
        guard let value = translations.first(where: { key, _ in
            key.localizedCaseInsensitiveCompare(normalizedLanguage) == .orderedSame
        })?.value else {
            return nil
        }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func setLanguageForm(
        _ value: String,
        for language: String,
        in translations: inout [String: String]
    ) {
        let normalizedLanguage = normalizedLanguageKey(language)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLanguage.isEmpty else { return }

        if let existingKey = translations.keys.first(where: {
            $0.localizedCaseInsensitiveCompare(normalizedLanguage) == .orderedSame
        }) {
            if cleanValue.isEmpty {
                translations.removeValue(forKey: existingKey)
            } else {
                translations[existingKey] = cleanValue
            }
        } else if !cleanValue.isEmpty {
            translations[normalizedLanguage] = cleanValue
        }
    }

    private static func normalizedLanguageKey(_ language: String) -> String {
        let clean = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        guard clean.localizedCaseInsensitiveCompare("Default") != .orderedSame else {
            return "Default"
        }
        return GlossaryLanguageCatalog.normalizedName(clean, fallback: clean)
    }

    private static func correctForms(for entry: GlossaryEntry) -> [String] {
        [entry.source, entry.translation] + Array(entry.translations.values)
    }

    private static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func csvEscapedField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ csv: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]

            if isQuoted {
                if character == "\"" {
                    let nextIndex = csv.index(after: index)
                    if nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                        field.append("\"")
                        index = nextIndex
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isQuoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }

            index = csv.index(after: index)
        }

        if isQuoted {
            throw GlossaryStoreError.invalidCSV
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }
}

private extension Array where Element == String {
    func cleanedGlossaryValues(excluding excludedValues: [String]) -> [String] {
        let excluded = Set(excludedValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            guard !clean.isEmpty, !excluded.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(clean)
        }

        return result
    }

    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }

        return result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
