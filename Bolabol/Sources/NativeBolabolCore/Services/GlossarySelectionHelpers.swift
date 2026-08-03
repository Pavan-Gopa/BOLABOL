import Foundation

public enum GlossaryCategorySelection {
    public static let noneID = "__glossary_category_none__"
    public static let customID = "__glossary_category_custom__"

    public static func selectionID(
        for category: String,
        categories: [String]
    ) -> String {
        let clean = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return noneID }

        if let existing = categories.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            return existing
        }

        return customID
    }

    public static func categoryValue(
        for selectionID: String,
        currentCategory: String = "",
        categories: [String] = []
    ) -> String {
        switch selectionID {
        case noneID:
            return ""
        case customID:
            let clean = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean == selectionID {
                return ""
            }
            if categories.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                return ""
            }
            return clean
        default:
            return selectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

public enum GlossaryEntrySearch {
    public static func filter(
        _ entries: [GlossaryEntry],
        query: String
    ) -> [GlossaryEntry] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return entries }

        return entries.filter { entry in
            let haystack = ([entry.source, entry.translation, entry.category ?? ""] + entry.variants)
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(cleanQuery)
        }
    }
}
