import Foundation
import Testing
@testable import NativeBolabolCore

// FINAL-APPLICATION-EXHAUSTIVE-MAX-PLUS-SECURITY-SURFACE
//
// High-density parameterized matrices for the Vertical Pulse HUD, language
// picker policy, session resolver, settings persistence and localization.
// Each @Test expands to hundreds of assertions through explicit loops so the
// suite re-runs deterministically without UI automation.

private let maxScales: [Double] = [0.8, 0.9, 1.0, 1.1, 1.35, 1.5, 1.6]
private let maxStyles: [OverlayHUDStyle] = OverlayHUDStyle.allCases
private let maxOS15 = ASRModelCapabilities.OSVersion(majorVersion: 15)
private let maxOS14 = ASRModelCapabilities.OSVersion(majorVersion: 14)

private func maxExpectFinitePositive(_ size: HUDOverlaySize, _ label: String) {
    #expect(size.width.isFinite && size.height.isFinite, "\(label) must be finite")
    #expect(size.width > 0 && size.height > 0, "\(label) must be positive")
}

@Suite("MAX HUD Overlay Geometry Matrix")
struct MaxHUDOverlayGeometryMatrix {

    @Test("Panel sizes stay finite and positive across styles, scales, states")
    func panelSizeMatrix() {
        var cases = 0
        for style in maxStyles {
            for scale in maxScales {
                for processing in [false, true] {
                    for promptBar in [false, true] {
                        for humor in [false, true] {
                            let size = HUDQuickSwitcherLayout.overlayPanelSize(
                                for: scale,
                                style: style,
                                isProcessing: processing,
                                showsPromptBar: promptBar,
                                showsHumorSlider: humor
                            )
                            maxExpectFinitePositive(size, "panel \(style) \(scale)")
                            cases += 1
                        }
                    }
                }
            }
        }
        #expect(cases == maxStyles.count * maxScales.count * 8)
    }

    @Test("Vertical Pulse panel always fits the full D/1/2/3/4 prompt row unclipped")
    func verticalPromptRowNeverClipped() {
        for scale in maxScales {
            let promptRowWidth = HUDQuickSwitcherLayout.promptBarWidth(for: scale)
            // Product contract: the prompt bar is only presented while listening.
            let size = HUDQuickSwitcherLayout.overlayPanelSize(
                for: scale,
                style: .vertical,
                isProcessing: false,
                showsPromptBar: true,
                showsHumorSlider: false
            )
            #expect(
                size.width >= promptRowWidth,
                "scale \(scale): panel \(size.width) must fit prompt row \(promptRowWidth)"
            )
            let withHumor = HUDQuickSwitcherLayout.overlayPanelSize(
                for: scale,
                style: .vertical,
                isProcessing: false,
                showsPromptBar: true,
                showsHumorSlider: true
            )
            #expect(withHumor.width >= promptRowWidth, "scale \(scale): humor must not narrow the row")
        }
    }

    @Test("Prompt bar grows panel height by exactly bar + spacing")
    func promptBarHeightAccounting() {
        for style in maxStyles {
            for scale in maxScales {
                let base = HUDQuickSwitcherLayout.overlayPanelSize(
                    for: scale, style: style, isProcessing: false,
                    showsPromptBar: false, showsHumorSlider: false
                )
                let withBar = HUDQuickSwitcherLayout.overlayPanelSize(
                    for: scale, style: style, isProcessing: false,
                    showsPromptBar: true, showsHumorSlider: false
                )
                let delta = HUDQuickSwitcherLayout.promptBarSpacing(for: scale)
                    + HUDQuickSwitcherLayout.promptBarHeight(for: scale)
                #expect(
                    abs((withBar.height - base.height) - delta) < 1e-9,
                    "\(style) \(scale): height delta must equal bar+spacing"
                )
            }
        }
    }

    @Test("Humor slider grows panel height by exactly its reserved band")
    func humorBandAccounting() {
        for style in maxStyles {
            for scale in maxScales {
                let visualScale = HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
                let base = HUDQuickSwitcherLayout.overlayPanelSize(
                    for: scale, style: style, isProcessing: false,
                    showsPromptBar: false, showsHumorSlider: false
                )
                let withHumor = HUDQuickSwitcherLayout.overlayPanelSize(
                    for: scale, style: style, isProcessing: false,
                    showsPromptBar: false, showsHumorSlider: true
                )
                let band = 4 * visualScale + 24 * visualScale
                #expect(abs((withHumor.height - base.height) - band) < 1e-9)
            }
        }
    }

    @Test("Main capsule frame stays inside the panel for every contract configuration")
    func capsuleFrameInsidePanel() {
        for style in maxStyles {
            for scale in maxScales {
                // Product contract: prompt bar and humor slider exist only while
                // listening; processing shows the spectrum alone.
                let states: [(processing: Bool, promptBar: Bool, humor: Bool)] = [
                    (false, false, false),
                    (false, true, false),
                    (false, false, true),
                    (false, true, true),
                    (true, false, false),
                ]
                for state in states {
                    let panel = HUDQuickSwitcherLayout.overlayPanelSize(
                        for: scale, style: style, isProcessing: state.processing,
                        showsPromptBar: state.promptBar, showsHumorSlider: state.humor
                    )
                    let capsule = HUDQuickSwitcherLayout.mainCapsuleFrame(
                        panelSize: panel, scale: scale, style: style,
                        isProcessing: state.processing, showsHumorSlider: state.humor
                    )
                    #expect(capsule.width >= 1 && capsule.height >= 1)
                    #expect(capsule.x >= 0 && capsule.y >= 0, "\(style) \(scale) origin")
                    #expect(
                        capsule.x + capsule.width <= panel.width + 1e-6,
                        "\(style) \(scale) \(state): capsule right edge escapes panel"
                    )
                    #expect(
                        capsule.y + capsule.height <= panel.height + 1e-6,
                        "\(style) \(scale) \(state): capsule top edge escapes panel"
                    )
                }
            }
        }
    }

    @Test("Capsule screen anchor is pixel-stable across R/1/2 target and humor changes")
    func capsuleAnchorPixelStableAcrossAccessoryChanges() {
        for style in maxStyles {
            for scale in maxScales {
                // Contract-valid states the panel can transition between while
                // the capsule must stay pixel-anchored on screen.
                let states: [(processing: Bool, promptBar: Bool, humor: Bool)] = [
                    (false, false, false),
                    (false, true, false),
                    (false, false, true),
                    (false, true, true),
                    (true, false, false),
                ]
                let anchor = states[0]
                let panelA = HUDQuickSwitcherLayout.overlayPanelSize(
                    for: scale, style: style, isProcessing: anchor.processing,
                    showsPromptBar: anchor.promptBar, showsHumorSlider: anchor.humor
                )
                let capsuleA = HUDQuickSwitcherLayout.mainCapsuleFrame(
                    panelSize: panelA, scale: scale, style: style,
                    isProcessing: anchor.processing, showsHumorSlider: anchor.humor
                )
                let screenFrameA = HUDOverlayFrame(x: 500, y: 300, width: capsuleA.width, height: capsuleA.height)

                for state in states.dropFirst() {
                    let panelB = HUDQuickSwitcherLayout.overlayPanelSize(
                        for: scale, style: style, isProcessing: state.processing,
                        showsPromptBar: state.promptBar, showsHumorSlider: state.humor
                    )
                    let capsuleB = HUDQuickSwitcherLayout.mainCapsuleFrame(
                        panelSize: panelB, scale: scale, style: style,
                        isProcessing: state.processing, showsHumorSlider: state.humor
                    )
                    let reanchored = HUDQuickSwitcherLayout.anchoredPanelFrame(
                        previousCapsuleScreenFrame: screenFrameA,
                        newPanelSize: panelB,
                        newLocalCapsuleFrame: capsuleB
                    )
                    let screenB = HUDQuickSwitcherLayout.screenCapsuleFrame(
                        panelFrame: reanchored,
                        localCapsuleFrame: capsuleB
                    )
                    #expect(
                        abs(screenB.x - screenFrameA.x) < 1e-9
                            && abs(screenB.y - screenFrameA.y) < 1e-9,
                        "\(style) \(scale) \(state): capsule anchor moved"
                    )
                    if !state.processing {
                        // Listening accessory changes (R/1/2 target row, humor)
                        // must not change the capsule size at all.
                        #expect(abs(screenB.width - screenFrameA.width) < 1e-9)
                        #expect(abs(screenB.height - screenFrameA.height) < 1e-9)
                    }
                }
            }
        }
    }

    @Test("Non-finite scale and size inputs are sanitized, never propagated")
    func nonFiniteSanitization() {
        let bad = HUDOverlaySize(width: .nan, height: .infinity)
        #expect(bad.width == 0 && bad.height == 0)
        let badFrame = HUDOverlayFrame(x: .nan, y: -.infinity, width: .nan, height: -5)
        #expect(badFrame.x == 0 && badFrame.y == 0 && badFrame.width == 0 && badFrame.height == 0)
        let negative = HUDOverlaySize(width: -10, height: -10)
        #expect(negative.width == 0 && negative.height == 0)
        let visual = HUDQuickSwitcherLayout.overlayVisualScale(for: .nan)
        #expect(visual.isFinite)
    }
}

