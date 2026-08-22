import Foundation
import Testing
@testable import NativeBolabolCore
@testable import NativeBolabol

@Suite("LocalModelScanner Multi-Layout & Deduplication Tests")
struct LocalModelScannerLayoutTests {

    private func tempMLXRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("bolabol-scan-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("mlx", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeScanner(sharedMLXDirectory: URL) -> LocalModelScanner {
        LocalModelScanner(
            excludedDirectories: [FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()],
            sharedMLXDirectory: sharedMLXDirectory
        )
    }

    private func populateValidModel(
        at url: URL,
        modelType: String = "qwen3_5",
        architectures: [String] = ["Qwen3_5ForCausalLM"]
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        let configJSON: [String: Any] = [
            "architectures": architectures,
            "model_type": modelType
        ]
        let configData = try JSONSerialization.data(withJSONObject: configJSON, options: [.prettyPrinted])
        try configData.write(to: url.appendingPathComponent("config.json"))

        try "{}".write(to: url.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try "weights".write(to: url.appendingPathComponent("model.safetensors"), atomically: true, encoding: .utf8)
    }

    private func populateUnsupportedModel(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        let configJSON: [String: Any] = [
            "architectures": ["BertModel"],
            "model_type": "bert"
        ]
        let configData = try JSONSerialization.data(withJSONObject: configJSON, options: [.prettyPrinted])
        try configData.write(to: url.appendingPathComponent("config.json"))

        try "{}".write(to: url.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try "weights".write(to: url.appendingPathComponent("model.safetensors"), atomically: true, encoding: .utf8)
    }

    @Test("Discovers flat-ID folder at depth 1 under shared mlx root")
    func flatIDFolderAtDepthOneUnderMLXDiscovered() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let flatModelURL = root.appendingPathComponent("qwen35-4b-4bit", isDirectory: true)
        try populateValidModel(at: flatModelURL)

        let scanner = makeScanner(sharedMLXDirectory: root)
        let result = scanner.scanAll()

        #expect(result.models.count == 1)
        #expect(result.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == flatModelURL.path)
        #expect(result.models[0].isCustom)
        #expect(result.skippedUnsupportedCount == 0)
    }

    @Test("Discovers HuggingFace snapshot under shared mlx root")
    func huggingFaceSnapshotUnderMLXDiscovered() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let snapshotURL = root
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("1234abcd", isDirectory: true)
        try populateValidModel(at: snapshotURL)

        let scanner = makeScanner(sharedMLXDirectory: root)
        let result = scanner.scanAll()

        #expect(result.models.count == 1)
        #expect(result.models[0].repositoryID == "mlx-community/Qwen3.5-4B-4bit")
        #expect(result.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == snapshotURL.path)
        #expect(result.skippedUnsupportedCount == 0)
    }

    @Test("Discovers HuggingFace snapshot under shared mlx/Direct/ directory")
    func huggingFaceSnapshotUnderMLXDirectDiscovered() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let directSnapshotURL = root
            .appendingPathComponent("Direct", isDirectory: true)
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("5678ef01", isDirectory: true)
        try populateValidModel(at: directSnapshotURL)

        let scanner = makeScanner(sharedMLXDirectory: root)
        let result = scanner.scanAll()

