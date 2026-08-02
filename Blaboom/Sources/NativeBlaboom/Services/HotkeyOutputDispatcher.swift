import AppKit
import ApplicationServices
import Carbon
import NativeBlaboomCore

@MainActor
final class HotkeyOutputDispatcher {
    static let shared = HotkeyOutputDispatcher()

    /// Minimum interval between consecutive dispatch calls (debounce guard).
    private static let debounceInterval: TimeInterval = 1.5
    private var lastDispatchTime: Date = .distantPast
    private var lastDispatchSignature: String?

    func dispatch(
        text: String,
        mode: HotkeyOutputMode,
        targetApplication: NSRunningApplication? = nil,
        targetElement: AXUIElement? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NativeBlaboomLog.hotkey.warning("Skipped hotkey output because resolved text is empty.")
            return
        }

        // Debounce: reject if the same output is dispatched again too quickly.
        let now = Date()
        let dispatchSignature = [
            mode.rawValue,
            targetApplication?.bundleIdentifier ?? "unknown",
            String(targetApplication?.processIdentifier ?? -1),
            trimmed
        ].joined(separator: "|")
        if dispatchSignature == lastDispatchSignature,
           now.timeIntervalSince(lastDispatchTime) < Self.debounceInterval {
            NativeBlaboomLog.hotkey.warning(
                "Debounced duplicate dispatch call interval=\(now.timeIntervalSince(self.lastDispatchTime), privacy: .public)"
            )
            return
        }
        lastDispatchTime = now
        lastDispatchSignature = dispatchSignature

        NativeBlaboomLog.hotkey.info(
            "Dispatching hotkey output mode=\(mode.rawValue, privacy: .public) length=\(trimmed.count, privacy: .public) targetPID=\(targetApplication?.processIdentifier ?? -1, privacy: .public) targetBundle=\(targetApplication?.bundleIdentifier ?? "unknown", privacy: .public)"
        )

        switch mode {
        case .clipboard:
            copyToPasteboard(text)
        case .typing:
            pasteIntoActiveApp(
                text,
                targetApplication: targetApplication,
                targetElement: targetElement
            )
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        let didSetString = NSPasteboard.general.setString(text, forType: .string)
        NativeBlaboomLog.hotkey.info(
            "Copied hotkey output to pasteboard success=\(didSetString, privacy: .public) changeCount=\(NSPasteboard.general.changeCount, privacy: .public)"
        )
    }

    // MARK: - Typing mode (paste into active app)

    private func pasteIntoActiveApp(
        _ text: String,
        targetApplication: NSRunningApplication?,
        targetElement: AXUIElement?
    ) {
        let hasAccessibilityPermission = ensureAccessibilityPermission()
        if !hasAccessibilityPermission {
            NativeBlaboomLog.hotkey.warning("Accessibility permission is required to paste hotkey output into the active app.")
            _ = AccessibilityPermissionService.requestTrustPrompt()
        }

        if let targetApplication {
            let didActivate = targetApplication.activate()
            NativeBlaboomLog.hotkey.info(
                "Requested target app activation success=\(didActivate, privacy: .public) pid=\(targetApplication.processIdentifier, privacy: .public) bundle=\(targetApplication.bundleIdentifier ?? "unknown", privacy: .public)"
            )
        } else {
            NativeBlaboomLog.hotkey.warning("No captured target app for hotkey paste; using current frontmost app.")
        }

        Task { @MainActor in
            // Wait for the target app to become active and settle.
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                NativeBlaboomLog.hotkey.error(
                    "Hotkey paste settle delay interrupted: \(error.localizedDescription, privacy: .public)"
                )
            }

            // Use exactly one insertion strategy. Mixing AX value insertion
            // with clipboard Cmd-V can duplicate text in apps that accept the
            // AX write but do not report it reliably.
            copyToPasteboard(text)
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // let pasteboard propagate
            } catch {
                NativeBlaboomLog.hotkey.error(
                    "Hotkey paste pasteboard propagation delay interrupted: \(error.localizedDescription, privacy: .public)"
                )
            }

            guard hasAccessibilityPermission else {
                NativeBlaboomLog.hotkey.warning("Cannot send synthetic Cmd-V because Accessibility is not trusted.")
                return
            }

