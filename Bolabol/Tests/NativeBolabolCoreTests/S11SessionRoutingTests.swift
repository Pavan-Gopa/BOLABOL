import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

private let s11OS15 = ASRModelCapabilities.OSVersion(majorVersion: 15)
private let s11OS14 = ASRModelCapabilities.OSVersion(majorVersion: 14)

private func s11Model(_ id: String) throws -> TranscriptionModelDescriptor {
    try #require(TranscriptionModelCatalog.nativeWhisperKit.model(withID: id))
}

private func s11Resolve(
    modelID: String,
    primary: String?,
    additional: String?,
    operation: TranscriptionSessionOperation = .asr,
    os: ASRModelCapabilities.OSVersion = s11OS15,
    complete: Bool = true
) throws -> TranscriptionSessionResolution {
    let model = try s11Model(modelID)
    return TranscriptionSessionResolver.resolve(
        activeModel: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/s11-\(modelID)"),
        engineIdentity: "engine-\(modelID)",
        currentOSVersion: os,
        hasCompleteModel: complete,
        primaryLanguageCode: primary,
        additionalLanguageCode: additional,
        operation: operation,
        legacyLanguageCode: "auto"
    )
}

@Test
func s11CanaryFlashPairMatrixUsesOnlyConfiguredSupportedSources() throws {
    let both = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "en", additional: "de")
    guard case .available(let bothPlan) = both else {
        Issue.record("Flash en/de should be available")
        return
    }
    #expect(bothPlan.languageMode == .fixed)
    #expect(bothPlan.sourceLanguageCode == "en")
    #expect(bothPlan.hudLanguageLabel == "E")
    #expect(bothPlan.request.forcedLanguageCode == "en")
    #expect(!bothPlan.request.translateToEnglish)
    #expect(bothPlan.route.postASRTextTranslationTargetLanguageCode == nil)

    #expect(bothPlan.sourceLanguageChoices == ["en"])

    let german = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "de", additional: "fr")
    guard case .available(let germanPlan) = german else {
        Issue.record("Flash de/fr should provide a fixed German source")
        return
    }
    #expect(germanPlan.sourceLanguageChoices == ["de"])
    #expect(germanPlan.sourceLanguageCode == "de")
    #expect(germanPlan.hudLanguageLabel == "G")
    #expect(germanPlan.route.postASRTextTranslationTargetLanguageCode == nil)

    let primaryOnly = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "en", additional: "ru")
    guard case .available(let primaryPlan) = primaryOnly else {
        Issue.record("Flash en/ru should clamp to English")
        return
    }
    #expect(primaryPlan.languageMode == .fixed)
    #expect(primaryPlan.sourceLanguageChoices == ["en"])
    #expect(!primaryPlan.languageControlEnabled)

    let unsupportedPrimary = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "ru", additional: "es")
    guard case .unavailable(.unsupportedSourceLanguage(
        let modelID,
        let requestedCode,
        let supportedCodes
    )) = unsupportedPrimary else {
        Issue.record("Flash ru/es should reject unsupported Primary instead of falling back")
        return
    }
    #expect(modelID == "canary-180m-flash-coreml")
    #expect(requestedCode == "ru")
    #expect(supportedCodes == ["en", "de", "fr", "es"])

    let same = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "fr", additional: "fr")
    guard case .available(let samePlan) = same else {
        Issue.record("Flash fr/fr should provide a fixed source")
        return
    }
    #expect(samePlan.sourceLanguageChoices == ["fr"])
    #expect(samePlan.languageMode == .fixed)

    let blank = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: nil, additional: " es ")
    guard case .unavailable(.noSupportedSource) = blank else {
        Issue.record("Flash requires an explicit Primary source")
        return
    }

    let none = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "ru", additional: "uk")
    guard case .unavailable(.unsupportedSourceLanguage(let modelID, let requestedCode, let supportedCodes)) = none else {
        Issue.record("Flash ru/uk should reject unsupported Primary")
        return
    }
    #expect(modelID == "canary-180m-flash-coreml")
    #expect(requestedCode == "ru")
    #expect(supportedCodes == ["en", "de", "fr", "es"])

    let defensiveAuto = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "auto", additional: nil)
    guard case .unavailable(.noSupportedSource) = defensiveAuto else {
        Issue.record("Flash auto must never become an explicit source")
        return
    }
}