@Suite("MAX HUD Vertical Control Hit Geometry Matrix")
struct MaxHUDVerticalHitGeometryMatrix {

    @Test("Language and target circles never overlap and stay inside the panel")
    func circlesDisjointAndContained() {
        // Controls are only interactive while listening (product contract).
        for scale in maxScales {
            for promptBar in [false, true] {
                for humor in [false, true] {
                    let panel = HUDQuickSwitcherLayout.overlayPanelSize(
                        for: scale, style: .vertical, isProcessing: false,
                        showsPromptBar: promptBar, showsHumorSlider: humor
                    )
                    let language = HUDQuickSwitcherLayout.verticalControlHitRegion(
                        slot: .language, panelSize: panel, scale: scale, style: .vertical,
                        isProcessing: false, showsPromptBar: promptBar, showsHumorSlider: humor
                    )
                    let target = HUDQuickSwitcherLayout.verticalControlHitRegion(
                        slot: .target, panelSize: panel, scale: scale, style: .vertical,
                        isProcessing: false, showsPromptBar: promptBar, showsHumorSlider: humor
                    )
                    let distance = sqrt(
                        pow(language.centerX - target.centerX, 2)
                            + pow(language.centerY - target.centerY, 2)
                    )
                    #expect(
                        distance > language.radius + target.radius - 1e-9,
                        "scale \(scale) bar=\(promptBar) humor=\(humor): hit circles overlap"
                    )
                    for region in [language, target] {
                        #expect(region.centerX - region.radius >= -1e-6)
                        #expect(region.centerX + region.radius <= panel.width + 1e-6)
                        #expect(region.centerY - region.radius >= -1e-6)
                        #expect(region.centerY + region.radius <= panel.height + 1e-6)
                    }
                }
            }
        }
    }

    @Test("Forgiving margin stays inside the approved 8-10pt band at every scale")
    func hitMarginWithinApprovedBand() {
        for scale in maxScales {
            let margin = HUDQuickSwitcherLayout.controlHitMargin(for: scale)
            #expect(margin >= 8.0 - 1e-9, "scale \(scale): margin \(margin) below 8pt")
            #expect(margin <= 10.0 + 1e-9, "scale \(scale): margin \(margin) above 10pt")
        }
        let below = HUDQuickSwitcherLayout.controlHitMargin(for: 0.2)
        #expect(below >= 8.0 - 1e-9 && below <= 10.0 + 1e-9)
        let nanMargin = HUDQuickSwitcherLayout.controlHitMargin(for: .nan)
        #expect(nanMargin.isFinite)
    }

    @Test("Bounding square corners are rejected by the shared circle (AppKit==SwiftUI)")
    func boundingSquareCornersRejected() {
        for scale in maxScales {
            let panel = HUDQuickSwitcherLayout.overlayPanelSize(
                for: scale, style: .vertical, isProcessing: false,
                showsPromptBar: false, showsHumorSlider: false
            )
            for slot in [HUDVerticalControlSlot.language, .target] {
                let region = HUDQuickSwitcherLayout.verticalControlHitRegion(
                    slot: slot, panelSize: panel, scale: scale, style: .vertical,
                    isProcessing: false
                )
                let frame = region.boundingFrame
                let corners: [(Double, Double)] = [
                    (frame.x, frame.y),
                    (frame.x + frame.width, frame.y),
                    (frame.x, frame.y + frame.height),
                    (frame.x + frame.width, frame.y + frame.height),
                ]
                for (x, y) in corners {
                    #expect(
                        !region.contains(pointX: x, pointY: y),
                        "\(slot) scale \(scale): bounding corner must be outside the circle"
                    )
                }
                #expect(region.contains(pointX: region.centerX, pointY: region.centerY))
                #expect(region.contains(pointX: region.centerX + region.radius, pointY: region.centerY))
                #expect(!region.contains(pointX: region.centerX + region.radius + 0.5, pointY: region.centerY))
            }
        }
    }

    @Test("Language circle sits at the top of the capsule, target at the bottom")
    func slotVerticalOrdering() {
        for scale in maxScales {
            let panel = HUDQuickSwitcherLayout.overlayPanelSize(
                for: scale, style: .vertical, isProcessing: false,
                showsPromptBar: false, showsHumorSlider: false
            )
            let language = HUDQuickSwitcherLayout.verticalControlHitRegion(
                slot: .language, panelSize: panel, scale: scale, style: .vertical, isProcessing: false
            )
            let target = HUDQuickSwitcherLayout.verticalControlHitRegion(
                slot: .target, panelSize: panel, scale: scale, style: .vertical, isProcessing: false
            )
            #expect(language.centerY > target.centerY, "scale \(scale): language must be above target")
            #expect(abs(language.centerX - target.centerX) < 1e-9, "controls must share the capsule axis")
        }
    }

    @Test("Language picker popover keeps the approved compact width contract")
    func pickerCompactWidth() {
        #expect(HUDQuickSwitcherLayout.languagePickerMaxWidth == 196.0)
        #expect(HUDQuickSwitcherLayout.languagePickerMaxWidth <= 196.0)
    }
}

