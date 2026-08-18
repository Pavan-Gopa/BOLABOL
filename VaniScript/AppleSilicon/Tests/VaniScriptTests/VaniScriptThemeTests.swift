import Foundation
import AppKit
import SwiftUI
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("VaniScript Theme & Dynamic Appearance Tests")
struct VaniScriptThemeTests {

    // MARK: - Helper Functions

    private func resolveNSColor(_ color: Color, appearance: NSAppearance) -> NSColor {
        var resolved: NSColor = .black
        appearance.performAsCurrentDrawingAppearance {
            let nsColor = NSColor(color)
            resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return resolved
    }

    private func relativeLuminance(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func sRGBtoLinear(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = sRGBtoLinear(rgb.redComponent)
        let g = sRGBtoLinear(rgb.greenComponent)
        let b = sRGBtoLinear(rgb.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func compositeColor(_ fg: NSColor, over bg: NSColor) -> NSColor {
        guard let fgRGB = fg.usingColorSpace(.sRGB),
              let bgRGB = bg.usingColorSpace(.sRGB) else { return fg }
        let a = fgRGB.alphaComponent
        let r = fgRGB.redComponent * a + bgRGB.redComponent * (1 - a)
        let g = fgRGB.greenComponent * a + bgRGB.greenComponent * (1 - a)
        let b = fgRGB.blueComponent * a + bgRGB.blueComponent * (1 - a)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    private func contrastRatio(between c1: NSColor, and c2: NSColor) -> CGFloat {
        let l1 = relativeLuminance(of: c1)
        let l2 = relativeLuminance(of: c2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Palette Contrast & Legibility Tests

    @Test("Light mode (Aqua) text and surface contrast meets WCAG thresholds")
    func lightModeContrast() throws {
        guard let aqua = NSAppearance(named: .aqua) else {
            Issue.record("Failed to create Aqua NSAppearance")
            return
        }

        let bg = resolveNSColor(VaniScriptTheme.background, appearance: aqua)
        let card = resolveNSColor(VaniScriptTheme.card, appearance: aqua)
        let bar = resolveNSColor(VaniScriptTheme.barSurface, appearance: aqua)
        let editor = resolveNSColor(VaniScriptTheme.editorSurface, appearance: aqua)

        let text0 = resolveNSColor(VaniScriptTheme.text0, appearance: aqua)
        let text1 = resolveNSColor(VaniScriptTheme.text1, appearance: aqua)
        let text2 = resolveNSColor(VaniScriptTheme.text2, appearance: aqua)
        let onAccent = resolveNSColor(VaniScriptTheme.onAccent, appearance: aqua)
        let accent = resolveNSColor(VaniScriptTheme.accent, appearance: aqua)

        // text0 (primary) > 7:1 AAA
        let text0OnBg = contrastRatio(between: text0, and: bg)
        let text0OnCard = contrastRatio(between: text0, and: card)
        let text0OnBar = contrastRatio(between: text0, and: bar)
        let text0OnEditor = contrastRatio(between: text0, and: editor)

        #expect(text0OnBg >= 7.0, "text0 on background contrast was \(text0OnBg)")
        #expect(text0OnCard >= 7.0, "text0 on card contrast was \(text0OnCard)")
        #expect(text0OnBar >= 7.0, "text0 on barSurface contrast was \(text0OnBar)")
        #expect(text0OnEditor >= 7.0, "text0 on editorSurface contrast was \(text0OnEditor)")

        // text1 (secondary) >= 4.5:1 AA
        let text1OnBg = contrastRatio(between: text1, and: bg)
        let text1OnCard = contrastRatio(between: text1, and: card)
        let text1OnBar = contrastRatio(between: text1, and: bar)

        #expect(text1OnBg >= 4.5, "text1 on background contrast was \(text1OnBg)")
        #expect(text1OnCard >= 4.5, "text1 on card contrast was \(text1OnCard)")
        #expect(text1OnBar >= 4.5, "text1 on barSurface contrast was \(text1OnBar)")

        // text2 (tertiary/caption) >= 4.5:1 AA
        let text2OnBg = contrastRatio(between: text2, and: bg)
        let text2OnCard = contrastRatio(between: text2, and: card)

        #expect(text2OnBg >= 4.5, "text2 on background contrast was \(text2OnBg)")
        #expect(text2OnCard >= 4.5, "text2 on card contrast was \(text2OnCard)")

        // onAccent on accent >= 7.0 (AAA)
        let onAccentContrast = contrastRatio(between: onAccent, and: accent)
        #expect(onAccentContrast >= 7.0, "onAccent on accent contrast was \(onAccentContrast)")
    }

    @Test("Dark mode (Dark Aqua) text and surface contrast meets WCAG thresholds")
    func darkModeContrast() throws {
        guard let darkAqua = NSAppearance(named: .darkAqua) else {
            Issue.record("Failed to create Dark Aqua NSAppearance")
            return
        }

        let bg = resolveNSColor(VaniScriptTheme.background, appearance: darkAqua)
        let card = resolveNSColor(VaniScriptTheme.card, appearance: darkAqua)
        let bar = resolveNSColor(VaniScriptTheme.barSurface, appearance: darkAqua)
        let editor = resolveNSColor(VaniScriptTheme.editorSurface, appearance: darkAqua)

        let text0 = resolveNSColor(VaniScriptTheme.text0, appearance: darkAqua)
        let text1 = resolveNSColor(VaniScriptTheme.text1, appearance: darkAqua)
        let text2 = resolveNSColor(VaniScriptTheme.text2, appearance: darkAqua)
        let onAccent = resolveNSColor(VaniScriptTheme.onAccent, appearance: darkAqua)
        let accent = resolveNSColor(VaniScriptTheme.accent, appearance: darkAqua)

        // text0 (primary) > 7:1 AAA
        let text0OnBg = contrastRatio(between: text0, and: bg)
        let text0OnCard = contrastRatio(between: text0, and: card)
        let text0OnBar = contrastRatio(between: text0, and: bar)
        let text0OnEditor = contrastRatio(between: text0, and: editor)

        #expect(text0OnBg >= 7.0, "text0 on background contrast was \(text0OnBg)")
        #expect(text0OnCard >= 7.0, "text0 on card contrast was \(text0OnCard)")
        #expect(text0OnBar >= 7.0, "text0 on barSurface contrast was \(text0OnBar)")
        #expect(text0OnEditor >= 7.0, "text0 on editorSurface contrast was \(text0OnEditor)")

        // text1 (secondary) >= 4.5:1 AA
        let text1OnBg = contrastRatio(between: text1, and: bg)
        let text1OnCard = contrastRatio(between: text1, and: card)
        let text1OnBar = contrastRatio(between: text1, and: bar)

        #expect(text1OnBg >= 4.5, "text1 on background contrast was \(text1OnBg)")
        #expect(text1OnCard >= 4.5, "text1 on card contrast was \(text1OnCard)")
        #expect(text1OnBar >= 4.5, "text1 on barSurface contrast was \(text1OnBar)")

        // text2 (tertiary/caption) >= 4.5:1 AA
        let text2OnBg = contrastRatio(between: text2, and: bg)
        let text2OnCard = contrastRatio(between: text2, and: card)

        #expect(text2OnBg >= 4.5, "text2 on background contrast was \(text2OnBg)")
        #expect(text2OnCard >= 4.5, "text2 on card contrast was \(text2OnCard)")

        // onAccent on accent >= 7.0 (AAA)
        let onAccentContrast = contrastRatio(between: onAccent, and: accent)
        #expect(onAccentContrast >= 7.0, "onAccent on accent contrast was \(onAccentContrast)")
    }

    @Test("Status and error colors provide legible contrast in both appearances")
    func statusAndErrorContrast() throws {
        guard let aqua = NSAppearance(named: .aqua),
              let darkAqua = NSAppearance(named: .darkAqua) else {
            Issue.record("Failed to create NSAppearance instances")
            return
        }

        for appearance in [aqua, darkAqua] {
            let bg = resolveNSColor(VaniScriptTheme.background, appearance: appearance)
            let errText = resolveNSColor(VaniScriptTheme.errorText, appearance: appearance)
            let warnText = resolveNSColor(VaniScriptTheme.warningText, appearance: appearance)
            let succText = resolveNSColor(VaniScriptTheme.successText, appearance: appearance)

            let errBg = compositeColor(resolveNSColor(VaniScriptTheme.errorSurface, appearance: appearance), over: bg)
            let warnBg = compositeColor(resolveNSColor(VaniScriptTheme.warningSurface, appearance: appearance), over: bg)
            let succBg = compositeColor(resolveNSColor(VaniScriptTheme.successSurface, appearance: appearance), over: bg)

            let errOnBg = contrastRatio(between: errText, and: bg)
            let warnOnBg = contrastRatio(between: warnText, and: bg)
            let succOnBg = contrastRatio(between: succText, and: bg)

            #expect(errOnBg >= 4.5, "Error text on background contrast was \(errOnBg)")
            #expect(warnOnBg >= 4.0, "Warning text on background contrast was \(warnOnBg)")
            #expect(succOnBg >= 4.5, "Success text on background contrast was \(succOnBg)")

            let errOnErrBg = contrastRatio(between: errText, and: errBg)
            let warnOnWarnBg = contrastRatio(between: warnText, and: warnBg)
            let succOnSuccBg = contrastRatio(between: succText, and: succBg)

            #expect(errOnErrBg >= 3.0, "Error text on error surface contrast was \(errOnErrBg)")
            #expect(warnOnWarnBg >= 3.0, "Warning text on warning surface contrast was \(warnOnWarnBg)")
            #expect(succOnSuccBg >= 3.0, "Success text on success surface contrast was \(succOnSuccBg)")
        }
    }

    @Test("Control surfaces and borders are distinguishable from parent surfaces in both appearances")
    func controlAndBorderDistinguishability() throws {
        guard let aqua = NSAppearance(named: .aqua),
              let darkAqua = NSAppearance(named: .darkAqua) else {
            Issue.record("Failed to create NSAppearance instances")
            return
        }

        for appearance in [aqua, darkAqua] {
            let normal = resolveNSColor(VaniScriptTheme.control, appearance: appearance)
            let pressed = resolveNSColor(VaniScriptTheme.controlPressed, appearance: appearance)
            let border = resolveNSColor(VaniScriptTheme.controlBorder, appearance: appearance)

            // Normal and pressed states have different opacities/luminance
            let normalLum = relativeLuminance(of: normal)
            let pressedLum = relativeLuminance(of: pressed)
            #expect(normal != pressed || normalLum != pressedLum, "Normal and pressed control states must be distinguishable")

            // Control border is non-zero alpha
            #expect(border.alphaComponent > 0.05, "Control border must be visible")
        }
    }

    @Test("Disabled text and surfaces meet >=3:1 contrast in Aqua and Dark Aqua")
    func disabledStateContrast() throws {
        guard let aqua = NSAppearance(named: .aqua),
              let darkAqua = NSAppearance(named: .darkAqua) else {
            Issue.record("Failed to create NSAppearance instances")
            return
        }

        for appearance in [aqua, darkAqua] {
            let bg = resolveNSColor(VaniScriptTheme.background, appearance: appearance)
            let card = compositeColor(resolveNSColor(VaniScriptTheme.card, appearance: appearance), over: bg)
            let bar = compositeColor(resolveNSColor(VaniScriptTheme.barSurface, appearance: appearance), over: bg)
            let control = compositeColor(resolveNSColor(VaniScriptTheme.control, appearance: appearance), over: bg)
            let disabledSurface = compositeColor(resolveNSColor(VaniScriptTheme.disabledSurface, appearance: appearance), over: bg)
            let disabledText = resolveNSColor(VaniScriptTheme.disabledText, appearance: appearance)

            let disabledOnBg = contrastRatio(between: disabledText, and: bg)
            let disabledOnCard = contrastRatio(between: disabledText, and: card)
            let disabledOnBar = contrastRatio(between: disabledText, and: bar)
            let disabledOnControl = contrastRatio(between: disabledText, and: control)
            let disabledOnDisabledSurface = contrastRatio(between: disabledText, and: disabledSurface)

            #expect(disabledOnBg >= 3.0, "Disabled text on background contrast in \(appearance.name) was \(disabledOnBg)")
            #expect(disabledOnCard >= 3.0, "Disabled text on card contrast in \(appearance.name) was \(disabledOnCard)")
            #expect(disabledOnBar >= 3.0, "Disabled text on barSurface contrast in \(appearance.name) was \(disabledOnBar)")
            #expect(disabledOnControl >= 3.0, "Disabled text on control contrast in \(appearance.name) was \(disabledOnControl)")
            #expect(disabledOnDisabledSurface >= 3.0, "Disabled text on disabledSurface contrast in \(appearance.name) was \(disabledOnDisabledSurface)")
        }
    }

    // MARK: - Document Attributed Editor & Appearance Tests

    @Test("Document editor nil spans use dynamic text0 and preserve nil on serialization")
    @MainActor
    func documentEditorDynamicTextAndSerialization() throws {
        let span1 = RichTextSpan(id: "s1", text: "Default appearance text", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: nil)
        let span2 = RichTextSpan(id: "s2", text: "Explicit red text", styleKey: "p", traits: [.bold], translationPolicy: .translate, foregroundColorHex: "#FF0000")
        let block = DocumentEditorBlockItem(id: "b1", spans: [span1, span2], fallbackText: "Default appearance text Explicit red text")

        var editedBlocks: [DocumentEditorBlockItem] = []

        let view = DocumentAttributedTextView(
            text: .constant(block.fallbackText),
            blocks: [block],
            onBlocksChanged: { blocks, _ in
                editedBlocks = blocks
            },
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0
        )

        let coordinator = view.makeCoordinator()
        let textView = DocumentNSTextView()
        coordinator.textView = textView
        coordinator.setAttributedString(from: [block], fallbackText: block.fallbackText, textView: textView)

        guard let textStorage = textView.textStorage else {
            Issue.record("Missing textStorage in textView")
            return
        }

        // Verify span1 attributes: foregroundColor is dynamic text0, explicitColorHex is nil
        let attrs1 = textStorage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs1[DocumentTextAttribute.explicitColorHex] == nil, "Span 1 should not have an explicit color hex")
        let color1 = attrs1[.foregroundColor] as? NSColor
        #expect(color1 != nil, "Span 1 should have a default dynamic foreground color")

        // Verify span2 attributes: foregroundColor has explicitColorHex = #FF0000
        let span2Location = (span1.text as NSString).length + 1 // accounts for boundary
        let attrs2 = textStorage.attributes(at: span2Location, effectiveRange: nil)
        #expect(attrs2[DocumentTextAttribute.explicitColorHex] as? String == "FF0000", "Span 2 should preserve explicit hex")

        // Appearance change must NOT wipe explicit red via textView.textColor.
        textView.viewDidChangeEffectiveAppearance()
        #expect(textView.insertionPointColor != nil, "Insertion point color should refresh on appearance change")

        guard let storageAfter = textView.textStorage else {
            Issue.record("Missing textStorage after appearance change")
            return
        }
        let attrs2After = storageAfter.attributes(at: span2Location, effectiveRange: nil)
        #expect(attrs2After[DocumentTextAttribute.explicitColorHex] as? String == "FF0000",
                "Explicit hex must survive appearance change")
        if let colorAfter = attrs2After[.foregroundColor] as? NSColor,
           let rgb = colorAfter.usingColorSpace(.sRGB) {
            #expect(abs(rgb.redComponent - 1.0) < 0.02)
            #expect(rgb.greenComponent < 0.02)
            #expect(rgb.blueComponent < 0.02)
        } else {
            Issue.record("Red foreground missing after appearance change")
        }

        // Setting the legacy whole-view textColor (old bug) must not permanently
        // leave the storage black once we re-apply from blocks.
        textView.textColor = NSColor.black
        coordinator.reapplyLastRenderedAttributedString()
        guard let storageRepaired = textView.textStorage else {
            Issue.record("Missing textStorage after reapply")
            return
        }
        let attrs2Repaired = storageRepaired.attributes(at: span2Location, effectiveRange: nil)
        #expect(attrs2Repaired[DocumentTextAttribute.explicitColorHex] as? String == "FF0000")
        if let colorRepaired = attrs2Repaired[.foregroundColor] as? NSColor,
           let rgb = colorRepaired.usingColorSpace(.sRGB) {
            #expect(abs(rgb.redComponent - 1.0) < 0.02)
            #expect(rgb.greenComponent < 0.02)
        } else {
            Issue.record("Red foreground missing after reapply from blocks")
        }

        coordinator.setAttributedString(from: [block], fallbackText: block.fallbackText, textView: textView)
        // Re-read storage blocks through the coordinator delegate
        let notification = Notification(name: NSText.didChangeNotification, object: textView)
        coordinator.textDidChange(notification)

        #expect(!editedBlocks.isEmpty, "Edited blocks should be serialized on textDidChange")
        if let firstBlock = editedBlocks.first, firstBlock.spans.count >= 2 {
            #expect(firstBlock.spans[0].foregroundColorHex == nil, "Nil document foreground color must remain nil after round-trip")
            #expect(firstBlock.spans[1].foregroundColorHex == "FF0000", "Explicit color must remain preserved after round-trip")
        }
    }

    @Test("Dark Aqua document text display-contrast adapts dark/default colors and preserves chromatic runs")
    func darkAquaDocumentTextContrast() throws {
        guard let darkAqua = NSAppearance(named: .darkAqua),
              let aqua = NSAppearance(named: .aqua) else {
            Issue.record("Failed to create NSAppearance instances")
            return
        }

        let darkEditorBg = resolveNSColor(VaniScriptTheme.editorSurface, appearance: darkAqua)
        let aquaEditorBg = resolveNSColor(VaniScriptTheme.editorSurface, appearance: aqua)

        // 1. Default (nil) text in Dark Aqua meets >= 7:1 AAA contrast
        let darkDefaultText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: nil)), appearance: darkAqua)
        let darkDefaultContrast = contrastRatio(between: darkDefaultText, and: darkEditorBg)
        #expect(darkDefaultContrast >= 7.0, "Dark Aqua default text contrast was \(darkDefaultContrast)")

        // 2. Imported black text (#000000) in Dark Aqua adapts to high-contrast legible color (>= 7:1)
        let darkBlackText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: "000000")), appearance: darkAqua)
        let darkBlackContrast = contrastRatio(between: darkBlackText, and: darkEditorBg)
        #expect(darkBlackContrast >= 7.0, "Dark Aqua imported black text contrast was \(darkBlackContrast)")

