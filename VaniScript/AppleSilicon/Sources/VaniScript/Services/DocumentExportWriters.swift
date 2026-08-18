import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import VaniScriptCore

public enum DocumentExportWriters {
    public enum ExportError: LocalizedError, Equatable {
        case missingSourceDocument
        case missingTranslation
        case sourceHashMismatch(expected: String, actual: String)
        case invalidPackage(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingSourceDocument:
                return "The original source document is missing or not available."
            case .missingTranslation:
                return "No translated content is available to export."
            case let .sourceHashMismatch(expected, actual):
                return "Source document hash mismatch (expected \(expected), got \(actual)). The original file may have been modified or corrupted."
            case let .invalidPackage(msg):
                return "The document package could not be processed: \(msg)"
            case let .writeFailed(msg):
                return "Failed to save exported file: \(msg)"
            }
        }
    }

    public struct DOCXExportResult: Equatable, Sendable {
        public var destinationURL: URL
        public var warnings: [String]
        public var detectedFonts: [String]

        public init(destinationURL: URL, warnings: [String] = [], detectedFonts: [String] = []) {
            self.destinationURL = destinationURL
            self.warnings = warnings
            self.detectedFonts = detectedFonts
        }
    }

    public struct TranslationPackageExportResult: Equatable, Sendable {
        public var destinationDirectoryURL: URL
        public var originalDocxURL: URL
        public var localizedDocxURL: URL
        public var projectBundleURL: URL
        public var warnings: [String]

        public init(
            destinationDirectoryURL: URL,
            originalDocxURL: URL,
            localizedDocxURL: URL,
            projectBundleURL: URL,
            warnings: [String] = []
        ) {
            self.destinationDirectoryURL = destinationDirectoryURL
            self.originalDocxURL = originalDocxURL
            self.localizedDocxURL = localizedDocxURL
            self.projectBundleURL = projectBundleURL
            self.warnings = warnings
        }
    }

    public static func writeTXT(
        text: String,
        to destinationURL: URL
    ) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.missingTranslation
        }
        guard let data = text.data(using: .utf8) else {
            throw ExportError.writeFailed("Could not encode document text as UTF-8.")
        }
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    public static func writePDF(
        documentState: DocumentState,
        language: String? = nil,
        to destinationURL: URL
    ) throws {
        let translations: [String: TranslatedBlock]
        if let language, TranslationArchive.isRealLanguage(language) {
            let key = TranslationArchive.languageKey(language)
            translations = documentState.translationsByLanguage[key]
                ?? documentState.translationsByLanguage[language.lowercased()]
                ?? [:]
        } else if let firstKey = documentState.translationsByLanguage.keys.sorted().first,
                  let firstTranslations = documentState.translationsByLanguage[firstKey] {
            translations = firstTranslations
        } else {
            translations = [:]
        }

        guard translations.values.contains(where: { TranslationArchive.isUsableTranslationText($0.text) }) else {
            throw ExportError.missingTranslation
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedResult = NSMutableAttributedString()

        for (bIdx, block) in documentState.blocks.enumerated() {
            guard let translatedBlock = translations[block.id],
                  TranslationArchive.isUsableTranslationText(translatedBlock.text)
            else { continue }

            let spans = translatedBlock.spans.isEmpty
                ? [RichTextSpan(id: UUID().uuidString, text: translatedBlock.text)]
                : translatedBlock.spans

            for span in spans {
                guard !span.text.isEmpty else { continue }
                let attrs = pdfSpanAttributes(for: span, paragraphStyle: paragraphStyle)
                attributedResult.append(NSAttributedString(string: span.text, attributes: attrs))
            }

            if bIdx < documentState.blocks.count - 1 {
                attributedResult.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraphStyle]))
            }
        }

        guard attributedResult.length > 0 else {
            throw ExportError.missingTranslation
        }

        try writeAttributedPDF(attributedResult, to: destinationURL)
    }

    public static func writePDF(
        text: String,
        to destinationURL: URL
    ) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.missingTranslation
        }

        let font = NSFont.systemFont(ofSize: 12)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        try writeAttributedPDF(attrString, to: destinationURL)
    }

    private static func writeAttributedPDF(_ attrString: NSAttributedString, to destinationURL: URL) throws {
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)

        let pageWidth: CGFloat = 595.28 // A4 width
        let pageHeight: CGFloat = 841.89 // A4 height
        var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 54.0 // 0.75 inch readable margins
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - 2 * margin,
            height: pageHeight - 2 * margin
        )
        let textPath = CGPath(rect: textRect, transform: nil)

        let tempPDF = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaniscript-pdf-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempPDF) }

        guard let consumer = CGDataConsumer(url: tempPDF as CFURL) else {
            throw ExportError.writeFailed("Could not create PDF data consumer.")
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw ExportError.writeFailed("Could not create PDF graphics context.")
        }

        var textRange = CFRange(location: 0, length: 0)
        let textLength = attrString.length

        if textLength == 0 {
            context.beginPDFPage(nil)
            context.endPDFPage()
        } else {
            while textRange.location < textLength {
                context.beginPDFPage(nil)
                let frame = CTFramesetterCreateFrame(framesetter, textRange, textPath, nil)
                CTFrameDraw(frame, context)
                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 {
                    break
                }
                textRange.location += visibleRange.length
                context.endPDFPage()
            }
        }
        context.closePDF()

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempPDF, to: destinationURL)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public static func writeDOCX(
        sourceDocxURL: URL,
        documentState: DocumentState,
        language: String? = nil,
        to destinationURL: URL
    ) throws -> DOCXExportResult {
        guard sourceDocxURL.isFileURL, FileManager.default.fileExists(atPath: sourceDocxURL.path) else {
            throw ExportError.missingSourceDocument
        }

        // Integrity check is advisory. A stale stored sha256 (path drift,
        // Refresh Source race, older projects) must not block export of an
        // otherwise readable source file the user is actively working with.
        if let expectedHash = documentState.originalAsset.sha256, !expectedHash.isEmpty {
            if let actualData = try? Data(contentsOf: sourceDocxURL, options: [.mappedIfSafe]) {
                let actualHash = sha256(actualData)
                if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                    AppLogger.shared.warn(
                        "DOCX export: source sha256 differs from archived asset (expected \(expectedHash.prefix(12))…, got \(actualHash.prefix(12))…). Continuing with the file on disk."
                    )
                }
            }
        }


        let translations: [String: TranslatedBlock]
        if let language, TranslationArchive.isRealLanguage(language) {
            let key = TranslationArchive.languageKey(language)
            translations = documentState.translationsByLanguage[key]
                ?? documentState.translationsByLanguage[language.lowercased()]
                ?? [:]
        } else if let firstKey = documentState.translationsByLanguage.keys.sorted().first,
                  let firstTranslations = documentState.translationsByLanguage[firstKey] {
            translations = firstTranslations
        } else {
            translations = [:]
        }

        guard translations.values.contains(where: { TranslationArchive.isUsableTranslationText($0.text) }) else {
            throw ExportError.missingTranslation
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaniscript-docx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Unzip source DOCX package
        let unzipProc = Process()
        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProc.arguments = ["-q", sourceDocxURL.path, "-d", tempDir.path]
        do {
            try unzipProc.run()
            unzipProc.waitUntilExit()
            guard unzipProc.terminationStatus == 0 else {
                throw ExportError.invalidPackage("Failed to extract source DOCX package.")
            }
        } catch {
            throw ExportError.invalidPackage("Failed to extract source DOCX package: \(error.localizedDescription)")
        }

        // Detect Brill/Gentium font references in styles.xml and font tables
        let (fontWarnings, detectedFonts) = detectStylesFontWarnings(
            in: tempDir,
            preflightWarnings: documentState.preflight.fontWarnings
        )

        // Group translated blocks by their part file path
        var blocksByPartPath: [String: [(block: DocumentBlock, translatedBlock: TranslatedBlock)]] = [:]
        for block in documentState.blocks {
            guard let translated = translations[block.id],
                  TranslationArchive.isUsableTranslationText(translated.text)
            else { continue }

            let partPath = relativePartPath(from: block.location)
            blocksByPartPath[partPath, default: []].append((block: block, translatedBlock: translated))
        }

        for (partPath, translatedItems) in blocksByPartPath {
            let partURL = tempDir.appendingPathComponent(partPath)
            guard FileManager.default.fileExists(atPath: partURL.path) else { continue }

            let partData: Data
            do {
                partData = try Data(contentsOf: partURL)
            } catch {
                throw ExportError.invalidPackage("Could not read \(partPath).")
            }

            let xmlDoc: XMLDocument
            do {
                xmlDoc = try XMLDocument(data: partData, options: [.nodePreserveWhitespace])
            } catch {
                throw ExportError.invalidPackage("Invalid XML in \(partPath): \(error.localizedDescription)")
            }

            let paragraphNodes: [XMLNode]
            do {
                paragraphNodes = try xmlDoc.nodes(forXPath: ".//*[local-name()=\"p\"]")
            } catch {
                throw ExportError.invalidPackage("Failed to query paragraphs in \(partPath).")
            }

            let replacementsByOrdinal = Dictionary(
                translatedItems.map { ($0.block.location.paragraphOrdinal, (block: $0.block, translatedBlock: $0.translatedBlock)) },
                uniquingKeysWith: { _, latest in latest }
            )

            for (ordinal, item) in replacementsByOrdinal {
                guard ordinal < paragraphNodes.count, let pElem = paragraphNodes[ordinal] as? XMLElement else {
                    continue
                }
                rewriteParagraph(pElem: pElem, block: item.block, translatedBlock: item.translatedBlock)
            }

            let modifiedXMLData = xmlDoc.xmlData(options: [.nodePreserveWhitespace])
            do {
                try modifiedXMLData.write(to: partURL)
            } catch {
                throw ExportError.writeFailed("Could not write modified \(partPath).")
            }
        }

        // Re-zip package to temporary file
        let tempOutputDOCX = tempDir.appendingPathComponent("repacked_output.docx")
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = tempDir
        zipProc.arguments = ["-q", "-r", "-X", tempOutputDOCX.path, ".", "-x", "*.docx"]
        do {
            try zipProc.run()
            zipProc.waitUntilExit()
            guard zipProc.terminationStatus == 0 else {
                throw ExportError.writeFailed("Failed to create repacked DOCX package.")
            }
        } catch {
            throw ExportError.writeFailed("Failed to create repacked DOCX package: \(error.localizedDescription)")
        }

        // Copy atomically to destinationURL
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempOutputDOCX, to: destinationURL)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        return DOCXExportResult(
            destinationURL: destinationURL,
            warnings: fontWarnings,
            detectedFonts: detectedFonts
        )
    }

    @discardableResult
    public static func exportTranslationPackage(
        sourceDocxURL: URL,
        documentState: DocumentState,
        projectRecord: ProjectRecord,
        language: String? = nil,
        to destinationDirectoryURL: URL
    ) throws -> TranslationPackageExportResult {
        guard sourceDocxURL.isFileURL, FileManager.default.fileExists(atPath: sourceDocxURL.path) else {
            throw ExportError.missingSourceDocument
        }

        // Same advisory policy as writeDOCX — do not block package export on a
        // stale archived sha256 when the managed source file is present.
        if let expectedHash = documentState.originalAsset.sha256, !expectedHash.isEmpty {
            if let actualData = try? Data(contentsOf: sourceDocxURL, options: [.mappedIfSafe]) {
                let actualHash = sha256(actualData)
                if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                    AppLogger.shared.warn(
                        "Package export: source sha256 differs from archived asset (expected \(expectedHash.prefix(12))…, got \(actualHash.prefix(12))…). Continuing with the file on disk."
                    )
                }
            }
        }

        let lang = language ?? projectRecord.session.selectedTranslationLanguage ?? projectRecord.session.targetLang
        let langKey = TranslationArchive.languageKey(lang)

        let originalStem: String
        if !projectRecord.session.sourceFileName.isEmpty {
            originalStem = URL(fileURLWithPath: projectRecord.session.sourceFileName).deletingPathExtension().lastPathComponent
        } else {
            originalStem = sourceDocxURL.deletingPathExtension().lastPathComponent
        }
        let safeStem = originalStem.isEmpty ? "Document" : originalStem
        let ext = sourceDocxURL.pathExtension.isEmpty ? "docx" : sourceDocxURL.pathExtension

        let originalFileName = "\(safeStem)_original.\(ext)"
        let localizedFileName = "\(safeStem)_\(langKey).\(ext)"
        let bundleFileName = "\(safeStem).vaniscript"

        let tempStagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaniscript-pkg-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempStagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempStagingDir) }

        // 1. Copy Original DOCX into staging
        let stagingOriginalURL = tempStagingDir.appendingPathComponent(originalFileName)
        do {
            try FileManager.default.copyItem(at: sourceDocxURL, to: stagingOriginalURL)
        } catch {
            throw ExportError.writeFailed("Failed to copy original document: \(error.localizedDescription)")
        }

        // 2. Generate Localized DOCX in staging
        let stagingLocalizedURL = tempStagingDir.appendingPathComponent(localizedFileName)
        let docxResult: DOCXExportResult
        do {
            docxResult = try writeDOCX(
                sourceDocxURL: sourceDocxURL,
                documentState: documentState,
                language: lang,
                to: stagingLocalizedURL
            )
        } catch {
            throw error
        }

        // 3. Generate .vaniscript project bundle in staging
        let stagingBundleURL = tempStagingDir.appendingPathComponent(bundleFileName)
        do {
            try ProjectBundleExporter.exportBundle(record: projectRecord, to: stagingBundleURL)
        } catch {
            throw ExportError.writeFailed("Failed to create project bundle: \(error.localizedDescription)")
        }

        // 4. Ensure destination directory exists
        do {
            try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writeFailed("Cannot create destination directory: \(error.localizedDescription)")
        }

        // 5. Atomically move/replace each of the three files to destinationDirectoryURL
        let finalOriginalURL = destinationDirectoryURL.appendingPathComponent(originalFileName)
        let finalLocalizedURL = destinationDirectoryURL.appendingPathComponent(localizedFileName)
        let finalBundleURL = destinationDirectoryURL.appendingPathComponent(bundleFileName)

        let itemsToMove: [(staging: URL, final: URL)] = [
            (stagingOriginalURL, finalOriginalURL),
            (stagingLocalizedURL, finalLocalizedURL),
            (stagingBundleURL, finalBundleURL)
        ]

        for item in itemsToMove {
            do {
                if FileManager.default.fileExists(atPath: item.final.path) {
                    try FileManager.default.removeItem(at: item.final)
                }
                try FileManager.default.moveItem(at: item.staging, to: item.final)
            } catch {
                throw ExportError.writeFailed("Failed to move \(item.final.lastPathComponent) to destination: \(error.localizedDescription)")
            }
        }

        return TranslationPackageExportResult(
            destinationDirectoryURL: destinationDirectoryURL,
            originalDocxURL: finalOriginalURL,
            localizedDocxURL: finalLocalizedURL,
            projectBundleURL: finalBundleURL,
            warnings: docxResult.warnings
        )
    }


    private static func relativePartPath(from location: DocumentLocation) -> String {
        if !location.xmlPath.isEmpty {
            let trimmed = location.xmlPath.hasPrefix("/") ? String(location.xmlPath.dropFirst()) : location.xmlPath
            let components = trimmed.split(separator: "/")
            if components.count >= 2 {
                let partComponents = components.dropLast()
                return partComponents.joined(separator: "/")
            }
        }
        switch location.part {
        case .mainBody:
            return "word/document.xml"
        case .header:
            return "word/header1.xml"
        case .footer:
            return "word/footer1.xml"
        case .footnote:
            return "word/footnotes.xml"
        case .endnote:
            return "word/endnotes.xml"
        case .textBox:
            return "word/document.xml"
        }
    }

    private static func rewriteParagraph(pElem: XMLElement, block: DocumentBlock, translatedBlock: TranslatedBlock) {
        let translatedSpans = translatedBlock.spans.isEmpty
            ? [RichTextSpan(id: UUID().uuidString, text: translatedBlock.text)]
            : translatedBlock.spans

        let existingRunNodes = (pElem.children ?? []).compactMap { $0 as? XMLElement }.filter {
            $0.localName == "r" || $0.name == "w:r"
        }

        var newRuns: [XMLElement] = []

        for (sIdx, span) in translatedSpans.enumerated() {
            guard !span.text.isEmpty else { continue }
            let rElem = XMLElement(name: "w:r")

            var matchingRunNode: XMLElement? = nil
            if let matchedSourceIndex = block.spans.firstIndex(where: { $0.id == span.id }),
               matchedSourceIndex < existingRunNodes.count {
                matchingRunNode = existingRunNodes[matchedSourceIndex]
            } else if let matchedSourceIndex = block.spans.firstIndex(where: { $0.styleKey == span.styleKey }),
                       matchedSourceIndex < existingRunNodes.count {
                matchingRunNode = existingRunNodes[matchedSourceIndex]
            } else if sIdx < existingRunNodes.count {
                matchingRunNode = existingRunNodes[sIdx]
            } else if let first = existingRunNodes.first {
                matchingRunNode = first
            }

            let rPrElem: XMLElement
            if let matchingRunNode,
               let existingRPr = (matchingRunNode.elements(forName: "w:rPr").first ?? matchingRunNode.elements(forName: "rPr").first) {
                rPrElem = existingRPr.copy() as! XMLElement
            } else {
                rPrElem = XMLElement(name: "w:rPr")
            }

            let sourceSpanForIndex = block.spans.indices.contains(sIdx) ? block.spans[sIdx] : block.spans.first(where: { $0.id == span.id })
            EditorRunPropertyOverlay.apply(to: rPrElem, span: span, sourceSpan: sourceSpanForIndex)

            if rPrElem.childCount > 0 || rPrElem.attributes?.isEmpty == false {
                rElem.addChild(rPrElem)
            }

            let tElem = XMLElement(name: "w:t", stringValue: span.text)
            if span.text.hasPrefix(" ") || span.text.hasSuffix(" ") || span.text.contains("  ") {
                tElem.addAttribute(XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as! XMLNode)
            }
            rElem.addChild(tElem)
            newRuns.append(rElem)
        }

        if newRuns.isEmpty {
            let rElem = XMLElement(name: "w:r")
            let tElem = XMLElement(name: "w:t", stringValue: translatedBlock.text)
            rElem.addChild(tElem)
            newRuns.append(rElem)
        }

        if let children = pElem.children {
            let firstRunIndex = children.firstIndex(where: { ($0 as? XMLElement)?.localName == "r" || ($0 as? XMLElement)?.name == "w:r" }) ?? children.count
            for child in children where (child as? XMLElement)?.localName == "r" || (child as? XMLElement)?.name == "w:r" {
                child.detach()
            }
            var insertIndex = firstRunIndex
            for newRun in newRuns {
                pElem.insertChild(newRun, at: min(insertIndex, pElem.childCount))
                insertIndex += 1
            }
        } else {
            for newRun in newRuns {
                pElem.addChild(newRun)
            }
        }
    }

    private static func rewriteParagraph(pElem: XMLElement, newText: String) {
        let dummyBlock = DocumentBlock(id: "dummy", location: DocumentLocation(paragraphOrdinal: 0))
        let dummyTranslated = TranslatedBlock(id: "dummy", sourceBlockID: "dummy", text: newText)
        rewriteParagraph(pElem: pElem, block: dummyBlock, translatedBlock: dummyTranslated)
    }

    /// The trait set the editor displays for a span: the span's own traits with
    /// explicit editor overrides applied in both directions. Superscript and
    /// subscript are mutually exclusive, so superscript wins if both appear.
    private static func effectiveTraits(_ span: RichTextSpan) -> Set<InlineTrait> {
        var traits = span.traits
        for (trait, isOn) in span.editorOverrides?.traitOverrides ?? [:] {
            if isOn {
                traits.insert(trait)
            } else {
                traits.remove(trait)
            }
        }
        if traits.contains(.superscript) {
            traits.remove(.subscriptText)
        }
        return traits
    }

    /// Builds the CoreText attributes for one translated span in the PDF export.
    ///
    /// Bold/italic map to symbolic font traits, underline/strikethrough to line
    /// styles, superscript/subscript to a smaller font shifted off the baseline,
    /// and small caps to the font's small-caps letterform feature. Editor
    /// overrides win over the span's own traits in both directions.
    static func pdfSpanAttributes(for span: RichTextSpan, paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        let overrides = span.editorOverrides
        let effectiveTraits = effectiveTraits(span)

        var fontDescriptor = NSFont.systemFont(ofSize: 12).fontDescriptor
        var traits: NSFontDescriptor.SymbolicTraits = []
        if effectiveTraits.contains(.bold) { traits.insert(.bold) }
        if effectiveTraits.contains(.italic) { traits.insert(.italic) }
        if !traits.isEmpty {
            fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
        }
        var font = NSFont(descriptor: fontDescriptor, size: 12) ?? NSFont.systemFont(ofSize: 12)

        if effectiveTraits.contains(.superscript) || effectiveTraits.contains(.subscriptText) {
            font = NSFont(descriptor: fontDescriptor, size: 12 * 0.58) ?? font
        }
        if effectiveTraits.contains(.smallCaps) {
            // AAT feature identifiers: Letter (3) → Small Caps (3) and
            // Lower Case (37) → Lower Case Small Caps (1). The SDK does not
            // export the kSFNT constants, so the values are literal.
            let smallCapsSettings: [[NSFontDescriptor.FeatureKey: Int]] = [
                [
                    .typeIdentifier: 3,
                    .selectorIdentifier: 3
                ],
                [
                    .typeIdentifier: 37,
                    .selectorIdentifier: 1
                ]
            ]
            if let smallCapsDescriptor = font.fontDescriptor.addingAttributes(
                [.featureSettings: smallCapsSettings]
            ) as NSFontDescriptor? {
                font = NSFont(descriptor: smallCapsDescriptor, size: font.pointSize) ?? font
            }
        }

        let color: NSColor
        if overrides?.clearsForegroundColor == true {
            color = NSColor.black
        } else if let hex = overrides?.foregroundColorOverride ?? span.foregroundColorHex,
                  let nsColor = NSColor(hex: hex) {
            color = nsColor
        } else {
            color = NSColor.black
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        if effectiveTraits.contains(.underline) {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if effectiveTraits.contains(.strikethrough) {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if effectiveTraits.contains(.superscript) {
            attrs[.baselineOffset] = CGFloat(12 * 0.33)
        } else if effectiveTraits.contains(.subscriptText) {
            attrs[.baselineOffset] = CGFloat(-(12 * 0.15))
        }
        return attrs
    }

    private static func detectStylesFontWarnings(
        in extractedDir: URL,
        preflightWarnings: [String] = []
    ) -> (warnings: [String], fonts: [String]) {
        var detectedFonts: Set<String> = []
        var warnings: [String] = []

        let candidatePaths = [
            "word/styles.xml",
            "word/fontTable.xml",
            "word/document.xml"
        ]

        for relPath in candidatePaths {
            let fileURL = extractedDir.appendingPathComponent(relPath)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let xmlDoc = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) else { continue }

            // Extract from w:rFonts
            if let rFontsNodes = try? xmlDoc.nodes(forXPath: ".//*[local-name()=\"rFonts\"]") {
                for node in rFontsNodes {
                    guard let elem = node as? XMLElement else { continue }
                    for attr in ["w:ascii", "ascii", "w:hAnsi", "hAnsi", "w:cs", "cs", "w:eastAsia", "eastAsia"] {
                        if let fontName = elem.attribute(forName: attr)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !fontName.isEmpty {
                            detectedFonts.insert(fontName)
                        }
                    }
                }
            }

            // Extract from w:font
            if let fontNodes = try? xmlDoc.nodes(forXPath: ".//*[local-name()=\"font\"]") {
                for node in fontNodes {
                    guard let elem = node as? XMLElement else { continue }
                    for attr in ["w:name", "name"] {
                        if let fontName = elem.attribute(forName: attr)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !fontName.isEmpty {
                            detectedFonts.insert(fontName)
                        }
                    }
                }
            }
        }

        let sortedFonts = detectedFonts.sorted()
        for font in sortedFonts {
            let lower = font.lowercased()
            if lower.contains("gentium") || lower.contains("brill") {
                warnings.append("Font '\(font)' is referenced in document styles but is not embedded in the DOCX package and is not distributed with VaniScript. External viewers without this font installed will rely on system font substitution.")
            }
        }

        for pw in preflightWarnings {
            if !warnings.contains(pw) {
                warnings.append(pw)
            }
        }

        return (warnings, sortedFonts)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Overlays the editor's effective formatting onto a DOCX run's `w:rPr`.
///
/// The copied source `w:rPr` stays the trusted base: traits the editor did not
/// touch keep whatever the source run declares. Editor overrides win in both
/// directions — an explicit `false` writes the OOXML "off" form (for example
/// `w:b w:val="0"`) so a user-disabled inherited trait survives the export
/// instead of silently re-enabling from the source formatting.
enum EditorRunPropertyOverlay {
    /// Applies effective traits and editor overrides onto an existing or fresh `w:rPr` element.
    static func apply(to rPrElem: XMLElement, span: RichTextSpan, sourceSpan: RichTextSpan? = nil) {
        let overrides = span.editorOverrides

        for trait in InlineTrait.allCases {
            switch desiredState(for: trait, span: span) {
            case .on:
                setOn(rPrElem, trait: trait)
            case .off:
                setOff(rPrElem, trait: trait)
            case .inherit:
                break
            }
        }

        // Superscript and subscript share `w:vertAlign` and are mutually
        // exclusive; force the element to the single effective value.
        let superState = desiredState(for: .superscript, span: span)
        let subState = desiredState(for: .subscriptText, span: span)
        if superState == .on {
            setVertAlign(rPrElem, value: "superscript")
        } else if subState == .on {
            setVertAlign(rPrElem, value: "subscript")
        } else if superState == .off || subState == .off {
            removeChildren(localName: "vertAlign", in: rPrElem)
        }

        if overrides?.clearsForegroundColor == true {
            removeChildren(localName: "color", in: rPrElem)
        } else if let colorHex = overrides?.foregroundColorOverride ?? span.foregroundColorHex {
            setColor(rPrElem, hex: colorHex)
        } else if sourceSpan?.foregroundColorHex == nil {
            // The translated span carries no color and neither did its source
            // span: drop any color the matched source run declared so the
            // export matches the plain editor text.
            removeChildren(localName: "color", in: rPrElem)
        }
    }

    private enum DesiredState {
        case on
        case off
        case inherit
    }

    private static func desiredState(for trait: InlineTrait, span: RichTextSpan) -> DesiredState {
        if let override = span.editorOverrides?.traitOverrides[trait] {
            return override ? .on : .off
        }
        return span.traits.contains(trait) ? .on : .inherit
    }

    private static func setOn(_ rPrElem: XMLElement, trait: InlineTrait) {
        switch trait {
        case .bold:
            setToggle(rPrElem, localName: "b", on: true)
        case .italic:
            setToggle(rPrElem, localName: "i", on: true)
        case .underline:
            if let elem = firstChild(localName: "u", in: rPrElem) {
                setValAttribute(elem, value: "single")
            } else {
                let elem = XMLElement(name: "w:u")
                elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "single") as! XMLNode)
                rPrElem.addChild(elem)
            }
        case .strikethrough:
            setToggle(rPrElem, localName: "strike", on: true)
        case .smallCaps:
            setToggle(rPrElem, localName: "smallCaps", on: true)
        case .superscript, .subscriptText:
            break // handled through `w:vertAlign`
        }
    }

    private static func setOff(_ rPrElem: XMLElement, trait: InlineTrait) {
        switch trait {
        case .bold:
            setToggle(rPrElem, localName: "b", on: false)
        case .italic:
            setToggle(rPrElem, localName: "i", on: false)
        case .underline:
            if let elem = firstChild(localName: "u", in: rPrElem) {
                setValAttribute(elem, value: "none")
            } else {
                let elem = XMLElement(name: "w:u")
                elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "none") as! XMLNode)
                rPrElem.addChild(elem)
            }
        case .strikethrough:
            setToggle(rPrElem, localName: "strike", on: false)
        case .smallCaps:
            setToggle(rPrElem, localName: "smallCaps", on: false)
        case .superscript, .subscriptText:
            break // handled through `w:vertAlign`
        }
    }

    /// Replaces any existing toggle element (matching `b` and `w:b`) with a
    /// single canonical element carrying the on/off state.
    private static func setToggle(_ rPrElem: XMLElement, localName: String, on: Bool) {
        removeChildren(localName: localName, in: rPrElem)
        let elem = XMLElement(name: "w:\(localName)")
        if !on {
            elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "0") as! XMLNode)
        }
        rPrElem.addChild(elem)
    }

    private static func setVertAlign(_ rPrElem: XMLElement, value: String) {
        if let elem = firstChild(localName: "vertAlign", in: rPrElem) {
            setValAttribute(elem, value: value)
        } else {
            let elem = XMLElement(name: "w:vertAlign")
            elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: value) as! XMLNode)
            rPrElem.addChild(elem)
        }
    }

    private static func setColor(_ rPrElem: XMLElement, hex: String) {
        if let elem = firstChild(localName: "color", in: rPrElem) {
            setValAttribute(elem, value: hex)
        } else {
            let elem = XMLElement(name: "w:color")
            elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: hex) as! XMLNode)
            rPrElem.addChild(elem)
        }
    }

    private static func setValAttribute(_ elem: XMLElement, value: String) {
        elem.removeAttribute(forName: "w:val")
        elem.removeAttribute(forName: "val")
        elem.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: value) as! XMLNode)
    }

    private static func firstChild(localName: String, in rPrElem: XMLElement) -> XMLElement? {
        (rPrElem.children ?? []).compactMap { $0 as? XMLElement }
            .first { $0.localName == localName }
    }

    private static func removeChildren(localName: String, in rPrElem: XMLElement) {
        for child in (rPrElem.children ?? []).compactMap({ $0 as? XMLElement }) where child.localName == localName {
            child.detach()
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        guard let normalized = RichTextSpan.normalizeHexColor(hex), normalized.count == 6 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&rgbValue)
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