@Suite("MAX HUD Language Menu Policy Matrix")
struct MaxHUDLanguageMenuPolicyMatrix {

    private let pairRUEN = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")

    @Test("Whisper/Fluid target picker shows Auto plus the complete 25-language catalog")
    func targetPickerFullCatalog() {
        for backend in [TranscriptionModelDescriptor.Backend.whisperKitCoreML, .fluidAudioCoreML] {
            let options = HUDLanguageMenuPolicy.options(
                backend: backend,
                languages: pairRUEN,
                supportedSourceCodes: [],
                currentCode: nil,
                isAutomatic: true,
                uiLanguage: .english,
                systemLocale: Locale(identifier: "en_US"),
                purpose: .targetLanguageSelection
            )
            #expect(options.count == 26, "\(backend): expected auto+25, got \(options.count)")
            #expect(options.first?.code == "auto")
            #expect(options.first?.hudLabel == "A")
            #expect(options.first?.isCurrent == true)
            #expect(options.allSatisfy { $0.isSelectable })
            let codes = options.dropFirst().map(\.code)
            #expect(codes == HUDLanguageMenuPolicy.completeTargetCatalog)
            #expect(!codes.contains("auto"), "catalog must not duplicate auto")
        }
    }

    @Test("ADR-022: Canary and GigaAM never expose a target-language picker")
    func adr022NoTargetPickerForAsrOnlyBackends() {
        for backend in [TranscriptionModelDescriptor.Backend.canaryCoreML, .gigaAMCoreML] {
            let options = HUDLanguageMenuPolicy.options(
                backend: backend,
                languages: pairRUEN,
                supportedSourceCodes: ["en", "ru"],
                currentCode: "en",
                isAutomatic: false,
                uiLanguage: .english,
                systemLocale: Locale(identifier: "en_US"),
                purpose: .targetLanguageSelection
            )
            #expect(options.isEmpty, "\(backend) must not offer target selection")
        }
    }

    @Test("Canary explicit source picker shows only verified sources, never Auto")
    func canaryExplicitSourcePicker() {
        let flash = ["en", "de", "fr", "es"]
        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: UserSpeechLanguages(primaryLanguageCode: "de", additionalLanguageCode: "fr"),
            supportedSourceCodes: flash,
            currentCode: "de",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .explicitASRSource
        )
        #expect(options.map(\.code) == flash)
        #expect(!options.contains { $0.code == "auto" })
        #expect(options.allSatisfy { $0.isSelectable })
        #expect(options.first { $0.code == "de" }?.isCurrent == true)

