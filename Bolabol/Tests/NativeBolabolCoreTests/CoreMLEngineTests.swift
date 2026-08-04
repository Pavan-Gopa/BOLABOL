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
        #expect(model.capabilities.supportedLanguageCodes == ["en", "fr"])
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