@Test
func s11CanaryOneBUsesExplicitMultilingualSourceASR() throws {
    let english = try s11Resolve(modelID: "canary-1b-v2-coreml", primary: "en", additional: "fr")
    guard case .available(let plan) = english else {
        Issue.record("Canary 1B en/fr should provide an English ASR plan")
        return
    }
    #expect(plan.languageMode == .fixed)
    #expect(plan.sourceLanguageChoices == ["en"])
    #expect(plan.sourceLanguageCode == "en")
    #expect(plan.hudLanguageLabel == "E")
    #expect(plan.request.forcedLanguageCode == "en")
    #expect(!plan.request.translateToEnglish)
    #expect(plan.route.postASRTextTranslationTargetLanguageCode == nil)

    let russian = try s11Resolve(modelID: "canary-1b-v2-coreml", primary: "ru", additional: "en")
    guard case .available(let russianPlan) = russian else {
        Issue.record("Canary 1B ru/en should provide a Russian ASR plan")
        return
    }
    #expect(russianPlan.sourceLanguageCode == "ru")
    #expect(russianPlan.hudLanguageLabel == "R")
    #expect(russianPlan.route.postASRTextTranslationTargetLanguageCode == nil)

    let frenchOnly = try s11Resolve(modelID: "canary-1b-v2-coreml", primary: "fr", additional: "de")
    guard case .available(let frenchPlan) = frenchOnly else {
        Issue.record("Canary 1B should accept French without requiring English")
        return
    }
    #expect(frenchPlan.sourceLanguageCode == "fr")
    #expect(frenchPlan.route.postASRTextTranslationTargetLanguageCode == nil)

    let oldOS = try s11Resolve(
        modelID: "canary-1b-v2-coreml",
        primary: "en",
        additional: "fr",
        os: s11OS14
    )
    guard case .unavailable(.unsupportedOS(let modelID, let required, let current)) = oldOS else {
        Issue.record("Canary 1B must be gated on macOS 15+")
        return
    }
    #expect(modelID == "canary-1b-v2-coreml")
    #expect(required == s11OS15)
    #expect(current == s11OS14)

    let incomplete = try s11Resolve(
        modelID: "canary-1b-v2-coreml",
        primary: "en",
        additional: "fr",
        complete: false
    )
    guard case .unavailable(.incompleteModel("canary-1b-v2-coreml")) = incomplete else {
        Issue.record("Canary 1B incomplete folder must be unavailable")
        return
    }
}

@Test
func s11GigaAMIsFixedRussianAndRejectsTranslation() throws {
    let result = try s11Resolve(modelID: "gigaam-v3-rnnt-coreml", primary: "en", additional: "fr")
    guard case .available(let plan) = result else {
        Issue.record("GigaAM should provide fixed RU ASR")
        return
    }
    #expect(plan.languageMode == .fixed)
    #expect(plan.sourceLanguageChoices == ["ru"])
    #expect(plan.sourceLanguageCode == "ru")
    #expect(plan.hudLanguageLabel == "R")
    #expect(!plan.languageControlEnabled)
    #expect(plan.request.forcedLanguageCode == "ru")
    #expect(!plan.request.translateToEnglish)

    let translation = try s11Resolve(
        modelID: "gigaam-v3-rnnt-coreml",
        primary: "ru",
        additional: "en",
        operation: .whisperTargetTranslation(languageCode: "en")
    )
    guard case .unavailable(.translationUnsupported("gigaam-v3-rnnt-coreml")) = translation else {
        Issue.record("GigaAM translation must be unavailable")
        return
    }

    let typedTranslation = try s11Resolve(
        modelID: "gigaam-v3-rnnt-coreml",
        primary: "ru",
        additional: "en",
        operation: .whisperTargetTranslation(languageCode: "en")
    )
    #expect(typedTranslation == .unavailable(.translationUnsupported(modelID: "gigaam-v3-rnnt-coreml")))
}

