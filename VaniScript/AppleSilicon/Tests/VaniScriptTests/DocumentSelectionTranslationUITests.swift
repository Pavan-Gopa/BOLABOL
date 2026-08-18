import AppKit
import Foundation
import Testing
@testable import VaniScript
@testable import VaniScriptCore

@Suite("DocumentSelectionTranslationUITests")
@MainActor
struct DocumentSelectionTranslationUITests {
    @Test("translated context menu enables only one-block non-empty selections")
    func contextMenuEligibility() {
        let textView = DocumentNSTextView()
        textView.isEditable = true
        textView.editorSide = .translation
        textView.textStorage?.setAttributedString(NSAttributedString(string: "Selected text", attributes: [
            DocumentTextAttribute.blockID: "block-1",
            DocumentTextAttribute.spanID: "span-1",
            DocumentTextAttribute.styleKey: "body",
            DocumentTextAttribute.translationPolicy: SpanTranslationPolicy.translate.rawValue,
            DocumentTextAttribute.inlineTraits: [String]()
        ]))
        textView.setSelectedRange(NSRange(location: 0, length: 8))

        let menu = textView.menu(for: NSEvent())
        let item = menu?.items.first(where: { $0.title == "Retranslate Selection with AI…" })
        #expect(item != nil)
        #expect(item?.isEnabled == true)
        #expect(menu?.items.contains(where: { $0.title == "Formatting" }) == false)
        textView.editorSide = .source
        #expect(textView.menu(for: NSEvent())?.items.contains(where: {
            $0.title == "Retranslate Selection with AI…"
        }) == false)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(textView.canRetranslateSelectionWithAI == false)
    }

    @Test("cross-block selection keeps AI command disabled")
    func crossBlockDisabled() {
        let textView = DocumentNSTextView()
        textView.isEditable = true
        textView.editorSide = .translation
        let storage = NSMutableAttributedString()
        storage.append(NSAttributedString(string: "One", attributes: [
            DocumentTextAttribute.blockID: "block-1",
            DocumentTextAttribute.spanID: "span-1",
            DocumentTextAttribute.inlineTraits: [String]()
        ]))
        storage.append(NSAttributedString(string: "\n\n", attributes: [
            DocumentTextAttribute.blockID: "block-2",
            DocumentTextAttribute.isBlockSeparator: true
        ]))
        storage.append(NSAttributedString(string: "Two", attributes: [
            DocumentTextAttribute.blockID: "block-2",
            DocumentTextAttribute.spanID: "span-2",
            DocumentTextAttribute.inlineTraits: [String]()
        ]))
        textView.textStorage?.setAttributedString(storage)
        textView.setSelectedRange(NSRange(location: 0, length: storage.length))

        #expect(textView.canRetranslateSelectionWithAI == false)
    }
}
