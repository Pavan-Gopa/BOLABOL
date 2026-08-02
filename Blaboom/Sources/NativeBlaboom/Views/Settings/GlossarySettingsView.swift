import AppKit
import NativeBlaboomCore
import SwiftUI
import UniformTypeIdentifiers

private enum GlossarySettingsLayout {
    static let headerControlHeight: CGFloat = 44
    static let headerLabelHeight: CGFloat = 12
    static let pickerHeight: CGFloat = 24
    static let toggleWidth: CGFloat = 96
    static let languageWidth: CGFloat = 136
    static let categoryFilterWidth: CGFloat = 180
}

@MainActor
struct GlossarySettingsView: View {
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    @State private var searchText = ""
    @State private var selectedCategory = Self.allCategoriesID
    @State private var newSource = ""
    @State private var newTranslation = ""
    @State private var newCategory = ""
    @State private var newVariants = ""
    @State private var statusMessage: String?
    @State private var isShowingClearConfirmation = false

    private static let allCategoriesID = "__all__"

    private var filteredEntries: [GlossaryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return glossaryStore.settings.entries
            .filter { entry in
                selectedCategory == Self.allCategoriesID || entry.category == selectedCategory
            }
            .filter { entry in
                guard !query.isEmpty else { return true }
                let haystack = ([entry.source, entry.translation, entry.category ?? ""] + entry.variants)
                    .joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            newEntryEditor

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredEntries) { entry in
                        GlossaryEntryRow(entry: entry)
                            .environmentObject(glossaryStore)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlayScrollbar()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(generalSettingsStore.text(.clearGlossaryTitle), isPresented: $isShowingClearConfirmation) {
            Button(generalSettingsStore.text(.cancel), role: .cancel) {}
            Button(generalSettingsStore.text(.clearGlossary), role: .destructive) {
                glossaryStore.clearEntries()
                searchText = ""
                selectedCategory = Self.allCategoriesID
                statusMessage = generalSettingsStore.text(.glossaryCleared)
            }
        } message: {
            Text(generalSettingsStore.text(.clearGlossaryMessage))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                GlossaryToggleControl(
                    isOn: Binding(
                        get: { glossaryStore.settings.enabled },
                        set: { glossaryStore.setEnabled($0) }
                    )
                )

                GlossaryLanguageSelector(
                    title: generalSettingsStore.text(.transcriptionModel),
                    currentLanguage: glossaryStore.settings.authorTranscriptionLanguage
                ) { language in
                    glossaryStore.setAuthorTranscriptionLanguage(language)
                    statusMessage = generalSettingsStore.formattedText(.transcriptionLanguageSetTo, language)
                }

                GlossaryLanguageSelector(
                    title: generalSettingsStore.text(.translation),
                    currentLanguage: glossaryStore.settings.autoTranslationLanguage
                ) { language in
                    glossaryStore.setAutoTranslationLanguage(language)
                    statusMessage = generalSettingsStore.formattedText(.translationLanguageSetTo, language)
                }

                Spacer()

                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label(generalSettingsStore.text(.clearGlossary), systemImage: "trash")
                }
                .disabled(glossaryStore.settings.entries.isEmpty)
                .controlSize(.regular)
                .frame(height: GlossarySettingsLayout.pickerHeight, alignment: .bottom)

                Menu {
                    Button(generalSettingsStore.text(.importJSON)) { importJSON() }
                    Button(generalSettingsStore.text(.importCSV)) { importCSV() }
                    Divider()
                    Button(generalSettingsStore.text(.exportJSON)) { exportJSON() }
                    Button(generalSettingsStore.text(.exportCSV)) { exportCSV() }
                } label: {
                    Label(generalSettingsStore.text(.importExport), systemImage: "square.and.arrow.up.on.square")
                }
                .controlSize(.regular)
                .frame(height: GlossarySettingsLayout.pickerHeight, alignment: .bottom)
            }
            .frame(height: GlossarySettingsLayout.headerControlHeight, alignment: .bottom)

            HStack(spacing: 10) {
                TextField(generalSettingsStore.text(.search), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker(generalSettingsStore.text(.category), selection: $selectedCategory) {
                    Text(generalSettingsStore.text(.allCategories)).tag(Self.allCategoriesID)
                    ForEach(glossaryStore.categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: GlossarySettingsLayout.categoryFilterWidth)
            }
        }
    }

    private var newEntryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(generalSettingsStore.text(.newEntry))
                .font(.headline)

            HStack(spacing: 8) {
                TextField(newSourceTitle, text: $newSource)
                    .textFieldStyle(.roundedBorder)
                TextField(newTranslationTitle, text: $newTranslation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                GlossaryCategoryPicker(
                    category: $newCategory,
                    categories: glossaryStore.categories
                )
                TextField(generalSettingsStore.text(.variantsSeparatedBySemicolons), text: $newVariants)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button {
                    createEntry()
                } label: {
                    Label(generalSettingsStore.text(.addEntry), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5))
        }
    }

    private func createEntry() {
        let source = newSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        let translation = newTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = isoString(from: .now)
        var translations: [String: String] = [:]
        translations[glossaryStore.settings.authorTranscriptionLanguage] = source
        if !translation.isEmpty {
            translations[glossaryStore.settings.autoTranslationLanguage] = translation
            translations["Default"] = translation
        }
        let entry = GlossaryEntry(
            id: UUID().uuidString,
            variants: splitVariants(newVariants, excluding: [source, translation]),
            source: source,
            translation: translation,
            category: category.isEmpty ? nil : category,
            translations: translations,
            remember: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        glossaryStore.upsert(entry)
        newSource = ""
        newTranslation = ""
        newCategory = ""
        newVariants = ""
        statusMessage = generalSettingsStore.text(.entryAdded)
    }

    private func importJSON() {
        guard let url = openPanel(allowedExtensions: ["json"]) else { return }
        do {
            try glossaryStore.importJSONData(Data(contentsOf: url))
            statusMessage = generalSettingsStore.text(.jsonImported)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importCSV() {
        guard let url = openPanel(allowedExtensions: ["csv"]) else { return }
        do {
            try glossaryStore.importCSVData(Data(contentsOf: url))
            statusMessage = generalSettingsStore.text(.csvImported)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exportJSON() {
        guard let url = savePanel(defaultName: "Blaboom-glossary.json") else { return }
        do {
            try glossaryStore.exportJSONData().write(to: url, options: .atomic)
            statusMessage = generalSettingsStore.text(.jsonExported)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        guard let url = savePanel(defaultName: "Blaboom-glossary.csv") else { return }
        do {
            try glossaryStore.exportCSVData().write(to: url, options: .atomic)
            statusMessage = generalSettingsStore.text(.csvExported)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openPanel(allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func savePanel(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    private var authorLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: glossaryStore.settings.authorTranscriptionLanguage)
    }

    private var autoTranslationLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: glossaryStore.settings.autoTranslationLanguage)
    }

    private var newSourceTitle: String {
        generalSettingsStore.formattedText(.languageForm, authorLanguageName)
    }

    private var newTranslationTitle: String {
        generalSettingsStore.formattedText(.languageForm, autoTranslationLanguageName)
    }

}

private struct GlossaryToggleControl: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    let isOn: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(generalSettingsStore.text(.useGlossary))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(
                    width: GlossarySettingsLayout.toggleWidth,
                    height: GlossarySettingsLayout.headerLabelHeight,
                    alignment: .leading
                )

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(
                    width: GlossarySettingsLayout.toggleWidth,
                    height: GlossarySettingsLayout.pickerHeight,
                    alignment: .leading
                )
        }
        .frame(
            width: GlossarySettingsLayout.toggleWidth,
            height: GlossarySettingsLayout.headerControlHeight,
            alignment: .bottomLeading
        )
    }
}

private struct GlossaryLanguageSelector: View {
    private static let customLanguageID = "__custom_glossary_language__"

    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    let title: String
    let currentLanguage: String
    let onChange: (String) -> Void

    @State private var isShowingCustomLanguage = false
    @State private var customLanguage = ""

    private var selection: Binding<String> {
        Binding(
            get: {
                optionLanguages.contains {
                    $0.localizedCaseInsensitiveCompare(currentLanguage) == .orderedSame
                } ? currentLanguage : Self.customLanguageID
            },
            set: { value in
                guard value != Self.customLanguageID else {
                    customLanguage = currentLanguage
                    isShowingCustomLanguage = true
                    return
                }
                onChange(value)
            }
        )
    }

    private var optionLanguages: [String] {
        var options = GlossaryLanguageCatalog.builtIn.map(\.name)
        if !currentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !options.contains(where: { $0.localizedCaseInsensitiveCompare(currentLanguage) == .orderedSame }) {
            options.append(currentLanguage)
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: GlossarySettingsLayout.languageWidth,
                    height: GlossarySettingsLayout.headerLabelHeight,
                    alignment: .leading
                )

            Picker(title, selection: selection) {
                ForEach(optionLanguages, id: \.self) { language in
                    Text(language).tag(language)
                }
                Text(generalSettingsStore.text(.custom)).tag(Self.customLanguageID)
            }
            .labelsHidden()
            .controlSize(.regular)
            .frame(
                width: GlossarySettingsLayout.languageWidth,
                height: GlossarySettingsLayout.pickerHeight
            )
        }
        .frame(
            width: GlossarySettingsLayout.languageWidth,
            height: GlossarySettingsLayout.headerControlHeight,
            alignment: .bottomLeading
        )
        .popover(isPresented: $isShowingCustomLanguage) {
            customLanguagePopover
        }
    }

    private var customLanguagePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(generalSettingsStore.text(.customLanguage))
                .font(.headline)

            TextField(generalSettingsStore.text(.targetLanguage), text: $customLanguage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitDraft)

            HStack {
                Spacer()
                Button(generalSettingsStore.text(.cancel)) {
                    isShowingCustomLanguage = false
                }
                Button(generalSettingsStore.text(.apply)) {
                    commitDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(customLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func commitDraft() {
        let clean = customLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        onChange(clean)
        isShowingCustomLanguage = false
    }
}

private struct GlossaryEntryRow: View {
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    let entry: GlossaryEntry

    @State private var draft: GlossaryEntry
    @State private var variantsText: String
    @State private var isShowingMergePicker = false
    @State private var mergeQuery = ""

    init(entry: GlossaryEntry) {
        self.entry = entry
        _draft = State(initialValue: entry)
        _variantsText = State(initialValue: entry.variants.joined(separator: "; "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(sourceTitle, text: $draft.source)
                    .textFieldStyle(.roundedBorder)
                TextField(translationTitle, text: $draft.translation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                GlossaryCategoryPicker(
                    category: categoryBinding,
                    categories: glossaryStore.categories
                )
                TextField(generalSettingsStore.text(.variants), text: $variantsText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Spacer()

                Button {
                    isShowingMergePicker.toggle()
                } label: {
                    Label(generalSettingsStore.text(.mergeInto), systemImage: "arrow.triangle.merge")
                }
                .disabled(glossaryStore.settings.entries.count < 2)
                .popover(isPresented: $isShowingMergePicker) {
                    GlossaryMergeTargetPicker(
                        currentEntryID: draft.id,
                        entries: glossaryStore.settings.entries,
                        query: $mergeQuery
                    ) { targetID in
                        glossaryStore.mergeEntry(draft.id, into: targetID)
                        mergeQuery = ""
                        isShowingMergePicker = false
                    }
                }

                Button {
                    save()
                } label: {
                    Label(generalSettingsStore.text(.save), systemImage: "checkmark")
                }
                .disabled(draft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    glossaryStore.delete(draft.id)
                } label: {
                    Label(generalSettingsStore.text(.delete), systemImage: "trash")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5))
        }
        .onChange(of: entry) { _, newEntry in
            syncDraft(with: newEntry)
        }
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { draft.category ?? "" },
            set: { draft.category = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private var authorLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: glossaryStore.settings.authorTranscriptionLanguage)
    }

    private var autoTranslationLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: glossaryStore.settings.autoTranslationLanguage)
    }

    private var sourceTitle: String {
        generalSettingsStore.formattedText(.languageForm, authorLanguageName)
    }

    private var translationTitle: String {
        generalSettingsStore.formattedText(.languageForm, autoTranslationLanguageName)
    }

    private func save() {
        let timestamp = isoString(from: .now)
        draft.source = draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.translation = draft.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.variants = splitVariants(variantsText, excluding: [draft.source, draft.translation])
        if draft.translation.isEmpty {
            draft.translations.removeValue(forKey: "Default")
        } else {
            draft.translations["Default"] = draft.translation
        }
        draft.updatedAt = timestamp
        glossaryStore.upsert(draft)
    }

    private func syncDraft(with entry: GlossaryEntry) {
        draft = entry
        variantsText = entry.variants.joined(separator: "; ")
    }
}

private struct GlossaryMergeTargetPicker: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    let currentEntryID: GlossaryEntry.ID
    let entries: [GlossaryEntry]
    @Binding var query: String
    let onSelect: (GlossaryEntry.ID) -> Void

    private var targets: [GlossaryEntry] {
        let candidates = entries
            .filter { $0.id != currentEntryID }
            .sorted { lhs, rhs in
                lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }
        return GlossaryEntrySearch.filter(candidates, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(generalSettingsStore.text(.searchTerm), text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if targets.isEmpty {
                        Text(generalSettingsStore.text(.noMatchingEntries))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(targets) { entry in
                            Button {
                                onSelect(entry.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.source.isEmpty ? entry.translation : entry.source)
                                        .font(.callout.weight(.medium))
                                    if !entry.translation.isEmpty && entry.translation != entry.source {
                                        Text(entry.translation)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !entry.variants.isEmpty {
                                        Text(entry.variants.prefix(3).joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .frame(height: 280)
        }
        .padding(12)
        .frame(width: 380)
    }
}

private func splitVariants(_ value: String, excluding excludedValues: [String]) -> [String] {
    let excluded = Set(excludedValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    var seen = Set<String>()
    var result: [String] = []

    for variant in value.split(separator: ";").map(String.init) {
        let clean = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = clean.lowercased()
        guard !clean.isEmpty, !excluded.contains(key), !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(clean)
    }

    return result
}

private func isoString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
