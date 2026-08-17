import AppKit
import NativeBolabolCore
import SwiftUI

// MARK: - Hotkey Recorder View

/// Compact macOS click-to-record shortcut control.
@MainActor
struct HotkeyRecorder: View {
    private let title: String
    private let value: String
    private let isRecording: Bool
    private let allowsRightModifierOnly: Bool
    private let rejectionReason: HotkeyCaptureRejectionReason?
    private let onBegin: () -> Void
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void
    private let onReject: (HotkeyCaptureRejectionReason) -> Void

    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    init(
        title: String,
        value: String,
        isRecording: Bool,
        allowsRightModifierOnly: Bool = false,
        rejectionReason: HotkeyCaptureRejectionReason? = nil,
        onBegin: @escaping () -> Void,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onReject: @escaping (HotkeyCaptureRejectionReason) -> Void = { _ in }
    ) {
        self.title = title
        self.value = value
        self.isRecording = isRecording
        self.allowsRightModifierOnly = allowsRightModifierOnly
        self.rejectionReason = rejectionReason
        self.onBegin = onBegin
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onReject = onReject
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: handleButtonClick) {
                recorderLabel
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 100, maxWidth: 220, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .background(responderBridge)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValueString)
            .accessibilityHint(accessibilityHintString)
            .help(helpTooltipString)
        }
    }

    private func handleButtonClick() {
        if isRecording {
            onCancel()
        } else {
            onBegin()
        }
    }

    @ViewBuilder
    private var recorderLabel: some View {
        HStack(spacing: 5) {
            if isRecording {
                if let rejectionReason {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(rejectionPromptText(for: rejectionReason))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Image(systemName: "record.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)

                    Text(recordingPromptText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(displayString)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var responderBridge: some View {
        HotkeyFirstResponderHost(
            isRecording: isRecording,
            allowsRightModifierOnly: allowsRightModifierOnly,
            onCommit: onCommit,
            onCancel: onCancel,
            onReject: onReject
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var displayString: String {
        HotkeySettings.displayString(for: value)
    }

    private var recordingPromptText: String {
        if allowsRightModifierOnly {
            return generalSettingsStore.text(.hotkeyRecorderPrimaryPrompt)
        } else {
            return generalSettingsStore.text(.hotkeyRecorderPrompt)
        }
    }

    private var accessibilityValueString: String {
        if isRecording {
            if let rejectionReason {
                return rejectionPromptText(for: rejectionReason)
            }
            return generalSettingsStore.text(.hotkeyRecorderRecordingAccessibility)
        } else {
            return displayString
        }
    }

    private var accessibilityHintString: String {
        if isRecording {
            if rejectionReason != nil {
                return generalSettingsStore.text(.hotkeyRecorderRecordingAccessibility)
            }
            return allowsRightModifierOnly
                ? generalSettingsStore.text(.hotkeyRecorderPrimaryPrompt)
                : generalSettingsStore.text(.hotkeyRecorderPrompt)
        } else {
            if allowsRightModifierOnly {
                return generalSettingsStore.text(.hotkeyRecorderIdleHint) + ". " + generalSettingsStore.text(.hotkeyRecorderPrimaryPrompt)
            } else {
                return generalSettingsStore.text(.hotkeyRecorderIdleHint)
            }
        }
    }

    private func rejectionPromptText(for reason: HotkeyCaptureRejectionReason) -> String {
        switch reason {
        case .modifierRequired:
            return generalSettingsStore.text(.hotkeyRejectModifierRequired)
        case .unsupportedKey:
            return generalSettingsStore.text(.hotkeyRejectUnsupportedKey)
        case .modifierOnlyPrimary:
            return generalSettingsStore.text(.hotkeyRejectModifierOnlyPrimary)
        }
    }

    private var helpTooltipString: String {
        if let rejectionReason {
            return rejectionPromptText(for: rejectionReason)
        }
        return isRecording ? recordingPromptText : generalSettingsStore.text(.hotkeyRecorderIdleHint)
    }
}

// MARK: - AppKit First Responder Bridge

/// Private accessibility-hidden NSViewRepresentable hosting key-capture without global NSEvent monitors.
struct HotkeyFirstResponderHost: NSViewRepresentable {
    let isRecording: Bool
    let allowsRightModifierOnly: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onReject: (HotkeyCaptureRejectionReason) -> Void

    func makeNSView(context: Context) -> HotkeyCaptureNSView {
        let view = HotkeyCaptureNSView()
        view.allowsRightModifierOnly = allowsRightModifierOnly
        view.onCommit = onCommit
        view.onCancel = onCancel
        view.onReject = onReject
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureNSView, context: Context) {
        nsView.allowsRightModifierOnly = allowsRightModifierOnly
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.onReject = onReject

        if isRecording {
            nsView.activateCapture()
        } else {
            nsView.deactivateCapture()
        }
    }

    static func dismantleNSView(_ nsView: HotkeyCaptureNSView, coordinator: ()) {
        nsView.deactivateCapture()
    }
}

// MARK: - Hotkey Capture NSView

final class HotkeyCaptureNSView: NSView {
    var allowsRightModifierOnly: Bool = false
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onReject: ((HotkeyCaptureRejectionReason) -> Void)?

    private var stateMachine = ShortcutCaptureStateMachine()
    private var windowResignObserver: Any?
    private var isActive: Bool = false

    override var acceptsFirstResponder: Bool {
        isActive
    }

    override func becomeFirstResponder() -> Bool {
        guard isActive else { return false }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if isActive {
            handleCancel()
        }
        return super.resignFirstResponder()
    }

    func activateCapture() {
        guard !isActive else { return }
        isActive = true
        stateMachine = ShortcutCaptureStateMachine()
        _ = stateMachine.handle(.start(HotkeyCapturePolicy(allowsRightModifierOnly: allowsRightModifierOnly)))

        setupWindowObserver()

        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }

    func deactivateCapture() {
        guard isActive else { return }
        handleCancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if isActive {
                handleCancel()
            } else {
                removeWindowObserver()
            }
        } else if isActive {
            setupWindowObserver()
            window?.makeFirstResponder(self)
        }
    }

    private func setupWindowObserver() {
        removeWindowObserver()
        guard let window else { return }

        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleFocusLost()
            }
        }
    }

    private func removeWindowObserver() {
        if let observer = windowResignObserver {
            NotificationCenter.default.removeObserver(observer)
            windowResignObserver = nil
        }
    }

    private func handleFocusLost() {
        guard isActive else { return }
        if let effect = stateMachine.handle(.focusLost) {
            processEffect(effect)
        }
    }

    private func handleCancel() {
        guard isActive else { return }
        if let effect = stateMachine.handle(.cancel) {
            processEffect(effect)
        } else {
            isActive = false
            removeWindowObserver()
            if let window, window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
        }
    }

    private func processEffect(_ effect: HotkeyCaptureEffect) {
        switch effect {
        case .committed(let recorded):
            isActive = false
            removeWindowObserver()
            if let window, window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
            onCommit?(recorded.settingsValue)

        case .cancelled:
            isActive = false
            removeWindowObserver()
            if let window, window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
            onCancel?()

        case .rejected(let reason):
            onReject?(reason)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }

        let keyCode = event.keyCode
        let rawFlags = event.modifierFlags.rawValue
        let isRepeat = event.isARepeat

        if let effect = stateMachine.handle(.keyDown(keyCode: keyCode, rawFlags: rawFlags, isRepeat: isRepeat)) {
            processEffect(effect)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard isActive else {
            super.keyUp(with: event)
            return
        }
        // Key-up is consumed during capture
    }

    override func flagsChanged(with event: NSEvent) {
        guard isActive else {
            super.flagsChanged(with: event)
            return
        }

        let keyCode = event.keyCode
        let rawFlags = event.modifierFlags.rawValue

        if let effect = stateMachine.handle(.flagsChanged(keyCode: keyCode, rawFlags: rawFlags)) {
            processEffect(effect)
        }
    }
    deinit {
        MainActor.assumeIsolated {
            removeWindowObserver()
        }
    }
}
