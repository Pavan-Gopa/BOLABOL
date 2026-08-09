import AppKit
import NativeBolabolCore
import SwiftUI

// Views layer: owns the transient HUD language-picker popover lifecycle.
// The controller must remain internal and main-actor isolated.

/// Production `NSPopoverDelegate` backing the HUD language picker. The outside-
/// close callback runs synchronously so no stale popover reference or identity
/// survives after the system closes the popover.
@MainActor
final class PopoverDelegate: NSObject, NSPopoverDelegate {
    private let onDidClose: () -> Void
    init(onDidClose: @escaping () -> Void) {
        self.onDidClose = onDidClose
    }
    func popoverDidClose(_ notification: Notification) {
        onDidClose()
    }
}

/// Testable production seam for the HUD language-picker popover lifecycle.
/// Creates the real transient `NSPopover` hosting the compact
/// `HUDLanguagePickerPopoverView` with a real `PopoverDelegate`; outside-close,
/// selection and finish/hide invalidation all flow through this controller
/// instead of duplicated view-local tokens.
@MainActor
final class LanguagePickerPopoverController {
    private(set) var popover: NSPopover?
    private(set) var popoverID: UUID?
    private(set) var popoverDelegate: PopoverDelegate?

    func present(
        options: [HUDLanguageMenuOption],
        languages: UserSpeechLanguages,
        anchorView: NSView,
        location: NSPoint,
        onSelectLanguage: @escaping (UUID, String) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        dismiss()
        let popoverID = UUID()
        self.popoverID = popoverID

        let pickerContentView = HUDLanguagePickerPopoverView(
            options: options,
            languages: languages,
            onSelectLanguage: { [weak self] selectedCode in
                guard let self, self.popoverID == popoverID else { return }
                self.dismiss()
                onSelectLanguage(popoverID, selectedCode)
            },
            onClose: { [weak self] in
                guard let self, self.popoverID == popoverID else { return }
                self.dismiss()
                onClose(popoverID)
            }
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: pickerContentView)
        let delegate = PopoverDelegate { [weak self] in
            guard let self, self.popoverID == popoverID else { return }
            self.popover = nil
            self.popoverID = nil
            self.popoverDelegate = nil
        }
        popover.delegate = delegate
        self.popoverDelegate = delegate
        self.popover = popover
        let anchorRect = NSRect(origin: location, size: .zero)
        popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxY)
    }

    func dismiss() {
        popover?.close()
        popover = nil
        popoverID = nil
        popoverDelegate = nil
    }

    /// Invalidates the picker as part of the common hotkey-session finish path.
    /// Keeping this operation on the production controller lets the finish path
    /// and the lifecycle tests exercise the same real popover state transition.
    func invalidateForFinishedHotkeySession() {
        dismiss()
    }
}
