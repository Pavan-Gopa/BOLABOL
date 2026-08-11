import Testing
import Foundation
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

    @Test("active native ASR lookup requires the same exact presence policy")
    func activeNativeASRRequiresExactPresence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptRouting-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let path = root.appendingPathComponent("canary-flash", isDirectory: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let url = path.appendingPathComponent(relativePath, isDirectory: relativePath.hasSuffix(".mlmodelc"))
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id]?.status = .downloaded
        settings.localAsrModels[descriptor.id]?.path = path.path
        #expect(
            NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: descriptor.id,
                onMacOSMajor: 14
            )?.id == descriptor.id
        )

        try FileManager.default.removeItem(at: path.appendingPathComponent("vocab.json"))
        #expect(
            NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: descriptor.id,
                onMacOSMajor: 14
        ) == nil
        )
    }

    @Test("provider lookup validates native ASR presence against the selected descriptor")
    func providerLookupRejectsAValidDifferentNativeModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptProvider-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let flash = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let path = root.appendingPathComponent("flash", isDirectory: true)
        for relativePath in flash.requiredLayout.requiredFiles {
            let url = path.appendingPathComponent(relativePath, isDirectory: relativePath.hasSuffix(".mlmodelc"))
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }

        var settings = AppSettings.defaults
        settings.localAsrModels["canary-1b-v2-coreml"] = LocalModelState(
            status: .downloaded,
            label: "Canary 1B v2",
            path: path.path,
            runtime: .canary
        )

        let providers = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        #expect(!providers.contains { $0.id == "canary-1b-v2-coreml" })
    }

    @Test("reconciles a missing external ASR path and clears its active badge")
    func missingExternalASRPathIsNotReady() throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptMissingExternal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingPath) }

        let id = "canary-180m-flash-coreml"
        var settings = AppSettings.defaults
        settings.transcriptionProvider = id
        settings.localAsrModels[id] = LocalModelState(
            status: .downloaded,
            label: "Canary Flash 180M",
            path: missingPath.path,
            runtime: .canary
        )

        #expect(!settings.isDownloadedLocalASRModelActive(id: id))

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.localAsrModels[id]?.status == .failed)
        #expect(settings.localAsrModels[id]?.path == missingPath.path)
        #expect(!settings.isDownloadedLocalASRModelActive(id: id))
    }
}
