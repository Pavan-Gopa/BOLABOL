import Foundation
import NativeBolabolCore
import Testing

// MARK: - Model Catalog Fixtures

private extension TranscriptionModelDescriptor {
    static var flashGO: TranscriptionModelDescriptor {
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")!
    }

    static var canary1BGO: TranscriptionModelDescriptor {
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")!
    }

    static var gigaAMGO: TranscriptionModelDescriptor {
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "gigaam-v3-rnnt-coreml")!
    }
}

// MARK: - Capabilities & Contract Tests
// Note: Engine construction tests require the NativeBolabol target and are
// covered by integration testing. This suite tests the Core-layer contracts
// that engines depend on: capabilities, chunking, and backend metadata.

struct CoreMLCapabilitiesTests {

    // MARK: - Language validation via capabilities

    @Test
    func flashCapabilitiesListFourLanguages() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.supportedLanguageCodes == ["en", "de", "fr", "es"])
        #expect(model.capabilities.supportsAutoLanguageDetect == false)
    }

    @Test
    func canary1BCapabilitiesListVerifiedLanguages() {
        let model = TranscriptionModelDescriptor.canary1BGO
        #expect(model.capabilities.supportedLanguageCodes == CanaryLanguageCatalog.oneBV2LanguageCodes)
        #expect(model.capabilities.supportsAutoLanguageDetect == false)
    }

    @Test
    func gigaAMCapabilitiesListRussianOnly() {
        let model = TranscriptionModelDescriptor.gigaAMGO
        #expect(model.capabilities.supportedLanguageCodes == ["ru"])
        #expect(model.capabilities.supportsAutoLanguageDetect == false)
    }

    @Test
    func flashDoesNotSupportAutoLanguageDetect() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.supportsAutoLanguageDetect == false)
    }

    @Test
    func gigaAMDoesNotSupportTranslation() {
        let model = TranscriptionModelDescriptor.gigaAMGO
        #expect(model.capabilities.supportsSpeechTranslation == false)
    }

    @Test
    func canaryFlashSupportsSpeechTranslation() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.supportsSpeechTranslation == true)
    }

    // MARK: - Chunk boundaries

    @Test
    func flashMaxChunkIs10Seconds() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.maxChunkSeconds == 10.0)
    }

    @Test
    func canary1BMaxChunkIs15Seconds() {
        let model = TranscriptionModelDescriptor.canary1BGO
        #expect(model.capabilities.maxChunkSeconds == 15.0)
    }

    @Test
    func gigaAMMaxChunkIs30Seconds() {
        let model = TranscriptionModelDescriptor.gigaAMGO
        #expect(model.capabilities.maxChunkSeconds == 30.0)
    }

    // MARK: - OS version gates

    @Test
    func canary1BRequiresMacOS15() {
        let model = TranscriptionModelDescriptor.canary1BGO
        guard let minOS = model.capabilities.minOSVersion else {
            Issue.record("canary1B should have a minOSVersion")
            return
        }
        #expect(minOS.majorVersion == 15)
        #expect(minOS.minorVersion == 0)
    }

    @Test
    func capabilityOSGateComparesBelowEqualAndAboveVersions() {
        let model = TranscriptionModelDescriptor.canary1BGO
        let capabilities = model.capabilities
        let below = ASRModelCapabilities.OSVersion(majorVersion: 14, minorVersion: 6)
        let equal = ASRModelCapabilities.OSVersion(majorVersion: 15)
        let above = ASRModelCapabilities.OSVersion(majorVersion: 15, minorVersion: 1)

        #expect(!capabilities.isAvailable(on: below))
        #expect(capabilities.isAvailable(on: equal))
        #expect(capabilities.isAvailable(on: above))
        #expect(TranscriptionModelDescriptor.flashGO.capabilities.isAvailable(on: below))
        #expect(TranscriptionModelDescriptor.gigaAMGO.capabilities.isAvailable(on: below))
    }

    @Test
    func flashHasNoOSVersionGate() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.minOSVersion == nil)
    }

    @Test
    func gigaAMHasNoOSVersionGate() {
        let model = TranscriptionModelDescriptor.gigaAMGO
        #expect(model.capabilities.minOSVersion == nil)
    }

    // MARK: - Recommendation flags

    @Test
    func flashIsRecommendedForEnDeFrEs() {
        let model = TranscriptionModelDescriptor.flashGO
        #expect(model.capabilities.isRecommendedForEnDeFrEs == true)
        #expect(model.capabilities.isRecommendedForPrimaryRU == false)
    }

    @Test
    func gigaAMIsRecommendedForPrimaryRU() {
        let model = TranscriptionModelDescriptor.gigaAMGO
        #expect(model.capabilities.isRecommendedForPrimaryRU == true)
        #expect(model.capabilities.isRecommendedForEnDeFrEs == false)
    }

    @Test
    func S10CanarySourceProjectionUsesVerifiedASRChoices() {
        let flash = TranscriptionModelDescriptor.flashGO
        let oneB = TranscriptionModelDescriptor.canary1BGO

        let enEs = flash.sourceLanguageProjection(primary: "en", additional: "es")
        let enRu = flash.sourceLanguageProjection(primary: "en", additional: "ru")
        let ruEs = flash.sourceLanguageProjection(primary: "ru", additional: "es")
        let ruUk = flash.sourceLanguageProjection(primary: "ru", additional: "uk")
        let sameAsPrimary = flash.sourceLanguageProjection(primary: "en", additional: "en")
        let missing = flash.sourceLanguageProjection(primary: nil, additional: "")

        #expect(enEs.effectiveChoices == ["en"])
        #expect(!enEs.isClamped)
        #expect(enRu.effectiveChoices == ["en"])
        #expect(!enRu.isClamped)
        #expect(ruEs.isHardBlocked)
        #expect(!ruEs.isClamped)
        #expect(ruUk.isHardBlocked)
        #expect(sameAsPrimary.effectiveChoices == ["en"])
        #expect(!sameAsPrimary.isClamped)
        #expect(missing.isHardBlocked)

        #expect(oneB.verifiedASRSourceChoices == CanaryLanguageCatalog.oneBV2LanguageCodes)
        #expect(oneB.effectiveCanarySourceChoices(primary: "fr", additional: "en") == ["fr"])
    }

    @Test
    func S10LanguageAndAutoDecisionsIgnoreLegacyMultilingual() {
        var gigaAM = TranscriptionModelDescriptor.gigaAMGO
        gigaAM.languageSupport = .multilingual
        var oneB = TranscriptionModelDescriptor.canary1BGO
        oneB.languageSupport = .multilingual

        #expect(gigaAM.verifiedASRSourceChoices == ["ru"])
        #expect(gigaAM.capabilities.supportsAutoLanguageDetect == false)
        #expect(oneB.verifiedASRSourceChoices == CanaryLanguageCatalog.oneBV2LanguageCodes)
        #expect(oneB.capabilities.supportsAutoLanguageDetect == false)
    }

    // MARK: - Backend metadata

    @Test
    func backendCasesExistForGOModels() {
        let canaryBackend = TranscriptionModelDescriptor.Backend.canaryCoreML
        let gigaAMBackend = TranscriptionModelDescriptor.Backend.gigaAMCoreML

        #expect(canaryBackend.runtimeBadge.contains("Canary"))
        #expect(gigaAMBackend.runtimeBadge.contains("GigaAM"))
    }
}