@Test
func s11EveryCoreMLASRPlanHasTheNoAutoInvariant() throws {
    let cases = [
        ("canary-180m-flash-coreml", "de"),
        ("canary-1b-v2-coreml", "en"),
        ("gigaam-v3-rnnt-coreml", "ru"),
    ]

    for (modelID, source) in cases {
        let result = try s11Resolve(
            modelID: modelID,
            primary: source,
            additional: source
        )
        guard case .available(let plan) = result else {
            Issue.record("Expected a valid plan for \(modelID)")
            continue
        }
        let forced = plan.request.forcedLanguageCode
        #expect(forced != nil)
        #expect(!forced!.isEmpty)
        #expect(forced != "auto")
        #expect(plan.capabilities.explicitSupportedLanguageCodes.contains(forced!))
        #expect(!plan.request.translateToEnglish)
    }
}

@Test
func s11WhisperAndParakeetKeepLegacyAutoBehavior() throws {
    let whisper = try s11Resolve(modelID: "whisperkit-large-v3-full", primary: "en", additional: "ru")
    guard case .available(let whisperPlan) = whisper else {
        Issue.record("Whisper plan should be available")
        return
    }
    #expect(whisperPlan.languageMode == .auto)
    #expect(whisperPlan.request.forcedLanguageCode == nil)
    #expect(!whisperPlan.request.translateToEnglish)

    let whisperTarget = try s11Resolve(
        modelID: "whisperkit-large-v3-full",
        primary: "en",
        additional: "ru",
        operation: .whisperTargetTranslation(languageCode: "en")
    )
    guard case .available(let targetPlan) = whisperTarget else {
        Issue.record("Whisper target plan should be available")
        return
    }
    #expect(targetPlan.languageMode == .target)
    #expect(targetPlan.request.forcedLanguageCode == nil)
    #expect(targetPlan.request.translateToEnglish)

    let parakeet = try s11Resolve(modelID: "parakeet-tdt-06b-v3", primary: "ru", additional: "en")
    guard case .available(let parakeetPlan) = parakeet else {
        Issue.record("Parakeet plan should be available")
        return
    }
    #expect(parakeetPlan.languageMode == .auto)
    #expect(parakeetPlan.request.forcedLanguageCode == nil)
    #expect(!parakeetPlan.request.translateToEnglish)
}

@Test
func s11SessionPlanFreezesModelAndPairUntilNextSession() throws {
    let first = try s11Resolve(modelID: "canary-180m-flash-coreml", primary: "en", additional: "de")
    guard case .available(let firstPlan) = first else {
        Issue.record("Initial Flash plan should be available")
        return
    }

    let next = try s11Resolve(modelID: "gigaam-v3-rnnt-coreml", primary: "ru", additional: "en")
    guard case .available(let nextPlan) = next else {
        Issue.record("Next GigaAM plan should be available")
        return
    }

    #expect(firstPlan.modelID == "canary-180m-flash-coreml")
    #expect(firstPlan.backend == .canaryCoreML)
    #expect(firstPlan.sourceLanguageCode == "en")
    #expect(firstPlan.request.forcedLanguageCode == "en")
    #expect(nextPlan.modelID == "gigaam-v3-rnnt-coreml")
    #expect(nextPlan.request.forcedLanguageCode == "ru")
    #expect(firstPlan.modelID != nextPlan.modelID)
    #expect(firstPlan.sourceLanguageCode != nextPlan.sourceLanguageCode)
}

@Test
func s11MissingActiveModelIsTypedUnavailable() {
    let result = TranscriptionSessionResolver.resolve(
        activeModel: nil,
        currentOSVersion: s11OS15,
        primaryLanguageCode: "en",
        additionalLanguageCode: "de",
        operation: .asr
    )
    #expect(result == .unavailable(.noActiveModel))
    #expect(result.hudLanguageMode == .unavailable)
    #expect(TranscriptionLanguageMode.unavailable.id == "unavailable")
}

