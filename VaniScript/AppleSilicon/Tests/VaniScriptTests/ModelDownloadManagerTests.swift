import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Model download manager", .serialized)
struct ModelDownloadManagerTests {
    @Test("Parakeet uses the catalog source and frozen v3/int8 layout")
    func installsInjectedParakeetWithoutNetwork() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let progressValues = ProgressBox()

        let manager = ModelDownloadManager(
            configuredRoot: root,
            parakeetDownloader: { destination, progress in
                let descriptor = NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3")!
                for relativePath in descriptor.requiredLayout.requiredFiles {
                    let url = destination.appendingPathComponent(
                        relativePath,
                        isDirectory: relativePath.hasSuffix(".mlmodelc")
                    )
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
                progress(1)
                return destination
            }
        )

        let installed = try await manager.downloadModel(id: "parakeet-tdt-06b-v3") { fraction, _ in
            progressValues.append(fraction)
        }

        #expect(installed.path == root.appendingPathComponent("parakeet/parakeet-tdt-0.6b-v3").path)
        #expect(progressValues.last == 1)
        #expect(
            NativeModelCatalog.isModelPresent(
                NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3")!,
                at: installed
            )
        )
    }

    @Test("serializes concurrent installs targeting one catalog destination")
    func serializesConcurrentParakeetInstalls() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = DownloadConcurrencyTracker()

        let manager = ModelDownloadManager(
            configuredRoot: root,
            parakeetDownloader: { destination, _ in
                await tracker.enter()
                do {
                    try await Task.sleep(for: .milliseconds(20))
                    let descriptor = NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3")!
                    for relativePath in descriptor.requiredLayout.requiredFiles {
                        let url = destination.appendingPathComponent(
                            relativePath,
                            isDirectory: relativePath.hasSuffix(".mlmodelc")
                        )
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
                    await tracker.leave()
                    return destination
                } catch {
                    await tracker.leave()
                    throw error
                }
            }
        )

        async let first = manager.downloadModel(id: "parakeet-tdt-06b-v3")
        async let second = manager.downloadModel(id: "parakeet-tdt-06b-v3")
        let (firstURL, secondURL) = try await (first, second)

        #expect(firstURL == secondURL)
        #expect(await tracker.maximumConcurrency() == 1)
        #expect(
            NativeModelCatalog.isModelPresent(
                NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3")!,
                at: firstURL
            )
        )
    }

    @Test("Canary Flash downloads an immutable recursive HF tree with byte progress")
    func downloadsCanaryFlashTree() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files: [String: Data] = [
            "CanaryEncoder.mlmodelc/weights.bin": Data([1]),
            "CanaryPrefill.mlmodelc/weights.bin": Data([2]),
            "CanaryDecoder.mlmodelc/weights.bin": Data([3]),
            "config.json": Data("{}".utf8),
            "vocab.json": Data("{}".utf8)
        ]
        let metadata: [[String: Any]] = [
            ["path": "CanaryEncoder.mlmodelc", "type": "directory"],
            ["path": "CanaryPrefill.mlmodelc", "type": "directory"],
            ["path": "CanaryDecoder.mlmodelc", "type": "directory"],
            ["path": "config.json", "type": "file", "size": 2],
            ["path": "vocab.json", "type": "file", "size": 2],
            ["path": "CanaryEncoder.mlmodelc/weights.bin", "type": "file", "size": 1],
            ["path": "CanaryPrefill.mlmodelc/weights.bin", "type": "file", "size": 1],
            ["path": "CanaryDecoder.mlmodelc/weights.bin", "type": "file", "size": 1]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let responses = files.reduce(into: [String: Data]()) { result, entry in
            result[entry.key] = entry.value
        }
        FixtureURLProtocol.install(
            responses: responses,
            metadata: metadataData
        )
        defer { FixtureURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let manager = ModelDownloadManager(
            session: session,
            configuredRoot: root
        )
        let progressValues = ProgressBox()

        let installed = try await manager.downloadModel(id: "canary-180m-flash-coreml") { fraction, _ in
            progressValues.append(fraction)
        }

        #expect(installed.path == root.appendingPathComponent("canary/180m-flash").path)
        #expect(progressValues.contains { $0 > 0 && $0 < 1 })
        #expect(progressValues.last == 1)
        #expect(
            NativeModelCatalog.isModelPresent(
                NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")!,
                at: installed
            )
        )
    }

    @Test("Canary Flash keeps aggregate progress bounded with mixed HF sizes")
    func normalizesMixedAndUnknownCanaryFlashProgress() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files: [String: Data] = [
            "CanaryEncoder.mlmodelc/weights.bin": Data([1]),
            "CanaryPrefill.mlmodelc/weights.bin": Data([2]),
            "CanaryDecoder.mlmodelc/weights.bin": Data([3]),
            "config.json": Data("{}".utf8),
            "vocab.json": Data("{}".utf8)
        ]
        let metadata: [[String: Any]] = [
            ["path": "CanaryEncoder.mlmodelc", "type": "directory"],
            ["path": "CanaryPrefill.mlmodelc", "type": "directory"],
            ["path": "CanaryDecoder.mlmodelc", "type": "directory"],
            ["path": "config.json", "type": "file", "size": 2],
            ["path": "vocab.json", "type": "file"],
            ["path": "CanaryEncoder.mlmodelc/weights.bin", "type": "file"],
            ["path": "CanaryPrefill.mlmodelc/weights.bin", "type": "file"],
            ["path": "CanaryDecoder.mlmodelc/weights.bin", "type": "file"]
        ]
        FixtureURLProtocol.install(
            responses: files,
            metadata: try JSONSerialization.data(withJSONObject: metadata)
        )
        defer { FixtureURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let manager = ModelDownloadManager(
            session: URLSession(configuration: configuration),
            configuredRoot: root
        )
        let progressValues = ProgressBox()

        _ = try await manager.downloadModel(id: "canary-180m-flash-coreml") { fraction, _ in
            progressValues.append(fraction)
        }

        #expect(progressValues.values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        #expect(progressValues.isMonotonic)
        #expect(progressValues.last == 1)
    }

    @Test("HF tree rejects unsafe paths before writing a destination")
    func rejectsUnsafeHuggingFacePath() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        FixtureURLProtocol.install(
            responses: [:],
            metadata: try JSONSerialization.data(withJSONObject: [
                ["path": "../escape.bin", "type": "file", "size": 1]
            ])
        )
        defer { FixtureURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let manager = ModelDownloadManager(
            session: URLSession(configuration: configuration),
            configuredRoot: root
        )

        await #expect(throws: ModelDownloadManagerError.self) {
            try await manager.downloadModel(id: "canary-180m-flash-coreml")
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("canary/180m-flash").path))
    }

    @Test("Canary 1B remains disabled while the catalog release is unbound")
    func canaryOneBDownloadIsDisabled() async throws {
        let manager = ModelDownloadManager(configuredRoot: temporaryRoot())
        await #expect(throws: ModelDownloadManagerError.self) {
            try await manager.downloadModel(id: "canary-1b-v2-coreml")
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptDownloadTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class FixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static nonisolated(unsafe) var bodyBySuffix: [String: Data] = [:]
    private static nonisolated(unsafe) var metadata = Data()

    static func install(responses: [String: Data], metadata: Data) {
        lock.lock()
        bodyBySuffix = responses
        self.metadata = metadata
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        bodyBySuffix = [:]
        metadata = Data()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "huggingface.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        let data = path.contains("/api/models/")
            ? Self.metadata
            : Self.bodyBySuffix.first(where: { path.hasSuffix($0.key) })?.value
        Self.lock.unlock()

        guard let data, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": path.contains("/api/models/") ? "application/json" : "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double] = []

    var last: Double? {
        lock.lock()
        defer { lock.unlock() }
        return fractions.last
    }

    func append(_ value: Double) {
        lock.lock()
        fractions.append(value)
        lock.unlock()
    }

    func contains(_ predicate: (Double) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fractions.contains(where: predicate)
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return fractions
    }

    var isMonotonic: Bool {
        let snapshot = values
        return zip(snapshot, snapshot.dropFirst()).allSatisfy { $0 <= $1 }
    }
}

private actor DownloadConcurrencyTracker {
    private var active = 0
    private var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }

    func maximumConcurrency() -> Int {
        maximum
    }
}
