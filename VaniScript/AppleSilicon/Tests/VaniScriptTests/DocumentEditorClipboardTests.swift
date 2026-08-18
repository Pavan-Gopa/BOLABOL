import AppKit
import Foundation
import Testing
@testable import VaniScript
@testable import VaniScriptCore

@Suite("DocumentEditorClipboardTests (PRD §26.3)")
@MainActor
struct DocumentEditorClipboardTests {

    @Test("External plain paste inserts clean text with destination block identity")
    func externalPlainPaste() {
        let textView = DocumentNSTextView()
        textView.isEditable = true

        let pastedString = "Plain text from browser"
        let pboard = NSPasteboard(name: NSPasteboard.Name("test.plain.paste"))
        pboard.clearContents()
        pboard.setString(pastedString, forType: .string)

        let handled = textView.readSelection(from: pboard, type: .string)
        #expect(handled == true)
        #expect(textView.string == pastedString)
    }

    @Test("External rich paste extracts supported traits and strips raw attributes")
    func externalRichPaste() {
        let textView = DocumentNSTextView()

        let baseFont = NSFont.systemFont(ofSize: 14)
        let boldFontDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        let boldFont = NSFont(descriptor: boldFontDescriptor, size: 14) ?? baseFont

        let richString = NSMutableAttributedString(string: "Bold external text")
        richString.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: 4))
        richString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 5, length: 8))

        let sanitized = textView.sanitizePastedAttributedString(richString)

        // Internal VaniScript keys must not exist
        var hasInternalKeys = false
        sanitized.enumerateAttributes(in: NSRange(location: 0, length: sanitized.length), options: []) { attrs, _, _ in
            if attrs[DocumentTextAttribute.blockID] != nil ||
               attrs[DocumentTextAttribute.spanID] != nil ||
               attrs[DocumentTextAttribute.styleKey] != nil {
                hasInternalKeys = true
            }
        }
        #expect(!hasInternalKeys)

        // Extracted inline traits must be present
        let boldRunTraits = sanitized.attribute(DocumentTextAttribute.inlineTraits, at: 0, effectiveRange: nil) as? [String]
        #expect(boldRunTraits?.contains(InlineTrait.bold.rawValue) == true)

        let underlineRunTraits = sanitized.attribute(DocumentTextAttribute.inlineTraits, at: 5, effectiveRange: nil) as? [String]
        #expect(underlineRunTraits?.contains(InlineTrait.underline.rawValue) == true)
    }

    @Test("Internal paste strips duplicated BlockID and SpanID")
    func internalPasteStripsDuplicatedIDs() {
        let textView = DocumentNSTextView()

        // Construct internal copied attributed string that had private attributes
        let internalCopy = NSMutableAttributedString(string: "Copied internal paragraph")
        internalCopy.addAttribute(DocumentTextAttribute.blockID, value: "source-block-1", range: NSRange(location: 0, length: internalCopy.length))
        internalCopy.addAttribute(DocumentTextAttribute.spanID, value: "source-span-99", range: NSRange(location: 0, length: internalCopy.length))
        internalCopy.addAttribute(DocumentTextAttribute.styleKey, value: "Heading1", range: NSRange(location: 0, length: internalCopy.length))
        internalCopy.addAttribute(DocumentTextAttribute.translationPolicy, value: SpanTranslationPolicy.protect.rawValue, range: NSRange(location: 0, length: internalCopy.length))

        let sanitized = textView.sanitizePastedAttributedString(internalCopy)

        // Sanitization must have stripped source BlockID and SpanID
        sanitized.enumerateAttributes(in: NSRange(location: 0, length: sanitized.length), options: []) { attrs, _, _ in
            #expect(attrs[DocumentTextAttribute.blockID] == nil)
            #expect(attrs[DocumentTextAttribute.spanID] == nil)
            #expect(attrs[DocumentTextAttribute.styleKey] == nil)
            #expect(attrs[DocumentTextAttribute.translationPolicy] == nil)
        }
    }

    @Test("SpanID collision is impossible upon multiple pastes")
    func spanIDCollisionImpossible() {
        let textView = DocumentNSTextView()

        let text1 = textView.sanitizePastedAttributedString(NSAttributedString(string: "Fragment 1"))
        let text2 = textView.sanitizePastedAttributedString(NSAttributedString(string: "Fragment 2"))

        var spanIDsFound: Set<String> = []

        for piece in [text1, text2] {
            piece.enumerateAttributes(in: NSRange(location: 0, length: piece.length), options: []) { attrs, _, _ in
                if let id = attrs[DocumentTextAttribute.spanID] as? String {
                    spanIDsFound.insert(id)
                }
            }
        }

        // Sanitized pasted strings have NO span IDs (they get fresh IDs upon insertion/serialization into destination block)
        #expect(spanIDsFound.isEmpty)
    }

    @Test("Unsupported attributed keys are removed")
    func unsupportedAttributedKeysRemoved() {
        let textView = DocumentNSTextView()

        let customKey1 = NSAttributedString.Key("com.external.app.metadata")
        let customKey2 = NSAttributedString.Key("VaniScript.UnrecognizedSecret")

        let richString = NSMutableAttributedString(string: "Text with unsupported keys")
        richString.addAttribute(customKey1, value: "secret-data", range: NSRange(location: 0, length: 4))
        richString.addAttribute(customKey2, value: "internal-leak", range: NSRange(location: 5, length: 4))

        let sanitized = textView.sanitizePastedAttributedString(richString)

        sanitized.enumerateAttributes(in: NSRange(location: 0, length: sanitized.length), options: []) { attrs, _, _ in
            #expect(attrs[customKey1] == nil)
            #expect(attrs[customKey2] == nil)
        }
    }

    @Test("Destination block policy remains trusted after paste")
    func destinationPolicyRemainsTrusted() throws {
        // A destination block with translation policy
        let destinationBlock = DocumentBlock(
            id: "dest-block-1",
            location: DocumentLocation(paragraphOrdinal: 1),
            spans: [
                RichTextSpan(
                    id: "dest-span-1",
                    text: "Existing block content: ",
                    styleKey: "BodyText",
                    traits: [],
                    translationPolicy: .translateWithGlossary
                )
            ],
            sourceHash: "hash-1",
            translationPolicy: .translateWithGlossary
        )

        // Mutating destination block with pasted text
        let insertRange = DocumentSpanRange(spanID: "dest-span-1", location: 24, length: 0) // At end
        let mutatedSpans = try DocumentRichTextMutation.replace(
            spans: destinationBlock.spans,
            range: insertRange,
            with: "pasted user content.",
            policy: .inheritExisting
        )

        #expect(mutatedSpans.count == 1)
        #expect(mutatedSpans[0].text == "Existing block content: pasted user content.")
        #expect(mutatedSpans[0].translationPolicy == .translateWithGlossary)
        #expect(mutatedSpans[0].styleKey == "BodyText")
    }
}