        // 3. Imported dark slate (#111827) in Dark Aqua adapts to high-contrast legible color (>= 7:1)
        let darkSlateText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: "111827")), appearance: darkAqua)
        let darkSlateContrast = contrastRatio(between: darkSlateText, and: darkEditorBg)
        #expect(darkSlateContrast >= 7.0, "Dark Aqua imported slate text contrast was \(darkSlateContrast)")

        // 4. Explicit red text (#FF0000) in Dark Aqua meets >= 4:1 contrast and preserves red chromaticity
        let darkRedText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: "FF0000")), appearance: darkAqua)
        let darkRedContrast = contrastRatio(between: darkRedText, and: darkEditorBg)
        #expect(darkRedContrast >= 4.0, "Dark Aqua red text contrast was \(darkRedContrast)")
        if let rgb = darkRedText.usingColorSpace(.sRGB) {
            #expect(rgb.redComponent > 0.85, "Red component should remain dominant")
            #expect(rgb.greenComponent < 0.20, "Green component should remain low")
            #expect(rgb.blueComponent < 0.20, "Blue component should remain low")
        }

        // 5. Explicit dark navy (#000080) in Dark Aqua adapts to legible contrast (>= 4.5:1) while preserving blue hue
        let darkNavyText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: "000080")), appearance: darkAqua)
        let darkNavyContrast = contrastRatio(between: darkNavyText, and: darkEditorBg)
        #expect(darkNavyContrast >= 4.5, "Dark Aqua navy text contrast was \(darkNavyContrast)")
        if let rgb = darkNavyText.usingColorSpace(.sRGB) {
            #expect(rgb.blueComponent > rgb.redComponent, "Blue should remain dominant for navy text")
        }

        // 6. In Aqua (Light), default and black text have high contrast (>= 7:1)
        let aquaDefaultText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: nil)), appearance: aqua)
        let aquaDefaultContrast = contrastRatio(between: aquaDefaultText, and: aquaEditorBg)
        #expect(aquaDefaultContrast >= 7.0, "Aqua default text contrast was \(aquaDefaultContrast)")

        let aquaBlackText = resolveNSColor(Color(nsColor: VaniScriptTheme.displayAdaptedTextColor(hex: "000000")), appearance: aqua)
        let aquaBlackContrast = contrastRatio(between: aquaBlackText, and: aquaEditorBg)
        #expect(aquaBlackContrast >= 7.0, "Aqua black text contrast was \(aquaBlackContrast)")
    }

    @Test("Proofreading highlight background and foreground meet high-contrast visibility thresholds in Aqua and Dark Aqua")
    func proofreadingHighlightContrastInBothAppearances() throws {
        guard let darkAqua = NSAppearance(named: .darkAqua),
              let aqua = NSAppearance(named: .aqua) else {
            Issue.record("Failed to create NSAppearance instances")
            return
        }

        // Dark Aqua verification
        let darkEditorBg = resolveNSColor(VaniScriptTheme.editorSurface, appearance: darkAqua)
        let darkHlBg = resolveNSColor(Color(nsColor: VaniScriptTheme.proofreadingHighlightNSBackground), appearance: darkAqua)
        let darkHlFg = resolveNSColor(Color(nsColor: VaniScriptTheme.proofreadingHighlightNSForeground), appearance: darkAqua)

        let darkCompositedHlBg = compositeColor(darkHlBg, over: darkEditorBg)
        // Highlight background against dark editor surface: >= 4.5:1 (prominent, clearly noticeable mark)
        let darkHlProminence = contrastRatio(between: darkCompositedHlBg, and: darkEditorBg)
        #expect(darkHlProminence >= 4.5, "Dark Aqua highlight background prominence was \(darkHlProminence)")

        // Text inside highlight against the highlight background: >= 6.0:1 (crisp, high-contrast reading)
        let darkHlTextLegibility = contrastRatio(between: darkHlFg, and: darkCompositedHlBg)
        #expect(darkHlTextLegibility >= 6.0, "Dark Aqua highlight text legibility was \(darkHlTextLegibility)")

        // Aqua verification
        let aquaEditorBg = resolveNSColor(VaniScriptTheme.editorSurface, appearance: aqua)
        let aquaHlBg = resolveNSColor(Color(nsColor: VaniScriptTheme.proofreadingHighlightNSBackground), appearance: aqua)
        let aquaHlFg = resolveNSColor(Color(nsColor: VaniScriptTheme.proofreadingHighlightNSForeground), appearance: aqua)

        let aquaCompositedHlBg = compositeColor(aquaHlBg, over: aquaEditorBg)
        let aquaHlTextLegibility = contrastRatio(between: aquaHlFg, and: aquaCompositedHlBg)
        #expect(aquaHlTextLegibility >= 7.0, "Aqua highlight text legibility was \(aquaHlTextLegibility)")
    }

    @Test("Document editor preserves canonical hex and isolates temporary highlight attributes during serialization")
    @MainActor
    func documentEditorCanonicalHexAndTemporaryHighlightIsolation() throws {
        let span1 = RichTextSpan(id: "s1", text: "Default text. ", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: nil)
        let span2 = RichTextSpan(id: "s2", text: "Imported black. ", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: "000000")
        let span3 = RichTextSpan(id: "s3", text: "Explicit red. ", styleKey: "p", traits: [.bold], translationPolicy: .translate, foregroundColorHex: "FF0000")
        let span4 = RichTextSpan(id: "s4", text: "Navy annotation.", styleKey: "p", traits: [.italic], translationPolicy: .translate, foregroundColorHex: "000080")
        let block = DocumentEditorBlockItem(id: "b1", spans: [span1, span2, span3, span4], fallbackText: "Default text. Imported black. Explicit red. Navy annotation.")

        var editedBlocks: [DocumentEditorBlockItem] = []
        let view = DocumentAttributedTextView(
            text: .constant(block.fallbackText),
            blocks: [block],
            onBlocksChanged: { blocks, _ in
                editedBlocks = blocks
            },
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0
        )

        let coordinator = view.makeCoordinator()
        let textView = DocumentNSTextView()
        coordinator.textView = textView
        coordinator.setAttributedString(from: [block], fallbackText: block.fallbackText, textView: textView)

        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager else {
            Issue.record("Missing textStorage or layoutManager in textView")
            return
        }

        // Apply a proofreading highlight over span2 (Imported black)
        let span2Location = (span1.text as NSString).length
        let span2Length = (span2.text as NSString).length
        let highlightRange = NSRange(location: span2Location, length: span2Length)

        coordinator.applyProofreadingHighlight(highlightRange, focusToken: 1, scroll: false)

        // Verify temporary attributes exist in layoutManager
        let tempBg = layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: span2Location, effectiveRange: nil)
        let tempFg = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: span2Location, effectiveRange: nil)
        #expect(tempBg != nil, "Temporary background attribute should be present during highlight")
        #expect(tempFg != nil, "Temporary foreground attribute should be present during highlight")

        // Verify textStorage itself is NOT modified by layoutManager temporary attributes
        let storageAttrs = textStorage.attributes(at: span2Location, effectiveRange: nil)
        #expect(storageAttrs[DocumentTextAttribute.explicitColorHex] as? String == "000000", "Storage explicit hex must remain canonical 000000")

        // Re-read storage blocks through the coordinator delegate
        let notification = Notification(name: NSText.didChangeNotification, object: textView)
        coordinator.textDidChange(notification)

        #expect(!editedBlocks.isEmpty, "Edited blocks should serialize on textDidChange")
        if let firstBlock = editedBlocks.first, firstBlock.spans.count == 4 {
            #expect(firstBlock.spans[0].foregroundColorHex == nil, "Span 1 nil hex preserved")
            #expect(firstBlock.spans[1].foregroundColorHex == "000000", "Span 2 explicit 000000 preserved")
            #expect(firstBlock.spans[2].foregroundColorHex == "FF0000", "Span 3 explicit FF0000 preserved")
            #expect(firstBlock.spans[3].foregroundColorHex == "000080", "Span 4 explicit 000080 preserved")
        } else {
            Issue.record("Expected 4 serialized spans, got \(editedBlocks.first?.spans.count ?? 0)")
        }

        // Clear highlight
        coordinator.applyProofreadingHighlight(nil, focusToken: 2, scroll: false)
        let clearedBg = layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: span2Location, effectiveRange: nil)
        let clearedFg = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: span2Location, effectiveRange: nil)
        #expect(clearedBg == nil, "Temporary background should be cleared")
        #expect(clearedFg == nil, "Temporary foreground should be cleared")
    }

    @Test("Proofreading highlight survives content rewrite via temporary-attribute restoration without touching canonical storage")
    @MainActor
    func proofreadingHighlightSurvivesContentRewrite() throws {
        guard let darkAqua = NSAppearance(named: .darkAqua) else {
            Issue.record("Failed to create Dark Aqua NSAppearance")
            return
        }

        let span1 = RichTextSpan(id: "s1", text: "Default text. ", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: nil)
        let span2 = RichTextSpan(id: "s2", text: "Imported black. ", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: "000000")
        let span3 = RichTextSpan(id: "s3", text: "Explicit red.", styleKey: "p", traits: [.bold], translationPolicy: .translate, foregroundColorHex: "FF0000")
        let block = DocumentEditorBlockItem(id: "b1", spans: [span1, span2, span3], fallbackText: "Default text. Imported black. Explicit red.")

        var editedBlocks: [DocumentEditorBlockItem] = []
        let view = DocumentAttributedTextView(
            text: .constant(block.fallbackText),
            blocks: [block],
            onBlocksChanged: { blocks, _ in
                editedBlocks = blocks
            },
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0,
            proofreadingHighlightRange: nil,
            proofreadingFocusToken: 1
        )

        let coordinator = view.makeCoordinator()
        let textView = DocumentNSTextView()
        coordinator.textView = textView
        coordinator.setAttributedString(from: [block], fallbackText: block.fallbackText, textView: textView)

        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager else {
            Issue.record("Missing textStorage or layoutManager in textView")
            return
        }

        let span2Location = (span1.text as NSString).length
        let span2Length = (span2.text as NSString).length
        let highlightRange = NSRange(location: span2Location, length: span2Length)

        coordinator.applyProofreadingHighlight(highlightRange, focusToken: 1, scroll: false)
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: span2Location, effectiveRange: nil) != nil,
                "Temporary background should be present after highlight apply")
        #expect(layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: span2Location, effectiveRange: nil) != nil,
                "Temporary foreground should be present after highlight apply")

        // A real content change forces a full storage rewrite, which wipes
        // layoutManager temporary attributes. The coordinator must restore the
        // proofreading mark (same unit + same focus token) display-only.
        let grownSpan2 = RichTextSpan(id: "s2", text: "Imported black text. ", styleKey: "p", traits: [], translationPolicy: .translate, foregroundColorHex: "000000")
        let grownBlock = DocumentEditorBlockItem(
            id: "b1",
            spans: [span1, grownSpan2, span3],
            fallbackText: "Default text. Imported black text. Explicit red."
        )
        coordinator.setAttributedString(from: [grownBlock], fallbackText: grownBlock.fallbackText, textView: textView)

        guard let rewrittenStorage = textView.textStorage else {
            Issue.record("Missing textStorage after content rewrite")
            return
        }

        // Restored temporary mark is present again at the highlighted unit.
        let restoredBg = layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: span2Location, effectiveRange: nil) as? NSColor
        let restoredFg = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: span2Location, effectiveRange: nil) as? NSColor
        #expect(restoredBg != nil, "Proofreading background must be restored after content rewrite")
        #expect(restoredFg != nil, "Proofreading foreground must be restored after content rewrite")

        // Restored mark resolves to the prominent Dark Aqua theme highlight.
        if let restoredBg {
            darkAqua.performAsCurrentDrawingAppearance {
                if let rgb = restoredBg.usingColorSpace(.sRGB) {
                    #expect(abs(rgb.redComponent - 245.0 / 255.0) < 0.02, "Restored highlight background red was \(rgb.redComponent)")
                    #expect(abs(rgb.greenComponent - 166.0 / 255.0) < 0.02, "Restored highlight background green was \(rgb.greenComponent)")
                    #expect(abs(rgb.blueComponent - 35.0 / 255.0) < 0.02, "Restored highlight background blue was \(rgb.blueComponent)")
                    #expect(abs(rgb.alphaComponent - 0.80) < 0.02, "Restored highlight background alpha was \(rgb.alphaComponent)")
                } else {
                    Issue.record("Restored highlight background could not be resolved to sRGB")
                }
            }
        }

        // Canonical storage is untouched by the temporary mark.
        let storageAttrs = rewrittenStorage.attributes(at: span2Location, effectiveRange: nil)
        #expect(storageAttrs[DocumentTextAttribute.explicitColorHex] as? String == "000000",
                "Storage explicit hex must remain canonical after rewrite and highlight restore")

        // Serialization round-trip keeps canonical hex values.
        let notification = Notification(name: NSText.didChangeNotification, object: textView)
        coordinator.textDidChange(notification)
        #expect(!editedBlocks.isEmpty, "Edited blocks should serialize on textDidChange")
        if let firstBlock = editedBlocks.first, firstBlock.spans.count == 3 {
            #expect(firstBlock.spans[0].foregroundColorHex == nil, "Span 1 nil hex preserved after rewrite")
            #expect(firstBlock.spans[1].foregroundColorHex == "000000", "Span 2 canonical 000000 preserved after rewrite")
            #expect(firstBlock.spans[2].foregroundColorHex == "FF0000", "Span 3 canonical FF0000 preserved after rewrite")
        } else {
            Issue.record("Expected 3 serialized spans, got \(editedBlocks.first?.spans.count ?? 0)")
        }
    }
}