// MARK: - Capabilities Contract Tests

struct CapabilitiesContractTests {

    @Test
    func allGOModelsHaveNonEmptyLanguageLists() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let goIDs = ["canary-180m-flash-coreml", "canary-1b-v2-coreml", "gigaam-v3-rnnt-coreml"]

        for id in goIDs {
            guard let model = catalog.model(withID: id) else {
                Issue.record("Model \(id) not found in catalog")
                continue
            }
            #expect(!model.capabilities.supportedLanguageCodes.isEmpty,
                    "Model \(id) has empty supportedLanguageCodes")
        }
    }

    @Test
    func allGOModelsDisableAutoLanguageDetect() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let goIDs = ["canary-180m-flash-coreml", "canary-1b-v2-coreml", "gigaam-v3-rnnt-coreml"]

        for id in goIDs {
            guard let model = catalog.model(withID: id) else { continue }
            #expect(model.capabilities.supportsAutoLanguageDetect == false,
                    "Model \(id) should not support auto language detect")
        }
    }

    @Test
    func allGOModelsHavePositiveMaxChunkSeconds() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let goIDs = ["canary-180m-flash-coreml", "canary-1b-v2-coreml", "gigaam-v3-rnnt-coreml"]

        for id in goIDs {
            guard let model = catalog.model(withID: id) else { continue }
            #expect(model.capabilities.maxChunkSeconds > 0,
                    "Model \(id) should have positive maxChunkSeconds")
        }
    }
}
