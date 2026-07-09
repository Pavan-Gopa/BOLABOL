import Darwin
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import NativeSmartScribeCore
import Tokenizers

extension ChatSession: @unchecked @retroactive Sendable {}

struct MLXPolishWorkerRequest: Codable, Sendable {
    let model: PolishingModelDescriptor
    let localModelDirectoryPath: String
    let rawText: String
    let variant: ProcessingVariant
    let templateID: String
    let templateTitle: String
    let templateBody: String
}

struct MLXPolishWorkerResponse: Codable, Sendable {
    let text: String
    let backendName: String
    let loadTimeMilliseconds: Int?
}

@main
struct NativeSmartScribePolishWorker {
    static func main() async {
        // Register custom model types in MLXLLM registry before loading the model
        await LLMTypeRegistry.shared.registerModelType("gemma4_unified") { @Sendable (data: Data) throws -> any LanguageModel in
            let configuration = try JSONDecoder.json5().decode(Gemma4Configuration.self, from: data)
            return Gemma4Model(configuration)
        }
        await LLMTypeRegistry.shared.registerModelType("gemma4_unified_text") { @Sendable (data: Data) throws -> any LanguageModel in
            let configuration = try JSONDecoder.json5().decode(Gemma4TextConfiguration.self, from: data)
            return Gemma4TextModel(configuration)
        }

        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(MLXPolishWorkerRequest.self, from: input)
            let response = try await run(request)
            let output = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(output)
            exit(EXIT_SUCCESS)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Suffix appended to every prompt to prevent reasoning models from
    /// dumping their chain-of-thought into the output.
    private static let noThinkingSuffix = """

    IMPORTANT: Do NOT include your thinking process, reasoning steps, or analysis in your response. Output ONLY the final text. Do NOT start with phrases like "The user wants me to…", "Let me analyze…", or "First, I need to…". Respond with nothing but the cleaned/rewritten text. Preserve the input language unless the user prompt explicitly asks for translation.
    """

    /// Finds the actual model directory within the given base directory
    private static func findModelDirectory(_ baseDirectory: URL) -> URL {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            FileHandle.standardError.write(Data("Worker findModelDirectory error for \(baseDirectory.path): \(error.localizedDescription)\n".utf8))
            files = []
        }
        FileHandle.standardError.write(Data("Worker found files: \(files.map { $0.lastPathComponent })\n".utf8))

        // Look for snapshots folder (HuggingFace cache structure)
        if files.contains(where: { $0.lastPathComponent == "snapshots" }) {
            let snapshotsDir = baseDirectory.appendingPathComponent("snapshots", isDirectory: true)
            if let subdirs = try? FileManager.default.contentsOfDirectory(
                at: snapshotsDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                // Find the main snapshot folder
                for subdir in subdirs {
                    if subdir.lastPathComponent != "refs" {
                        return snapshotsDir.appendingPathComponent(subdir.lastPathComponent, isDirectory: true)
                    }
                }
            }
        }

        // Look for any subdirectory that might contain the model
        for file in files where file.lastPathComponent != "snapshots" {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) && isDir.boolValue {
                return file
            }
        }

