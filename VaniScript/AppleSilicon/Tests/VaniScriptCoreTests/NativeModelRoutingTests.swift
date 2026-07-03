import Testing
@testable import VaniScriptCore

@Suite("Native model routing")
struct NativeModelRoutingTests {
    @Test("routes transcription to Core ML")
    func transcriptionUsesCoreML() {
        #expect(NativeModelRouting.backend(for: .transcription) == .coreML)
    }

    @Test("routes LLM text tasks to MLX")
    func llmTextTasksUseMLX() {
        for task in NativeTask.llmTextTasks {
            #expect(NativeModelRouting.backend(for: task) == .mlx)
        }
    }

    @Test("does not route native tasks through llama cpp")
    func nativeTasksDoNotUseLlamaCpp() {
        for task in NativeTask.allCases {
            #expect(NativeModelRouting.backend(for: task) != .llamaCpp)
        }
    }
}
