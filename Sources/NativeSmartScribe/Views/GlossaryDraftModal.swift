import NativeSmartScribeCore
import SwiftUI

struct GlossaryDraftSaveRequest: Equatable {
    var selectedText: String
    var side: GlossaryDraftSide
    var existingEntryID: GlossaryEntry.ID?
    var source: String
    var translation: String
    var category: String?
}

struct GlossaryDraftModal: View {
    private static let newEntryID = "__new_glossary_entry__"

    let selectedText: String
    let initialSide: GlossaryDraftSide
    let authorTranscriptionLanguage: String
    let autoTranslationLanguage: String
    let entries: [GlossaryEntry]
    let categories: [String]
    let onCancel: () -> Void
    let onSave: (GlossaryDraftSaveRequest) -> Void

    @State private var selectedEntryID = Self.newEntryID
    @State private var side: GlossaryDraftSide
    @State private var source: String
    @State private var translation = ""
    @State private var category = ""

    init(
        selectedText: String,
        initialSide: GlossaryDraftSide,
        authorTranscriptionLanguage: String,
        autoTranslationLanguage: String,
        entries: [GlossaryEntry],
        categories: [String],
        onCancel: @escaping () -> Void,
        onSave: @escaping (GlossaryDraftSaveRequest) -> Void
    ) {
        self.selectedText = selectedText
        self.initialSide = initialSide
        self.authorTranscriptionLanguage = authorTranscriptionLanguage
        self.autoTranslationLanguage = autoTranslationLanguage
        self.entries = entries
        self.categories = categories
        self.onCancel = onCancel
        self.onSave = onSave
        _side = State(initialValue: initialSide)
        _source = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Add to Glossary", systemImage: "text.badge.plus")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Selected Variant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            Picker("Target", selection: $selectedEntryID) {
                Text("Create new entry").tag(Self.newEntryID)
                ForEach(entries.sorted { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }) { entry in
                    Text(entry.source.isEmpty ? entry.translation : entry.source).tag(entry.id)
                }
            }

            Picker("Apply As", selection: $side) {
                Text("Author Transcription").tag(GlossaryDraftSide.source)
                Text("Auto-translation").tag(GlossaryDraftSide.translation)
            }
            .pickerStyle(.segmented)

            TextField("Correct \(authorLanguageName) form", text: $source)
                .textFieldStyle(.roundedBorder)
            TextField("\(autoTranslationLanguageName) / auto-translation form", text: $translation)
                .textFieldStyle(.roundedBorder)

            GlossaryCategoryPicker(category: $category, categories: categories)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onChange(of: selectedEntryID) { _, entryID in
            guard entryID != Self.newEntryID,
                  let entry = entries.first(where: { $0.id == entryID })
            else { return }
            source = entry.source
            translation = entry.translation
            category = entry.category ?? ""
        }
    }

    private var isSaveDisabled: Bool {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (selectedEntryID == Self.newEntryID
                && source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            GlossaryDraftSaveRequest(
                selectedText: selectedText,
                side: side,
                existingEntryID: selectedEntryID == Self.newEntryID ? nil : selectedEntryID,
                source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
                category: cleanCategory.isEmpty ? nil : cleanCategory
            )
        )
    }

    private var authorLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: authorTranscriptionLanguage)
    }

    private var autoTranslationLanguageName: String {
        GlossaryLanguageCatalog.displayName(for: autoTranslationLanguage)
    }
}
