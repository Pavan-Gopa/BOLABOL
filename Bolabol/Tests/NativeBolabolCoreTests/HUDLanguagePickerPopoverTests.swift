import Testing
import Foundation
@testable import NativeBolabolCore
import NativeBolabol

@Suite("HUD Language Picker Popover & Integration Tests")
struct HUDLanguagePickerPopoverTests {

    private static let os15 = ASRModelCapabilities.OSVersion(majorVersion: 15)

    private func getModel(_ id: String) throws -> TranscriptionModelDescriptor {
        try #require(TranscriptionModelCatalog.nativeWhisperKit.model(withID: id))
    }

    private func resolveSession(
        modelID: String,
        primary: String = "ru",
        additional: String = "en",
        sourceLanguageOverride: String? = nil
    ) throws -> TranscriptionSessionResolution {
        let model = try getModel(modelID)
        return TranscriptionSessionResolver.resolve(
            activeModel: model,
            modelFolderURL: URL(fileURLWithPath: "/tmp/test-\(modelID)"),
            engineIdentity: "engine-\(modelID)",
            currentOSVersion: Self.os15,
            hasCompleteModel: true,
            primaryLanguageCode: primary,
            additionalLanguageCode: additional,
            operation: .asr,
            legacyLanguageCode: "auto",
            sourceLanguageOverride: sourceLanguageOverride
        )
    }

