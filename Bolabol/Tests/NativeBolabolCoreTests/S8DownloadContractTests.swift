import Foundation
import CryptoKit
@testable import NativeBolabol
import NativeBolabolCore
import Testing

@Test
func s8GoInstallSourcesNeverUseUpstreamModelRepositoryIDs() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let flash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
    let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))

    #expect(flash.modelRepositoryID == "nvidia/canary-180m-flash")
    #expect(flash.installSource == .huggingFace(repositoryID: "aufklarer/Canary-180M-Flash-CoreML"))
    #expect(flash.installSource != .huggingFace(repositoryID: flash.modelRepositoryID))

    #expect(gigaAM.modelRepositoryID == "salute-developers/gigaam-v3")
    #expect(gigaAM.installSource == .huggingFace(repositoryID: "huggingfinger0/gigaam-v3-coreml"))
    #expect(gigaAM.installSource != .huggingFace(repositoryID: gigaAM.modelRepositoryID))

    guard case .googleDrive(let packageID, _) = canary1B.installSource else {
        #expect(Bool(false), "Canary 1B must use the explicit Google Drive source")
        return
    }
    #expect(packageID == "bolabol-canary-1b-v2-coreml-r1")
    #expect(canary1B.installSource != .huggingFace(repositoryID: canary1B.modelRepositoryID))
}

@Test
func s8CanaryOneBAdvertisesPackageSizeAboveDiskWarningThreshold() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))

    #expect(canary1B.capabilities.approxDownloadBytes > 1_000_000_000)
    #expect(canary1B.downloadSize.localizedCaseInsensitiveContains("GB"))
}

@Test
func s8GoStoragePathsAreExactAndDoNotUseTheParakeetPlaceholder() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let models = try [
        #require(catalog.model(withID: "canary-1b-v2-coreml")),
        #require(catalog.model(withID: "canary-180m-flash-coreml")),
        #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
    ]
    let paths = models.map(\.relativeStorageSubpath)

    #expect(paths == ["canary/1b-v2", "canary/180m-flash", "gigaam/v3-rnnt"])
    #expect(Set(paths).count == paths.count)
    #expect(paths.allSatisfy { !$0.localizedCaseInsensitiveContains("parakeet") })
}

@MainActor
@Test
func s11CanaryOneBDNSFailureIsTerminalFailedRetryAndCleansEmptyFolder() async throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let model = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolabol-s11-dns-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let suiteName = "bolabol-s11-dns-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let general = GeneralSettings(uiLanguage: .english)
    defaults.set(try JSONEncoder().encode(general), forKey: "general.settings")

    CannotFindHostURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CannotFindHostURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let store = TranscriptionModelStore(
        catalog: catalog,
        userDefaults: defaults,
        modelsDirectory: root,
        urlSession: session
    )

    await store.download(model)

    #expect(CannotFindHostURLProtocol.requests.count == 1)
    #expect(store.installationState(for: model).status == .failed)
    #expect(store.installationState(for: model).errorMessage == AppText.localized(
        .localModelsDownloadHostFailure,
        language: .english
    ))
    #expect(!store.hasAnyLocalFiles(for: model))
    #expect(store.settings.activeModelID == nil)

    // Retry is a fresh request to the same configured source, not an automatic loop.
    await store.download(model)
    #expect(CannotFindHostURLProtocol.requests.count == 2)
    #expect(CannotFindHostURLProtocol.requests[0] == CannotFindHostURLProtocol.requests[1])
    #expect(store.installationState(for: model).status == .failed)
}

@MainActor
@Test
func s11CanaryOneBPreservesOnlySHAValidFilesAfterTrustedManifestDNSFailure() async throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let model = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolabol-s11-trusted-manifest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let destination = root.appendingPathComponent(model.relativeStorageSubpath, isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let trustedData = Data([1, 2, 3])
    let trustedHash = SHA256.hash(data: trustedData)
        .map { String(format: "%02x", $0) }
        .joined()
    try trustedData.write(to: destination.appendingPathComponent("verified.bin"))
    try Data([9]).write(to: destination.appendingPathComponent("unverified.tmp"))
    let manifest = """
    {"packageId":"bolabol-canary-1b-v2-coreml-r1","files":[{"path":"verified.bin","sha256":"\(trustedHash)","sizeBytes":3}]}
    """
    try manifest.write(
        to: destination.appendingPathComponent("MANIFEST.json"),
        atomically: true,
        encoding: .utf8
    )

    let suiteName = "bolabol-s11-trusted-manifest-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TrustedManifestCannotFindHostURLProtocol.self]
    let store = TranscriptionModelStore(
        catalog: catalog,
        userDefaults: defaults,
        modelsDirectory: root,
        urlSession: URLSession(configuration: configuration)
    )

    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("verified.bin").path))
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("MANIFEST.json").path))

    await store.download(model)

    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("verified.bin").path))
    #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("unverified.tmp").path))
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("MANIFEST.json").path))
    #expect(!store.hasLocalFiles(for: model))
    #expect(store.installationState(for: model).status == .failed)
}

private final class CannotFindHostURLProtocol: URLProtocol {
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []

    static func reset() {
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSLocalizedDescriptionKey: "injected DNS failure"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}

private final class TrustedManifestCannotFindHostURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSLocalizedDescriptionKey: "injected DNS failure"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
