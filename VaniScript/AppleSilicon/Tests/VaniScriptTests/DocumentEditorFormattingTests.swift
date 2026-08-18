import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import VaniScript
@testable import VaniScriptCore

@Suite("DocumentEditorFormattingTests (PRD §26.2)")
@MainActor
struct DocumentEditorFormattingTests {

    @Test("Bold on and off toggle through mutation engine")
    func boldToggle() throws {
        let span = RichTextSpan(id: "s1", text: "Bold formatting test", traits: [])
        let range = DocumentSpanRange(spanID: "s1", location: 5, length: 10) // "formatting"

        // Toggle ON
        let boldOn = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [range], trait: .bold)
        #expect(boldOn.count == 3)
        #expect(boldOn[0].text == "Bold ")
        #expect(boldOn[0].traits.isEmpty)
        #expect(boldOn[1].text == "formatting")
        #expect(boldOn[1].traits == [.bold])
        #expect(boldOn[2].text == " test")
        #expect(boldOn[2].traits.isEmpty)

        // Toggle OFF on the bold piece
        let boldRange = DocumentSpanRange(spanID: boldOn[1].id, location: 0, length: 10)
        let boldOff = try DocumentRichTextMutation.toggleTrait(spans: boldOn, ranges: [boldRange], trait: .bold)
        #expect(boldOff.count == 1)
        #expect(boldOff[0].id == "s1")
        #expect(boldOff[0].text == "Bold formatting test")
        #expect(boldOff[0].traits.isEmpty)
    }

    @Test("Italic on and off toggle")
    func italicToggle() throws {
        let span = RichTextSpan(id: "s1", text: "Pure literary translation", traits: [])
        let range = DocumentSpanRange(spanID: "s1", location: 5, length: 8) // "literary"

        let italicOn = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [range], trait: .italic)
        #expect(italicOn.count == 3)
        #expect(italicOn[1].text == "literary")
        #expect(italicOn[1].traits == [.italic])

        let italicOff = try DocumentRichTextMutation.toggleTrait(
            spans: italicOn,
            ranges: [DocumentSpanRange(spanID: italicOn[1].id, location: 0, length: 8)],
            trait: .italic
        )
        #expect(italicOff.count == 1)
        #expect(italicOff[0].text == "Pure literary translation")
        #expect(italicOff[0].traits.isEmpty)
    }

    @Test("Underline, Strikethrough, and Small Caps toggles")
    func otherTraitsToggle() throws {
        let span = RichTextSpan(id: "s1", text: "Underline Strike SmallCaps", traits: [])

        let uRange = DocumentSpanRange(spanID: "s1", location: 0, length: 9) // "Underline"

        var current = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [uRange], trait: .underline)
        #expect(current[0].text == "Underline")
        #expect(current[0].traits.contains(.underline))

        let strikeTarget = current.first(where: { $0.text.contains("Strike") })!
        current = try DocumentRichTextMutation.toggleTrait(
            spans: current,
            ranges: [DocumentSpanRange(spanID: strikeTarget.id, location: 1, length: 6)],
            trait: .strikethrough
        )
        let strikePiece = current.first(where: { $0.text == "Strike" })!
        #expect(strikePiece.traits.contains(.strikethrough))

        let scTarget = current.first(where: { $0.text.contains("SmallCaps") })!
        current = try DocumentRichTextMutation.toggleTrait(
            spans: current,
            ranges: [DocumentSpanRange(spanID: scTarget.id, location: 1, length: 9)],
            trait: .smallCaps
        )
        let scPiece = current.first(where: { $0.text == "SmallCaps" })!
        #expect(scPiece.traits.contains(.smallCaps))
    }

    @Test("Superscript and Subscript mutual exclusion")
    func superAndSubscriptMutualExclusion() throws {
        let span = RichTextSpan(id: "s1", text: "Formula H2O is water", traits: [])
        let range = DocumentSpanRange(spanID: "s1", location: 9, length: 1) // "2"

        // Apply subscript: H₂O
        let sub = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [range], trait: .subscriptText)
        let twoSub = sub.first(where: { $0.text == "2" })!
        #expect(twoSub.traits.contains(.subscriptText))
        #expect(!twoSub.traits.contains(.superscript))

        // Now toggle superscript on that same '2' -> subscript must be cleared
        let superRange = DocumentSpanRange(spanID: twoSub.id, location: 0, length: 1)
        let superResult = try DocumentRichTextMutation.toggleTrait(
            spans: sub,
            ranges: [superRange],
            trait: .superscript
        )
        let twoSuper = superResult.first(where: { $0.text == "2" })!
        #expect(twoSuper.traits.contains(.superscript))
        #expect(!twoSuper.traits.contains(.subscriptText))
    }

    @Test("Clear manual formatting removes overrides and restores base")
    func clearFormattingRestoresBase() throws {
        let span = RichTextSpan(
            id: "styled-1",
            text: "Important Notice",
            styleKey: "BodyStyle",
            traits: [.bold, .underline],
            translationPolicy: .translate,
            foregroundColorHex: "CC0000",
            editorOverrides: EditorInlineOverrides(traitOverrides: [.bold: true, .underline: true], foregroundColorOverride: "CC0000")
        )

        let cleared = try DocumentRichTextMutation.clearFormatting(
            spans: [span],
            ranges: [DocumentSpanRange(spanID: "styled-1", location: 0, length: 16)]
        )

        #expect(cleared.count == 1)
        #expect(cleared[0].id == "styled-1")
        #expect(cleared[0].text == "Important Notice")
        #expect(cleared[0].traits.isEmpty)
        #expect(cleared[0].foregroundColorHex == nil)
        #expect(cleared[0].editorOverrides == nil)
        #expect(cleared[0].styleKey == "BodyStyle")
    }

    @Test("Formatting across multiple spans in a block")
    func formattingAcrossMultipleSpans() throws {
        let span1 = RichTextSpan(id: "s1", text: "Hello ", traits: [])
        let span2 = RichTextSpan(id: "s2", text: "beautiful ", traits: [])
        let span3 = RichTextSpan(id: "s3", text: "World", traits: [.italic])

        // Format whole span1, span2, and first 2 chars of span3 with bold
        let ranges = [
            DocumentSpanRange(spanID: "s1", location: 0, length: 6),  // "Hello "
            DocumentSpanRange(spanID: "s2", location: 0, length: 10), // "beautiful "
            DocumentSpanRange(spanID: "s3", location: 0, length: 2)   // "Wo"
        ]

        let mutated = try DocumentRichTextMutation.toggleTrait(spans: [span1, span2, span3], ranges: ranges, trait: .bold)

        // "Hello " and "beautiful " now have identical formatting and overrides, merging into s1!
        #expect(mutated[0].id == "s1")
        #expect(mutated[0].text == "Hello beautiful ")
        #expect(mutated[0].traits == [.bold])

        // The "Wo" piece was italic, now [.italic, .bold]
        let woPiece = mutated.first(where: { $0.text == "Wo" })!
        #expect(woPiece.traits == [.italic, .bold])

        // The "rld" piece was italic, stays [.italic]
        let rldPiece = mutated.first(where: { $0.text == "rld" })!
        #expect(rldPiece.traits == [.italic])
    }

    @Test("Formatting across block boundary never formats block separators")
    func formattingAcrossBlockBoundary() throws {
        // Create attributed string as Coordinator does
        let attrString = NSMutableAttributedString()
        let b1Attrs: [NSAttributedString.Key: Any] = [
            DocumentTextAttribute.blockID: "b1",
            DocumentTextAttribute.spanID: "s1",
            DocumentTextAttribute.inlineTraits: [String]()
        ]
        attrString.append(NSAttributedString(string: "First paragraph.", attributes: b1Attrs))

        let sepAttrs: [NSAttributedString.Key: Any] = [
            DocumentTextAttribute.isBlockSeparator: true,
            DocumentTextAttribute.blockID: "b2"
        ]
        attrString.append(NSAttributedString(string: "\n\n", attributes: sepAttrs))

        let b2Attrs: [NSAttributedString.Key: Any] = [
            DocumentTextAttribute.blockID: "b2",
            DocumentTextAttribute.spanID: "s2",
            DocumentTextAttribute.inlineTraits: [String]()
        ]
        attrString.append(NSAttributedString(string: "Second paragraph.", attributes: b2Attrs))

        // Select from "paragraph." of b1 through separator to "Second" of b2
        let fullStr = attrString.string as NSString
        let selRange = fullStr.range(of: "paragraph.\n\nSecond")
        #expect(selRange.location != NSNotFound)

        let snapshot = DocumentSelectionBridge.buildSnapshot(
            from: attrString,
            selectedRange: selRange,
            side: .source
        )

        // Fragments must only contain text from b1 and b2, NEVER the "\n\n" separator
        #expect(snapshot.fragments.count == 2)
        #expect(snapshot.fragments[0].blockID == "b1")
        #expect(snapshot.fragments[0].text == "paragraph.")
        #expect(snapshot.fragments[1].blockID == "b2")
        #expect(snapshot.fragments[1].text == "Second")

        // Separator is not in selectedText
        #expect(!snapshot.fragments.map(\.text).joined().contains("\n\n"))
    }


    @Test("DocumentSelectionBridge block hashes are deterministic SHA-256 and preserve editor side")
    func deterministicBlockHashesAndSideParameter() {
        let text1 = "First block text for hashing."
        let text2 = "Second block text with different content."

        let attrString = NSMutableAttributedString()
        attrString.append(NSAttributedString(
            string: text1,
            attributes: [
                DocumentTextAttribute.blockID: "block-1",
                DocumentTextAttribute.spanID: "span-1",
                DocumentTextAttribute.inlineTraits: [String]()
            ]
        ))
        attrString.append(NSAttributedString(
            string: "\n\n",
            attributes: [
                DocumentTextAttribute.isBlockSeparator: true,
                DocumentTextAttribute.blockID: "block-2"
            ]
        ))
        attrString.append(NSAttributedString(
            string: text2,
            attributes: [
                DocumentTextAttribute.blockID: "block-2",
                DocumentTextAttribute.spanID: "span-2",
                DocumentTextAttribute.inlineTraits: [String]()
            ]
        ))

        let fullLen = (attrString.string as NSString).length
        let selRange = NSRange(location: 0, length: fullLen)

        let snapshotSource1 = DocumentSelectionBridge.buildSnapshot(
            from: attrString,
            selectedRange: selRange,
            side: .source
        )

        #expect(snapshotSource1.side == .source)
        guard let hash1 = snapshotSource1.blockHashes["block-1"],
              let hash2 = snapshotSource1.blockHashes["block-2"] else {
            Issue.record("Expected blockHashes for block-1 and block-2")
            return
        }

        // SHA-256 hex string is 64 lowercase hex characters
        #expect(hash1.count == 64)
        let isHex1 = hash1.allSatisfy { $0.isHexDigit }
        let isHex2 = hash2.allSatisfy { $0.isHexDigit }
        #expect(isHex1)
        #expect(hash2.count == 64)
        #expect(isHex2)
        #expect(hash1 != hash2)

        let expectedHash1 = SHA256.hash(data: Data(text1.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(hash1 == expectedHash1)

        // Determinism check: same input always produces identical hash
        let snapshotSource2 = DocumentSelectionBridge.buildSnapshot(
            from: attrString,
            selectedRange: selRange,
            side: .source
        )
        #expect(snapshotSource2.blockHashes["block-1"] == hash1)
        #expect(snapshotSource2.blockHashes["block-2"] == hash2)

        // Side preservation for translation
        let snapshotTranslation = DocumentSelectionBridge.buildSnapshot(
            from: attrString,
            selectedRange: selRange,
            side: .translation
        )
        #expect(snapshotTranslation.side == .translation)
        #expect(snapshotTranslation.blockHashes["block-1"] == hash1)
    }

    @Test("DocumentAttributedTextView makeNSView wires scrollView.documentView correctly")
    func makeNSViewDocumentViewWiring() {
        var text = "Hello document view"
        let binding = Binding(get: { text }, set: { text = $0 })
        let block = DocumentEditorBlockItem(
            id: "b1",
            spans: [RichTextSpan(id: "s1", text: "Hello document view", traits: [])],
            fallbackText: "Hello document view"
        )

        let view = DocumentAttributedTextView(
            text: binding,
            blocks: [block],
            onBlocksChanged: nil,
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0,
            side: .translation
        )
        #expect(view.side == .translation)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()

        func findScrollView(_ v: NSView) -> NSScrollView? {
            if let sv = v as? NSScrollView { return sv }
            for sub in v.subviews {
                if let found = findScrollView(sub) { return found }
            }
            return nil
        }

        let scrollView = findScrollView(hostingView)
        #expect(scrollView != nil)
        #expect(scrollView?.documentView != nil)
        #expect(scrollView?.documentView is DocumentNSTextView)
        #expect((scrollView?.documentView as? DocumentNSTextView)?.string == "Hello document view")
    }

    @Test("applyMutation failure leaves model unchanged and records error honestly")
    func honestApplyMutationFailure() {
        enum TestMutationError: Error {
            case intentionalFailure
        }

        var text = "Unmodified text"
        var callbackCalled = false
        let binding = Binding(get: { text }, set: { text = $0 })
        let block = DocumentEditorBlockItem(
            id: "b1",
            spans: [RichTextSpan(id: "s1", text: "Unmodified text", traits: [])],
            fallbackText: "Unmodified text"
        )

        let view = DocumentAttributedTextView(
            text: binding,
            blocks: [block],
            onBlocksChanged: { _, _ in
                callbackCalled = true
            },
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0,
            side: .source
        )

        let coordinator = view.makeCoordinator()
        let textView = DocumentNSTextView()
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.setAttributedString(from: [block], fallbackText: text, textView: textView)

        #expect(coordinator.lastMutationError == nil)

        // Attempt failing mutation
        coordinator.applyMutation { _ in
            throw TestMutationError.intentionalFailure
        }

        // Failure must be honest: error recorded, model untouched, no callback
        #expect(coordinator.lastMutationError != nil)
        #expect(text == "Unmodified text")
        #expect(callbackCalled == false)
        #expect(textView.string == "Unmodified text")
    }
}
