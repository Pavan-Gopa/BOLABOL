import AppKit
import NativeBolabolCore
import SwiftUI

@MainActor
final class HotkeySessionOverlayManager {
    enum Mode {
        case listening
        case processing

        func tint(for style: OverlayHUDStyle) -> Color {
            switch (style, self) {
            case (.capsule, .listening):
                .red
            case (.capsule, .processing):
                .green
            case (.tech, .listening):
                Color(red: 1.0, green: 0.72, blue: 0.16)
            case (.tech, .processing):
                Color(red: 0.20, green: 0.82, blue: 1.0)
            case (.vertical, _):
                .white
            }
        }
    }

    private let state = OverlayState()
    private var currentSettings = OverlayHUDSettings()
    private var panel: DraggableOverlayPanel?
    private var originChangeHandler: ((OverlayHUDOrigin) -> Void)?
    private var languageTapHandler: (() -> Void)?
    private var languageRightClickHandler: ((_ anchorView: NSView, _ locationInAnchor: NSPoint) -> Void)?
    private var targetTapHandler: (() -> Void)?
    private var scrollHandler: ((_ deltaY: CGFloat) -> Void)?

    func show(
        mode: Mode,
        settings: OverlayHUDSettings,
        languageMode: TranscriptionLanguageMode = .auto,
        hotkeyTarget: HotkeyTarget = .note,
        targetLanguageLabel: String = "E",
        activePromptSlot: PromptSlot = .default,
        promptSlotNames: [PromptSlot: String] = [:],
        humorLevel: HumorLevel = .none,
        humorSliderEnabled: Bool = false,
        humorAccessibilityLabel: String? = nil,
        promptSlotSelectedLabel: String? = nil,
        promptSlotUnselectedLabel: String? = nil,
        promptSlotSwitchHint: String? = nil,
        showsControls: Bool = false,
        languageControlEnabled: Bool = true,
        onOriginChange: ((OverlayHUDOrigin) -> Void)? = nil,
        onLanguageTap: (() -> Void)? = nil,
        onLanguageRightClick: ((_ anchorView: NSView, _ locationInAnchor: NSPoint) -> Void)? = nil,
        onTargetTap: (() -> Void)? = nil,
        onPromptSlotChange: ((PromptSlot) -> Void)? = nil,
        onHumorLevelChange: ((HumorLevel) -> Void)? = nil,
        onScroll: ((_ deltaY: CGFloat) -> Void)? = nil,
        sessionPlan: TranscriptionSessionPlan? = nil
    ) {
        let styleChanged = state.style != settings.style
        let modeChanged = state.mode != mode
        currentSettings = settings
        state.isHovered = false
        state.isVisible = true
        state.mode = mode
        state.scale = settings.scale
        state.style = settings.style
        state.capsuleOpacity = settings.capsuleOpacity
        state.languageMode = languageMode
        state.hotkeyTarget = hotkeyTarget
        state.targetLanguageLabel = targetLanguageLabel
        state.activePromptSlot = activePromptSlot
        state.promptSlotNames = promptSlotNames
        state.promptSlotChangeHandler = onPromptSlotChange
        state.humorLevel = humorLevel
        state.humorSliderEnabled = humorSliderEnabled
        if let humorAccessibilityLabel {
            state.humorAccessibilityLabel = humorAccessibilityLabel
        }
        if let promptSlotSelectedLabel {
            state.promptSlotSelectedLabel = promptSlotSelectedLabel
        }
        if let promptSlotUnselectedLabel {
            state.promptSlotUnselectedLabel = promptSlotUnselectedLabel
        }
        if let promptSlotSwitchHint {
            state.promptSlotSwitchHint = promptSlotSwitchHint
        }
        state.humorLevelChangeHandler = onHumorLevelChange
        state.languageTapHandler = onLanguageTap
        state.targetTapHandler = onTargetTap
        state.showsControls = showsControls
        state.languageControlEnabled = languageControlEnabled
        if let sessionPlan {
            apply(sessionPlan: sessionPlan, legacyLanguageControlEnabled: languageControlEnabled)
        }
        if mode == .processing || settings.style != .vertical {
            state.dragOffset = .zero
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        self.originChangeHandler = onOriginChange
        self.languageTapHandler = onLanguageTap
        self.languageRightClickHandler = onLanguageRightClick
        self.targetTapHandler = onTargetTap
        self.scrollHandler = onScroll
        panel.updateControlsVisibility(showsControls)
        panel.prepareForDisplay(
            settings: settings,
            restoreStoredOrigin: styleChanged,
            animated: modeChanged && !styleChanged
        )
        panel.orderFrontRegardless()
    }

    func update(
        mode: Mode? = nil,
        spectrumBands: [Float]? = nil,
        settings: OverlayHUDSettings? = nil,
        languageMode: TranscriptionLanguageMode? = nil,
        hotkeyTarget: HotkeyTarget? = nil,
        targetLanguageLabel: String? = nil,
        activePromptSlot: PromptSlot? = nil,
        promptSlotNames: [PromptSlot: String]? = nil,
        humorLevel: HumorLevel? = nil,
        humorSliderEnabled: Bool? = nil,
        showsControls: Bool? = nil,
        languageControlEnabled: Bool? = nil,
        sessionPlan: TranscriptionSessionPlan? = nil
    ) {
        if let mode {
            let modeChanged = state.mode != mode
            state.mode = mode
            if mode == .processing {
                state.dragOffset = .zero
            }
            if modeChanged {
                panel?.updateLayout(
                    settings: currentSettings,
                    restoreStoredOrigin: false,
                    animated: true
                )
            }
        }
        if let spectrumBands, !spectrumBands.isEmpty {
            state.spectrumBands = spectrumBands
        }
        if let settings {
            let styleChanged = state.style != settings.style
            currentSettings = settings
            state.scale = settings.scale
            state.style = settings.style
            state.capsuleOpacity = settings.capsuleOpacity
            panel?.updateLayout(
                settings: settings,
                restoreStoredOrigin: styleChanged
            )
        }
        if let languageMode {
            state.languageMode = languageMode
        }
        var shouldRefreshLayout = false
        if let hotkeyTarget {
            state.hotkeyTarget = hotkeyTarget
            shouldRefreshLayout = true
        }
        if let targetLanguageLabel {
            state.targetLanguageLabel = targetLanguageLabel
        }
        if let activePromptSlot {
            state.activePromptSlot = activePromptSlot
        }
        if let promptSlotNames {
            state.promptSlotNames = promptSlotNames
        }
        if let humorLevel {
            state.humorLevel = humorLevel
        }
        if let humorSliderEnabled {
            state.humorSliderEnabled = humorSliderEnabled
            shouldRefreshLayout = true
        }
        if let showsControls {
            state.showsControls = showsControls
            panel?.updateControlsVisibility(showsControls)
            shouldRefreshLayout = true
        }
        if let languageControlEnabled {
            state.languageControlEnabled = languageControlEnabled
        }
        if let sessionPlan {
            apply(
                sessionPlan: sessionPlan,
                legacyLanguageControlEnabled: languageControlEnabled ?? state.languageControlEnabled
            )
        }
        if shouldRefreshLayout {
            panel?.updateLayout(
                settings: currentSettings,
                restoreStoredOrigin: false,
                animated: true
            )
        }
    }

    func hide() {
        state.isVisible = false
        state.isHovered = false
        state.dragOffset = .zero
        panel?.invalidatePendingLayoutCallbacks()
        panel?.orderOut(nil)
    }

    func playCue(_ cue: AudioCuePlayer.Cue, settings: OverlayHUDSettings) {
        AudioCuePlayer.shared.play(cue, settings: settings)
    }

    func currentHUDFrame() -> NSRect? {
        guard state.isVisible, let panel else { return nil }
        return panel.frame
    }

    private func apply(
        sessionPlan: TranscriptionSessionPlan,
        legacyLanguageControlEnabled: Bool
    ) {
        state.languageMode = sessionPlan.languageMode
        state.targetLanguageLabel = sessionPlan.hudLanguageLabel
        state.languageControlEnabled = sessionPlan.backend == .canaryCoreML
            || sessionPlan.backend == .gigaAMCoreML
            ? sessionPlan.languageControlEnabled
            : legacyLanguageControlEnabled
    }

    private func makePanel() -> DraggableOverlayPanel {
        let panel = DraggableOverlayPanel(
            overlayState: state,
            initialSize: OverlayHUDLayout.panelSize(
                for: state.scale,
                style: state.style,
                mode: state.mode,
                showsPromptBar: state.showsPromptBar,
                showsHumorSlider: state.showsHumorControl
            )
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.originDidChange = { [weak self] origin in
            self?.originChangeHandler?(origin)
        }
        panel.onScroll = { [weak self] delta in
            self?.scrollHandler?(delta)
        }
        panel.onLanguageRightClick = { [weak self] anchorView, location in
            self?.languageRightClickHandler?(anchorView, location)
        }
        panel.updateControlsVisibility(state.showsControls)
        return panel
    }
}

@MainActor
private final class OverlayState: ObservableObject {
    @Published var mode: HotkeySessionOverlayManager.Mode = .listening
    @Published var spectrumBands: [Float] = Array(repeating: 0.04, count: 40)
    @Published var scale: Double = 1
    @Published var capsuleOpacity: Double = 0.32
    @Published var style: OverlayHUDStyle = .capsule
    @Published var languageMode: TranscriptionLanguageMode = .auto
    @Published var hotkeyTarget: HotkeyTarget = .note
    @Published var targetLanguageLabel: String = "E"
    @Published var activePromptSlot: PromptSlot = .default
    @Published var promptSlotNames: [PromptSlot: String] = [:]
    @Published var humorLevel: HumorLevel = .none
    @Published var humorSliderEnabled = false
    @Published var humorAccessibilityLabel = ""
    @Published var promptSlotSelectedLabel = ""
    @Published var promptSlotUnselectedLabel = ""
    @Published var promptSlotSwitchHint = ""
    @Published var showsControls: Bool = false
    @Published var languageControlEnabled: Bool = true
    @Published var isVisible: Bool = false
    @Published var dragOffset: CGSize = .zero
    @Published var isHovered: Bool = false
    var languageTapHandler: (() -> Void)?
    var targetTapHandler: (() -> Void)?
    var promptSlotChangeHandler: ((PromptSlot) -> Void)?
    var humorLevelChangeHandler: ((HumorLevel) -> Void)?

    var showsPromptBar: Bool {
        showsControls && mode == .listening && (hotkeyTarget == .note || hotkeyTarget == .x2)
    }

    var showsHumorControl: Bool {
        showsControls && mode == .listening && hotkeyTarget == .x2 && humorSliderEnabled
    }
}

private enum OverlayHUDLayout {
    static let baseWidth: CGFloat = 142
    static let baseHeight: CGFloat = 42
    static let shadowPad: CGFloat = 6
    static let capsuleHPad: CGFloat = 3
    static let controlButtonDiameter: CGFloat = 24
    static let buttonSpectrumGap: CGFloat = 6
    static let classicButtonSpectrumGap: CGFloat = 2.5
    static let techButtonSpectrumGap: CGFloat = 3
    static let verticalButtonSpectrumGap: CGFloat = 3
    static let humorSliderBaseWidth: CGFloat = 90
    static let humorSliderVerticalWidth: CGFloat = 42

    static let minScale: Double = 0.8
    static let maxScale: Double = 1.6

    static func promptBarHeight(for scale: Double) -> CGFloat {
        18 * visualScale(for: scale)
    }

    static func promptBarSpacing(for scale: Double) -> CGFloat {
        4 * visualScale(for: scale)
    }

    static func humorControlHeight(for scale: Double) -> CGFloat {
        24 * visualScale(for: scale)
    }

    static func humorControlSpacing(for scale: Double) -> CGFloat {
        4 * visualScale(for: scale)
    }
    static func controlHitMargin(for scale: Double) -> CGFloat {
        CGFloat(HUDQuickSwitcherLayout.controlHitMargin(for: scale))
    }

    static func humorSliderWidth(for scale: Double, style: OverlayHUDStyle) -> CGFloat {
        switch style {
        case .vertical:
            humorSliderVerticalWidth * visualScale(for: scale)
        case .capsule, .tech:
            humorSliderBaseWidth * visualScale(for: scale)
        }
    }

    static func panelSize(
        for scale: Double,
        style: OverlayHUDStyle,
        mode: HotkeySessionOverlayManager.Mode,
        showsPromptBar: Bool = false,
        showsHumorSlider: Bool = false
    ) -> CGSize {
        let metrics = HUDQuickSwitcherLayout.overlayPanelSize(
            for: scale,
            style: style,
            isProcessing: mode == .processing,
            showsPromptBar: showsPromptBar,
            showsHumorSlider: showsHumorSlider
        )
        return CGSize(width: CGFloat(metrics.width), height: CGFloat(metrics.height))
    }

    static func visualScale(for scale: Double) -> CGFloat {
        if scale <= 1 {
            return CGFloat(0.88 + 0.12 * normalized(scale, from: minScale, to: 1))
        }
        return CGFloat(1 + 0.12 * smoothStep(normalized(scale, from: 1, to: maxScale)))
    }

    static func spectrumBarCount(for scale: Double, style: OverlayHUDStyle) -> Int {
        switch style {
        case .capsule:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((6 * progress).rounded())
        case .tech:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((4 * progress).rounded())
        case .vertical:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((2 * progress).rounded())
        }
    }

    static func controlDiameter(for scale: Double, style: OverlayHUDStyle) -> CGFloat {
        guard style == .capsule else {
            return controlButtonDiameter * visualScale(for: scale)
        }

        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 23.5 + 1.5 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 25 + 3 * progress
    }

    static func classicProcessingSpectrumWidth(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 44 + 4 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 48 + 28 * progress
    }

    static func techSpectrumWidth(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 38 + 4 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 42 + 30 * progress
    }

    static func verticalSpectrumHeight(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 34 + 6 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 40 + 18 * progress
    }

    private static func normalized(_ value: Double, from lower: Double, to upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }

    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

private final class DraggableOverlayPanel: NSPanel {
    var originDidChange: ((OverlayHUDOrigin) -> Void)?
    var onLanguageRightClick: ((_ anchorView: NSView, _ locationInAnchor: NSPoint) -> Void)?
    var onScroll: ((_ deltaY: CGFloat) -> Void)? {
        get { rootView.onScroll }
        set { rootView.onScroll = newValue }
    }

    private let overlayState: OverlayState
    private let rootView: OverlayRootView
    private var hasPlacedFrame = false
    private var layoutGeneration = 0
    private var laidOutCapsuleScreenFrame: CGRect?
    private var isApplyingLayoutFrame = false

    init(overlayState: OverlayState, initialSize: CGSize) {
        self.overlayState = overlayState
        self.rootView = OverlayRootView(state: overlayState)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isMovableByWindowBackground = true
        contentView = rootView
        rootView.translatesAutoresizingMaskIntoConstraints = false
        setContentSize(initialSize)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateTrackedCapsuleAfterExternalMove()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        let visibleFrame = screenVisibleFrame()
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return }
        let currentPanelFrame = frame
        let clampedOrigin = clamp(
            origin: currentPanelFrame.origin,
            size: currentPanelFrame.size,
            visibleFrame: visibleFrame
        )
        setFrameOrigin(clampedOrigin)
        updateTrackedCapsuleAfterExternalMove()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateTrackedCapsuleAfterExternalMove()
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        updateTrackedCapsuleAfterExternalMove()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseUp,
           overlayState.mode == .listening,
           overlayState.showsControls,
           languageControlHitRect().contains(contentPoint(for: event)) {
            guard let anchorView = contentView else { return }
            let location = anchorView.convert(event.locationInWindow, from: nil)
            onLanguageRightClick?(anchorView, location)
            return
        }

        // Left mouse down outside interactive control buttons initiates native window drag
        if event.type == .leftMouseDown,
           overlayState.mode == .listening,
           !isClickInInteractiveControl(contentPoint(for: event)) {
            perform(NSSelectorFromString("performWindowDragWithEvent:"), with: event)
            updateTrackedCapsuleAfterExternalMove()
            return
        }

        // Capture the wheel before SwiftUI hit-testing can route it to an inner
        // control instead of the HUD's scroll handler.
        if event.type == .scrollWheel {
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 3.0
                : ProviderQuickSwitcherModel.nonPreciseHUDScrollDelta(event.scrollingDeltaY)
            if abs(delta) > 0.001 {
                onScroll?(delta)
                return
            }
        }
        super.sendEvent(event)
    }

    func updateControlsVisibility(_ visible: Bool) {
        rootView.showsControls = visible
    }

    func invalidatePendingLayoutCallbacks() {
        layoutGeneration += 1
        hasPlacedFrame = false
        laidOutCapsuleScreenFrame = nil
    }

    func prepareForDisplay(
        settings: OverlayHUDSettings,
        restoreStoredOrigin: Bool,
        animated: Bool
    ) {
        overlayState.capsuleOpacity = settings.capsuleOpacity
        updateLayout(
            settings: settings,
            restoreStoredOrigin: restoreStoredOrigin,
            animated: animated
        )
        guard !hasPlacedFrame else { return }

        let visibleFrame = screenVisibleFrame()
        let baseSize = OverlayHUDLayout.panelSize(
            for: settings.scale,
            style: settings.style,
            mode: overlayState.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )
        let origin: CGPoint
        if let storedOrigin = settings.origin(for: settings.style) {
            let humorOffset = overlayState.showsHumorControl
                ? (OverlayHUDLayout.humorControlHeight(for: settings.scale) + OverlayHUDLayout.humorControlSpacing(for: settings.scale))
                : 0
            let newOriginX = CGFloat(storedOrigin.x) + baseSize.width / 2 - frame.width / 2
            let newOriginY = CGFloat(storedOrigin.y) - humorOffset
            origin = clamp(
                origin: CGPoint(x: newOriginX, y: newOriginY),
                size: frame.size,
                visibleFrame: visibleFrame
            )
        } else {
            origin = bottomCenterOrigin(for: frame.size, visibleFrame: visibleFrame)
        }
        setFrameOrigin(origin)
        hasPlacedFrame = true
        laidOutCapsuleScreenFrame = capsuleScreenFrame(for: frame)
    }

    func updateLayout(
        settings: OverlayHUDSettings,
        restoreStoredOrigin: Bool,
        animated _: Bool = false
    ) {
        layoutGeneration += 1
        let newSize = OverlayHUDLayout.panelSize(
            for: settings.scale,
            style: settings.style,
            mode: overlayState.mode,
            showsPromptBar: overlayState.showsPromptBar,
            showsHumorSlider: overlayState.showsHumorControl
        )
        let previousFrame = frame
        guard hasPlacedFrame else {
            setContentSize(newSize)
            return
        }

        let visibleFrame = screenVisibleFrame()
        let baseSize = OverlayHUDLayout.panelSize(
            for: settings.scale,
            style: settings.style,
            mode: overlayState.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )

        let newOrigin: CGPoint
        if (restoreStoredOrigin || laidOutCapsuleScreenFrame == nil), let storedOrigin = settings.origin(for: settings.style) {
            let humorOffset = overlayState.showsHumorControl
                ? (OverlayHUDLayout.humorControlHeight(for: settings.scale) + OverlayHUDLayout.humorControlSpacing(for: settings.scale))
                : 0
            let topAlignedOrigin = CGPoint(
                x: CGFloat(storedOrigin.x) + baseSize.width / 2 - newSize.width / 2,
                y: CGFloat(storedOrigin.y) - humorOffset
            )
            newOrigin = clamp(
                origin: topAlignedOrigin,
                size: newSize,
                visibleFrame: visibleFrame
            )
        } else if let previousCapsuleFrame = laidOutCapsuleScreenFrame {
            let newPanelSize = HUDOverlaySize(
                width: Double(newSize.width),
                height: Double(newSize.height)
            )
            let newLocalCapsuleFrame = HUDQuickSwitcherLayout.mainCapsuleFrame(
                panelSize: newPanelSize,
                scale: settings.scale,
                style: settings.style,
                isProcessing: overlayState.mode == .processing,
                showsHumorSlider: overlayState.showsHumorControl
            )
            let anchored = HUDQuickSwitcherLayout.anchoredPanelFrame(
                previousCapsuleScreenFrame: HUDOverlayFrame(
                    x: Double(previousCapsuleFrame.origin.x),
                    y: Double(previousCapsuleFrame.origin.y),
                    width: Double(previousCapsuleFrame.width),
                    height: Double(previousCapsuleFrame.height)
                ),
                newPanelSize: newPanelSize,
                newLocalCapsuleFrame: newLocalCapsuleFrame
            )
            newOrigin = clamp(
                origin: CGPoint(x: anchored.x, y: anchored.y),
                size: newSize,
                visibleFrame: visibleFrame
            )
        } else {
            newOrigin = CGPoint(
                x: previousFrame.midX - newSize.width / 2,
                y: previousFrame.midY - newSize.height / 2
            )
        }

        let newFrame = CGRect(origin: newOrigin, size: newSize)
        // Accessory opacity is animated by SwiftUI. The transparent AppKit
        // panel must move synchronously, otherwise AppKit frame animation and
        // SwiftUI accessory reflow move the capsule twice.
        applyLayoutFrame(newFrame)
        persistCurrentOrigin()
    }

    private func applyLayoutFrame(_ newFrame: CGRect) {
        isApplyingLayoutFrame = true
        setFrame(newFrame, display: true)
        isApplyingLayoutFrame = false
        laidOutCapsuleScreenFrame = capsuleScreenFrame(for: frame)
    }

    private func updateTrackedCapsuleAfterExternalMove() {
        guard hasPlacedFrame, !isApplyingLayoutFrame else { return }
        laidOutCapsuleScreenFrame = capsuleScreenFrame(for: frame)
        persistCurrentOrigin()
    }

    private func persistCurrentOrigin() {
        let baseSize = OverlayHUDLayout.panelSize(
            for: overlayState.scale,
            style: overlayState.style,
            mode: overlayState.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )
        let humorOffset = overlayState.showsHumorControl
            ? (OverlayHUDLayout.humorControlHeight(for: overlayState.scale) + OverlayHUDLayout.humorControlSpacing(for: overlayState.scale))
            : 0
        let baseOriginY = frame.origin.y + humorOffset
        let baseOriginX = frame.midX - baseSize.width / 2
        originDidChange?(OverlayHUDOrigin(x: Double(baseOriginX), y: Double(baseOriginY)))
    }

    private func contentPoint(for event: NSEvent) -> NSPoint {
        contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
    }

    private func capsuleScreenFrame(for panelFrame: CGRect) -> CGRect {
        let panelSize = HUDOverlaySize(
            width: Double(panelFrame.width),
            height: Double(panelFrame.height)
        )
        let localFrame = HUDQuickSwitcherLayout.mainCapsuleFrame(
            panelSize: panelSize,
            scale: overlayState.scale,
            style: overlayState.style,
            isProcessing: overlayState.mode == .processing,
            showsHumorSlider: overlayState.showsHumorControl
        )
        let screenFrame = HUDQuickSwitcherLayout.screenCapsuleFrame(
            panelFrame: HUDOverlayFrame(
                x: Double(panelFrame.origin.x),
                y: Double(panelFrame.origin.y),
                width: Double(panelFrame.width),
                height: Double(panelFrame.height)
            ),
            localCapsuleFrame: localFrame
        )
        return CGRect(
            x: screenFrame.x,
            y: screenFrame.y,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    private func languageControlHitRect() -> CGRect {
        let panelSize = frame.size
        let visualScale = OverlayHUDLayout.visualScale(for: overlayState.scale)
        let shadowInset = OverlayHUDLayout.shadowPad * visualScale
        let humorOffset = overlayState.showsHumorControl
            ? OverlayHUDLayout.humorControlSpacing(for: overlayState.scale)
                + OverlayHUDLayout.humorControlHeight(for: overlayState.scale)
            : 0
        if overlayState.style == .vertical {
            let shared = HUDQuickSwitcherLayout.verticalControlHitFrame(
                slot: .language,
                panelSize: HUDOverlaySize(width: panelSize.width, height: panelSize.height),
                scale: overlayState.scale,
                style: overlayState.style,
                isProcessing: overlayState.mode == .processing,
                showsPromptBar: false,
                showsHumorSlider: overlayState.showsHumorControl
            )
            return CGRect(
                x: shared.x,
                y: shared.y,
                width: shared.width,
                height: shared.height
            )
        }
        let pillSize = OverlayHUDLayout.panelSize(
            for: overlayState.scale,
            style: overlayState.style,
            mode: overlayState.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )
        let pillOriginX = (panelSize.width - pillSize.width) / 2
        let pillBottom = shadowInset + humorOffset
        let controlDiameter = OverlayHUDLayout.controlDiameter(
            for: overlayState.scale,
            style: overlayState.style
        )
        return CGRect(
            x: pillOriginX - 4 * visualScale,
            y: pillBottom - 4 * visualScale,
            width: controlDiameter + 12 * visualScale,
            height: controlDiameter + 8 * visualScale
        )
    }

    private func targetControlHitRect() -> CGRect {
        let panelSize = frame.size
        let visualScale = OverlayHUDLayout.visualScale(for: overlayState.scale)
        let shadowInset = OverlayHUDLayout.shadowPad * visualScale
        let humorOffset = overlayState.showsHumorControl
            ? OverlayHUDLayout.humorControlSpacing(for: overlayState.scale)
                + OverlayHUDLayout.humorControlHeight(for: overlayState.scale)
            : 0
        if overlayState.style == .vertical {
            let shared = HUDQuickSwitcherLayout.verticalControlHitFrame(
                slot: .target,
                panelSize: HUDOverlaySize(width: panelSize.width, height: panelSize.height),
                scale: overlayState.scale,
                style: overlayState.style,
                isProcessing: overlayState.mode == .processing,
                showsPromptBar: false,
                showsHumorSlider: overlayState.showsHumorControl
            )
            return CGRect(
                x: shared.x,
                y: shared.y,
                width: shared.width,
                height: shared.height
            )
        }
        let pillSize = OverlayHUDLayout.panelSize(
            for: overlayState.scale,
            style: overlayState.style,
            mode: overlayState.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )
        let pillOriginX = (panelSize.width - pillSize.width) / 2
        let pillBottom = shadowInset + humorOffset
        let controlDiameter = OverlayHUDLayout.controlDiameter(
            for: overlayState.scale,
            style: overlayState.style
        )
        let targetX = pillOriginX + pillSize.width - controlDiameter - shadowInset
        return CGRect(
            x: targetX - 4 * visualScale,
            y: pillBottom - 4 * visualScale,
            width: controlDiameter + 12 * visualScale,
            height: controlDiameter + 8 * visualScale
        )
    }

    private func promptBarHitRect() -> CGRect {
        let panelSize = frame.size
        let visualScale = OverlayHUDLayout.visualScale(for: overlayState.scale)
        let shadowInset = OverlayHUDLayout.shadowPad * visualScale
        let barHeight = OverlayHUDLayout.promptBarHeight(for: overlayState.scale)
        let bottomY = panelSize.height - shadowInset - barHeight - 4 * visualScale
        return CGRect(
            x: 0,
            y: bottomY,
            width: panelSize.width,
            height: barHeight + 8 * visualScale
        )
    }

    private func humorSliderHitRect() -> CGRect {
        let panelSize = frame.size
        let visualScale = OverlayHUDLayout.visualScale(for: overlayState.scale)
        let shadowInset = OverlayHUDLayout.shadowPad * visualScale
        let sliderHeight = OverlayHUDLayout.humorControlHeight(for: overlayState.scale)
        let sliderWidth = OverlayHUDLayout.humorSliderWidth(for: overlayState.scale, style: overlayState.style) + 24 * visualScale
        let originX = (panelSize.width - sliderWidth) / 2
        return CGRect(
            x: originX,
            y: shadowInset - 4 * visualScale,
            width: sliderWidth,
            height: sliderHeight + 8 * visualScale
        )
    }

    private func isClickInInteractiveControl(_ point: NSPoint) -> Bool {
        if overlayState.showsControls && overlayState.languageControlEnabled && languageControlHitRect().contains(point) {
            return true
        }
        if overlayState.showsControls && targetControlHitRect().contains(point) {
            return true
        }
        if overlayState.showsPromptBar && overlayState.isHovered && promptBarHitRect().contains(point) {
            return true
        }
        if overlayState.showsHumorControl && overlayState.isHovered && humorSliderHitRect().contains(point) {
            return true
        }
        return false
    }

    private func screenVisibleFrame() -> CGRect {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }
}

private final class HUDHostingView: NSHostingView<HotkeySessionOverlayView> {
    var onScroll: ((_ deltaY: CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * 3.0
            : ProviderQuickSwitcherModel.nonPreciseHUDScrollDelta(event.scrollingDeltaY)
        if abs(delta) > 0.001 {
            onScroll?(delta)
        }
        super.scrollWheel(with: event)
    }
}

private final class OverlayRootView: NSView {
    var onScroll: ((_ deltaY: CGFloat) -> Void)? {
        get { hostingView.onScroll }
        set { hostingView.onScroll = newValue }
    }
    var showsControls: Bool = false

    private let state: OverlayState
    private let hostingView: HUDHostingView
    private var trackingArea: NSTrackingArea?

    init(state: OverlayState) {
        self.state = state
        self.hostingView = HUDHostingView(rootView: HotkeySessionOverlayView(state: state))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        state.isHovered = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if !state.isHovered {
            state.isHovered = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) {
            state.isHovered = false
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * 3.0
            : ProviderQuickSwitcherModel.nonPreciseHUDScrollDelta(event.scrollingDeltaY)
        if abs(delta) > 0.001 {
            onScroll?(delta)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct HotkeySessionOverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        hudContent
            .frame(
                width: max(1, panelSize.width - shadowInset * 2),
                height: max(1, panelSize.height - shadowInset * 2)
            )
            .padding(shadowInset)
            .frame(width: panelSize.width, height: panelSize.height)
    }

    private var hudContent: some View {
        ZStack {
            promptBar
                .frame(
                    width: innerContentSize.width,
                    height: OverlayHUDLayout.promptBarHeight(for: state.scale)
                )
                .position(
                    x: innerContentSize.width / 2,
                    y: promptBarCenterY
                )

            hudPill
                .position(
                    x: innerContentSize.width / 2,
                    y: capsuleCenterY
                )

            humorSlider
                .position(
                    x: innerContentSize.width / 2,
                    y: humorSliderCenterY
                )
        }
        .frame(
            width: innerContentSize.width,
            height: innerContentSize.height
        )
        .animation(.easeInOut(duration: 0.24), value: state.style)
        .animation(.easeInOut(duration: 0.2), value: state.mode)
        .animation(
            .spring(response: 0.36, dampingFraction: 0.52, blendDuration: 0.04),
            value: state.dragOffset
        )
    }

    private var promptBar: some View {
        HStack(spacing: 3 * visualScale) {
            ForEach(PromptSlot.allCases) { slot in
                promptSlotButton(slot: slot)
            }
        }
        .frame(height: OverlayHUDLayout.promptBarHeight(for: state.scale))
        .opacity(state.showsPromptBar && state.isHovered ? 0.95 : 0.0)
        .allowsHitTesting(HUDInteractionPolicy.allowsHitTesting(isVisible: state.showsPromptBar && state.isHovered))
        .accessibilityHidden(HUDInteractionPolicy.isAccessibilityHidden(isVisible: state.showsPromptBar && state.isHovered))
        .animation(.easeInOut(duration: 0.2), value: state.isHovered)
        .animation(.easeInOut(duration: 0.2), value: state.showsPromptBar)
    }

    private func promptSlotButton(slot: PromptSlot) -> some View {
        let isSelected = state.activePromptSlot == slot
        let slotName = state.promptSlotNames[slot] ?? slot.title
        let accessibility = HUDAccessibilityMetadataPolicy.promptSlot(
            name: slotName,
            isSelected: isSelected,
            selectedState: state.promptSlotSelectedLabel,
            unselectedState: state.promptSlotUnselectedLabel,
            switchHint: state.promptSlotSwitchHint
        )

        return Button {
            state.activePromptSlot = slot
            state.promptSlotChangeHandler?(slot)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4 * visualScale, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 4 * visualScale, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.25), lineWidth: 1 * visualScale)
                Text(slot.shortTitle)
                    .font(.system(size: 11 * visualScale, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
            }
            .frame(width: 17 * visualScale, height: 17 * visualScale)
        }
        .buttonStyle(.plain)
        .help(slotName)
        .accessibilityLabel(Text(accessibility.label))
        .accessibilityValue(Text(accessibility.value))
        .accessibilityHint(Text(accessibility.hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(accessibility.isSelected ? .isSelected : [])
    }

    private var hudPill: some View {
        layoutContent
            .padding(contentPadding)
            .frame(
                width: max(1, pillSize.width - shadowInset * 2),
                height: max(1, pillSize.height - shadowInset * 2)
            )
            .background {
                if state.style != .vertical {
                    ZStack {
                        containerShape
                            .fill(.ultraThinMaterial)
                        containerShape
                            .fill(surfaceGradient)
                        containerShape
                            .fill(
                                RadialGradient(
                                    colors: [tint.opacity(0.16), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 84 * visualScale
                                )
                            )
                    }
                    .opacity(state.capsuleOpacity)
                }
            }
            .overlay {
                if state.style != .vertical {
                    containerShape
                        .stroke(.white.opacity(0.24), lineWidth: 1.0 * visualScale)
                }
            }
            .overlay {
                if state.style != .vertical {
                    containerShape
                        .stroke(.black.opacity(0.08), lineWidth: 0.7 * visualScale)
                        .padding(2 * visualScale)
                }
            }
            .shadow(
                color: state.style == .vertical
                    ? .clear
                    : tint.opacity(state.style == .capsule ? 0.08 : 0.14),
                radius: 12 * visualScale,
                x: 0,
                y: 4 * visualScale
            )
            .shadow(
                color: state.style == .vertical ? .clear : .black.opacity(0.18),
                radius: 14 * visualScale,
                x: 0,
                y: 6
            )
            .animation(.easeInOut(duration: 0.24), value: state.style)
            .animation(.easeInOut(duration: 0.2), value: state.mode)
            .animation(
                .spring(response: 0.36, dampingFraction: 0.52, blendDuration: 0.04),
                value: state.dragOffset
            )
    }

    private var humorSlider: some View {
        let accessibility = HUDAccessibilityMetadataPolicy.humorSlider(
            label: state.humorAccessibilityLabel,
            level: state.humorLevel
        )
        return humorSliderContainer
            .opacity(state.showsHumorControl && state.isHovered ? 0.95 : 0.0)
            .allowsHitTesting(HUDInteractionPolicy.allowsHitTesting(isVisible: state.showsHumorControl && state.isHovered))
            .accessibilityHidden(HUDInteractionPolicy.isAccessibilityHidden(isVisible: state.showsHumorControl && state.isHovered))
            .animation(.easeInOut(duration: 0.2), value: state.isHovered)
            .animation(.easeInOut(duration: 0.2), value: state.showsHumorControl)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibility.label))
            .accessibilityValue(Text(accessibility.value))
            .accessibilityAdjustableAction { direction in
                adjustHumorLevel(direction)
            }
    }

    private var humorSliderContainer: some View {
        humorSliderVisual
            .padding(.horizontal, 6 * visualScale)
            .padding(.vertical, 2 * visualScale)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.50))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75 * visualScale)
            }
            .frame(
                width: OverlayHUDLayout.humorSliderWidth(for: state.scale, style: state.style) + 12 * visualScale,
                height: OverlayHUDLayout.humorControlHeight(for: state.scale)
            )
    }

    private func adjustHumorLevel(_ direction: AccessibilityAdjustmentDirection) {
        let step = 20
        let nextValue: Int
        if direction == .increment {
            nextValue = state.humorLevel.rawValue + step
        } else if direction == .decrement {
            nextValue = state.humorLevel.rawValue - step
        } else {
            return
        }
        let nextLevel = HumorLevel.nearest(Double(nextValue))
        let currentLevel = state.humorLevel
        guard nextLevel.rawValue != currentLevel.rawValue else { return }
        state.humorLevel = nextLevel
        state.humorLevelChangeHandler?(nextLevel)
    }

    private var humorSliderVisual: some View {
        VStack(spacing: 1 * visualScale) {
            Slider(value: humorLevelBinding, in: 0...100, step: 20)
                .labelsHidden()
                .controlSize(.mini)
                .tint(tint.opacity(0.85))
                .frame(
                    width: OverlayHUDLayout.humorSliderWidth(for: state.scale, style: state.style),
                    height: 12 * visualScale
                )

            humorSliderMarks
            .frame(width: OverlayHUDLayout.humorSliderWidth(for: state.scale, style: state.style))
        }
    }

    private var humorSliderMarks: some View {
        HStack(spacing: 0) {
            ForEach(HumorLevel.allCases) { level in
                Rectangle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 1, height: 3.0 * visualScale)
                if level != .standUp {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var humorLevelBinding: Binding<Double> {
        Binding(
            get: { Double(state.humorLevel.rawValue) },
            set: { rawValue in
                let nextLevel = HumorLevel.nearest(rawValue)
                guard nextLevel != state.humorLevel else { return }
                state.humorLevel = nextLevel
                state.humorLevelChangeHandler?(nextLevel)
            }
        )
    }

    @ViewBuilder
    private var layoutContent: some View {
        switch state.style {
        case .capsule:
            if state.mode == .processing {
                classicSpectrum(barCount: classicProcessingBarCount)
                    .frame(
                        width: OverlayHUDLayout.classicProcessingSpectrumWidth(
                            for: state.scale
                        )
                    )
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: OverlayHUDLayout.classicButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: languageButtonLabel,
                        isActive: languageButtonIsActive,
                        isEnabled: state.languageControlEnabled,
                        action: {
                            guard state.languageControlEnabled else { return }
                            state.languageTapHandler?()
                        }
                    )

                    classicSpectrum(barCount: spectrumBarCount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw,
                        action: {
                            state.targetTapHandler?()
                        }
                    )
                }
            }
        case .tech:
            if state.mode == .processing {
                techSpectrum
                    .frame(width: OverlayHUDLayout.techSpectrumWidth(for: state.scale))
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: OverlayHUDLayout.techButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: languageButtonLabel,
                        isActive: languageButtonIsActive,
                        isEnabled: state.languageControlEnabled,
                        action: {
                            guard state.languageControlEnabled else { return }
                            state.languageTapHandler?()
                        }
                    )

                    techSpectrum
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw,
                        action: {
                            state.targetTapHandler?()
                        }
                    )
                }
            }
        case .vertical:
            if state.mode == .processing {
                verticalSpectrum
                    .frame(height: OverlayHUDLayout.verticalSpectrumHeight(for: state.scale))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: OverlayHUDLayout.verticalButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: languageButtonLabel,
                        isActive: languageButtonIsActive,
                        isEnabled: state.languageControlEnabled,
                        action: {
                            guard state.languageControlEnabled else { return }
                            state.languageTapHandler?()
                        }
                    )

                    verticalSpectrum
                        .frame(height: OverlayHUDLayout.verticalSpectrumHeight(for: state.scale))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(y: verticalDragStretch, anchor: .top)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw,
                        action: {
                            state.targetTapHandler?()
                        }
                    )
                    .offset(
                        x: state.dragOffset.width,
                        y: state.dragOffset.height
                    )
                }
            }
        }
    }

    private var languageButtonLabel: String {
        if state.languageMode == .unavailable {
            return "!"
        }
        return state.languageMode == .auto ? "A" : state.targetLanguageLabel
    }

    private var languageButtonIsActive: Bool {
        switch state.languageMode {
        case .auto, .unavailable:
            false
        case .target, .switchable, .fixed:
            true
        }
    }

    private var containerShape: AnyShape {
        switch state.style {
        case .capsule:
            AnyShape(Capsule(style: .continuous))
        case .tech:
            AnyShape(
                RoundedRectangle(
                    cornerRadius: 11 * visualScale,
                    style: .continuous
                )
            )
        case .vertical:
            AnyShape(Circle())
        }
    }

    private var surfaceGradient: LinearGradient {
        let colors: [Color]
        switch state.style {
        case .capsule:
            colors = [
                .white.opacity(0.16),
                .white.opacity(0.035),
                .black.opacity(0.04),
            ]
        case .tech:
            colors = [
                tint.opacity(0.12),
                .black.opacity(0.08),
                .white.opacity(0.05),
            ]
        case .vertical:
            colors = [
                .white.opacity(0.14),
                .white.opacity(0.025),
                .black.opacity(0.075),
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contentPadding: EdgeInsets {
        switch state.style {
        case .capsule:
            EdgeInsets(
                top: 3.5 * visualScale,
                leading: 4 * visualScale,
                bottom: 3.5 * visualScale,
                trailing: 4 * visualScale
            )
        case .tech:
            EdgeInsets(
                top: 4 * visualScale,
                leading: 5 * visualScale,
                bottom: 4 * visualScale,
                trailing: 5 * visualScale
            )
        case .vertical:
            EdgeInsets(
                top: 4 * visualScale,
                leading: 4 * visualScale,
                bottom: 4 * visualScale,
                trailing: 4 * visualScale
            )
        }
    }

    private var visualScale: CGFloat {
        OverlayHUDLayout.visualScale(for: state.scale)
    }

    private var panelSize: CGSize {
        OverlayHUDLayout.panelSize(
            for: state.scale,
            style: state.style,
            mode: state.mode,
            showsPromptBar: state.showsPromptBar,
            showsHumorSlider: state.showsHumorControl
        )
    }

    private var pillSize: CGSize {
        OverlayHUDLayout.panelSize(
            for: state.scale,
            style: state.style,
            mode: state.mode,
            showsPromptBar: false,
            showsHumorSlider: false
        )
    }

    private var innerContentSize: CGSize {
        CGSize(
            width: max(1, panelSize.width - shadowInset * 2),
            height: max(1, panelSize.height - shadowInset * 2)
        )
    }

    private var capsuleVisibleSize: CGSize {
        CGSize(
            width: max(1, pillSize.width - shadowInset * 2),
            height: max(1, pillSize.height - shadowInset * 2)
        )
    }

    private var humorAccessoryOffset: CGFloat {
        state.showsHumorControl
            ? OverlayHUDLayout.humorControlSpacing(for: state.scale)
                + OverlayHUDLayout.humorControlHeight(for: state.scale)
            : 0
    }

    private var capsuleCenterY: CGFloat {
        innerContentSize.height
            - humorAccessoryOffset
            - capsuleVisibleSize.height / 2
    }

    private var promptBarCenterY: CGFloat {
        innerContentSize.height
            - humorAccessoryOffset
            - capsuleVisibleSize.height
            - OverlayHUDLayout.promptBarSpacing(for: state.scale)
            - OverlayHUDLayout.promptBarHeight(for: state.scale) / 2
    }

    private var humorSliderCenterY: CGFloat {
        innerContentSize.height
            - OverlayHUDLayout.humorControlHeight(for: state.scale) / 2
    }

    private var shadowInset: CGFloat {
        OverlayHUDLayout.shadowPad * visualScale
    }

    private var tint: Color {
        state.mode.tint(for: state.style)
    }

    private var spectrumBarCount: Int {
        OverlayHUDLayout.spectrumBarCount(
            for: state.scale,
            style: state.style
        )
    }

    private var classicProcessingBarCount: Int {
        max(7, spectrumBarCount + 2)
    }

    private func classicSpectrum(barCount: Int) -> some View {
        MinimalBarSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isActive: true,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing,
            barCount: barCount
        )
    }

    private var techSpectrum: some View {
        EnergyZigzagSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing
        )
    }

    private var verticalSpectrum: some View {
        VerticalPulseSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing,
            segmentCount: max(5, spectrumBarCount),
            dragOffset: state.mode == .listening ? state.dragOffset : .zero
        )
    }

    private var verticalDragStretch: CGFloat {
        guard state.style == .vertical, state.mode == .listening else { return 1 }
        let magnitude = sqrt(
            state.dragOffset.width * state.dragOffset.width
                + state.dragOffset.height * state.dragOffset.height
        )
        return 1 + min(0.08, magnitude * 0.012)
    }

    private var controlDiameter: CGFloat {
        OverlayHUDLayout.controlDiameter(
            for: state.scale,
            style: state.style
        )
    }

    private var controlTextScale: CGFloat {
        controlDiameter / OverlayHUDLayout.controlButtonDiameter
    }

    @ViewBuilder
    private func controlSlot(
        label: String,
        isActive: Bool,
        isEnabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> some View {
        let margin = OverlayHUDLayout.controlHitMargin(for: state.scale)
        if state.showsControls {
            Button {
                action?()
            } label: {
                controlButton(label: label, isActive: isActive)
                    .padding(margin)
                    .contentShape(controlHitShape)
            }
            .buttonStyle(.plain)
            .padding(-margin)
            .opacity(isEnabled ? 1 : 0.34)
            .disabled(!isEnabled)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else {
            Color.clear
                .frame(
                    width: controlDiameter,
                    height: controlDiameter
                )
        }
    }

    private func controlButton(label: String, isActive: Bool) -> some View {
        let xOffset: CGFloat = (label == "1" ? 0.35 : 0) * visualScale
        let yOffset: CGFloat = (0.65 + (state.style == .vertical ? 0.35 : 0)) * visualScale

        return ZStack {
            Text(label)
                .font(
                    .system(
                        size: 12 * controlTextScale,
                        weight: .semibold,
                        design: state.style == .vertical ? .monospaced : .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .offset(x: xOffset, y: yOffset)
        }
        .frame(width: controlDiameter, height: controlDiameter, alignment: .center)
        .background {
            controlShape.fill(.ultraThinMaterial)
        }
        .background {
            controlShape.fill(
                tint.opacity(isActive ? 0.20 : 0.05)
            )
        }
        .overlay {
            controlShape
                .stroke(
                    .white.opacity(isActive ? 0.88 : 0.42),
                    lineWidth: 1.0 * visualScale
                )
        }
        .shadow(
            color: state.style == .vertical ? .clear : tint.opacity(0.18),
            radius: 5 * visualScale,
            x: 0,
            y: 2
        )
    }

    private var controlShape: AnyShape {
        switch state.style {
        case .capsule:
            AnyShape(Circle())
        case .tech:
            AnyShape(
                RoundedRectangle(
                    cornerRadius: 6 * visualScale,
                    style: .continuous
                )
            )
        case .vertical:
            AnyShape(Circle())
        }
    }

    private var controlHitShape: AnyShape {
        let margin = OverlayHUDLayout.controlHitMargin(for: state.scale)
        switch state.style {
        case .capsule, .vertical:
            return AnyShape(Circle())
        case .tech:
            return AnyShape(
                RoundedRectangle(
                    cornerRadius: 6 * visualScale + margin,
                    style: .continuous
                )
            )
        }
    }
}

private struct MinimalBarSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isActive: Bool
    let isVisible: Bool
    let isProcessing: Bool
    var barCount: Int = 5
    var noiseFloor: CGFloat = 0.10
    var processingSpeed: CGFloat = 1.1

    @State private var phase: TimeInterval = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 45.0,
        on: .main,
        in: .common
    ).autoconnect()

    private var values: [CGFloat] {
        if isProcessing {
            return (0..<barCount).map { index in
                processingValue(at: index, phase: phase)
            }
        }

        if isActive {
            return HUDSpectrumResponse.classicListeningValues(
                bands: bands,
                barCount: barCount,
                noiseFloor: Float(noiseFloor)
            )
            .map { CGFloat($0) }
        }

        return Array(repeating: noiseFloor, count: barCount)
    }

    private func processingValue(at index: Int, phase: TimeInterval) -> CGFloat {
        let t = CGFloat(index) / CGFloat(max(barCount - 1, 1))
        let envelope = 0.45 + 0.55 * sin(t * .pi)
        let travel = phase * processingSpeed - CGFloat(index) * 0.9
        let carrier = 0.5 + 0.5 * sin(travel * .pi * 2.0)
        let harmonic = 0.5 + 0.5 * sin(travel * .pi * 4.0 + 1.1)
        let synthetic = 0.30 + 0.50 * carrier + 0.20 * harmonic
        return min(1, max(noiseFloor, synthetic * envelope + 0.12))
    }

    var body: some View {
        Canvas { context, size in
            drawBars(in: &context, size: size)
        }
        .onAppear { phase = Date().timeIntervalSinceReferenceDate }
        .onReceive(animationTimer) { date in
            guard isVisible, isProcessing else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize) {
        let resolved = values
        let count = resolved.count
        guard count > 0, size.width > 0, size.height > 0 else { return }

        // Adaptive bar sizing: bars are proportional to the height, but shrink
        // to fit whenever many bars are requested so the equalizer never
        // overflows the available width or collapses into a single blob.
        let preferredBarWidth = max(3.6, size.height * 0.15)
        let preferredGap = max(3.4, preferredBarWidth * 0.9)
        let preferredTotal = preferredBarWidth * CGFloat(count) + preferredGap * CGFloat(count - 1)
        let fit = preferredTotal > size.width ? size.width / preferredTotal : 1
        let barWidth = max(2.8, preferredBarWidth * fit)
        let gap = preferredGap * fit
        let totalWidth = barWidth * CGFloat(count) + gap * CGFloat(count - 1)
        let startX = (size.width - totalWidth) / 2
        let centerY = size.height / 2
        let maxHeight = size.height * 0.82
        let minHeight = size.height * 0.14
        let cornerRadius = barWidth / 2

        for (index, value) in resolved.enumerated() {
            let height = max(minHeight, value * maxHeight)
            let x = startX + CGFloat(index) * (barWidth + gap)
            let rect = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
            let barPath = Path(roundedRect: rect, cornerRadius: cornerRadius)

            var glowContext = context
            glowContext.addFilter(.blur(radius: barWidth * 0.5))
            glowContext.fill(barPath, with: .color(color.opacity(isActive ? 0.28 : 0.14)))

            context.fill(
                barPath,
                with: .linearGradient(
                    Gradient(colors: [
                        color.opacity(0.45),
                        color.opacity(0.98),
                        color.opacity(0.45)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )

            if height > minHeight * 1.8 {
                let highlight = Path(
                    roundedRect: rect.insetBy(dx: barWidth * 0.28, dy: height * 0.16),
                    cornerRadius: max(0.5, cornerRadius - barWidth * 0.28)
                )
                context.fill(highlight, with: .color(.white.opacity(isActive ? 0.18 : 0.08)))
            }
        }
    }
}

/// A deliberately technical alternative to the classic equalizer. The live
/// signal is rendered as a connected, angular energy trace with travelling
/// phase and luminous node markers instead of a row of ordinary bars.
private struct EnergyZigzagSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isVisible: Bool
    let isProcessing: Bool

    @State private var phase = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 36.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Canvas { context, size in
            drawCenterLine(in: &context, size: size)
            drawEnergyTrace(in: &context, size: size)
        }
        .onReceive(animationTimer) { date in
            guard isVisible else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
        .accessibilityHidden(true)
    }

    private var signalValues: [CGFloat] {
        let pointCount = 9
        if isProcessing {
            return (0..<pointCount).map { index in
                let offset = phase * 4.2 - Double(index) * 0.74
                let primary = 0.5 + 0.5 * sin(offset)
                let harmonic = 0.5 + 0.5 * sin(offset * 1.9 + 0.8)
                return 0.20 + 0.55 * CGFloat(primary) + 0.25 * CGFloat(harmonic)
            }
        }

        let resampled = resample(bands, count: pointCount)
        let peak = resampled.max() ?? 0
        guard peak >= 0.10 else {
            return (0..<pointCount).map { index in
                0.10 + 0.025 * sin(CGFloat(index) * 1.35 + CGFloat(phase * 1.7))
            }
        }
        return resampled.map { value in
            let cleaned = max(0, (value - 0.10) / 0.90)
            return max(0.12, min(1, pow(cleaned * 2.15, 0.78)))
        }
    }

    private func drawCenterLine(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(
            path,
            with: .color(.white.opacity(0.08)),
            style: StrokeStyle(lineWidth: 0.6, dash: [2.5, 3.5])
        )
    }

    private func drawEnergyTrace(in context: inout GraphicsContext, size: CGSize) {
        let values = signalValues
        guard values.count > 1, size.width > 0, size.height > 0 else { return }

        let horizontalInset: CGFloat = 2
        let usableWidth = max(1, size.width - horizontalInset * 2)
        let midY = size.height / 2
        let amplitude = size.height * 0.36
        var points: [CGPoint] = []

        for (index, value) in values.enumerated() {
            let t = CGFloat(index) / CGFloat(values.count - 1)
            let x = horizontalInset + usableWidth * t
            let polarity: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let traveling = sin(CGFloat(phase * 2.8) + t * .pi * 2.1) * 0.18
            let y = midY + polarity * amplitude * min(1, value + traveling)
            points.append(CGPoint(x: x, y: y))
        }

        var trace = Path()
        trace.move(to: points[0])
        for point in points.dropFirst() {
            trace.addLine(to: point)
        }

        var glow = context
        glow.addFilter(.blur(radius: 4.5))
        glow.stroke(
            trace,
            with: .color(color.opacity(0.48)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .square, lineJoin: .miter)
        )
        context.stroke(
            trace,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.45),
                    color,
                    .white.opacity(0.92),
                    color,
                    color.opacity(0.45),
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            ),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter)
        )

        for (index, point) in points.enumerated() where index.isMultiple(of: 2) {
            let nodeSize: CGFloat = isProcessing ? 3.2 : 2.6
            let nodeRect = CGRect(
                x: point.x - nodeSize / 2,
                y: point.y - nodeSize / 2,
                width: nodeSize,
                height: nodeSize
            )
            context.fill(
                Path(roundedRect: nodeRect, cornerRadius: 0.8),
                with: .color(index == points.count / 2 ? .white : color)
            )
        }
    }
}

/// A shell-free monochrome HUD. Listening is shown as a column of responsive
/// white spheres; processing switches to a moving double helix so the two
/// states remain unmistakable without relying on color.
private struct VerticalPulseSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isVisible: Bool
    let isProcessing: Bool
    let segmentCount: Int
    let dragOffset: CGSize

    @State private var phase = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 36.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Canvas { context, size in
            if isProcessing {
                drawProcessingHelix(in: &context, size: size)
            } else {
                drawListeningSpheres(in: &context, size: size)
            }
        }
        .onReceive(animationTimer) { date in
            guard isVisible else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
        .accessibilityHidden(true)
    }

    private var listeningValues: [CGFloat] {
        let count = max(5, segmentCount)
        let resampled = resample(bands, count: count)
        let peak = resampled.max() ?? 0
        guard peak >= 0.035 else {
            return (0..<count).map { index in
                0.08 + 0.02 * sin(CGFloat(phase * 1.35) + CGFloat(index) * 0.8)
            }
        }
        let global = min(1, pow(max(0, (peak - 0.03) / 0.22), 0.5))
        return resampled.enumerated().map { index, value in
            let local = min(1, pow(max(0, (value - 0.025) / 0.20), 0.58))
            let modulation =
                0.64
                + 0.36 * abs(sin(CGFloat(phase * 1.4) + CGFloat(index) * 0.9))
            return max(0.10, max(local, global * modulation))
        }
    }

    private func drawListeningSpheres(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let resolved = listeningValues
        guard !resolved.isEmpty, size.width > 0, size.height > 0 else { return }

        let step = size.height / CGFloat(resolved.count + 1)
        let maximumDiameter = min(7.2, step * 1.05, size.width * 0.26)
        let minimumDiameter = min(2.0, maximumDiameter)
        let centerX = size.width / 2

        var rope = Path()
        rope.move(to: CGPoint(x: centerX, y: 0))
        rope.addCurve(
            to: CGPoint(x: centerX + dragOffset.width, y: size.height),
            control1: CGPoint(
                x: centerX + dragOffset.width * 0.10,
                y: size.height * 0.34
            ),
            control2: CGPoint(
                x: centerX + dragOffset.width * 0.72,
                y: size.height * 0.70
            )
        )
        context.stroke(
            rope,
            with: .color(color.opacity(0.18)),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
        )

        for (index, value) in resolved.enumerated() {
            let progress = CGFloat(index + 1) / CGFloat(resolved.count + 1)
            let ropeInfluence = pow(progress, 1.55)
            let diameter =
                minimumDiameter
                + (maximumDiameter - minimumDiameter) * sqrt(max(0, value))
            let horizontalMotion =
                sin(CGFloat(phase * 4.8) + CGFloat(index) * 1.15)
                * (0.35 + 4.4 * value)
            let verticalMotion =
                cos(CGFloat(phase * 3.9) + CGFloat(index) * 0.82)
                * (0.20 + 1.6 * value)
            drawSphere(
                in: &context,
                center: CGPoint(
                    x: centerX + dragOffset.width * ropeInfluence + horizontalMotion,
                    y: step * CGFloat(index + 1)
                        + dragOffset.height * ropeInfluence
                        + verticalMotion
                ),
                diameter: diameter,
                opacity: 0.96
            )
        }
    }

    private func drawProcessingHelix(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let count = max(6, segmentCount + 1)
        let verticalInset: CGFloat = 2.5
        let usableHeight = max(1, size.height - verticalInset * 2)
        let radius = min(7.5, size.width * 0.28)

        for index in 0..<count {
            let progress = CGFloat(index) / CGFloat(max(1, count - 1))
            let y = verticalInset + usableHeight * progress
            let angle = CGFloat(phase * 3.0) + CGFloat(index) * 0.98
            let offset = sin(angle) * radius
            let depth = 0.5 + 0.5 * cos(angle)
            let firstCenter = CGPoint(x: size.width / 2 + offset, y: y)
            let secondCenter = CGPoint(x: size.width / 2 - offset, y: y)

            var connector = Path()
            connector.move(to: firstCenter)
            connector.addLine(to: secondCenter)
            context.stroke(
                connector,
                with: .color(color.opacity(0.10 + 0.08 * depth)),
                lineWidth: 0.7
            )

            drawSphere(
                in: &context,
                center: firstCenter,
                diameter: 2.5 + 1.0 * depth,
                opacity: 0.52 + 0.42 * depth
            )
            drawSphere(
                in: &context,
                center: secondCenter,
                diameter: 3.5 - 1.0 * depth,
                opacity: 0.94 - 0.42 * depth
            )
        }
    }

    private func drawSphere(
        in context: inout GraphicsContext,
        center: CGPoint,
        diameter: CGFloat,
        opacity: CGFloat
    ) {
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let sphere = Path(ellipseIn: rect)

        if isProcessing {
            var glow = context
            glow.addFilter(.blur(radius: 1.2))
            glow.fill(sphere, with: .color(color.opacity(0.18 * opacity)))
        }
        context.fill(sphere, with: .color(color.opacity(opacity)))
    }
}

private func resample(_ bands: [Float], count: Int) -> [CGFloat] {
    guard count > 0 else { return [] }
    guard !bands.isEmpty else { return Array(repeating: 0, count: count) }

    return (0..<count).map { index in
        let source =
            Double(index) / Double(max(count - 1, 1))
            * Double(max(bands.count - 1, 0))
        let lower = Int(floor(source))
        let upper = min(lower + 1, bands.count - 1)
        let fraction = CGFloat(source - Double(lower))
        return min(
            1,
            max(
                0,
                CGFloat(bands[lower]) * (1 - fraction)
                    + CGFloat(bands[upper]) * fraction
            )
        )
    }
}

private func bottomCenterOrigin(for size: CGSize, visibleFrame: CGRect) -> CGPoint {
    let inset: CGFloat = 18
    return CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + inset)
}

private func clamp(origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
    CGPoint(
        x: min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12),
        y: min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
    )
}

private extension CGPoint {
    init(origin: OverlayHUDOrigin) {
        self.init(x: CGFloat(origin.x), y: CGFloat(origin.y))
    }
}
