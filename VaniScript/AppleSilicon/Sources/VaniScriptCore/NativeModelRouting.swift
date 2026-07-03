public enum NativeTask: String, CaseIterable, Codable, Equatable, Sendable {
    case transcription
    case translation
    case literaryPolish
    case audioReview
    case documentExport
    case shortsPlanning

    public static let llmTextTasks: [NativeTask] = [
        .translation,
        .literaryPolish,
        .audioReview,
        .documentExport,
        .shortsPlanning,
    ]
}

public enum NativeModelBackend: String, Codable, Equatable, Sendable {
    case coreML = "Core ML"
    case mlx = "MLX"
    case llamaCpp = "llama.cpp"
}

public enum NativeModelRouting {
    public static func backend(for task: NativeTask) -> NativeModelBackend {
        switch task {
        case .transcription:
            .coreML
        case .translation, .literaryPolish, .audioReview, .documentExport, .shortsPlanning:
            .mlx
        }
    }
}
