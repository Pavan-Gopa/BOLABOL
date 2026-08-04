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

    guard case .bolabolCDN(let packageID, _) = canary1B.installSource else {
        #expect(Bool(false), "Canary 1B must use the explicit Bolabol CDN source")
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