        // Fall back to the original directory
        return baseDirectory
    }

    private static func prepareModelDirectory(at baseDirectory: URL) -> URL {
        let configURL = baseDirectory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              var json = (try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers])) as? [String: Any]
        else {
            return baseDirectory
        }

        guard let modelType = json["model_type"] as? String, modelType == "nemotron_h" else {
            return baseDirectory
        }

        let requiredFields: [String: Any] = [
            "moe_intermediate_size": 0,
            "moe_shared_expert_intermediate_size": 0,
            "n_routed_experts": 0,
            "num_experts_per_tok": 0
        ]

        var needsPatch = false
        for (key, _) in requiredFields {
            if json[key] == nil {
                needsPatch = true
                break
            }
        }

        guard needsPatch else {
            return baseDirectory
        }

        for (key, defaultValue) in requiredFields {
            if json[key] == nil {
                json[key] = defaultValue
            }
        }

        guard let outputData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return baseDirectory
        }

        // Try in-place write first
        do {
            try outputData.write(to: configURL)
            FileHandle.standardError.write(Data("Worker: successfully patched config.json in-place for nemotron_h model.\n".utf8))
            return baseDirectory
        } catch {
            FileHandle.standardError.write(Data("Worker: in-place patch failed (\(error.localizedDescription)). Creating symlinked temporary directory...\n".utf8))
        }

        // Fallback: create symlinked temp directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // List files in the original directory
            let files = try FileManager.default.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
            for file in files {
                let filename = file.lastPathComponent
                if filename == "config.json" {
                    continue
                }
                let dest = tempDir.appendingPathComponent(filename)
                try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: file)
            }
            
            // Write patched config
            try outputData.write(to: tempDir.appendingPathComponent("config.json"))
            FileHandle.standardError.write(Data("Worker: successfully created symlinked patched directory at \(tempDir.path)\n".utf8))
            return tempDir
        } catch {
            FileHandle.standardError.write(Data("Worker: failed to create symlinked patched directory: \(error.localizedDescription)\n".utf8))
            return baseDirectory
        }
    }

    private static func run(
        _ request: MLXPolishWorkerRequest
    ) async throws -> MLXPolishWorkerResponse {
        let basePrompt = try PromptTemplate(
            id: request.templateID,
            title: request.templateTitle,
            body: request.templateBody
        ).render(transcription: request.rawText)

        // Parse system instructions and user input by splitting at "INPUT:"
        let systemInstructions: String
        var userPrompt: String

        if let inputIndex = basePrompt.range(of: "INPUT:", options: [.backwards, .caseInsensitive]) {
            let instructionsPart = basePrompt[..<inputIndex.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let userPart = basePrompt[inputIndex.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            systemInstructions = modelPromptControlPrefix(for: request.model)
                + instructionsPart
                + "\n\n"
                + noThinkingSuffix
            userPrompt = userPart
        } else {
            systemInstructions = modelPromptControlPrefix(for: request.model) + noThinkingSuffix
            userPrompt = basePrompt
        }

        // (B) Qwen3-family soft switch to suppress the <think> block. Harmless
        // for models that do not recognise it; for those whose chat template
        // hard-starts <think>, (C) below gives them enough token headroom to
        // finish thinking and still emit the final answer.
        if PolishingModelPromptControl.needsThinkingSuppression(request.model) {
            userPrompt += "\n\n/no_think"
        }

        let startedAt = Date()
        let modelDirectory = URL(fileURLWithPath: request.localModelDirectoryPath, isDirectory: true)

        // Find the actual model directory - look for snapshots folder or the first subfolder
        let actualModelDirectory = findModelDirectory(modelDirectory)
        guard FileManager.default.fileExists(atPath: actualModelDirectory.path) else {
            throw MLXSwiftPolishingError.workerFailed("Model directory not found at \(actualModelDirectory.path)")
        }

        let preparedModelDirectory = prepareModelDirectory(at: actualModelDirectory)

        let configuration = ModelConfiguration(
            directory: preparedModelDirectory,
            extraEOSTokens: Set(request.model.extraEOSTokens)
        )
        let hubCache = HubCache(cacheDirectory: preparedModelDirectory.deletingLastPathComponent())
        let hubClient = HubClient(cache: hubCache)
        let container = try await MLXLMCommon.loadModelContainer(
            from: #hubDownloader(hubClient),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration
        )
        // (C) Reasoning models (Qwopus/Opus) emit a long <think> block before
        // the answer. With the default cap they get cut off mid-reasoning,
        // never close </think>, and never produce usable text. Give them far
        // more headroom and run greedy (temperature 0) to reduce the CJK-token
        // drift seen on heavily-quantised builds.
        let isReasoning = request.model.isReasoningModel
        let session = ChatSession(
            container,
            instructions: systemInstructions,
            generateParameters: GenerateParameters(
                maxTokens: generationTokenLimit(for: request.rawText, isReasoningModel: isReasoning),
                temperature: isReasoning ? 0.0 : 0.1,
                topP: 0.9,
                repetitionPenalty: 1.08
            ),
            additionalContext: modelAdditionalContext(for: request.model)
        )
        let rawOutput = try await session.respond(to: userPrompt)
        let sanitized = ModelOutputSanitizer.sanitize(rawOutput)

        // If the sanitizer stripped everything, the model produced only
        // chain-of-thought and never reached a final answer (typical for
        // reasoning models such as Qwopus/Opus that spend their whole token
        // budget "thinking"). NEVER fall back to the raw output here: dumping
        // the raw reasoning into the note is the worst possible result.
        // Surface a clear, actionable error instead so the user can react
        // (switch to a non-reasoning instruct model, or raise the token limit).
        guard !sanitized.isEmpty else {
            throw MLXSwiftPolishingError.workerFailed(
                "The model returned only its reasoning and no final text. "
                + "This usually happens with reasoning models (e.g. Qwopus/Opus) "
                + "that spend the whole token budget thinking. Try a non-reasoning "
                + "instruct model for polishing, or increase the token limit."
            )
        }
        let response = sanitized

        return MLXPolishWorkerResponse(
            text: response,
            backendName: "MLX Swift \(request.model.displayName)",
            loadTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    private static func generationTokenLimit(
        for rawText: String,
        isReasoningModel: Bool
    ) -> Int {
        let base = rawText.count / 3 + 512
        if isReasoningModel {
            // Reasoning models spend most of their budget inside <think>; they
            // need enough room to finish reasoning AND emit the final answer,
            // otherwise the output is pure (truncated) chain-of-thought.
            return min(max(base + 2048, 4096), 8192)
        }
        // Non-reasoning instruct models answer directly — keep it tight.
        return min(max(base, 1024), 2048)
    }

    private static func modelPromptControlPrefix(
        for model: PolishingModelDescriptor
    ) -> String {
        guard PolishingModelPromptControl.needsThinkingSuppression(model) else { return "" }
        // Newer Qwen/Qwopus templates may intercept these tags and remove
        // them from context while switching the template to concise mode.
        return "<|think_off|>\n<|think_forget|>\n"
    }

    private static func modelAdditionalContext(
        for model: PolishingModelDescriptor
    ) -> [String: any Sendable] {
        var context: [String: any Sendable] = [
            "enable_thinking": false,
            "preserve_thinking": false
        ]

        if PolishingModelPromptControl.isQwenLike(model) {
            context["thinking"] = false
        }

        return context
    }
}

private enum MLXSwiftPolishingError: LocalizedError {
    case workerFailed(String)

    var errorDescription: String? {
        switch self {
        case .workerFailed(let message):
            return message
        }
    }
}
