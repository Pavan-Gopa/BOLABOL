import AppKit
import ApplicationServices
import NativeBolabolCore

enum AccessibilityPermissionService {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestTrustPrompt() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard status == .success, let focusedElementRef else {
            NativeBolabolLog.hotkey.warning(
                "Unable to capture focused AX element status=\(String(describing: status), privacy: .public)"
            )
            return nil
        }

        NativeBolabolLog.hotkey.info("Captured focused AX element for hotkey insertion.")
        return unsafeDowncast(focusedElementRef as AnyObject, to: AXUIElement.self)
    }
}
