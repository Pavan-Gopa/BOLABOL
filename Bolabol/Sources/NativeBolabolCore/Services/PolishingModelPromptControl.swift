public enum PolishingModelPromptControl {
    public static func needsThinkingSuppression(_ model: PolishingModelDescriptor) -> Bool {
        let searchable = searchableModelText(model)

        return searchable.contains("qwopus")
            || searchable.contains("qwen3.5")
            || searchable.contains("qwen 3.5")
            || searchable.contains("qwen-3.5")
            || searchable.contains("qwen3_5")
            || searchable.contains("qwen35")
            || searchable.contains("qwen3.6")
            || searchable.contains("qwen 3.6")
            || searchable.contains("qwen-3.6")
            || searchable.contains("qwen3_6")
            || (searchable.contains("qwen") && searchable.contains("reasoning"))
            || (searchable.contains("qwen") && searchable.contains("opus"))
            || (searchable.contains("qwen") && searchable.contains("think"))
    }

    public static func isQwenLike(_ model: PolishingModelDescriptor) -> Bool {
        let searchable = searchableModelText(model)
        return searchable.contains("qwen") || searchable.contains("qwopus")
    }

    private static func searchableModelText(_ model: PolishingModelDescriptor) -> String {
        [
            model.displayName,
            model.repositoryID,
            model.description
        ]
            .joined(separator: " ")
            .lowercased()
    }
}
