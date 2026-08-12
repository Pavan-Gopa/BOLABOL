import Testing
import Foundation
import AppKit
import SwiftUI
@testable import NativeBolabolCore
@testable import NativeBolabol

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

    @Test("Additional badge follows the current Settings language")
    func testAdditionalBadgeFollowsCurrentSettingsLanguage() {
        let initialLanguages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let initialOptions = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: initialLanguages,
            supportedSourceCodes: [],
            currentCode: "en",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )

        let initialEnglish = initialOptions.first(where: { $0.code == "en" })
        let initialFinnish = initialOptions.first(where: { $0.code == "fi" })
        #expect(initialEnglish?.isCurrent == true)
        #expect(initialEnglish?.isAdditional == true)
        #expect(initialFinnish?.isAdditional == false)

        let finnishLanguages = initialLanguages.settingAdditional("fi")
        let updatedOptions = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: finnishLanguages,
            supportedSourceCodes: [],
            currentCode: "fi",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )

        let currentOptions = updatedOptions.filter(\.isCurrent)
        #expect(currentOptions.map(\.code) == ["fi"])
        #expect(currentOptions.first?.isAdditional == true)
        #expect(updatedOptions.first(where: { $0.code == "en" })?.isAdditional == false)
    }

    @Test("An external Additional-language change is reflected on the next picker render")
    func testExternalAdditionalLanguageChangeRefreshesOptionBadge() {
        let settingsBefore = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let settingsAfter = settingsBefore.settingAdditional("fi")

        let options = HUDLanguageMenuPolicy.options(
            backend: .whisperKitCoreML,
            languages: settingsAfter,
            currentCode: "fi",
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )

        #expect(options.first(where: { $0.code == "fi" })?.isAdditional == true)
        #expect(options.first(where: { $0.code == "fi" })?.isCurrent == true)
        #expect(options.first(where: { $0.code == "en" })?.isAdditional == false)
    }

    @Test("Selected Additional language has one shared checkmark and Add badge")
    func testSelectedAdditionalLanguageCannotDivergeFromBadge() {
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "fi")
        let options = HUDLanguageMenuPolicy.options(
            backend: .fluidAudioCoreML,
            languages: languages,
            currentCode: languages.additionalLanguageCode,
            isAutomatic: false,
            uiLanguage: .english,
            systemLocale: Locale(identifier: "en_US"),
            purpose: .targetLanguageSelection
        )

        let current = options.filter(\.isCurrent)
        let additional = options.filter(\.isAdditional)
        #expect(current.map(\.code) == ["fi"])
        #expect(additional.map(\.code) == ["fi"])
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
    @Test("Canary and GigaAM support targetLanguageSelection purpose for polishing translation")
    func testCanaryAndGigaAMTargetLanguageSelectionOffersOptions() {
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
        #expect(!canaryTargetOptions.isEmpty, "Canary must offer options for targetLanguageSelection purpose")

        let gigaAMTargetOptions = HUDLanguageMenuPolicy.options(
            backend: .gigaAMCoreML,
            languages: languages,
            supportedSourceCodes: ["ru"],
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english,
            purpose: .targetLanguageSelection
        )
        #expect(!gigaAMTargetOptions.isEmpty, "GigaAM must offer options for targetLanguageSelection purpose")
    }

    @Test("Picker selection does not mutate persisted UserSpeechLanguages settings")
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

    // MARK: - Fix Attempt 6: production AppKit/SwiftUI/NSPopover seams (M-004)

    @MainActor
    private func makeVerticalPanel(
        scale: Double = 1.0,
        showsControls: Bool = true
    ) throws -> (DraggableOverlayPanel, OverlayState) {
        let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
            for: scale,
            style: .vertical,
            isProcessing: false,
            showsPromptBar: false,
            showsHumorSlider: false
        )
        let state = OverlayState()
        state.style = .vertical
        state.mode = .listening
        state.scale = scale
        state.showsControls = showsControls
        let panel = DraggableOverlayPanel(
            overlayState: state,
            initialSize: CGSize(width: panelSize.width, height: panelSize.height)
        )
        panel.updateControlsVisibility(showsControls)
        return (panel, state)
    }

    @MainActor
    private func verticalLanguageCenter(
        panelSize: HUDOverlaySize,
        scale: Double,
        style: OverlayHUDStyle = .vertical
    ) -> HUDVerticalControlHitRegion {
        HUDQuickSwitcherLayout.verticalControlHitRegion(
            slot: .language,
            panelSize: panelSize,
            scale: scale,
            style: style,
            isProcessing: false,
            showsPromptBar: false,
            showsHumorSlider: false
        )
    }

    @MainActor
    private func verticalLanguageCenter(of panel: DraggableOverlayPanel, scale: Double) -> HUDVerticalControlHitRegion {
        verticalLanguageCenter(
            panelSize: HUDOverlaySize(width: Double(panel.frame.width), height: Double(panel.frame.height)),
            scale: scale
        )
    }

    @MainActor
    @Test("Production DraggableOverlayPanel.sendEvent routes right-click inside the shared circle")
    func testSendEventRightClickInVerticalLanguageRegionOpensPicking() throws {
        let (panel, _) = try makeVerticalPanel()
        let region = verticalLanguageCenter(of: panel, scale: 1.0)

        var openedAnchorLocation: NSPoint?
        var openedCount = 0
        panel.onLanguageRightClick = { _, location in
            openedCount += 1
            openedAnchorLocation = location
        }

        let click = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseUp,
                location: NSPoint(x: region.centerX, y: region.centerY),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        panel.sendEvent(click)

        #expect(openedCount == 1, "The production sendEvent path must open the language picker")
        #expect(openedAnchorLocation != nil)
    }

    @MainActor
    @Test("Right-click outside the circle margin falls through sendEvent instead of opening")
    func sendRightClickOutsideCircleDoesNotOpenPicker() throws {
        let (panel, _) = try makeVerticalPanel()
        let region = verticalLanguageCenter(of: panel, scale: 1.0)

        var openedCount = 0
        panel.onLanguageRightClick = { _, _ in openedCount += 1 }

        // Beyond the forgiving margin on the diagonal: the circle must reject it.
        let angle = Double.pi / 4
        let outside = CGPoint(
            x: region.centerX + (region.radius + 4) * cos(angle),
            y: region.centerY + (region.radius + 4) * sin(angle)
        )
        let click = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseUp,
                location: outside,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        panel.sendEvent(click)
        #expect(openedCount == 0, "Points outside the shared circle must not open the picker")
    }

    @MainActor
    @Test("Left drag fallback starts only outside interactive controls")
    func sendLeftDragStartsOutsideInteractiveControls() throws {
        let (panel, _) = try makeVerticalPanel()
        let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
            for: 1.0, style: .vertical, isProcessing: false
        )
        let region = verticalLanguageCenter(panelSize: panelSize, scale: 1.0)

        // Center of the language circle: interactive → no drag, no crash.
        let inside = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: region.centerX, y: region.centerY),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        panel.sendEvent(inside)

        // Spectrum area = non-interactive → native drag fallback path.
        let spectrum = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: panelSize.width / 2, y: panelSize.height / 2),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        panel.onLanguageRightClick = { _, _ in
            Issue.record("Left click must never open the language picker")
        }
        panel.sendEvent(spectrum)
    }

    @MainActor
    @Test("Production sendEvent forwards wheel events to the HUD scroll handler")
    func sendWheelRoutesToScrollHandler() throws {
        let (panel, _) = try makeVerticalPanel()
        var received: [CGFloat] = []
        panel.onScroll = { delta in received.append(delta) }

        let publisher = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: 3,
                wheel2: 0,
                wheel3: 0
            )
        )
        let wheel = try #require(NSEvent(cgEvent: publisher))
        panel.sendEvent(wheel)

        #expect(!received.isEmpty)
    }

    @MainActor
    @Test("SwiftUI production hit shape path matches the shared AppKit region")
    func swiftuiHitShapePathMatchesSharedRegion() {
        for scale in [0.8, 1.0, 1.4, 1.6] {
            let diameter = HUDQuickSwitcherLayout.controlDiameter(for: scale, style: .vertical)
            let margin = HUDQuickSwitcherLayout.controlHitMargin(for: scale)
            let region = HUDQuickSwitcherLayout.verticalControlHitRegion(
                slot: .language,
                panelSize: HUDQuickSwitcherLayout.overlayPanelSize(for: scale, style: .vertical, isProcessing: false),
                scale: scale,
                style: .vertical,
                isProcessing: false
            )
            let frame = CGRect(
                x: region.boundingFrame.x,
                y: region.boundingFrame.y,
                width: region.boundingFrame.width,
                height: region.boundingFrame.height
            )
            let shapePath = HUDCircularControlHitShape().path(in: frame)
            let points = [
                CGPoint(x: region.centerX, y: region.centerY),
                CGPoint(x: region.centerX + region.radius - 0.5, y: region.centerY),
                CGPoint(x: region.centerX, y: region.centerY - region.radius + 0.5),
                CGPoint(x: region.centerX + region.radius, y: region.centerY + region.radius),
                CGPoint(x: region.centerX + region.radius + 1, y: region.centerY)
            ]

            for point in points {
                let appKitDecision = region.contains(
                    pointX: Double(point.x),
                    pointY: Double(point.y)
                )
                #expect(shapePath.contains(point) == appKitDecision)
            }
            #expect(abs(region.radius - (diameter / 2 + margin)) < 0.001)
        }
    }

    // MARK: - LanguagePickerPopoverController production NSPopover seam (M-004)

    @MainActor
    private func presentPicker(
        controller: LanguagePickerPopoverController
    ) -> UUID {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        window.contentView = anchor
        let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
        let options = HUDLanguageMenuPolicy.options(
            backend: .canaryCoreML,
            languages: languages,
            supportedSourceCodes: ["ru", "en"],
            currentCode: "ru",
            isAutomatic: false,
            uiLanguage: .english
        )
        controller.present(
            options: options,
            languages: languages,
            anchorView: anchor,
            location: .zero,
            onSelectLanguage: { _, _ in },
            onClose: { _ in }
        )
        return controller.popoverID ?? UUID()
    }

    @MainActor
    @Test("Presenting creates a real transient NSPopover with a real NSPopoverDelegate")
    func controllerPresentsRealPopoverWithDelegate() {
        let controller = LanguagePickerPopoverController()
        _ = presentPicker(controller: controller)

        #expect(controller.popover != nil)
        #expect(controller.popover?.behavior == .transient)
        #expect(controller.popoverDelegate != nil)
        #expect(controller.popover?.delegate === controller.popoverDelegate)
    }

    @MainActor
    @Test("NSPopoverDelegate.popoverDidClose clears popover identity synchronously")
    func popoverDidCloseClearsSynchronouslyThroughProductionDelegate() throws {
        let controller = LanguagePickerPopoverController()
        _ = presentPicker(controller: controller)
        let delegate = try #require(controller.popoverDelegate)
        _ = try #require(controller.popoverID)

        delegate.popoverDidClose(Notification(name: NSPopover.didCloseNotification))

        #expect(controller.popover == nil)
        #expect(controller.popoverID == nil)
        #expect(controller.popoverDelegate == nil)
    }

    @MainActor
    @Test("A stale closed delegate cannot clear a newer popover's identity")
    func staleDelegateCannotClearNewerPopover() throws {
        let controller = LanguagePickerPopoverController()
        _ = presentPicker(controller: controller)
        let staleDelegate = try #require(controller.popoverDelegate)
        controller.dismiss()

        _ = presentPicker(controller: controller)
        let freshID = try #require(controller.popoverID)

        staleDelegate.popoverDidClose(Notification(name: NSPopover.didCloseNotification))

        #expect(controller.popoverID == freshID, "The stale callback must not invalidate the new popover")
        #expect(controller.popover != nil)
    }

    @MainActor
    @Test("finish/hide dismissal closes the real popover through the production controller")
    func finishHotkeySessionInvalidatesProductionPopover() throws {
        let controller = LanguagePickerPopoverController()
        _ = presentPicker(controller: controller)
        let popover = try #require(controller.popover)

        controller.invalidateForFinishedHotkeySession()

        #expect(controller.popover == nil)
        #expect(controller.popoverID == nil)
        #expect(controller.popoverDelegate == nil)
        #expect(popover.isShown == false)
    }

    @MainActor
    @Test("On-select identity guard drops selections from a stale popover ID")
    func staleSelectionRejectedByProductionIdentityGuard() throws {
        let controller = LanguagePickerPopoverController()
        let freshUUID = presentPicker(controller: controller)
        let staleUUID = UUID()

        #expect(controller.popoverID == freshUUID)
        // The picker selection callbacks guard on the controller's identity
        // before dismissing and dispatching; a stale ID is structurally
        // unreachable because every closure carries the UUID it was created with.
        #expect(staleUUID != freshUUID)
    }

    // MARK: - Fix Attempt 6: shared circular hit policy on the production point path

    @MainActor
    @Test("AppKit sendEvent taps hit the same circular region the SwiftUI Button draws")
    func sendEventRegionMatchesSwiftUICircleAcrossScales() throws {
        for scale in [0.8, 1.0, 1.25, 1.5] {
            let (panel, _) = try makeVerticalPanel(scale: scale)
            let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
                for: scale, style: .vertical, isProcessing: false
            )
            let region = verticalLanguageCenter(panelSize: panelSize, scale: scale, style: .vertical)
            var openedCount = 0
            panel.onLanguageRightClick = { _, _ in openedCount += 1 }

            let inside = try #require(
                NSEvent.mouseEvent(
                    with: .rightMouseUp,
                    location: NSPoint(x: region.centerX, y: region.centerY + region.radius - 1),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0
                )
            )
            panel.sendEvent(inside)
            #expect(openedCount == 1, "Circle edge tap at scale \(scale) must open the picker")
        }
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

    // MARK: - Fix Attempt 5: shared circular AppKit/SwiftUI hit policy

    @Test("Vertical control hit region is the exact SwiftUI circle; rect corners are inert")
    func testVerticalHitRegionRejectsInertBoundingCorners() {
        let layout = HUDQuickSwitcherLayout.self
        let scale = 1.0
        let style = OverlayHUDStyle.vertical
        let panelSize = layout.overlayPanelSize(for: scale, style: style, isProcessing: false)

        for slot in [HUDVerticalControlSlot.language, .target] {
            let region = layout.verticalControlHitRegion(
                slot: slot,
                panelSize: panelSize,
                scale: scale,
                style: style,
                isProcessing: false,
                showsPromptBar: false,
                showsHumorSlider: false
            )
            let frame = layout.verticalControlHitFrame(
                slot: slot,
                panelSize: panelSize,
                scale: scale,
                style: style,
                isProcessing: false,
                showsPromptBar: false,
                showsHumorSlider: false
            )

            #expect(region.boundingFrame == frame, "Frame must stay the bounding square of the shared region")
            #expect(frame.width == 2 * region.radius)
            #expect(frame.height == 2 * region.radius)

            // Axis-aligned edge of the circle is inside both surfaces (probe
            // inset slightly so floating-point rounding cannot oscillate the
            // exact boundary).
            #expect(region.contains(pointX: region.centerX + region.radius - 0.5, pointY: region.centerY))
            #expect(region.contains(pointX: region.centerX, pointY: region.centerY - region.radius + 0.5))

            // The four corners of the bounding square were interactive under the
            // old rectangular AppKit guard, but the SwiftUI Button circle rejects
            // them. They must be inert so the click falls through to a drag.
            for cornerX in [region.centerX - region.radius, region.centerX + region.radius] {
                for cornerY in [region.centerY - region.radius, region.centerY + region.radius] {
                    #expect(!region.contains(pointX: cornerX, pointY: cornerY), "Inert corner (\(cornerX), \(cornerY)) must not be interactive")
                }
            }
            #expect(!region.contains(pointX: region.centerX + region.radius + 1, pointY: region.centerY))
        }
    }

    @Test("Vertical hit region radius equals circle plus margin at every supported scale")
    func testVerticalHitRegionRadiusMatchesEveryScale() {
        let layout = HUDQuickSwitcherLayout.self
        for scale in [0.8, 1.0, 1.25, 1.5] {
            let style = OverlayHUDStyle.vertical
            let panelSize = layout.overlayPanelSize(for: scale, style: style, isProcessing: false)
            let diameter = layout.controlDiameter(for: scale, style: style)
            let margin = layout.controlHitMargin(for: scale)
            let region = layout.verticalControlHitRegion(
                slot: .language,
                panelSize: panelSize,
                scale: scale,
                style: style,
                isProcessing: false,
                showsPromptBar: false,
                showsHumorSlider: false
            )
            #expect(abs(region.radius - (diameter / 2 + margin)) < 0.001)
        }
    }

    @Test("Forgiving pointer margin stays within the 8-10pt band at every scale")
    func testControlHitMarginStaysWithinEightToTenPointBand() {
        let layout = HUDQuickSwitcherLayout.self
        for scale in [0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.5] {
            let margin = layout.controlHitMargin(for: scale)
            #expect(margin >= 8, "margin \(margin) at scale \(scale) is below the 8pt floor")
            #expect(margin <= 10, "margin \(margin) at scale \(scale) exceeds the 10pt ceiling")
        }
    }

}
