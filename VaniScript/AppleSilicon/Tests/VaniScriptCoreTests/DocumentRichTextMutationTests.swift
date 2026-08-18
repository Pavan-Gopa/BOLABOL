import Foundation
import Testing
@testable import VaniScriptCore

@Suite("DocumentRichTextMutationTests (PRD §26.1)")
struct DocumentRichTextMutationTests {

    @Test("replace inside one span preserves span ID")
    func replaceInsideOneSpan() throws {
        let span = RichTextSpan(id: "span-1", text: "The sacred mantra", styleKey: "Heading1", traits: [.bold])
        let range = DocumentSpanRange(spanID: "span-1", location: 4, length: 6) // "sacred"

        let mutated = try DocumentRichTextMutation.replace(spans: [span], range: range, with: "divine")

        #expect(mutated.count == 1)
        #expect(mutated[0].id == "span-1")
        #expect(mutated[0].text == "The divine mantra")
        #expect(mutated[0].traits == [.bold])
        #expect(mutated[0].styleKey == "Heading1")
    }

    @Test("replace at beginning and end of span")
    func replaceAtBeginningAndEnd() throws {
        let span = RichTextSpan(id: "span-1", text: "Hello World", traits: [.italic])

        // Replace at beginning: "Hello" -> "Greetings"
        let atStart = try DocumentRichTextMutation.replace(
            spans: [span],
            range: DocumentSpanRange(spanID: "span-1", location: 0, length: 5),
            with: "Greetings"
        )
        #expect(atStart.count == 1)
        #expect(atStart[0].id == "span-1")
        #expect(atStart[0].text == "Greetings World")
        #expect(atStart[0].traits == [.italic])

        // Replace at end: "World" -> "Universe"
        let atEnd = try DocumentRichTextMutation.replace(
            spans: atStart,
            range: DocumentSpanRange(spanID: "span-1", location: 10, length: 5),
            with: "Universe"
        )
        #expect(atEnd.count == 1)
        #expect(atEnd[0].id == "span-1")
        #expect(atEnd[0].text == "Greetings Universe")
        #expect(atEnd[0].traits == [.italic])
    }

    @Test("replacement across identical adjacent spans merges into single span with first ID")
    func replacementAcrossIdenticalSpans() throws {
        let span1 = RichTextSpan(id: "span-1", text: "Hello ", traits: [.bold])
        let span2 = RichTextSpan(id: "span-2", text: "World", traits: [.bold])

        let normalized = DocumentRichTextMutation.normalize([span1, span2])
        #expect(normalized.count == 1)
        #expect(normalized[0].id == "span-1")
        #expect(normalized[0].text == "Hello World")
        #expect(normalized[0].traits == [.bold])
    }

    @Test("formatting selection splits into 3 spans, left keeping original ID")
    func formattingSelectionSplit() throws {
        let span = RichTextSpan(id: "span-A", text: "The sacred name is Krishna today", traits: [])
        // Select "Krishna" at location 19, length 7
        let range = DocumentSpanRange(spanID: "span-A", location: 19, length: 7)

        let mutated = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [range], trait: .italic)

        #expect(mutated.count == 3)
        #expect(mutated[0].id == "span-A")
        #expect(mutated[0].text == "The sacred name is ")
        #expect(mutated[0].traits == [])

        #expect(mutated[1].id != "span-A")
        #expect(mutated[1].text == "Krishna")
        #expect(mutated[1].traits == [.italic])