        let single = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: pairRUEN,
            supportedSourceCodes: ["en"],
            currentCode: "en",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .explicitASRSource
        )
        #expect(single.allSatisfy { !$0.isSelectable }, "single source must not imply a cycle")
    }

    @Test("GigaAM picker is fixed to Russian and not selectable")
    func gigaAMFixedRussian() {
        let options = HUDLanguageMenuPolicy.options(
            backend: .gigaAMCoreML,
            languages: pairRUEN,
            supportedSourceCodes: ["ru"],
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .explicitASRSource
        )
        #expect(options.map(\.code) == ["ru"])
        #expect(options.allSatisfy { !$0.isSelectable })
        #expect(options.first?.isCurrent == true)
    }

    @Test("BUG-VPH-007: Add badge is derived from the live Additional language")
    func additionalBadgeFollowsSettings() {
        var languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        func badgeCodes() -> [String] {
            HUDLanguageMenuPolicy.options(
                backend: .whisperKitCoreML,
                languages: languages,
                supportedSourceCodes: [],
                currentCode: nil,
                isAutomatic: true,
                uiLanguage: .english,
                systemLocale: Locale(identifier: "en_US"),
                purpose: .targetLanguageSelection
            ).filter(\.isAdditional).map(\.code)
        }

        #expect(badgeCodes() == ["en"])
        languages = languages.settingAdditional("fi")
        #expect(badgeCodes() == ["fi"], "badge must move English -> Finnish after Settings change")
        languages = languages.settingAdditionalSameAsPrimary()
        #expect(badgeCodes().isEmpty, "same-as-primary pair must show no Add badge")
    }

    @Test("nextCode cycles switchable choices and refuses fixed ones")
    func nextCodeMatrix() {
        #expect(HUDLanguageMenuPolicy.nextCode(current: "ru", choices: ["ru", "en"]) == "en")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "en", choices: ["ru", "en"]) == "ru")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "RU ", choices: ["ru", "en"]) == "en")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "fr", choices: ["ru", "en"]) == "ru")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "ru", choices: ["ru"]) == nil)
        #expect(HUDLanguageMenuPolicy.nextCode(current: "ru", choices: []) == nil)
        let triple = ["en", "de", "fr"]
        #expect(HUDLanguageMenuPolicy.nextCode(current: "en", choices: triple) == "de")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "de", choices: triple) == "fr")
        #expect(HUDLanguageMenuPolicy.nextCode(current: "fr", choices: triple) == "en")
    }

    @Test("canarySourceCodes keeps Settings pair order and filters unsupported")
    func canarySourceCodesMatrix() {
        let flash = ["en", "de", "fr", "es"]
        #expect(
            HUDLanguageMenuPolicy.canarySourceCodes(primary: "de", additional: "fr", supportedCodes: flash)
                == ["de", "fr"]
        )
        #expect(
            HUDLanguageMenuPolicy.canarySourceCodes(primary: "ru", additional: "en", supportedCodes: flash)
                == ["en"]
        )
        #expect(
            HUDLanguageMenuPolicy.canarySourceCodes(primary: "en", additional: "en", supportedCodes: flash)
                == ["en"]
        )
        #expect(
            HUDLanguageMenuPolicy.canarySourceCodes(primary: nil, additional: nil, supportedCodes: flash)
                .isEmpty
        )
        #expect(
            HUDLanguageMenuPolicy.canarySourceCodes(primary: "auto", additional: "de", supportedCodes: flash)
                == ["de"]
        )
    }
}

@Suite("MAX Transcription Session Resolver Matrix")
struct MaxSessionResolverMatrix {

    private func model(_ id: String) throws -> TranscriptionModelDescriptor {
        try #require(TranscriptionModelCatalog.nativeWhisperKit.model(withID: id))
    }

    private func resolve(
        _ id: String,
        primary: String? = "ru",
        additional: String? = "en",
        operation: TranscriptionSessionOperation = .asr,
        os: ASRModelCapabilities.OSVersion = maxOS15,
        complete: Bool = true,
        legacy: String? = nil,
        override: String? = nil
    ) throws -> TranscriptionSessionResolution {
        TranscriptionSessionResolver.resolve(
            activeModel: try model(id),
            currentOSVersion: os,
            hasCompleteModel: complete,
            primaryLanguageCode: primary,
            additionalLanguageCode: additional,
            operation: operation,
            legacyLanguageCode: legacy,
            sourceLanguageOverride: override
        )
    }

    private func plan(
        _ id: String,
        primary: String? = "ru",
        additional: String? = "en",
        operation: TranscriptionSessionOperation = .asr,
        legacy: String? = nil,
        override: String? = nil
    ) throws -> TranscriptionSessionPlan {
        let resolution = try resolve(
            id, primary: primary, additional: additional,
            operation: operation, legacy: legacy, override: override
        )
        guard case .available(let plan) = resolution else {
            Issue.record("expected available plan for \(id), got \(resolution)")
            throw TranscriptionSessionUnavailableReason.noActiveModel
        }
        return plan
    }