@MainActor
@Test
func s11EngineBindingFreezesDescriptorBackendAndEngineIdentity() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let flash = try s11Model("canary-180m-flash-coreml")
    let gigaAM = try s11Model("gigaam-v3-rnnt-coreml")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolabol-s11-binding-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try s11CreateCompleteFolder(for: flash, under: root)
    try s11CreateCompleteFolder(for: gigaAM, under: root)

    let suiteName = "bolabol-s11-binding-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let general = GeneralSettings(
        speechLanguages: UserSpeechLanguages(
            primaryLanguageCode: "en",
            additionalLanguageCode: "de"
        )
    )
    defaults.set(try JSONEncoder().encode(general), forKey: "general.settings")

    let modelStore = TranscriptionModelStore(
        catalog: catalog,
        userDefaults: defaults,
        modelsDirectory: root
    )
    modelStore.activate(flash)
    let engineStore = TranscriptionEngineStore.live()
    let first = engineStore.makeSession(
        modelStore: modelStore,
        operation: .asr
    )
    guard case .available(let firstSession) = first else {
        Issue.record("Flash should produce an engine-bound session")
        return
    }

    modelStore.activate(gigaAM)
    let second = engineStore.makeSession(
        modelStore: modelStore,
        operation: .asr
    )
    guard case .available(let secondSession) = second else {
        Issue.record("GigaAM should produce the next engine-bound session")
        return
    }

    #expect(firstSession.plan.modelID == "canary-180m-flash-coreml")
    #expect(firstSession.plan.backend == .canaryCoreML)
    #expect(firstSession.plan.engineIdentity == firstSession.engine.id)
    #expect(firstSession.plan.request.forcedLanguageCode == "en")
    #expect(secondSession.plan.modelID == "gigaam-v3-rnnt-coreml")
    #expect(secondSession.plan.backend == .gigaAMCoreML)
    #expect(secondSession.plan.engineIdentity == secondSession.engine.id)
    #expect(secondSession.plan.request.forcedLanguageCode == "ru")
    #expect(firstSession.plan.modelID != secondSession.plan.modelID)
    #expect(firstSession.engine.id != secondSession.engine.id)
}

@Test
func s11TypedWhisperTargetTranslationIsUnavailableForCanaryAndParakeet() throws {
    let result = try s11Resolve(
        modelID: "canary-1b-v2-coreml",
        primary: "en",
        additional: "ru",
        operation: .whisperTargetTranslation(languageCode: "ru")
    )

    #expect(result == .unavailable(.translationUnsupported(modelID: "canary-1b-v2-coreml")))

    let parakeet = try s11Resolve(
        modelID: "parakeet-tdt-06b-v3",
        primary: "en",
        additional: "ru",
        operation: .whisperTargetTranslation(languageCode: "en")
    )
    #expect(parakeet == .unavailable(.translationUnsupported(modelID: "parakeet-tdt-06b-v3")))
}

private func s11CreateCompleteFolder(
    for model: TranscriptionModelDescriptor,
    under root: URL
) throws {
    let folder = root.appendingPathComponent(model.relativeStorageSubpath, isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let items: [(String, Bool)]
    switch model.id {
    case "canary-1b-v2-coreml":
        items = [
            ("canary_encoder.mlmodelc", true),
            ("canary_cross_kv.mlmodelc", true),
            ("canary_decoder_kv.mlmodelc", true),
            ("canary_spe.model", false),
        ]
    case "canary-180m-flash-coreml":
        items = [
            ("CanaryEncoder.mlmodelc", true),
            ("CanaryPrefill.mlmodelc", true),
            ("CanaryDecoder.mlmodelc", true),
            ("config.json", false),
            ("vocab.json", false),
        ]
    case "gigaam-v3-rnnt-coreml":
        items = [
            ("Encoder.mlmodelc", true),
            ("Predictor.mlmodelc", true),
            ("JointDecision.mlmodelc", true),
            ("vocab.txt", false),
        ]
    default:
        items = []
    }
    for (name, isDirectory) in items {
        let url = folder.appendingPathComponent(name, isDirectory: isDirectory)
        if isDirectory {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data([0]).write(to: url)
        }
    }
}