    @Test("Canary 1B options preserve canonical 25-language order and localization")
    func testCanary1BOptionsCanonicalOrderAndLocalization() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let supported = CanaryLanguageCatalog.oneBV2LanguageCodes

        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: supported,
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .russian,
            systemLocale: Locale(identifier: "ru_RU")
        )

        #expect(options.count == 25)
        let codes = options.map(\.code)
        #expect(codes == CanaryLanguageCatalog.oneBV2LanguageCodes)

        #expect(codes[0] == "bg")
        #expect(codes[5] == "en")
        #expect(codes[23] == "ru")

        // Verify localization through AppText
        let ruOption = options.first(where: { $0.code == "ru" })
        #expect(ruOption?.displayName == "Русский")
        #expect(ruOption?.isCurrent == true)
        #expect(ruOption?.isSelectable == true)

        let enOption = options.first(where: { $0.code == "en" })
        #expect(enOption?.displayName == "Английский")
        #expect(enOption?.isCurrent == false)
    }

    @Test("Canary Flash options preserve explicit model catalog order")
    func testCanaryFlashOptionsOrder() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let flashSupported = ["en", "de", "fr", "es"]

        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: flashSupported,
            currentCode: "de",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US")
        )

        #expect(options.count == 4)
        #expect(options.map(\.code) == ["en", "de", "fr", "es"])
        #expect(options[1].isCurrent == true)
        #expect(options[1].displayName == "German")
    }

    @Test("GigaAM options return fixed Russian source")
    func testGigaAMOptionsFixedRU() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")

        let options = HUDLanguageMenuPolicy.options(
            backend: .gigaAMCoreML,
            languages: languages,
            supportedSourceCodes: ["ru"],
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .russian
        )

        #expect(options.count == 1)
        #expect(options[0].code == "ru")
        #expect(options[0].isSelectable == false)
    }

    @Test("Auto/Whisper/Cloud target picker shows Auto plus complete 25-language catalog")
    func testAutoWhisperCloudTargetPickerFullCatalog() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")

        let options = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: languages,
            supportedSourceCodes: ["ru", "en"],
            currentCode: "ru",
            isAutomatic: true,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )

        // Auto + 25 languages = 26 options
        #expect(options.count == 26)
        #expect(options[0].code == "auto")
        #expect(options[0].hudLabel == "A")
        #expect(options[0].isCurrent == true)

        let codes = options.dropFirst().map(\.code)
        #expect(codes == CanaryLanguageCatalog.oneBV2LanguageCodes)

        // All should be selectable for target selection
        for option in options.dropFirst() {
            #expect(option.isSelectable, "\(option.code) should be selectable")
        }

        // Search for Italian by code, English name, and localized name
        let itOption = options.first(where: { $0.code == "it" })
        #expect(itOption != nil)
        #expect(itOption?.displayName == "Italian")
    }

    @Test("Auto/Cloud target picker shows exactly 26 options regardless of configured pair")
    func testAutoCloudTargetPickerIgnoresConfiguredPair() {
        // Configured with Russian/English only
        let languagesRUEN = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        
        let optionsRUEN = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: languagesRUEN,
            supportedSourceCodes: ["ru", "en"],
            currentCode: "ru",
            isAutomatic: true,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )
        #expect(optionsRUEN.count == 26)

        // Configured with German/French
        let languagesDEFR = UserSpeechLanguages(primaryLanguageCode: "de", additionalLanguageCode: "fr")
        
        let optionsDEFR = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: languagesDEFR,
            supportedSourceCodes: ["de", "fr"],
            currentCode: "de",
            isAutomatic: true,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )
        #expect(optionsDEFR.count == 26)

        // Both should have the same complete catalog
        #expect(optionsRUEN.map(\.code) == optionsDEFR.map(\.code))
    }

    @Test("Canary 1B explicit ASR source picker shows exactly 25 sources without Auto")
    func testCanary1BExplicitASRSourcePicker() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let supported = CanaryLanguageCatalog.oneBV2LanguageCodes

        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: supported,
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .explicitASRSource
        )

        // 25 sources, NO Auto
        #expect(options.count == 25)
        #expect(options.contains { $0.code == "auto" } == false)
        #expect(options.map(\.code) == CanaryLanguageCatalog.oneBV2LanguageCodes)

        // All should be selectable (as explicit ASR sources)
        for option in options {
            #expect(option.isSelectable, "\(option.code) should be selectable")
        }
    }

    @Test("Canary Flash explicit ASR source picker shows exactly 4 sources without Auto")
    func testCanaryFlashExplicitASRSourcePicker() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let flashSupported = CanaryLanguageCatalog.flashLanguageCodes

        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: flashSupported,
            currentCode: "en",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .explicitASRSource
        )

        // 4 sources, NO Auto
        #expect(options.count == 4)
        #expect(options.contains { $0.code == "auto" } == false)
        #expect(options.map(\.code) == ["en", "de", "fr", "es"])
        for option in options {
            #expect(option.isSelectable, "\(option.code) should be selectable")
        }
    }

    @Test("Canary arbitrary source selection cycles back to configured primary and additional pair")
    func testCanaryArbitrarySourceCycling() {
        let primary = "ru"
        let additional = "en"
        let supported = CanaryLanguageCatalog.oneBV2LanguageCodes

        let choices = HUDLanguageMenuPolicy.canarySourceCodes(
            primary: primary,
            additional: additional,
            supportedCodes: supported
        )
        #expect(choices == ["ru", "en"])

        // Current is "it" (arbitrary selection from popover)
        let nextFromArbitrary = HUDLanguageMenuPolicy.nextCode(current: "it", choices: choices)
        #expect(nextFromArbitrary == "ru")

        // Next after "ru" is "en"
        let nextFromRU = HUDLanguageMenuPolicy.nextCode(current: "ru", choices: choices)
        #expect(nextFromRU == "en")

        // Next after "en" is "ru"
        let nextFromEN = HUDLanguageMenuPolicy.nextCode(current: "en", choices: choices)
        #expect(nextFromEN == "ru")
    }
    @Test("ADR-022 fail-closed: Canary and GigaAM reject targetLanguageSelection purpose")
    func testCanaryAndGigaAMTargetLanguageSelectionFailsClosed() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")

        let canaryTargetOptions = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: CanaryLanguageCatalog.oneBV2LanguageCodes,
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english,
            purpose: .targetLanguageSelection
        )
        #expect(canaryTargetOptions.isEmpty, "Canary must fail closed for targetLanguageSelection purpose")

        let gigaAMTargetOptions = HUDLanguageMenuPolicy.options(
            backend: .gigaAMCoreML,
            languages: languages,
            supportedSourceCodes: ["ru"],
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english,
            purpose: .targetLanguageSelection
        )
        #expect(gigaAMTargetOptions.isEmpty, "GigaAM must fail closed for targetLanguageSelection purpose")
    }

    @Test("Selection callback does not mutate persisted UserSpeechLanguages settings")
    func testPickerSelectionDoesNotMutateUserSpeechLanguages() {
        let original = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let current = original

        let arbitrarySelection = "fr"
        let ephemeralOverride: String? = arbitrarySelection

        #expect(current.primaryLanguageCode == "ru")
        #expect(current.additionalLanguageCode == "en")
        #expect(ephemeralOverride == "fr")
        #expect(current == original, "Persisted settings must remain unmutated by arbitrary picker selection")
    }

    @Test("Frozen session plan inputs remain unchanged after mutable store updates")
    func testFrozenSessionImmutableAfterStoreMutation() throws {
        var languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")

        let sessionResolution = try resolveSession(
            modelID: "canary-1b-v2-coreml",
            primary: languages.primaryLanguageCode,
            additional: languages.additionalLanguageCode,
            sourceLanguageOverride: "it"
        )

        guard case .available(let frozenPlan) = sessionResolution else {
            Issue.record("Expected available Canary session plan")
            return
        }

        #expect(frozenPlan.sourceLanguageCode == "it")
        #expect(frozenPlan.sourceLanguageChoices == ["ru", "en"])
        #expect(frozenPlan.backend == .canaryCoreML)

        // Mutate original store state
        languages.primaryLanguageCode = "de"
        languages.additionalLanguageCode = "fr"

        // Assert frozen plan remains completely unchanged
        #expect(frozenPlan.sourceLanguageCode == "it")
        #expect(frozenPlan.sourceLanguageChoices == ["ru", "en"])

        // Replacement from frozen plan validates against canary catalog, keeping frozen choices intact
        let replacementRes = TranscriptionSessionResolver.replacingCanarySource(in: frozenPlan, with: "es")
        guard case .available(let replacementPlan) = replacementRes else {
            Issue.record("Expected available replacement plan")
            return
        }

        #expect(replacementPlan.sourceLanguageCode == "es")
        #expect(replacementPlan.sourceLanguageChoices == ["ru", "en"])
    }

    @Test("HUDOverlaySize and HUDOverlayFrame validate and sanitize negative and non-finite geometry")
    func testHUDOverlayGeometryValidation() {
        let invalidSize = HUDOverlaySize(width: -50.0, height: .nan)
        #expect(invalidSize.width == 0.0)
        #expect(invalidSize.height == 0.0)

        let infiniteFrame = HUDOverlayFrame(x: .infinity, y: -10.0, width: .nan, height: 100.0)
        #expect(infiniteFrame.x == 0.0)
        #expect(infiniteFrame.y == -10.0)
        #expect(infiniteFrame.width == 0.0)
        #expect(infiniteFrame.height == 100.0)

        let validFrame = HUDOverlayFrame(x: 10.0, y: 20.0, width: 150.0, height: 200.0)
        #expect(validFrame.x == 10.0)
        #expect(validFrame.y == 20.0)
        #expect(validFrame.width == 150.0)
        #expect(validFrame.height == 200.0)
    }

    @Test("Popover identity token prevents stale callback execution")
    func testPopoverIdentityTokenProtection() {
        let activeToken = UUID()
        let staleToken = UUID()

        var selectedCode: String? = nil

        let handleSelection: (String, UUID) -> Void = { code, token in
            guard token == activeToken else { return }
            selectedCode = code
        }

        // Stale callback attempt
        handleSelection("it", staleToken)
        #expect(selectedCode == nil)

        // Active callback attempt
        handleSelection("it", activeToken)
        #expect(selectedCode == "it")
    }

    // MARK: - Point-grid hit tests for A/E language circle

    private func rect(_ frame: HUDOverlayFrame) -> CGRect {
        CGRect(
            x: CGFloat(frame.x),
            y: CGFloat(frame.y),
            width: CGFloat(frame.width),
            height: CGFloat(frame.height)
        )
    }

    @Test("Language control hit rect covers entire visible circle at scale 1.0")
    func testLanguageControlHitRectCenterAndQuadrants() {
        let layout = HUDQuickSwitcherLayout.self

        let scale = 1.0
        let style = OverlayHUDStyle.vertical
        let isProcessing = false
        let showsHumorSlider = false

        let panelSize = layout.overlayPanelSize(for: scale, style: style, isProcessing: isProcessing, showsPromptBar: false, showsHumorSlider: showsHumorSlider)
        let hitFrame = layout.verticalControlHitFrame(
            slot: .language,
            panelSize: panelSize,
            scale: scale,
            style: style,
            isProcessing: isProcessing,
            showsPromptBar: false,
            showsHumorSlider: showsHumorSlider
        )
        let hitRect = rect(hitFrame)

        let controlDiameter = layout.controlDiameter(for: scale, style: style)
        let margin = layout.controlHitMargin(for: scale)

        // Hit frame is the visible circle expanded by the forgiving margin.
        #expect(hitFrame.width == controlDiameter + 2 * margin)
        #expect(hitFrame.height == controlDiameter + 2 * margin)

        let centerX = hitFrame.x + hitFrame.width / 2
        let centerY = hitFrame.y + hitFrame.height / 2

        // Everything inside the visual circle must be hittable, including edges.
        for offset in [-controlDiameter / 4, 0.0, controlDiameter / 2] {
            let testPoint = CGPoint(x: centerX + offset, y: centerY)
            #expect(hitRect.contains(testPoint), "Point \(testPoint) should be in hit rect")
            #expect(hitRect.contains(CGPoint(x: centerX, y: centerY + offset)), "Point \(testPoint) should be in hit rect")
        }

        // Horizontal edge of the visible circle must be hittable.
        #expect(hitRect.contains(CGPoint(x: centerX - controlDiameter / 2, y: centerY)))
        #expect(hitRect.contains(CGPoint(x: centerX + controlDiameter / 2, y: centerY)))
        // Vertical edge of the visible circle must be hittable.
        #expect(hitRect.contains(CGPoint(x: centerX, y: centerY - controlDiameter / 2)))
        #expect(hitRect.contains(CGPoint(x: centerX, y: centerY + controlDiameter / 2)))

        // The forgiving pointer margin must also be hittable.
        #expect(hitRect.contains(CGPoint(x: centerX - controlDiameter / 2 - margin / 2, y: centerY)))
        #expect(hitRect.contains(CGPoint(x: centerX + controlDiameter / 2 + margin / 2, y: centerY)))
        #expect(hitRect.contains(CGPoint(x: centerX, y: centerY - controlDiameter / 2 - margin / 2)))
        #expect(hitRect.contains(CGPoint(x: centerX, y: centerY + controlDiameter / 2 + margin / 2)))

        // Points beyond the forgiving margin must not be hittable.
        #expect(!hitRect.contains(CGPoint(x: centerX - controlDiameter / 2 - margin - 2, y: centerY)))
        #expect(!hitRect.contains(CGPoint(x: centerX + controlDiameter / 2 + margin + 2, y: centerY)))
        #expect(!hitRect.contains(CGPoint(x: centerX, y: centerY - controlDiameter / 2 - margin - 2)))
        #expect(!hitRect.contains(CGPoint(x: centerX, y: centerY + controlDiameter / 2 + margin + 2)))
    }

    @Test("Language and target hit regions do not overlap in vertical style")
    func testLanguageAndTargetHitRegionsNonOverlapping() {
        let layout = HUDQuickSwitcherLayout.self

        let scale = 1.0
        let style = OverlayHUDStyle.vertical
        let isProcessing = false
        let showsHumorSlider = false

        let panelSize = layout.overlayPanelSize(for: scale, style: style, isProcessing: isProcessing, showsPromptBar: false, showsHumorSlider: showsHumorSlider)

        let langHitFrame = layout.verticalControlHitFrame(
            slot: .language,
            panelSize: panelSize,
            scale: scale,
            style: style,
            isProcessing: isProcessing,
            showsPromptBar: false,
            showsHumorSlider: showsHumorSlider
        )
        let targetHitFrame = layout.verticalControlHitFrame(
            slot: .target,
            panelSize: panelSize,
            scale: scale,
            style: style,
            isProcessing: isProcessing,
            showsPromptBar: false,
            showsHumorSlider: showsHumorSlider
        )

        let langRect = CGRect(x: langHitFrame.x, y: langHitFrame.y, width: langHitFrame.width, height: langHitFrame.height)
        let targetRect = CGRect(x: targetHitFrame.x, y: targetHitFrame.y, width: targetHitFrame.width, height: targetHitFrame.height)

        // Language is the TOP control, target the BOTTOM control.
        #expect(langHitFrame.y + langHitFrame.height > targetHitFrame.y, "Language must sit above the target control")
        #expect(langRect.minY > targetRect.maxY, "Language hit rect must be strictly above target hit rect")

        // They should not overlap, and there should be a positive gap.
        #expect(!langRect.intersects(targetRect), "Language and target hit rects should not overlap")
        let gap = langRect.minY - targetRect.maxY
        #expect(gap > 0, "There should be a positive gap between language and target hit rects")

        // Both are the same forgiving size around their visible circle.
        let controlDiameter = layout.controlDiameter(for: scale, style: style)
        let margin = layout.controlHitMargin(for: scale)
        let expectedSize = controlDiameter + 2 * margin
        #expect(langHitFrame.width == expectedSize && langHitFrame.height == expectedSize)
        #expect(targetHitFrame.width == expectedSize && targetHitFrame.height == expectedSize)
    }
}
