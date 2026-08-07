@testable import NativeBolabol
import Testing

@Test
@MainActor
func selectedTextCaptureUsesExistingClipboardWhenAccessibilityIsUnavailable() {
    let status = SelectedTextCaptureService.statusBeforeSelectionLookup(
        isAccessibilityTrusted: false,
        existingClipboardText: "  copied text  "
    )

    #expect(status == .clipboardFallback)
}

@Test
@MainActor
func selectedTextCaptureReportsPermissionRequirementWithoutClipboard() {
    let status = SelectedTextCaptureService.statusBeforeSelectionLookup(
        isAccessibilityTrusted: false,
        existingClipboardText: " \n\t"
    )

    #expect(status == .accessibilityPermissionRequired)
}

@Test
@MainActor
func selectedTextCaptureAllowsSelectionLookupWhenAccessibilityIsTrusted() {
    let status = SelectedTextCaptureService.statusBeforeSelectionLookup(
        isAccessibilityTrusted: true,
        existingClipboardText: nil
    )

    #expect(status == .selectedText)
}
