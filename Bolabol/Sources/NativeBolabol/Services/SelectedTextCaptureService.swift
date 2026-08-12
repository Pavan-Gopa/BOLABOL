import AppKit
import ApplicationServices
import Carbon
import NativeBolabolCore

/// Captures the selection that existed before Bolabol opens a translation panel.
///
/// The frontmost application is sampled before any translation window is shown.
/// Accessibility is the fast path; a targeted Cmd+C is the compatibility fallback
/// for applications that expose no readable AX selection.
@MainActor
enum SelectedTextCaptureService {
    enum CaptureStatus: Equatable {
        case selectedText
        case clipboardFallback
        case accessibilityPermissionRequired
        case noSelection
    }

    struct Capture {
        let text: String
        let sourceApplication: NSRunningApplication?
        let status: CaptureStatus
    }

    private static var permissionPromptState = AccessibilityPermissionPromptState()

    static func statusBeforeSelectionLookup(
        isAccessibilityTrusted: Bool,
        existingClipboardText: String?
    ) -> CaptureStatus {
        guard !isAccessibilityTrusted else { return .selectedText }
        return trimmedText(existingClipboardText) == nil
            ? .accessibilityPermissionRequired
            : .clipboardFallback
    }

    static func capture() async -> Capture {
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let initialText = pasteboard.string(forType: .string)
        let isAccessibilityTrusted = AccessibilityPermissionService.isTrusted()
        if isAccessibilityTrusted {
            permissionPromptState.reset()
        }

        // Reading AXSelectedText and posting Cmd+C to another application both
        // require Accessibility permission. Request it on the first translation
        // hotkey press instead of silently returning an empty translation.
        guard !isAccessibilityTrusted else {
            return await captureWithAccessibility(
                sourceApplication: sourceApplication,
                pasteboard: pasteboard,
                initialChangeCount: initialChangeCount,
                initialText: initialText
            )
        }

        switch statusBeforeSelectionLookup(
            isAccessibilityTrusted: isAccessibilityTrusted,
            existingClipboardText: initialText
        ) {
        case .clipboardFallback:
            guard let initialText = trimmedText(initialText) else { break }
            if permissionPromptState.shouldRequestPrompt(isTrusted: false) {
                _ = AccessibilityPermissionService.requestTrustPrompt()
            }
            NativeBolabolLog.hotkey.warning(
                "Accessibility permission is unavailable; using the existing clipboard text as a translation fallback length=\(initialText.count, privacy: .public)"
            )
            return Capture(
                text: initialText,
                sourceApplication: sourceApplication,
                status: .clipboardFallback
            )

        case .accessibilityPermissionRequired:
            if permissionPromptState.shouldRequestPrompt(isTrusted: false) {
                _ = AccessibilityPermissionService.requestTrustPrompt()
            }
            NativeBolabolLog.hotkey.warning(
                "Accessibility permission is required to capture selected text from another application."
            )
            return Capture(
                text: "",
                sourceApplication: sourceApplication,
                status: .accessibilityPermissionRequired
            )

        case .selectedText, .noSelection:
            break
        }

        return Capture(
            text: "",
            sourceApplication: sourceApplication,
            status: .noSelection
        )
    }

    private static func captureWithAccessibility(
        sourceApplication: NSRunningApplication?,
        pasteboard: NSPasteboard,
        initialChangeCount: Int,
        initialText: String?
    ) async -> Capture {
        permissionPromptState.reset()

        if let focusedElement = AccessibilityPermissionService.focusedElement(),
           let selectedText = selectedText(from: focusedElement) {
            NativeBolabolLog.hotkey.info(
                "Captured translation selection through Accessibility length=\(selectedText.count, privacy: .public) sourcePID=\(sourceApplication?.processIdentifier ?? -1, privacy: .public)"
            )
            return Capture(
                text: selectedText,
                sourceApplication: sourceApplication,
                status: .selectedText
            )
        }

        await postCopy(to: sourceApplication?.processIdentifier)

        // Different applications acknowledge Cmd+C at different speeds. Wait for
        // the pasteboard transaction rather than relying on a fixed 80 ms delay.
        for _ in 0..<24 {
            if let copiedText = nonEmptyPasteboardText(
                pasteboard,
                initialChangeCount: initialChangeCount,
                initialText: initialText
            ) {
                NativeBolabolLog.hotkey.info(
                    "Captured translation selection through Cmd+C length=\(copiedText.count, privacy: .public) sourcePID=\(sourceApplication?.processIdentifier ?? -1, privacy: .public)"
                )
                return Capture(
                    text: copiedText,
                    sourceApplication: sourceApplication,
                    status: .selectedText
                )
            }

            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                break
            }
        }

        NativeBolabolLog.hotkey.warning(
            "Could not capture selected text from the frontmost application; ignoring unchanged clipboard content."
        )
        return Capture(
            text: "",
            sourceApplication: sourceApplication,
            status: .noSelection
        )
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard status == .success,
              let value,
              let text = value as? String
        else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmptyPasteboardText(
        _ pasteboard: NSPasteboard,
        initialChangeCount: Int,
        initialText: String?
    ) -> String? {
        guard pasteboard.changeCount != initialChangeCount,
              let text = pasteboard.string(forType: .string)
        else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != initialText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return trimmed
    }

    private static func trimmedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func postCopy(to targetPID: pid_t?) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        )
        let cUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        )

        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand

        if let targetPID {
            cDown?.postToPid(targetPID)
            try? await Task.sleep(nanoseconds: 30_000_000)
            cUp?.postToPid(targetPID)
        } else {
            cDown?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 30_000_000)
            cUp?.post(tap: .cghidEventTap)
        }
    }
}
