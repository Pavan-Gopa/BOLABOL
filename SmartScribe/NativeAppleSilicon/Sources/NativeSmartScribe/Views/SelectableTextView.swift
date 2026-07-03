import AppKit
import SwiftUI

struct SelectableTextView: NSViewRepresentable {
    private enum Appearance {
        static let darkSelectionBackground = NSColor(calibratedRed: 0.47, green: 0.49, blue: 0.53, alpha: 0.9)
        static let darkSelectionForeground = NSColor.white
        static let lightSelectionBackground = NSColor(calibratedRed: 0.74, green: 0.80, blue: 0.92, alpha: 0.95)
        static let lightSelectionForeground = NSColor.labelColor
    }

    @Binding var text: String
    @Binding var selectedText: String
    let placeholder: String
    let isEditable: Bool
    let selectionActionTitle: String?
    let onSelectionAction: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.string = displayText
        configureSelectionAppearance(for: textView)
        context.coordinator.textView = textView
        textView.menu = context.coordinator.makeSelectionContextMenu()

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let nextText = displayText
        if textView.string != nextText {
            textView.string = nextText
        }

        textView.isEditable = isEditable
        textView.textColor = text.isEmpty ? .secondaryLabelColor : .labelColor
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        configureSelectionAppearance(for: textView)
        context.coordinator.parent = self
        context.coordinator.textView = textView
        textView.menu = context.coordinator.makeSelectionContextMenu()
    }

    private var displayText: String {
        if isEditable {
            return text
        }

        return text.isEmpty ? placeholder : text
    }

    private func configureSelectionAppearance(for textView: NSTextView) {
        let isDark = effectiveIsDark(for: textView)
        let background = isDark ? Appearance.darkSelectionBackground : Appearance.lightSelectionBackground
        let foreground = isDark ? Appearance.darkSelectionForeground : Appearance.lightSelectionForeground
        textView.selectedTextAttributes = [
            .backgroundColor: background,
            .foregroundColor: foreground
        ]
        textView.insertionPointColor = isDark ? .white : .labelColor
    }

    private func effectiveIsDark(for textView: NSTextView) -> Bool {
        let appearance = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return appearance == .darkAqua
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextView
        weak var textView: NSTextView?

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        func makeSelectionContextMenu() -> NSMenu? {
            guard let title = parent.selectionActionTitle,
                  parent.onSelectionAction != nil
            else {
                return nil
            }

            let menu = NSMenu()
            let actionItem = NSMenuItem(
                title: title,
                action: #selector(performSelectionAction(_:)),
                keyEquivalent: ""
            )
            actionItem.target = self
            menu.addItem(actionItem)
            menu.addItem(.separator())

            if parent.isEditable {
                menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            if parent.isEditable {
                menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
            return menu
        }

        @objc private func performSelectionAction(_ sender: NSMenuItem) {
            guard let textView,
                  let onSelectionAction = parent.onSelectionAction
            else {
                return
            }

            let selected = Self.selectedText(in: textView)
            guard !selected.isEmpty else { return }
            onSelectionAction(selected)
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            guard menuItem.action == #selector(performSelectionAction(_:)),
                  let textView
            else {
                return true
            }

            return !Self.selectedText(in: textView).isEmpty
        }

        func textDidChange(_ notification: Notification) {
            guard parent.isEditable,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string)
            else {
                parent.selectedText = ""
                return
            }

            parent.selectedText = String(textView.string[swiftRange])
        }

        private static func selectedText(in textView: NSTextView) -> String {
            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string)
            else {
                return ""
            }

            return String(textView.string[swiftRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
