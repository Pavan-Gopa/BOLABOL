import Foundation

public enum ShortsIdeaDisplayLanguage: String, Codable, Equatable, Sendable {
    case source
    case target
}

public enum ShortsIdeasExporter {
    public static func renderText(
        plans: [ShortsClipPlan],
        displayLanguage: ShortsIdeaDisplayLanguage
    ) -> String {
        plans.enumerated().map { index, plan in
            let display = displayFields(for: plan, language: displayLanguage)
            var lines = [
                "\(index + 1). \(display.title)",
                "\(plan.start) -> \(plan.end)",
                "Category: \(display.category)",
                "Hook: \(display.hook)",
                "Summary: \(display.summary)"
            ]
            if !display.captionText.isEmpty {
                lines.append("Captions:\n\(display.captionText)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    public static func renderJSON(
        plans: [ShortsClipPlan],
        displayLanguage: ShortsIdeaDisplayLanguage
    ) throws -> String {
        let ideas = plans.map { plan in
            let display = displayFields(for: plan, language: displayLanguage)
            return ExportedShortsIdea(
                start: plan.start,
                end: plan.end,
                title: display.title,
                summary: display.summary,
                hook: display.hook,
                category: display.category,
                captionText: display.captionText,
                languageMode: plan.languageMode?.rawValue
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ideas)
        return String(decoding: data, as: UTF8.self)
    }

    public static func displayFields(
        for plan: ShortsClipPlan,
        language: ShortsIdeaDisplayLanguage
    ) -> ShortsIdeaFields {
        switch language {
        case .source:
            return ShortsIdeaFields(
                title: clean(plan.sourceTitle) ?? clean(plan.title) ?? "Untitled clip",
                summary: clean(plan.sourceSummary) ?? clean(plan.summary) ?? "",
                hook: clean(plan.sourceHook) ?? clean(plan.hook) ?? "",
                category: clean(plan.sourceCategory) ?? clean(plan.category) ?? "clip",
                captionText: clean(plan.sourceCaptionText) ?? clean(plan.captionText) ?? ""
            )
        case .target:
            return ShortsIdeaFields(
                title: clean(plan.targetTitle) ?? clean(plan.title) ?? "Untitled clip",
                summary: clean(plan.targetSummary) ?? clean(plan.summary) ?? "",
                hook: clean(plan.targetHook) ?? clean(plan.hook) ?? "",
                category: clean(plan.targetCategory) ?? clean(plan.category) ?? "clip",
                captionText: clean(plan.targetCaptionText) ?? clean(plan.captionText) ?? ""
            )
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ShortsIdeaFields: Equatable, Sendable {
    public var title: String
    public var summary: String
    public var hook: String
    public var category: String
    public var captionText: String
}

private struct ExportedShortsIdea: Encodable {
    var start: String
    var end: String
    var title: String
    var summary: String
    var hook: String
    var category: String
    var captionText: String
    var languageMode: String?
}