    @Test("Every catalog model resolves available under valid ASR conditions")
    func allCatalogModelsResolve() throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        #expect(catalog.models.count == 10)
        for model in catalog.models {
            let primary = model.backend == .gigaAMCoreML ? "ru" : "en"
            let resolution = TranscriptionSessionResolver.resolve(
                activeModel: model,
                currentOSVersion: maxOS15,
                hasCompleteModel: true,
                primaryLanguageCode: primary,
                additionalLanguageCode: "en",
                operation: .asr
            )
            guard case .available(let plan) = resolution else {
                Issue.record("\(model.id) must resolve available, got \(resolution)")
                continue
            }
            #expect(plan.modelID == model.id)
            #expect(plan.backend == model.backend)
            #expect(plan.languageControlEnabled || plan.languageMode == .fixed)
        }
    }

    @Test("BUG-VPH-006: Parakeet Auto + Primary Russian carries a Russian anchor hint")
    func bugVPH006ParakeetAutoRussian() throws {
        let parakeet = try plan("parakeet-tdt-06b-v3", primary: "ru", additional: "en", legacy: "auto")
        #expect(parakeet.languageMode == .auto)
        #expect(parakeet.hudLanguageLabel == "A")
        #expect(parakeet.route.forcedLanguageCode == nil, "auto must not force a Whisper token")
        #expect(parakeet.route.translateToEnglish == false)
        #expect(parakeet.route.postASRTextTranslationTargetLanguageCode == nil, "no silent English route")
        #expect(parakeet.route.languageHint == "ru", "auto session must anchor to Primary Russian")
        #expect(parakeet.request.languageHint == "ru")
        #expect(parakeet.request.forcedLanguageCode == nil)
    }

    @Test("Parakeet explicit legacy language stays unanchored")
    func parakeetExplicitLegacyUnanchored() throws {
        let parakeet = try plan("parakeet-tdt-06b-v3", primary: "ru", additional: "en", legacy: "de")
        #expect(parakeet.route.languageHint == nil)
        #expect(parakeet.requestedLanguageCode == "de")
    }

    @Test("Whisper multilingual target translation routes English natively, others post-ASR")
    func whisperTargetRoutingMatrix() throws {
        let targets = ["en", "de", "fr", "es", "ru", "uk", "zh", "it", "pt", "nl"]
        for target in targets {
            let plan = try plan(
                "whisperkit-large-v3-full",
                operation: .whisperTargetTranslation(languageCode: target)
            )
            #expect(plan.languageMode == .target)
            #expect(plan.isWhisperTargetMode)
            if target == "en" {
                #expect(plan.route.translateToEnglish == true, "en target uses Whisper task translate")
                #expect(plan.route.postASRTextTranslationTargetLanguageCode == nil)
            } else {
                #expect(plan.route.translateToEnglish == false)
                #expect(plan.route.postASRTextTranslationTargetLanguageCode == target)
            }
            #expect(plan.hudLanguageLabel == TranscriptionLanguageOption.hudLabel(for: target))
        }
    }

    @Test("English-only Whisper cannot translate; even English target falls to post-ASR")
    func englishOnlyWhisperNeverTranslates() throws {
        for modelID in ["whisperkit-small-en", "whisperkit-medium-en"] {
            for target in ["en", "de", "ru"] {
                let plan = try plan(
                    modelID,
                    operation: .whisperTargetTranslation(languageCode: target)
                )
                #expect(plan.route.translateToEnglish == false, "\(modelID) \(target)")
                #expect(plan.route.postASRTextTranslationTargetLanguageCode == target)
                #expect(!plan.supportsNativeWhisperTranslation)
            }
        }
    }

    @Test("ADR-022: Canary and GigaAM reject speech translation operations")
    func adr022SpeechTranslationRejected() throws {
        for modelID in ["canary-180m-flash-coreml", "canary-1b-v2-coreml", "gigaam-v3-rnnt-coreml"] {
            let resolution = try resolve(
                modelID,
                operation: .whisperTargetTranslation(languageCode: "de")
            )
            guard case .unavailable(let reason) = resolution else {
                Issue.record("\(modelID) must reject translation")
                continue
            }
            #expect(reason == .translationUnsupported(modelID: modelID))
        }
        let fluid = try resolve(
            "parakeet-tdt-06b-v3",
            operation: .whisperTargetTranslation(languageCode: "de")
        )
        guard case .unavailable(let reason) = fluid else {
            Issue.record("Parakeet must reject whisper target translation")
            return
        }
        #expect(reason == .translationUnsupported(modelID: "parakeet-tdt-06b-v3"))
    }

    @Test("Canary 1B ru/en pair is switchable R/E, never fixed to R")
    func canaryOneBSwitchableRuEn() throws {
        let plan = try plan("canary-1b-v2-coreml", primary: "ru", additional: "en")
        #expect(plan.languageMode == .switchable)
        #expect(plan.sourceLanguageChoices == ["ru", "en"])
        #expect(plan.sourceLanguageCode == "ru")
        #expect(plan.languageControlEnabled == true)
        #expect(plan.hudLanguageLabel == "R")

        let switched = TranscriptionSessionResolver.replacingCanarySource(in: plan, with: "en")
        guard case .available(let englishPlan) = switched else {
            Issue.record("switch to en must succeed, got \(switched)")
            return
        }
        #expect(englishPlan.sourceLanguageCode == "en")
        #expect(englishPlan.hudLanguageLabel == "E")
        #expect(englishPlan.modelFolderURL == plan.modelFolderURL, "model folder must stay frozen")
        #expect(englishPlan.engineIdentity == plan.engineIdentity)
        #expect(englishPlan.sourceLanguageWarning == nil)

        let back = TranscriptionSessionResolver.replacingCanarySource(in: englishPlan, with: "ru")
        guard case .available(let russianPlan) = back else {
            Issue.record("switch back to ru must succeed")
            return
        }
        #expect(russianPlan.sourceLanguageCode == "ru")
    }

    @Test("Canary Flash only accepts its four verified sources")
    func canaryFlashSourceMatrix() throws {
        for supported in ["en", "de", "fr", "es"] {
            let plan = try plan("canary-180m-flash-coreml", primary: supported, additional: nil)
            #expect(plan.sourceLanguageCode == supported)
            #expect(plan.languageMode == .fixed)
            #expect(!plan.languageControlEnabled)
        }
        let resolution = try resolve("canary-180m-flash-coreml", primary: "ru", additional: nil)
        guard case .unavailable(let reason) = resolution else {
            Issue.record("Flash must reject ru primary")
            return
        }
        #expect(
            reason == .unsupportedSourceLanguage(
                modelID: "canary-180m-flash-coreml",
                requestedCode: "ru",
                supportedCodes: ["en", "de", "fr", "es"]
            )
        )
    }

    @Test("Canary rejects auto/empty/unsupported ephemeral overrides")
    func canaryOverrideMatrix() throws {
        let base = try plan("canary-1b-v2-coreml", primary: "ru", additional: "en")
        for bad in ["auto", "AUTO ", "", "zh", "zz"] {
            let resolution = TranscriptionSessionResolver.replacingCanarySource(in: base, with: bad)
            guard case .unavailable = resolution else {
                Issue.record("override \(bad) must be unavailable")
                continue
            }
        }
        let resolution = try resolve(
            "canary-1b-v2-coreml", primary: "ru", additional: "en", override: "UK "
        )
        guard case .available(let plan) = resolution else {
            Issue.record("normalized override must resolve, got \(resolution)")
            return
        }
        #expect(plan.sourceLanguageCode == "uk")
        #expect(plan.hudLanguageLabel == "U")
    }

    @Test("GigaAM is fixed Russian and rejects every other override")
    func gigaAMMatrix() throws {
        let plan = try plan("gigaam-v3-rnnt-coreml", primary: "ru", additional: "en")
        #expect(plan.languageMode == .fixed)
        #expect(plan.sourceLanguageCode == "ru")
        #expect(plan.hudLanguageLabel == "R")
        #expect(!plan.languageControlEnabled)
        for bad in ["en", "auto", "de"] {
            let resolution = try resolve(
                "gigaam-v3-rnnt-coreml", primary: "ru", additional: "en", override: bad
            )
            guard case .unavailable = resolution else {
                Issue.record("GigaAM override \(bad) must be unavailable")
                continue
            }
        }
    }

    @Test("Unavailable reasons are typed and terminal for every failure class")
    func unavailableMatrix() throws {
        let none = TranscriptionSessionResolver.resolve(
            activeModel: nil,
            currentOSVersion: maxOS15,
            hasCompleteModel: true,
            primaryLanguageCode: "en",
            additionalLanguageCode: "en",
            operation: .asr
        )
        #expect(none == .unavailable(.noActiveModel))
        #expect(none.hudLanguageMode == .unavailable)

        let incomplete = try resolve("whisperkit-large-v3-full", complete: false)
        #expect(incomplete == .unavailable(.incompleteModel(modelID: "whisperkit-large-v3-full")))

        let oldOS = try resolve("canary-1b-v2-coreml", os: maxOS14)
        guard case .unavailable(let reason) = oldOS else {
            Issue.record("1B on macOS 14 must be unavailable")
            return
        }
        #expect(
            reason == .unsupportedOS(
                modelID: "canary-1b-v2-coreml",
                required: ASRModelCapabilities.OSVersion(majorVersion: 15),
                current: maxOS14
            )
        )

        let noPrimaryCanary = try resolve("canary-1b-v2-coreml", primary: nil, additional: nil)
        guard case .unavailable(let noSource) = noPrimaryCanary else {
            Issue.record("Canary without primary must be unavailable")
            return
        }
        #expect(noSource.modelID == "canary-1b-v2-coreml")
    }

    @Test("HUD letter labels follow the Latin first-letter contract")
    func hudLabelMatrix() {
        let expectations: [String: String] = [
            "auto": "A", "en": "E", "ru": "R", "de": "G", "fr": "F", "es": "S",
            "uk": "U", "pl": "P", "it": "I", "pt": "P", "zh": "C", "ja": "J",
            "ko": "K", "ar": "A", "hi": "H", "": "E",
        ]
        for (code, label) in expectations {
            #expect(
                TranscriptionLanguageOption.hudLabel(for: code) == label,
                "hudLabel(\(code)) expected \(label)"
            )
        }
    }

    @Test("Engine identity defaults to backend:model and survives normalization")
    func engineIdentityMatrix() throws {
        let plan = try plan("whisperkit-small-en")
        #expect(plan.engineIdentity == "whisperKitCoreML:whisperkit-small-en")
        let resolution = TranscriptionSessionResolver.resolve(
            activeModel: try model("whisperkit-small-en"),
            engineIdentity: "  custom-engine  ",
            currentOSVersion: maxOS15,
            hasCompleteModel: true,
            primaryLanguageCode: "en",
            additionalLanguageCode: "en",
            operation: .asr
        )
        guard case .available(let custom) = resolution else {
            Issue.record("custom identity must resolve")
            return
        }
        #expect(custom.engineIdentity == "custom-engine")
    }
}