        #expect(mutated[2].id != "span-A")
        #expect(mutated[2].id != mutated[1].id)
        #expect(mutated[2].text == " today")
        #expect(mutated[2].traits == [])
    }

    @Test("repeated toggle does not churn IDs and merges back to original ID")
    func repeatedToggleDoesNotChurnIDs() throws {
        let initialSpan = RichTextSpan(id: "span-root", text: "The sacred name is Krishna today", traits: [])
        let range = DocumentSpanRange(spanID: "span-root", location: 19, length: 7) // "Krishna"

        // 1st toggle: turn italic ON for "Krishna"
        let splitResult = try DocumentRichTextMutation.toggleTrait(spans: [initialSpan], ranges: [range], trait: .italic)
        #expect(splitResult.count == 3)
        #expect(splitResult[0].id == "span-root")
        let italicSpanID = splitResult[1].id

        // 2nd toggle: select the italicized "Krishna" span and toggle italic OFF
        let secondRange = DocumentSpanRange(spanID: italicSpanID, location: 0, length: 7)
        let toggledBack = try DocumentRichTextMutation.toggleTrait(spans: splitResult, ranges: [secondRange], trait: .italic)

        // Normalization should merge everything back into a single span with the root ID
        #expect(toggledBack.count == 1)
        #expect(toggledBack[0].id == "span-root")
        #expect(toggledBack[0].text == "The sacred name is Krishna today")
        #expect(toggledBack[0].traits.isEmpty)
    }

    @Test("normalization merges equivalent spans and drops empty ones")
    func normalizationMergesEquivalentSpans() {
        let spans = [
            RichTextSpan(id: "s1", text: "Hello ", styleKey: "p", traits: [.bold], foregroundColorHex: "FF0000"),
            RichTextSpan(id: "s2", text: "", styleKey: "p", traits: [.bold], foregroundColorHex: "FF0000"),
            RichTextSpan(id: "s3", text: "World", styleKey: "p", traits: [.bold], foregroundColorHex: "FF0000"),
            RichTextSpan(id: "s4", text: "!", styleKey: "p", traits: [.italic], foregroundColorHex: "FF0000")
        ]

        let normalized = DocumentRichTextMutation.normalize(spans)
        #expect(normalized.count == 2)
        #expect(normalized[0].id == "s1")
        #expect(normalized[0].text == "Hello World")
        #expect(normalized[0].traits == [.bold])

        #expect(normalized[1].id == "s4")
        #expect(normalized[1].text == "!")
        #expect(normalized[1].traits == [.italic])
    }

    @Test("protected span stays untouched in replaceAll")
    func protectedSpanUntouchedInReplaceAll() throws {
        let spans = [
            RichTextSpan(id: "s1", text: "Hare Krishna, ", translationPolicy: .translate),
            RichTextSpan(id: "s2", text: "Hare Krishna", translationPolicy: .protect),
            RichTextSpan(id: "s3", text: ", Krishna Krishna", translationPolicy: .translate)
        ]

        let match1 = DocumentTextMatch(
            side: .source,
            blockID: "b1",
            spanRanges: [DocumentSpanRange(spanID: "s1", location: 5, length: 7)], // "Krishna"
            matchedText: "Krishna",
            protectedMatch: false
        )
        let match2 = DocumentTextMatch(
            side: .source,
            blockID: "b1",
            spanRanges: [DocumentSpanRange(spanID: "s2", location: 5, length: 7)], // "Krishna"
            matchedText: "Krishna",
            protectedMatch: true
        )
        let match3 = DocumentTextMatch(
            side: .source,
            blockID: "b1",
            spanRanges: [DocumentSpanRange(spanID: "s3", location: 2, length: 7)], // "Krishna"
            matchedText: "Krishna",
            protectedMatch: false
        )

        let result = try DocumentRichTextMutation.replaceAll(
            spans: spans,
            matches: [match1, match2, match3],
            replacement: "Rama"
        )

        #expect(result.replacedCount == 2)
        #expect(result.skippedProtectedCount == 1)
        #expect(result.spans.count == 3)
        #expect(result.spans[0].text == "Hare Rama, ")
        #expect(result.spans[1].text == "Hare Krishna") // Protected span was not replaced
        #expect(result.spans[1].translationPolicy == .protect)
        #expect(result.spans[2].text == ", Rama Krishna")
    }

    @Test("Bengali and Devanagari combining marks survive mutation")
    func indicCombiningMarksSurvive() throws {
        // Bengali text: শ্রীচৈতন্যচরিতামৃত (Sri Chaitanya Charitamrita)
        let bengaliSpan = RichTextSpan(id: "bengali-1", text: "জয় শ্রীচৈতন্য জয় নিত্যানন্দ", traits: [])
        let nsText = bengaliSpan.text as NSString
        let targetRange = nsText.range(of: "শ্রীচৈতন্য")

        #expect(targetRange.location != NSNotFound)

        let mutated = try DocumentRichTextMutation.toggleTrait(
            spans: [bengaliSpan],
            ranges: [DocumentSpanRange(spanID: "bengali-1", utf16Range: targetRange)],
            trait: .bold
        )

        #expect(mutated.count == 3)
        #expect(mutated[1].text == "শ্রীচৈতন্য")
        #expect(mutated[1].traits == [.bold])

        // Devanagari text: श्रीमद्भगवद्गीता
        let devanagariSpan = RichTextSpan(id: "deva-1", text: "अथ श्रीमद्भगवद्गीता प्रथमोऽध्यायः", traits: [])
        let devaNS = devanagariSpan.text as NSString
        let devaRange = devaNS.range(of: "श्रीमद्भगवद्गीता")

        let devaMutated = try DocumentRichTextMutation.toggleTrait(
            spans: [devanagariSpan],
            ranges: [DocumentSpanRange(spanID: "deva-1", utf16Range: devaRange)],
            trait: .italic
        )

        #expect(devaMutated.count == 3)
        #expect(devaMutated[1].text == "श्रीमद्भगवद्गीता")
        #expect(devaMutated[1].traits == [.italic])
    }

    @Test("selection at surrogate-pair boundaries")
    func surrogatePairBoundarySafety() throws {
        // Emoji: 🌟 (U+1F31F) is 2 UTF-16 code units
        let textWithEmoji = "Star 🌟 Glow"
        let span = RichTextSpan(id: "emoji-span", text: textWithEmoji, traits: [])

        // If a range requests the whole emoji at UTF-16 [5, 2]
        let emojiRange = DocumentSpanRange(spanID: "emoji-span", location: 5, length: 2)
        let formatted = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [emojiRange], trait: .bold)

        #expect(formatted.count == 3)
        #expect(formatted[0].text == "Star ")
        #expect(formatted[1].text == "🌟")
        #expect(formatted[1].traits == [.bold])
        #expect(formatted[2].text == " Glow")
    }

    @Test("color, styleKey, and translationPolicy survive mutation")
    func metadataSurvivesMutation() throws {
        let span = RichTextSpan(
            id: "meta-span",
            text: "Important Notice for Readers",
            styleKey: "SpecialCallout",
            traits: [.italic],
            translationPolicy: .translateWithGlossary,
            foregroundColorHex: "336699"
        )

        let range = DocumentSpanRange(spanID: "meta-span", location: 10, length: 6) // "Notice"
        let mutated = try DocumentRichTextMutation.toggleTrait(spans: [span], ranges: [range], trait: .bold)

        #expect(mutated.count == 3)
        for piece in mutated {
            #expect(piece.styleKey == "SpecialCallout")
            #expect(piece.translationPolicy == .translateWithGlossary)
            #expect(piece.foregroundColorHex == "336699")
        }
        #expect(mutated[1].traits == [.italic, .bold])
    }

    @Test("superscript and subscript are mutually exclusive")
    func superscriptSubscriptMutualExclusion() throws {
        let span = RichTextSpan(id: "math-span", text: "x2 + y2", traits: [])

        // Apply superscript to the first '2' at loc 1, len 1
        let step1 = try DocumentRichTextMutation.toggleTrait(
            spans: [span],
            ranges: [DocumentSpanRange(spanID: "math-span", location: 1, length: 1)],
            trait: .superscript
        )
        #expect(step1.count == 3)
        #expect(step1[1].text == "2")
        #expect(step1[1].traits.contains(.superscript))
        #expect(!step1[1].traits.contains(.subscriptText))

        // Now apply subscript to the same '2' span
        let subRange = DocumentSpanRange(spanID: step1[1].id, location: 0, length: 1)
        let step2 = try DocumentRichTextMutation.toggleTrait(
            spans: step1,
            ranges: [subRange],
            trait: .subscriptText
        )

        #expect(step2.count == 3)
        #expect(step2[1].text == "2")
        #expect(step2[1].traits.contains(.subscriptText))
        #expect(!step2[1].traits.contains(.superscript))
    }

    @Test("clear formatting removes overrides and resets traits")
    func clearFormattingResetsTraits() throws {
        let span = RichTextSpan(
            id: "styled-span",
            text: "Heavily styled text fragment",
            styleKey: "BodyText",
            traits: [.bold, .italic, .underline],
            translationPolicy: .translate,
            foregroundColorHex: "FF5500",
            editorOverrides: EditorInlineOverrides(traitOverrides: [.bold: true], foregroundColorOverride: "FF5500")
        )

        let range = DocumentSpanRange(spanID: "styled-span", location: 8, length: 6) // "styled"
        let cleared = try DocumentRichTextMutation.clearFormatting(spans: [span], ranges: [range])

        #expect(cleared.count == 3)
        #expect(cleared[1].text == "styled")
        #expect(cleared[1].traits.isEmpty)
        #expect(cleared[1].foregroundColorHex == nil)
        #expect(cleared[1].editorOverrides == nil)
        #expect(cleared[1].styleKey == "BodyText") // preserved
    }

    @Test("EditorInlineOverrides Codable round trip with old and new schemas")
    func editorInlineOverridesCodableRoundTrip() throws {
        let overrides = EditorInlineOverrides(
            traitOverrides: [.bold: true, .italic: false],
            foregroundColorOverride: "00AAFF",
            clearsForegroundColor: false
        )

        let span = RichTextSpan(
            id: "test-span",
            text: "Sample",
            styleKey: "Normal",
            traits: [.bold],
            translationPolicy: .translate,
            foregroundColorHex: "00AAFF",
            editorOverrides: overrides
        )

        let data = try JSONEncoder().encode(span)
        let decoded = try JSONDecoder().decode(RichTextSpan.self, from: data)

        #expect(decoded.id == "test-span")
        #expect(decoded.editorOverrides?.traitOverrides[.bold] == true)
        #expect(decoded.editorOverrides?.traitOverrides[.italic] == false)
        #expect(decoded.editorOverrides?.foregroundColorOverride == "00AAFF")

        // Old schema without editorOverrides decodes to nil cleanly
        let legacyJSON = """
        {"id":"legacy-1","text":"Old bundle text","styleKey":"","traits":["italic"],"translationPolicy":"translate"}
        """.data(using: .utf8)!

        let legacySpan = try JSONDecoder().decode(RichTextSpan.self, from: legacyJSON)
        #expect(legacySpan.id == "legacy-1")
        #expect(legacySpan.traits == [.italic])
        #expect(legacySpan.editorOverrides == nil)
    }
}
