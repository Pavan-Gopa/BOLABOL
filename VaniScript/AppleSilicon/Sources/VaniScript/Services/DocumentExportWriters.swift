import AppKit
import CoreGraphics
import CoreText
import Foundation
import VaniScriptCore

public enum DocumentExportWriters {
    public enum ExportError: LocalizedError, Equatable {
        case missingSourceDocument
        case missingTranslation
        case invalidPackage(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingSourceDocument:
                return "The original source document is missing or not available."
            case .missingTranslation:
                return "No translated content is available to export."
            case let .invalidPackage(msg):
                return "The document package could not be processed: \(msg)"
            case let .writeFailed(msg):
                return "Failed to save exported file: \(msg)"
            }
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

    public static func writeDOCX(
        sourceDocxURL: URL,
        documentState: DocumentState,
        language: String? = nil,
        to destinationURL: URL
    ) throws {
        guard sourceDocxURL.isFileURL, FileManager.default.fileExists(atPath: sourceDocxURL.path) else {
            throw ExportError.missingSourceDocument
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

        // Group translated blocks by their part file path
        var blocksByPartPath: [String: [(block: DocumentBlock, translatedText: String)]] = [:]
        for block in documentState.blocks {
            guard let translated = translations[block.id]?.text,
                  TranslationArchive.isUsableTranslationText(translated)
            else { continue }

            let partPath = relativePartPath(from: block.location)
            blocksByPartPath[partPath, default: []].append((block: block, translatedText: translated))
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
                translatedItems.map { ($0.block.location.paragraphOrdinal, $0.translatedText) },
                uniquingKeysWith: { _, latest in latest }
            )

            for (ordinal, newText) in replacementsByOrdinal {
                guard ordinal < paragraphNodes.count, let pElem = paragraphNodes[ordinal] as? XMLElement else {
                    continue
                }
                rewriteParagraph(pElem: pElem, newText: newText)
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

    private static func rewriteParagraph(pElem: XMLElement, newText: String) {
        let runs: [XMLNode]
        do {
            runs = try pElem.nodes(forXPath: ".//*[local-name()=\"r\"]")
        } catch {
            return
        }

        if runs.isEmpty {
            let rElem = XMLElement(name: "w:r")
            let tElem = XMLElement(name: "w:t", stringValue: newText)
            if let attr = XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as? XMLNode {
                tElem.addAttribute(attr)
            }
            rElem.addChild(tElem)
            pElem.addChild(rElem)
            return
        }

        for (rIdx, rNode) in runs.enumerated() {
            guard let rElem = rNode as? XMLElement else { continue }
            let textNodes: [XMLNode]
            do {
                textNodes = try rElem.nodes(forXPath: ".//*[local-name()=\"t\"]")
            } catch {
                textNodes = []
            }

            if rIdx == 0 {
                if let firstT = textNodes.first as? XMLElement {
                    firstT.stringValue = newText
                    for remainingT in textNodes.dropFirst() {
                        (remainingT as? XMLElement)?.stringValue = ""
                    }
                } else {
                    let tElem = XMLElement(name: "w:t", stringValue: newText)
                    if let attr = XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as? XMLNode {
                        tElem.addAttribute(attr)
                    }
                    rElem.addChild(tElem)
                }
            } else {
                for tNode in textNodes {
                    (tNode as? XMLElement)?.stringValue = ""
                }
            }
        }
    }
}