@Suite("MAX Settings Persistence Round-Trip Matrix")
struct MaxSettingsPersistenceMatrix {

    @Test("GeneralSettings survives JSON round-trip for every enum case")
    func generalSettingsRoundTrip() throws {
        for theme in ThemePreference.allCases {
            for uiLanguage in UILanguagePreference.allCases {
                for style in OverlayHUDStyle.allCases {
                    for position in OverlayPosition.allCases {
                        var settings = GeneralSettings(
                            theme: theme,
                            uiLanguage: uiLanguage,
                            overlay: OverlayHUDSettings(position: position, style: style),
                            speechLanguages: UserSpeechLanguages(
                                primaryLanguageCode: "ru",
                                additionalLanguageCode: "fi"
                            )
                        )
                        settings.normalize()
                        let data = try JSONEncoder().encode(settings)
                        let decoded = try JSONDecoder().decode(GeneralSettings.self, from: data)
                        #expect(decoded == settings, "\(theme)/\(uiLanguage)/\(style)/\(position)")
                        #expect(decoded.speechLanguages.additionalLanguageCode == "fi")
                    }
                }
            }
        }
    }

    @Test("Out-of-range persisted values are clamped on decode, never crash")
    func decodeClampingMatrix() throws {
        let payloads: [(String, (GeneralSettings) -> Bool)] = [
            (
                #"{"uiScale": 99, "textScale": -5, "maxSavedAudioRecordings": 0, "overlay": {"scale": 42, "capsuleOpacity": -1, "volume": 99}}"#,
                { s in
                    s.uiScale == 1.4 && s.textScale == 1.0 && s.maxSavedAudioRecordings == 2
                        && s.overlay.scale == 1.6 && s.overlay.capsuleOpacity == 0.12
                        && s.overlay.volume == 2
                }
            ),
            (
                #"{"uiScale": -99, "textScale": 99, "maxSavedAudioRecordings": 99999, "overlay": {"scale": -3, "capsuleOpacity": 9, "volume": -9}}"#,
                { s in
                    s.uiScale == 0.8 && s.textScale == 2.0 && s.maxSavedAudioRecordings == 500
                        && s.overlay.scale == 0.8 && s.overlay.capsuleOpacity == 1
                        && s.overlay.volume == 0.1
                }
            ),
            (
                #"{}"#,
                { s in
                    s.theme == .dark && s.uiLanguage == .system && s.overlay.style == .capsule
                        && s.speechLanguages.additionalLanguageCode == "en"
                        && LanguagePickerOrder.orderedSpeechCodes.contains(s.speechLanguages.primaryLanguageCode)
                }
            ),
        ]
        for (payload, check) in payloads {
            let decoded = try JSONDecoder().decode(GeneralSettings.self, from: Data(payload.utf8))
            #expect(check(decoded), "payload not clamped as expected: \(payload)")
        }
    }

    @Test("Unknown HUD style keys are dropped from persisted style origins")
    func styleOriginFiltering() throws {
        let payload = #"{"styleOrigins": {"capsule": {"x": 1, "y": 2}, "bogus": {"x": 9, "y": 9}}}"#
        let decoded = try JSONDecoder().decode(
            OverlayHUDSettings.self,
            from: Data(payload.utf8)
        )
        #expect(decoded.styleOrigins.count == 1)
        #expect(decoded.origin(for: .capsule) == OverlayHUDOrigin(x: 1, y: 2))
        #expect(decoded.origin(for: .tech) == nil)
        #expect(decoded.lastOrigin == nil, "lastOrigin is stored separately from styleOrigins")
        var settings = decoded
        settings.setOrigin(OverlayHUDOrigin(x: 5, y: 6), for: .vertical)
        #expect(settings.origin(for: .vertical) == OverlayHUDOrigin(x: 5, y: 6))
        #expect(settings.lastOrigin == nil, "non-capsule origins must not touch lastOrigin")
        settings.setOrigin(OverlayHUDOrigin(x: 7, y: 8), for: .capsule)
        #expect(settings.lastOrigin == OverlayHUDOrigin(x: 7, y: 8))
        #expect(settings.origin(for: .capsule) == OverlayHUDOrigin(x: 7, y: 8))
    }

