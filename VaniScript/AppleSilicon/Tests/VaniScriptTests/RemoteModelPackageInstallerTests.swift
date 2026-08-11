import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Remote model package installer", .serialized)
struct RemoteModelPackageInstallerTests {
    @Test("installs a verified archive with a manifest and atomic replacement")
    func installsVerifiedArchive() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("new-model".utf8)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }

        let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old-model".utf8).write(to: destination.appendingPathComponent("old.bin"))
        let release = try makeRelease(archive: archiveData, files: ["canary_spe.model": Data("new-model".utf8)])
        let installer = makeInstaller(configuredRoot: fixture.root)

        let progress = RemoteProgressBox()
        let installed = try await installer.install(
            release: release,
            requiredRelativePaths: ["canary_spe.model"],
            destination: destination,
            directURL: URL(string: "https://fixture.test/package.zip")
        ) { snapshot in
            progress.append(snapshot)
        }

        #expect(installed == destination)
        #expect(String(data: try Data(contentsOf: destination.appendingPathComponent("canary_spe.model")), encoding: .utf8) == "new-model")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("old.bin").path))
        #expect(progress.last?.fractionCompleted == 1)
        #expect(
            FileManager.default.fileExists(
                atPath: LocalASRPresencePolicy.installationManifestURL(at: destination).path
            )
        )
    }

    @Test("serializes concurrent replacements of one remote destination")
    func serializesConcurrentReplacements() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("model".utf8)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }

        let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)
        let release = try makeRelease(
            archive: archiveData,
            files: ["canary_spe.model": Data("model".utf8)]
        )
        let installer = makeInstaller(configuredRoot: fixture.root)

        async let first = installer.install(
            release: release,
            requiredRelativePaths: ["canary_spe.model"],
            destination: destination,
            directURL: URL(string: "https://fixture.test/package.zip")
        )
        async let second = installer.install(
            release: release,
            requiredRelativePaths: ["canary_spe.model"],
            destination: destination,
            directURL: URL(string: "https://fixture.test/package.zip")
        )
        let (firstURL, secondURL) = try await (first, second)

        #expect(firstURL == destination)
        #expect(secondURL == destination)
        #expect(
            NativeModelCatalog.isModelPresent(
                descriptorForTest(release: release),
                at: destination
            )
        )
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("unexpected-link"),
            withDestinationURL: destination.appendingPathComponent("canary_spe.model")
        )
        #expect(
            !NativeModelCatalog.isModelPresent(
                descriptorForTest(release: release),
                at: destination
            )
        )
        #expect(String(data: try Data(contentsOf: destination.appendingPathComponent("canary_spe.model")), encoding: .utf8) == "model")
    }

    @Test("wrong archive hash leaves a previous destination untouched")
    func wrongArchiveHashDoesNotReplace() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("new-model".utf8)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }

        let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old-model".utf8).write(to: destination.appendingPathComponent("canary_spe.model"))
        var release = try makeRelease(archive: archiveData, files: ["canary_spe.model": Data("new-model".utf8)])
        release.expectedArchiveSHA256 = String(repeating: "0", count: 64)

        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await makeInstaller(configuredRoot: fixture.root).install(
                release: release,
                requiredRelativePaths: ["canary_spe.model"],
                destination: destination,
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }
        #expect(String(data: try Data(contentsOf: destination.appendingPathComponent("canary_spe.model")), encoding: .utf8) == "old-model")
    }

    @Test("rejects duplicate manifest paths as a non-ready installation")
    func rejectsDuplicateManifestPaths() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("model".utf8)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }

        let release = try makeRelease(archive: archiveData, files: ["canary_spe.model": Data("model".utf8)])
        let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)
        _ = try await makeInstaller(configuredRoot: fixture.root).install(
            release: release,
            requiredRelativePaths: ["canary_spe.model"],
            destination: destination,
            directURL: URL(string: "https://fixture.test/package.zip")
        )

        let manifestURL = LocalASRPresencePolicy.installationManifestURL(at: destination)
        var manifest = try JSONDecoder().decode(
            RemoteModelPackageInstallationManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        manifest.files.append(try #require(manifest.files.first))
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: [.atomic])

        #expect(!NativeModelCatalog.isModelPresent(descriptorForTest(release: release), at: destination))
    }

    @Test("rejects symlinked destination parents without touching the external directory")
    func rejectsSymlinkedDestinationParent() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("model".utf8)])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalRoot = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("VaniScriptExternal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        let externalModel = externalRoot.appendingPathComponent("180m-flash", isDirectory: true)
        try FileManager.default.createDirectory(at: externalModel, withIntermediateDirectories: true)
        let sentinel = externalModel.appendingPathComponent("sentinel.txt")
        try Data("keep-me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("canary", isDirectory: true),
            withDestinationURL: externalRoot
        )

        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let destination = fixture.root.appendingPathComponent("canary/180m-flash", isDirectory: true)
        #expect(
            !SharedModelsRoot.isOwnedModelDirectory(
                for: descriptor,
                candidate: destination,
                configuredRoot: fixture.root
            )
        )
        let removed = try SharedModelsRoot.removeOwnedModelDirectory(
            for: descriptor,
            candidate: destination,
            configuredRoot: fixture.root
        )
        #expect(!removed)

        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }
        let release = try makeRelease(archive: archiveData, files: ["canary_spe.model": Data("model".utf8)])
        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await makeInstaller(configuredRoot: fixture.root).install(
                release: release,
                requiredRelativePaths: ["canary_spe.model"],
                destination: destination,
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }

        #expect(FileManager.default.fileExists(atPath: externalModel.path))
        #expect(String(data: try Data(contentsOf: sentinel), encoding: .utf8) == "keep-me")
    }

    @Test("rejects HTML before extraction")
    func rejectsHTMLResponse() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        FixturePackageURLProtocol.install(data: Data("<html>login</html>".utf8), contentType: "text/html")
        defer { FixturePackageURLProtocol.reset() }
        let release = RemoteModelPackageRelease(
            packageID: "fixture",
            layoutVersion: "v1",
            directURLOverrideEnvironmentKey: "FIXTURE_URL",
            expectedArchiveSHA256: String(repeating: "a", count: 64),
            expectedCompressedSizeBytes: 18,
            expectedUncompressedSizeBytes: 18,
            allowlistedFiles: [
                RemoteModelPackageFile(
                    relativePath: "canary_spe.model",
                    expectedByteCount: 18,
                    expectedSHA256: String(repeating: "a", count: 64)
                )
            ]
        )

        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await makeInstaller(configuredRoot: root).install(
                release: release,
                destination: root.appendingPathComponent("installed", isDirectory: true),
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }
    }

    @Test("rejects archive symlinks and insufficient disk before replacement")
    func rejectsSymlinkAndInsufficientDisk() async throws {
        let symlinkFixture = try makeArchive(
            entries: ["canary_spe.model": Data("target".utf8)],
            symlinkName: "canary_spe.model"
        )
        defer { try? FileManager.default.removeItem(at: symlinkFixture.root) }
        let archiveData = try Data(contentsOf: symlinkFixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }
        let release = try makeRelease(archive: archiveData, files: ["canary_spe.model": Data("target".utf8)])

        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await makeInstaller(configuredRoot: symlinkFixture.root).install(
                release: release,
                requiredRelativePaths: ["canary_spe.model"],
                destination: symlinkFixture.root.appendingPathComponent("installed", isDirectory: true),
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }

        let regularFixture = try makeArchive(entries: ["canary_spe.model": Data("target".utf8)])
        defer { try? FileManager.default.removeItem(at: regularFixture.root) }
        let regularData = try Data(contentsOf: regularFixture.archive)
        FixturePackageURLProtocol.install(data: regularData)
        let regularRelease = try makeRelease(archive: regularData, files: ["canary_spe.model": Data("target".utf8)])
        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await RemoteModelPackageInstaller(
                configuredRoot: regularFixture.root,
                availableDiskSpace: { _ in 0 }
            ).install(
                release: regularRelease,
                requiredRelativePaths: ["canary_spe.model"],
                destination: regularFixture.root.appendingPathComponent("installed", isDirectory: true),
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }
    }

    @Test("rejects empty archive directories outside the trusted allowlist")
    func rejectsUnexpectedArchiveDirectory() async throws {
        let fixture = try makeArchive(
            entries: ["canary_spe.model": Data("model".utf8)],
            directories: ["unexpected"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archiveData = try Data(contentsOf: fixture.archive)
        FixturePackageURLProtocol.install(data: archiveData)
        defer { FixturePackageURLProtocol.reset() }
        let release = try makeRelease(
            archive: archiveData,
            files: ["canary_spe.model": Data("model".utf8)]
        )

        await #expect(throws: RemoteModelPackageInstallerError.self) {
            try await makeInstaller(configuredRoot: fixture.root).install(
                release: release,
                requiredRelativePaths: ["canary_spe.model"],
                destination: fixture.root.appendingPathComponent("installed", isDirectory: true),
                directURL: URL(string: "https://fixture.test/package.zip")
            )
        }
    }

    @Test("rejects path traversal archive names before extraction")
    func rejectsPathTraversalArchiveEntries() async throws {
        let fixture = try makeArchive(entries: ["canary_spe.model": Data("model".utf8)])
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: fixture.archive)
        }
        let maliciousArchive = try archiveReplacingEntryName(
            Data(contentsOf: fixture.archive),
            from: "canary_spe.model",
            to: "../traversal.txt"
        )
        FixturePackageURLProtocol.install(data: maliciousArchive)
        defer { FixturePackageURLProtocol.reset() }

        let release = try makeRelease(
            archive: maliciousArchive,
            files: ["canary_spe.model": Data("model".utf8)]
        )
        let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)

        var failure: RemoteModelPackageInstallerError?
        do {
            _ = try await makeInstaller(configuredRoot: fixture.root).install(
                release: release,
                requiredRelativePaths: ["canary_spe.model"],
                destination: destination,
                directURL: URL(string: "https://fixture.test/package.zip")
            )
            Issue.record("Traversal archive unexpectedly installed")
        } catch let error as RemoteModelPackageInstallerError {
            failure = error
        }
        #expect(failure == .unsafeArchivePath("invalid UTF-8 path"))

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(remoteStagingDirectories(in: fixture.root).isEmpty)
    }

    @Test("cancellation removes staging and preserves a verified destination")
    func cancellationCleansUpStagingAndPreservesVerifiedDestination() async throws {
        let baseline = try makeArchive(entries: ["canary_spe.model": Data("old-model".utf8)])
        let candidate = try makeArchive(entries: ["canary_spe.model": Data("new-model".utf8)])
        defer {
            for url in [baseline.root, baseline.archive, candidate.root, candidate.archive] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let baselineArchive = try Data(contentsOf: baseline.archive)
        let candidateArchive = try Data(contentsOf: candidate.archive)
        let baselineRelease = try makeRelease(
            archive: baselineArchive,
            files: ["canary_spe.model": Data("old-model".utf8)]
        )
        let candidateRelease = try makeRelease(
            archive: candidateArchive,
            files: ["canary_spe.model": Data("new-model".utf8)]
        )
        let destination = baseline.root.appendingPathComponent("installed", isDirectory: true)
        let installer = makeInstaller(configuredRoot: baseline.root)
        FixturePackageURLProtocol.install(data: baselineArchive)
        defer { FixturePackageURLProtocol.reset() }

        _ = try await installer.install(
            release: baselineRelease,
            requiredRelativePaths: ["canary_spe.model"],
            destination: destination,
            directURL: URL(string: "https://fixture.test/package.zip")
        )
        #expect(
            NativeModelCatalog.isModelPresent(
                descriptorForTest(release: baselineRelease),
                at: destination
            )
        )

        FixturePackageURLProtocol.install(data: candidateArchive)
        let cancellation = RemoteInstallCancellation()
        let gate = RemoteInstallStartGate()
        let installation = Task {
            await gate.wait()
            return try await installer.install(
                release: candidateRelease,
                requiredRelativePaths: ["canary_spe.model"],
                destination: destination,
                directURL: URL(string: "https://fixture.test/package.zip")
            ) { snapshot in
                guard snapshot.bytesReceived > 0 else { return }
                cancellation.cancel()
            }
        }
        cancellation.set { installation.cancel() }
        await gate.open()

        do {
            _ = try await installation.value
            Issue.record("Cancelled package installation unexpectedly succeeded")
        } catch {}

        #expect(installation.isCancelled)
        #expect(
            NativeModelCatalog.isModelPresent(
                descriptorForTest(release: baselineRelease),
                at: destination
            )
        )
        #expect(
            String(
                data: try Data(contentsOf: destination.appendingPathComponent("canary_spe.model")),
                encoding: .utf8
            ) == "old-model"
        )
        #expect(remoteStagingDirectories(in: baseline.root).isEmpty)
    }

    private func makeInstaller(configuredRoot: URL) -> RemoteModelPackageInstaller {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixturePackageURLProtocol.self]
        return RemoteModelPackageInstaller(
            session: URLSession(configuration: configuration),
            configuredRoot: configuredRoot
        )
    }

    private func makeRelease(
        archive: Data,
        files: [String: Data]
    ) throws -> RemoteModelPackageRelease {
        RemoteModelPackageRelease(
            packageID: "fixture",
            layoutVersion: "v1",
            directURLOverrideEnvironmentKey: "FIXTURE_URL",
            expectedArchiveSHA256: SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined(),
            expectedCompressedSizeBytes: Int64(archive.count),
            expectedUncompressedSizeBytes: Int64(files.values.reduce(0) { $0 + $1.count }),
            allowlistedFiles: files.map { path, data in
                RemoteModelPackageFile(
                    relativePath: path,
                    expectedByteCount: Int64(data.count),
                    expectedSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                )
            }
        )
    }

    private func descriptorForTest(release: RemoteModelPackageRelease) -> LocalASRModelDescriptor {
        LocalASRModelDescriptor(
            id: release.packageID,
            displayName: release.packageID,
            backend: .canaryCoreML,
            installSource: .remotePackage(release),
            relativeStorageSubpath: "canary/fixture",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: ["en"],
                maxEngineWindowSeconds: 1,
                approximateDownloadBytes: 1
            ),
            requiredLayout: LocalASRRequiredLayout(requiredRelativePaths: ["canary_spe.model"])
        )
    }

    private func makeArchive(
        entries: [String: Data],
        symlinkName: String? = nil,
        directories: [String] = []
    ) throws -> (root: URL, archive: URL) {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, data) in entries {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        if let symlinkName {
            let target = root.appendingPathComponent("target.bin")
            try Data("target".utf8).write(to: target)
            try FileManager.default.removeItem(at: root.appendingPathComponent(symlinkName))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent(symlinkName),
                withDestinationURL: target
            )
        }
        for directory in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let archive = root.deletingLastPathComponent()
            .appendingPathComponent("fixture-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", "-y", archive.path] + entries.keys.sorted() + directories.sorted()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "RemoteModelPackageInstallerTests", code: 1)
        }
        return (root, archive)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptRemoteTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func remoteStagingDirectories(in root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(".vaniscript-remote-") } ?? []
    }

    private func archiveReplacingEntryName(
        _ archive: Data,
        from source: String,
        to replacement: String
    ) throws -> Data {
        let sourceBytes = Array(source.utf8)
        let replacementBytes = Array(replacement.utf8)
        guard !sourceBytes.isEmpty, sourceBytes.count == replacementBytes.count else {
            throw NSError(domain: "RemoteModelPackageInstallerTests", code: 2)
        }

        var bytes = Array(archive)
        var replacements = 0
        guard bytes.count >= sourceBytes.count else {
            throw NSError(domain: "RemoteModelPackageInstallerTests", code: 3)
        }
        for offset in 0...(bytes.count - sourceBytes.count) {
            guard bytes[offset..<(offset + sourceBytes.count)].elementsEqual(sourceBytes) else {
                continue
            }
            bytes.replaceSubrange(offset..<(offset + sourceBytes.count), with: replacementBytes)
            replacements += 1
        }
        guard replacements >= 2 else {
            throw NSError(domain: "RemoteModelPackageInstallerTests", code: 4)
        }
        return Data(bytes)
    }
}

private final class FixturePackageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static nonisolated(unsafe) var data = Data()
    private static nonisolated(unsafe) var contentType = "application/zip"

    static func install(data: Data, contentType: String = "application/zip") {
        lock.lock()
        self.data = data
        self.contentType = contentType
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        data = Data()
        contentType = "application/zip"
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fixture.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let body = Self.data
        let type = Self.contentType
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": type, "Content-Length": String(body.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RemoteProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RemoteModelPackageProgress] = []

    var last: RemoteModelPackageProgress? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    func append(_ value: RemoteModelPackageProgress) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private actor RemoteInstallStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private final class RemoteInstallCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?

    func set(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        self.action = action
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let action = action
        lock.unlock()
        action?()
    }
}