            if let targetApplication {
                await postCommandV(to: targetApplication.processIdentifier)
            } else {
                await postCommandV()
            }
        }
    }

    // MARK: - AX insertion (single-shot)

    /// Try to insert text via Accessibility API.  Returns `true` if text was
    /// successfully placed into the target field (no further action needed).
    private func attemptAXInsertion(
        text: String,
        capturedElement: AXUIElement?,
        targetApplication: NSRunningApplication?
    ) async -> Bool {
        guard let element = resolveInsertionElement(
            capturedElement: capturedElement,
            targetApplication: targetApplication
        ) else {
            return false
        }

        let valueBefore = axStringValue(of: element)
        let inserted = insert(text, into: element, source: "resolved")

        if inserted {
            return true
        }

        // AX may have silently applied the change despite returning a
        // non-success status.  Give the target app a moment to process
        // the change before re-reading the value.
        try? await Task.sleep(nanoseconds: 150_000_000)

        let valueAfter = axStringValue(of: element)
        if let before = valueBefore,
           let after = valueAfter,
           before != after {
            NativeBlaboomLog.hotkey.info(
                "AX insertion returned failure but the field value changed; treating as success."
            )
            return true
        }

        NativeBlaboomLog.hotkey.info("AX insertion did not modify the field; will fall back to clipboard paste.")
        return false
    }

    // MARK: - AX helpers

    private func ensureAccessibilityPermission() -> Bool {
        AccessibilityPermissionService.isTrusted()
    }

    /// Pick the single best AX element for text insertion.
    /// Priority: captured element → target app's focused element → system-wide focused element.
    private func resolveInsertionElement(
        capturedElement: AXUIElement?,
        targetApplication: NSRunningApplication?
    ) -> AXUIElement? {
        // 1. Captured element from when hotkey recording started
        if let capturedElement {
            return capturedElement
        }

        // 2. Focused element inside the target application
        if let pid = targetApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success, let focusedRef {
                return unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
            }
        }

        // 3. System-wide focused element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef {
            return unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
        }

        NativeBlaboomLog.hotkey.warning("Could not resolve any AX element for text insertion.")
        return nil
    }

    /// Read the current string value of an AX element (for before/after comparison).
    private func axStringValue(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &ref
        ) == .success else { return nil }
        return ref as? String
    }

    private func insert(_ text: String, into element: AXUIElement, source: String) -> Bool {
        guard let snapshot = focusedTextSnapshot(for: element, source: source) else {
            return false
        }

        let updatedSnapshot = snapshot.inserting(text)
        let setValueStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedSnapshot.value as CFTypeRef
        )

        guard setValueStatus == .success else {
            NativeBlaboomLog.hotkey.warning(
                "AX insertion failed to set value source=\(source, privacy: .public) status=\(String(describing: setValueStatus), privacy: .public)"
            )
            return false
        }

        if let selectionValue = axValue(for: updatedSnapshot.selection) {
            let selectionStatus = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                selectionValue
            )
            NativeBlaboomLog.hotkey.info(
                "AX insertion updated selection source=\(source, privacy: .public) status=\(String(describing: selectionStatus), privacy: .public)"
            )
        }

        NativeBlaboomLog.hotkey.info("Inserted hotkey output through AX value source=\(source, privacy: .public).")
        return true
    }

    private func focusedTextSnapshot(
        for element: AXUIElement,
        source: String
    ) -> FocusedTextInsertionSnapshot? {
        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueStatus == .success, let value = valueRef as? String else {
            NativeBlaboomLog.hotkey.warning(
                "AX insertion could not read value source=\(source, privacy: .public) status=\(String(describing: valueStatus), privacy: .public)"
            )
            return nil
        }

        var selectionRef: CFTypeRef?
        let selectionStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectionRef
        )

        let selection: NSRange
        if selectionStatus == .success,
           let selectionRef,
           let range = axRangeValue(from: selectionRef) {
            selection = NSRange(location: range.location, length: range.length)
        } else {
            selection = NSRange(location: (value as NSString).length, length: 0)
            NativeBlaboomLog.hotkey.info(
                "AX insertion using append selection source=\(source, privacy: .public) selectionStatus=\(String(describing: selectionStatus), privacy: .public)"
            )
        }

        return FocusedTextInsertionSnapshot(value: value, selection: selection)
    }

    // MARK: - CGEvent Cmd-V (single synthetic keystroke)

    private func postCommandV() async {
        await postCommandV(to: nil)
    }

    private func postCommandV(to targetPID: pid_t?) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        let vUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        post(vDown, targetPID: targetPID)
        try? await Task.sleep(nanoseconds: 30_000_000)
        post(vUp, targetPID: targetPID)

        NativeBlaboomLog.hotkey.info(
            "Posted hotkey paste through CGEvent command-v targetPID=\(targetPID ?? -1, privacy: .public)."
        )
    }

    private func post(_ event: CGEvent?, targetPID: pid_t?) {
        guard let event else { return }
        if let targetPID {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }
}

private func axValue(for range: NSRange) -> AXValue? {
    var cfRange = CFRange(location: range.location, length: range.length)
    return AXValueCreate(.cfRange, &cfRange)
}

private func axRangeValue(from value: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
}