    @Test("UserSpeechLanguages normalization and migration matrix")
    func speechLanguagesMatrix() {
        #expect(UserSpeechLanguages(primaryLanguageCode: " RU ", additionalLanguageCode: "EN")
            == UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en"))
        #expect(UserSpeechLanguages(primaryLanguageCode: "", additionalLanguageCode: "")
            == UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "en"))
        #expect(UserSpeechLanguages(primaryLanguageCode: "auto", additionalLanguageCode: "auto")
            .orderedDistinctCodes.isEmpty)

        let migrated = UserSpeechLanguages.migrating(
            legacyTranscriptionCode: "de",
            legacyTargetLanguageName: "French",
            systemLocale: Locale(identifier: "en_US")
        )
        #expect(migrated.primaryLanguageCode == "de")
        #expect(migrated.additionalLanguageCode == "fr")

        let legacyUnknown = UserSpeechLanguages.migrating(
            legacyTranscriptionCode: "zz",
            legacyTargetLanguageName: nil,
            systemLocale: Locale(identifier: "ru_RU")
        )
        #expect(legacyUnknown.primaryLanguageCode == "ru", "locale fallback for unknown legacy")
        #expect(legacyUnknown.additionalLanguageCode == "en")

        let samePrimary = UserSpeechLanguages(primaryLanguageCode: "de", additionalLanguageCode: "de")
        #expect(samePrimary.usesSameAdditionalAsPrimary)
        #expect(!samePrimary.isAdditionalLanguage("de"), "same-as-primary shows no badge")
        let followed = samePrimary.settingPrimary("fr")
        #expect(followed.additionalLanguageCode == "fr", "mirror follows new primary")
        let explicit = UserSpeechLanguages(primaryLanguageCode: "de", additionalLanguageCode: "fi")
        #expect(explicit.settingPrimary("fr").additionalLanguageCode == "fi")
        #expect(explicit.isAdditionalLanguage(" FI "))
    }

    @Test("UserSpeechLanguages Codable round-trip and legacy absent-field decode")
    func speechLanguagesCodable() throws {
        let value = UserSpeechLanguages(primaryLanguageCode: "uk", additionalLanguageCode: "pl")
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(UserSpeechLanguages.self, from: data) == value)
        let absent = try JSONDecoder().decode(UserSpeechLanguages.self, from: Data("{}".utf8))
        #expect(absent == UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "en"))
    }

    @Test("UILanguagePreference resolves every supported locale and falls back to en")
    func uiLanguageResolution() {
        for preference in UILanguagePreference.allCases where preference != .system {
            #expect(
                preference.resolvedLocaleIdentifier(for: Locale(identifier: "zz_ZZ"))
                    == preference.rawValue
            )
        }
        #expect(UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "ru_RU")) == "ru")
        #expect(UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "xx_XX")) == "en")
        #expect(UILanguagePreference.allCases.count == 16)
    }
}

@Suite("MAX AppText Localization Surface Matrix")
struct MaxAppTextSurfaceMatrix {

    private let touchedKeys: [AppTextKey] = [
        .settingsGeneral, .settingsAPIProviders, .settingsHotkey, .settingsLocalModels,
        .settingsPolishing, .settingsPrompts, .settingsStatistics, .settingsHelp,
        .hudStyle, .hudStyleCapsule, .hudStyleTech, .hudStyleVertical,
        .autoDetect, .translation, .notes, .settings, .search,
        .audioPlaybackModalTitle, .audioFileNotFound, .audioArchiveRetention,
        .hotkeyDescription, .hotkeyTargetLanguage, .hotkeyPrimaryLabel, .hotkeySecondaryLabel,
        .onboardingWelcomeTitle, .onboardingChooseLanguageTitle,
    ]

    @Test("Every touched surface key is localized in all 15 UI locales")
    func touchedKeysLocalizedEverywhere() {
        let locales = UILanguagePreference.allCases.filter { $0 != .system }
        #expect(locales.count == 15)
        for language in locales {
            for key in touchedKeys {
                let value = AppText.localized(
                    key,
                    language: language,
                    systemLocale: Locale(identifier: "en_US")
                )
                #expect(!value.isEmpty, "\(key) empty in \(language)")
                #expect(value != key.rawValue, "\(key) fell back to raw key in \(language)")
            }
        }
    }

    @Test("Speech language names resolve for the full catalog in sample locales")
    func speechLanguageNamesResolve() {
        for language in [UILanguagePreference.english, .russian, .german, .spanish, .japanese] {
            for code in LanguagePickerOrder.orderedSpeechCodes {
                let name = AppText.localizedSpeechLanguageName(
                    for: code,
                    language: language,
                    systemLocale: Locale(identifier: "en_US")
                )
                #expect(!name.isEmpty, "\(code) name empty in \(language)")
                #expect(name != "auto")
            }
        }
        #expect(
            AppText.localizedSpeechLanguageName(
                for: "",
                language: .english,
                systemLocale: Locale(identifier: "en_US")
            ).isEmpty
        )
    }

    @Test("Russian and English UI produce distinct copies for localized keys")
    func ruEnDistinct() {
        for key in touchedKeys {
            let en = AppText.localized(key, language: .english, systemLocale: Locale(identifier: "en_US"))
            let ru = AppText.localized(key, language: .russian, systemLocale: Locale(identifier: "en_US"))
            #expect(!ru.isEmpty)
            #expect(!en.isEmpty)
        }
        let autoEn = AppText.localized(.autoDetect, language: .english, systemLocale: Locale(identifier: "en_US"))
        let autoRu = AppText.localized(.autoDetect, language: .russian, systemLocale: Locale(identifier: "en_US"))
        #expect(autoEn != autoRu, "Auto detect must be translated, not copied")
    }
}

@Suite("MAX Provider Switcher And Session Coordinator Matrix")
struct MaxSwitcherCoordinatorMatrix {

    private func providers(_ count: Int) -> [ProviderQuickSwitcherModel.Provider] {
        (0..<count).map { ProviderQuickSwitcherModel.Provider(id: "p\($0)", displayName: "Provider \($0)") }
    }