        #expect(result.models.count == 1)
        #expect(result.models[0].repositoryID == "mlx-community/Qwen3.5-4B-4bit")
        #expect(result.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == directSnapshotURL.path)
        #expect(result.skippedUnsupportedCount == 0)
    }

    @Test("Dual-layout discovery discovers each physical path exactly once through seenPaths deduplication")
    func dualLayoutDiscoveryDeduplicatesPaths() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let flatURL = root.appendingPathComponent("qwen35-4b-4bit", isDirectory: true)
        try populateValidModel(at: flatURL)

        let directSnapshotURL = root
            .appendingPathComponent("Direct", isDirectory: true)
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("directrev1", isDirectory: true)
        try populateValidModel(at: directSnapshotURL)

        let rootSnapshotURL = root
            .appendingPathComponent("models--mlx-community--Qwen3.5-2B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("rootrev2", isDirectory: true)
        try populateValidModel(at: rootSnapshotURL)

        let scanner = makeScanner(sharedMLXDirectory: root)
        let result = scanner.scanAll()

        #expect(result.models.count == 3)
        let paths = result.models.compactMap { $0.localDirectoryURL?.resolvingSymlinksInPath().path }
        #expect(paths.count == 3)
        #expect(Set(paths).count == 3)
        #expect(Set(paths) == Set([flatURL.path, directSnapshotURL.path, rootSnapshotURL.path]))
    }
    @Test("Generic scanDirectory discovers HuggingFace layout when skipsHubLayoutChildren is false")
    func genericScanDirectoryDiscoversHuggingFaceLayoutWhenGuardsNotScoped() throws {
        let tempDocRoot = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("bolabol-doc-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDocRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDocRoot) }

        let snapshotURL = tempDocRoot
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("docrev123", isDirectory: true)
        try populateValidModel(at: snapshotURL)

        let scanner = LocalModelScanner()

        // 1. When skipsHubLayoutChildren is false (default in Documents/Downloads generic scans), HF-layout tree IS discovered
        let genericResult = scanner.scanDirectory(tempDocRoot, skipsHubLayoutChildren: false)
        #expect(genericResult.models.count == 1)
        #expect(genericResult.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == snapshotURL.resolvingSymlinksInPath().path)
        #expect(genericResult.models[0].badge == "Local")
        #expect(genericResult.models[0].isCustom)
        #expect(genericResult.models[0].repositoryID == genericResult.models[0].localDirectoryURL?.path)
        #expect(genericResult.skippedUnsupportedCount == 0)
        let scopedResult = scanner.scanDirectory(tempDocRoot, skipsHubLayoutChildren: true)
        #expect(scopedResult.models.isEmpty)
        #expect(scopedResult.skippedUnsupportedCount == 0)
    }

    @Test("True duplicate candidate reachable in shared-root appears exactly once with HF-derived repositoryID")
    func trueDuplicateCandidateReachableInSharedRootRetainsRicherHFCacheEntry() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let snapshotURL = root
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("rev-rich-entry", isDirectory: true)
        try populateValidModel(at: snapshotURL)

        // Confirm snapshotURL is a valid model that would be discovered by generic scanDirectory if guards were false
        let scanner = makeScanner(sharedMLXDirectory: root)
        let rawGenericResult = scanner.scanDirectory(root, skipsHubLayoutChildren: false)
        #expect(rawGenericResult.models.count == 1)
        #expect(rawGenericResult.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == snapshotURL.resolvingSymlinksInPath().path)
        #expect(rawGenericResult.models[0].badge == "Local")
        #expect(rawGenericResult.models[0].repositoryID != "mlx-community/Qwen3.5-4B-4bit")
        // and HF cache pass (pass 1b) discovers the snapshot with repositoryID: "mlx-community/Qwen3.5-4B-4bit".
        // seenPaths deduplication ensures the single physical path appears exactly once with the richer HF descriptor.
        let scanAllResult = scanner.scanAll()
        #expect(scanAllResult.models.count == 1)
        #expect(scanAllResult.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == snapshotURL.resolvingSymlinksInPath().path)
        #expect(scanAllResult.models[0].repositoryID == "mlx-community/Qwen3.5-4B-4bit")
        #expect(scanAllResult.models[0].badge == "HF Cache")
        #expect(scanAllResult.skippedUnsupportedCount == 0)
    }

    @Test("Unsupported and invalid model directories increment skipped count without crashing")
    func unsupportedAndInvalidDirectoriesIncrementSkippedWithoutCrashing() throws {
        let root = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let unsupportedFlatURL = root.appendingPathComponent("unsupported-bert", isDirectory: true)
        try populateUnsupportedModel(at: unsupportedFlatURL)

        let unsupportedHFURL = root
            .appendingPathComponent("models--org--unsupported", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("badrev", isDirectory: true)
        try populateUnsupportedModel(at: unsupportedHFURL)

        let invalidCorruptURL = root.appendingPathComponent("invalid-corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidCorruptURL, withIntermediateDirectories: true)
        try "corrupt json".write(to: invalidCorruptURL.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let emptyDirURL = root.appendingPathComponent("empty-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDirURL, withIntermediateDirectories: true)

        let validURL = root.appendingPathComponent("valid-qwen", isDirectory: true)
        try populateValidModel(at: validURL)

        let scanner = makeScanner(sharedMLXDirectory: root)
        let result = scanner.scanAll()

        #expect(result.models.count == 1)
        #expect(result.models[0].localDirectoryURL?.resolvingSymlinksInPath().path == validURL.path)
        #expect(result.skippedUnsupportedCount == 2)
    }

    @Test("Missing and empty roots return empty result without throwing")
    func missingAndEmptyRootsReturnEmptyResultWithoutThrowing() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("bolabol-missing-\(UUID().uuidString)", isDirectory: true)

        let scannerMissing = LocalModelScanner(
            excludedDirectories: [FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()],
            sharedMLXDirectory: missingURL
        )
        let resultMissing = scannerMissing.scanAll()
        #expect(resultMissing.models.isEmpty)
        #expect(resultMissing.skippedUnsupportedCount == 0)

        // Also test scanAll(sharedMLXDirectory:) parameter override
        let resultParam = LocalModelScanner(
            excludedDirectories: [FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()]
        ).scanAll(sharedMLXDirectory: missingURL)
        #expect(resultParam.models.isEmpty)
        #expect(resultParam.skippedUnsupportedCount == 0)

        let emptyRoot = try tempMLXRoot()
        defer { try? FileManager.default.removeItem(at: emptyRoot.deletingLastPathComponent()) }

        let scannerEmpty = makeScanner(sharedMLXDirectory: emptyRoot)
        let resultEmpty = scannerEmpty.scanAll()
        #expect(resultEmpty.models.isEmpty)
        #expect(resultEmpty.skippedUnsupportedCount == 0)
    }
}