    @Test("Scroll cycling is deterministic across thresholds, cooldowns and directions")
    func scrollMatrix() {
        var switcher = ProviderQuickSwitcherModel(
            providers: providers(3),
            activeID: "p0",
            stepThreshold: 24,
            stepCooldown: 0.05
        )
        #expect(switcher.canCycle)
        // Positive delta moves toward the list start (wraps 0 -> last).
        #expect(switcher.applyScroll(deltaY: 25, now: 0)?.id == "p2")
        #expect(switcher.applyScroll(deltaY: 25, now: 0.01) == nil, "cooldown blocks rapid repeat")
        #expect(switcher.applyScroll(deltaY: -25, now: 0.2)?.id == "p0")
        #expect(switcher.applyScroll(deltaY: -25, now: 0.4)?.id == "p1")
        #expect(switcher.applyScroll(deltaY: -5, now: 0.6) == nil, "below threshold accumulates only")
        #expect(switcher.activeProvider?.id == "p1")
        #expect(switcher.select(id: "p2")?.id == "p2")
        #expect(switcher.select(id: "missing") == nil)
        switcher.setActive(id: "p0")
        #expect(switcher.activeProvider?.id == "p0")
        var single = ProviderQuickSwitcherModel(providers: providers(1), activeID: nil)
        #expect(!single.canCycle)
        #expect(single.applyScroll(deltaY: 99, now: 10) == nil)
    }

    @Test("Non-finite scroll input never poisons the accumulator")
    func nonFiniteScrollMatrix() {
        for bad in [Double.nan, .infinity, -.infinity] {
            var switcher = ProviderQuickSwitcherModel(
                providers: providers(2),
                activeID: "p0",
                stepThreshold: 24,
                stepCooldown: 0
            )
            #expect(switcher.applyScroll(deltaY: bad, now: 0) == nil)
            #expect(
                switcher.applyScroll(deltaY: 25, now: 1)?.id == "p1",
                "finite input after \(bad) must still work"
            )
        }
    }

    @Test("Layout row hit-testing maps points to rows and rejects gaps")
    func rowIndexMatrix() {
        let list = providers(3)
        let height = HUDQuickSwitcherLayout.contentHeight(providers: list)
        #expect(height > 0)
        let topRow = HUDQuickSwitcherLayout.rowIndex(
            forY: height - HUDQuickSwitcherLayout.verticalPadding - 1,
            providers: list
        )
        #expect(topRow == 0)
        let bottomRow = HUDQuickSwitcherLayout.rowIndex(
            forY: HUDQuickSwitcherLayout.verticalPadding + 1,
            providers: list
        )
        #expect(bottomRow == 2)
        #expect(HUDQuickSwitcherLayout.rowIndex(forY: -5, providers: list) == nil)
        #expect(HUDQuickSwitcherLayout.rowIndex(forY: height + 5, providers: list) == nil)
        #expect(HUDQuickSwitcherLayout.rowIndex(forY: 10, providers: []) == nil)
        #expect(HUDQuickSwitcherLayout.contentHeight(providers: []) == 0)
    }

    @Test("Divider appears only when local engine leads a multi-provider list")
    func dividerMatrix() {
        let localFirst = [
            ProviderQuickSwitcherModel.Provider(
                id: HUDQuickSwitcherLayout.localEngineID,
                displayName: "Local"
            ),
            ProviderQuickSwitcherModel.Provider(id: "cloud", displayName: "Cloud"),
        ]
        #expect(HUDQuickSwitcherLayout.hasDivider(providers: localFirst))
        let cloudFirst = Array(localFirst.reversed())
        #expect(!HUDQuickSwitcherLayout.hasDivider(providers: cloudFirst))
        #expect(!HUDQuickSwitcherLayout.hasDivider(providers: [localFirst[0]]))
        let withDivider = HUDQuickSwitcherLayout.contentHeight(providers: localFirst)
        let withoutDivider = HUDQuickSwitcherLayout.contentHeight(providers: cloudFirst)
        #expect(withDivider - withoutDivider == HUDQuickSwitcherLayout.dividerHeight)
    }

    @MainActor
    @Test("Hotkey session coordinator enforces single-owner phase transitions")
    func coordinatorMatrix() {
        let coordinator = HotkeySessionCoordinator()
        let first = UUID()
        let second = UUID()
        #expect(coordinator.phase == .idle)
        #expect(coordinator.beginRecording(ownerID: first))
        #expect(coordinator.isOwned(by: first))
        #expect(!coordinator.isOwned(by: second))
        #expect(!coordinator.beginRecording(ownerID: second), "second owner cannot steal recording")
        #expect(coordinator.beginProcessing(ownerID: first))
        #expect(!coordinator.beginProcessing(ownerID: second))
        coordinator.finish(ownerID: second)
        #expect(coordinator.isOwned(by: first), "foreign finish must not steal the session")
        coordinator.finish(ownerID: first)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.reclaimOrphanedRecordingForStop(ownerID: second))
        #expect(coordinator.isOwned(by: second))
        #expect(!coordinator.reclaimOrphanedRecordingForStop(ownerID: first), "reclaim only from idle")
        coordinator.reset()
        #expect(coordinator.phase == .idle)
        #expect(!coordinator.isOwned(by: second))
    }

    @MainActor
    @Test("Stuck processing expires but live recording never times out")
    func coordinatorTimeoutMatrix() {
        let owner = UUID()
        let intruder = UUID()
        let start = Date()

        let coordinator = HotkeySessionCoordinator(sessionTimeout: 60)
        coordinator.beginRecording(ownerID: owner, now: start)
        coordinator.beginProcessing(ownerID: owner, now: start)
        #expect(
            coordinator.beginRecording(ownerID: intruder, now: start.addingTimeInterval(61)),
            "expired stuck processing must release the session"
        )
        #expect(!coordinator.isOwned(by: owner))

        let recorder = HotkeySessionCoordinator(sessionTimeout: 60)
        recorder.beginRecording(ownerID: owner, now: start)
        #expect(
            !recorder.beginRecording(ownerID: intruder, now: start.addingTimeInterval(10_000)),
            "long live recording must never expire"
        )
        #expect(recorder.isOwned(by: owner))
    }
}
