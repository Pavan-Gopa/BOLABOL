import AppKit
import CoreText
import CryptoKit
import Foundation
import VaniScriptCore
/// A small, read-only OOXML reader for the first document-import slice.
///
/// The app deliberately does not round-trip a DOCX through attributed strings:
/// the original package remains the source of truth for the writer in a later
/// slice. This reader only extracts paragraph structure and run styling.
struct DOCXPackageReader {
    struct Limits: Sendable, Equatable {
        var maxPackageBytes: Int64 = 64 * 1024 * 1024
        var maxEntryCount: Int = 2_000
        var maxEntryBytes: Int64 = 32 * 1024 * 1024

        static let `default` = Limits()
    }

    struct ParsedDocument: Sendable, Equatable {
        let blocks: [DocumentBlock]
        let metadata: DocumentMetadata
        let preflight: DocumentPreflight
        let sourceHash: String
        let entryNames: [String]
    }

    enum DOCXPackageReaderError: LocalizedError, Equatable {
        case fileNotFound
        case unsupportedPackage(String)
        case packageTooLarge(Int64)
        case tooManyEntries(Int)
        case entryTooLarge(String, Int64)
        case invalidZip(String)
        case unsafeEntryPath(String)
        case encryptedEntry(String)
        case unsupportedCompression(String)
        case cannotReadEntry(String)
        case externalRelationship(String)
        case externalEntity(String)
        case invalidXML(String)
        case missingMainDocument

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The selected document could not be found."
            case let .unsupportedPackage(message):
                return message
            case let .packageTooLarge(size):
                return "The document package is too large to import safely (\(size) bytes)."
            case let .tooManyEntries(count):
                return "The document package contains too many entries (\(count))."
            case let .entryTooLarge(name, size):
                return "The document package entry \(name) is too large to import safely (\(size) bytes)."
            case let .invalidZip(message):
                return "The document package is not a valid ZIP archive: \(message)"
            case let .unsafeEntryPath(name):
                return "The document package contains an unsafe ZIP path: \(name)"
            case let .encryptedEntry(name):
                return "Encrypted ZIP entries are not supported: \(name)"
            case let .unsupportedCompression(name):
                return "The document package uses unsupported compression for \(name)."
            case let .cannotReadEntry(name):
                return "The document package entry \(name) could not be read."
            case let .externalRelationship(name):
                return "External relationships are not allowed in imported documents (\(name))."
            case let .externalEntity(name):
                return "External XML entities are not allowed in imported documents (\(name))."
            case let .invalidXML(name):
                return "The document contains invalid XML in \(name)."
            case .missingMainDocument:
                return "The DOCX package does not contain word/document.xml."
            }
        }
    }

    private struct ZIPEntry: Sendable, Equatable {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
    }

    private struct ParagraphRecord {
        var part: DocumentPart
        var styleID: String?
        var paragraphPropertiesXML: String
        var hasNumbering: Bool
        var tablePath: [Int]?
        var runs: [RunRecord]
        var text: String
    }

    private struct RunFormatting: Equatable {
        var bold: Bool = false
        var italic: Bool = false
        var underline: String? = nil
        var strike: Bool = false
        var vertAlign: String? = nil
        var smallCaps: Bool = false
        var caps: Bool = false
        var highlight: String? = nil
        var color: String? = nil
        var size: String? = nil
        var font: String? = nil
        var language: String? = nil
        var styleID: String? = nil
        var hyperlink: Bool = false
        var isProtected: Bool = false

        var traits: Set<InlineTrait> {
            var result: Set<InlineTrait> = []
            if bold { result.insert(.bold) }
            if italic { result.insert(.italic) }
            if underline != nil { result.insert(.underline) }
            if strike { result.insert(.strikethrough) }
            if vertAlign == "superscript" { result.insert(.superscript) }
            if vertAlign == "subscript" { result.insert(.subscriptText) }
            if smallCaps { result.insert(.smallCaps) }
            return result
        }

        var key: String {
            "b:\(bold)|i:\(italic)|u:\(underline ?? "")|str:\(strike)|va:\(vertAlign ?? "")|sc:\(smallCaps)|caps:\(caps)|hl:\(highlight ?? "")|c:\(color ?? "")|sz:\(size ?? "")|font:\(font ?? "")|lang:\(language ?? "")|sid:\(styleID ?? "")|link:\(hyperlink)|prot:\(isProtected)"
        }
    }

    private struct RunRecord {
        var text: String
        var styleXML: String
        var formatting: RunFormatting
    }

    private final class XMLFragmentBuilder {
        var value = ""

        func start(name: String, attributes: [String: String]) {
            value += "<\(name)"
            for key in attributes.keys.sorted() {
                let escaped = Self.escape(attributes[key] ?? "")
                value += " \(key)=\"\(escaped)\""
            }
            value += ">"
        }

        func end(name: String) {
            value += "</\(name)>"
        }

        func characters(_ text: String) {
            value += Self.escape(text)
        }

        private static func escape(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
    }

    private final class ParagraphXMLDelegate: NSObject, XMLParserDelegate {
        private(set) var paragraphs: [ParagraphRecord] = []
        private(set) var sectionCount: Int = 0
        private(set) var fontNames: Set<String> = []

        private let defaultPart: DocumentPart

        private var currentParagraph: ParagraphRecord?
        private var currentRun: RunRecord?
        private var currentFormatting = RunFormatting()
        private var inRun = false

        private var paragraphStack: [ParagraphRecord] = []
        private var runStack: [RunRecord?] = []

        private struct TableContext {
            var tableIndex: Int
            var rowIndex: Int
            var cellIndex: Int
        }
        private var tableStack: [TableContext] = []
        private var tableCountersByDepth: [Int: Int] = [:]

        private var pPrBuilder: XMLFragmentBuilder?
        private var pPrDepth = 0
        private var rPrBuilder: XMLFragmentBuilder?
        private var rPrDepth = 0
        private var textDepth = 0
        private var ignoredDepth = 0
        private var hyperlinkDepth = 0
        private var textBoxDepth = 0

        init(defaultPart: DocumentPart) {
            self.defaultPart = defaultPart
            super.init()
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = Self.localName(qName ?? elementName)
            let attributes = Dictionary(uniqueKeysWithValues: attributeDict.map { key, value in
                (Self.localName(key), value)
            })

            if ignoredDepth > 0 {
                ignoredDepth += 1
                return
            }

            if name == "del" || name == "instrText" || name == "fldChar" || name == "bookmarkStart"
                || name == "bookmarkEnd" || name == "proofErr" || name == "delText"
                || name == "commentReference" || name == "commentRangeStart" || name == "commentRangeEnd" {
                ignoredDepth = 1
                return
            }

            if name == "sectPr" {
                sectionCount += 1
            }

            if name == "txbxContent" {
                textBoxDepth += 1
            }

            if name == "tbl" {
                let depth = tableStack.count
                let tableIndex = tableCountersByDepth[depth, default: 0]
                tableCountersByDepth[depth] = tableIndex + 1
                tableStack.append(TableContext(tableIndex: tableIndex, rowIndex: -1, cellIndex: -1))
                return
            }

            if name == "tr" {
                if !tableStack.isEmpty {
                    tableStack[tableStack.count - 1].rowIndex += 1
                    tableStack[tableStack.count - 1].cellIndex = -1
                }
                return
            }

            if name == "tc" {
                if !tableStack.isEmpty {
                    tableStack[tableStack.count - 1].cellIndex += 1
                }
                return
            }

            if pPrDepth > 0 {
                pPrBuilder?.start(name: name, attributes: attributes)
                pPrDepth += 1
                if name == "pStyle" {
                    currentParagraph?.styleID = attributes["val"]
                }
                if name == "numPr" {
                    currentParagraph?.hasNumbering = true
                }
                return
            }

            if rPrDepth > 0 {
                rPrBuilder?.start(name: name, attributes: attributes)
                rPrDepth += 1

                let val = attributes["val"]
                let isOff = (val == "0" || val == "false" || val == "off")

                switch name {
                case "b", "bCs":
                    currentFormatting.bold = !isOff
                case "i", "iCs":
                    currentFormatting.italic = !isOff
                case "smallCaps":
                    currentFormatting.smallCaps = !isOff
                case "caps":
                    currentFormatting.caps = !isOff
                case "strike", "dstrike":
                    currentFormatting.strike = !isOff
                case "u":
                    if val == "none" || isOff {
                        currentFormatting.underline = nil
                    } else {
                        currentFormatting.underline = val ?? "single"
                    }
                case "vertAlign":
                    if val == "superscript" || val == "subscript" {
                        currentFormatting.vertAlign = val
                    } else {
                        currentFormatting.vertAlign = nil
                    }
                case "highlight":
                    if val == "none" || isOff {
                        currentFormatting.highlight = nil
                    } else {
                        currentFormatting.highlight = val
                    }
                case "color":
                    if val == "auto" || val == nil {
                        currentFormatting.color = nil
                    } else {
                        currentFormatting.color = val
                    }
                case "sz", "szCs":
                    currentFormatting.size = val
                case "rFonts":
                    if let font = attributes["ascii"] ?? attributes["hAnsi"] ?? attributes["cs"] ?? attributes["val"] {
                        currentFormatting.font = font
                        fontNames.insert(font)
                    }
                case "lang":
                    currentFormatting.language = attributes["val"] ?? attributes["bidi"] ?? attributes["eastAsia"]
                case "rStyle":
                    currentFormatting.styleID = val
                case "vaniscriptProtect", "protect":
                    currentFormatting.isProtected = !isOff
                default:
                    break
                }
                return
            }

            switch name {
            case "p":
                if let active = currentParagraph {
                    finishRun()
                    paragraphStack.append(active)
                    runStack.append(currentRun)
                    currentRun = nil
                }
                let part: DocumentPart = textBoxDepth > 0 ? .textBox : defaultPart
                let tablePath: [Int]? = tableStack.isEmpty ? nil : tableStack.flatMap { [$0.tableIndex, $0.rowIndex, $0.cellIndex] }
                currentParagraph = ParagraphRecord(
                    part: part,
                    styleID: nil,
                    paragraphPropertiesXML: "",
                    hasNumbering: false,
                    tablePath: tablePath,
                    runs: [],
                    text: ""
                )
            case "pPr":
                guard currentParagraph != nil else { return }
                pPrBuilder = XMLFragmentBuilder()
                pPrBuilder?.start(name: name, attributes: attributes)
                pPrDepth = 1
            case "pStyle":
                if currentParagraph != nil {
                    currentParagraph?.styleID = attributes["val"]
                }
            case "numPr":
                currentParagraph?.hasNumbering = true
            case "r":
                finishRun()
                inRun = true
                currentFormatting = RunFormatting(hyperlink: hyperlinkDepth > 0)
                currentRun = RunRecord(
                    text: "",
                    styleXML: "",
                    formatting: currentFormatting
                )
            case "rPr":
                guard inRun, currentRun != nil else { return }
                rPrBuilder = XMLFragmentBuilder()
                rPrBuilder?.start(name: name, attributes: attributes)
                rPrDepth = 1
            case "hyperlink":
                hyperlinkDepth += 1
            case "t":
                if inRun, currentRun != nil {
                    textDepth = 1
                }
            case "tab":
                if inRun {
                    currentRun?.text.append("\t")
                }
            case "br", "cr":
                if inRun {
                    currentRun?.text.append("\n")
                }
            case "noBreakHyphen":
                if inRun {
                    currentRun?.text.append("\u{2011}")
                }
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = Self.localName(qName ?? elementName)

            if ignoredDepth > 0 {
                ignoredDepth -= 1
                return
            }

            if textDepth > 0, name == "t" {
                textDepth = 0
                return
            }

            if pPrDepth > 0 {
                pPrBuilder?.end(name: name)
                pPrDepth -= 1
                if pPrDepth == 0 {
                    currentParagraph?.paragraphPropertiesXML = pPrBuilder?.value ?? ""
                    pPrBuilder = nil
                }
                return
            }

            if rPrDepth > 0 {
                rPrBuilder?.end(name: name)
                rPrDepth -= 1
                if rPrDepth == 0 {
                    let styleXML = rPrBuilder?.value ?? ""
                    currentRun?.styleXML = styleXML
                    currentFormatting.hyperlink = hyperlinkDepth > 0
                    currentRun?.formatting = currentFormatting
                    rPrBuilder = nil
                }
                return
            }

            switch name {
            case "r":
                finishRun()
                inRun = false
            case "p":
                finishRun()
                finishParagraph()
            case "tbl":
                if !tableStack.isEmpty {
                    tableStack.removeLast()
                }
            case "txbxContent":
                textBoxDepth = max(0, textBoxDepth - 1)
            case "hyperlink":
                hyperlinkDepth = max(0, hyperlinkDepth - 1)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if pPrDepth > 0 {
                pPrBuilder?.characters(string)
            } else if rPrDepth > 0 {
                rPrBuilder?.characters(string)
            } else if textDepth > 0, ignoredDepth == 0, inRun {
                currentRun?.text.append(string)
            }
        }

        private func finishRun() {
            guard var paragraph = currentParagraph, var run = currentRun else {
                currentRun = nil
                return
            }
            currentRun = nil
            run.text = run.text.precomposedStringWithCanonicalMapping
            guard !run.text.isEmpty else { return }

            currentFormatting.hyperlink = hyperlinkDepth > 0
            run.formatting = currentFormatting

            if let previous = paragraph.runs.last,
               previous.formatting.key == run.formatting.key {
                paragraph.runs[paragraph.runs.count - 1].text += run.text
            } else {
                paragraph.runs.append(run)
            }
            paragraph.text = paragraph.runs.map(\.text).joined()
            currentParagraph = paragraph
        }

        private func finishParagraph() {
            guard let paragraph = currentParagraph else { return }
            paragraphs.append(paragraph)
            currentParagraph = nil
            currentRun = nil
            pPrBuilder = nil
            pPrDepth = 0
            rPrBuilder = nil
            rPrDepth = 0
            textDepth = 0
            ignoredDepth = 0
            inRun = false

            if !paragraphStack.isEmpty {
                currentParagraph = paragraphStack.removeLast()
                currentRun = runStack.removeLast()
                inRun = currentRun != nil
            }
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    private final class CoreMetadataDelegate: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private var currentElement: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentElement = Self.localName(qName ?? elementName)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let currentElement else { return }
            values[currentElement, default: ""] += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            currentElement = nil
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    private final class AppPropertiesDelegate: NSObject, XMLParserDelegate {
        var pages: Int = 0
        var words: Int = 0
        var characters: Int = 0
        var lines: Int = 0
        var paragraphs: Int = 0
        private var currentElement: String?
        private var currentText = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentElement = Self.localName(qName ?? elementName)
            currentText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentElement {
            case "Pages":
                pages = Int(value) ?? 0
            case "Words":
                words = Int(value) ?? 0
            case "Characters":
                characters = Int(value) ?? 0
            case "Lines":
                lines = Int(value) ?? 0
            case "Paragraphs":
                paragraphs = Int(value) ?? 0
            default:
                break
            }
            currentElement = nil
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    private final class FontTableDelegate: NSObject, XMLParserDelegate {
        var fontNames: Set<String> = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = Self.localName(qName ?? elementName)
            if name == "font" {
                if let fontName = attributeDict["w:name"] ?? attributeDict["name"] {
                    let cleaned = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        fontNames.insert(cleaned)
                    }
                }
            }
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    let limits: Limits

    init(limits: Limits = .default) {
        self.limits = limits
    }

    func read(from url: URL) throws -> ParsedDocument {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw DOCXPackageReaderError.fileNotFound
        }
        guard url.pathExtension.lowercased() == "docx" else {
            if url.pathExtension.lowercased() == "docm" {
                throw DOCXPackageReaderError.unsupportedPackage(
                    "Macro-enabled Word documents (.docm) are not supported."
                )
            }
            throw DOCXPackageReaderError.unsupportedPackage("Only .docx packages can be read by DOCXPackageReader.")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let packageSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard packageSize <= limits.maxPackageBytes else {
            throw DOCXPackageReaderError.packageTooLarge(packageSize)
        }
        let packageData = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard Int64(packageData.count) <= limits.maxPackageBytes else {
            throw DOCXPackageReaderError.packageTooLarge(Int64(packageData.count))
        }

        let entries = try parseEntries(packageData)
        guard entries.count <= limits.maxEntryCount else {
            throw DOCXPackageReaderError.tooManyEntries(entries.count)
        }
        guard entries.contains(where: { $0.path == "word/document.xml" }) else {
            throw DOCXPackageReaderError.missingMainDocument
        }

        var entryData: [String: Data] = [:]
        entryData.reserveCapacity(entries.count)
        var totalExpandedBytes: Int64 = 0
        for entry in entries where !entry.path.hasSuffix("/") {
            if entry.path.lowercased().contains("vbaproject") {
                throw DOCXPackageReaderError.unsupportedPackage("Macro-enabled content is not supported in DOCX packages.")
            }
            guard entry.uncompressedSize <= limits.maxEntryBytes else {
                throw DOCXPackageReaderError.entryTooLarge(entry.path, entry.uncompressedSize)
            }
            totalExpandedBytes += entry.uncompressedSize
            guard totalExpandedBytes <= limits.maxPackageBytes else {
                throw DOCXPackageReaderError.packageTooLarge(totalExpandedBytes)
            }
            let data = try readEntry(entry, from: packageData, archiveURL: url)
            guard Int64(data.count) <= limits.maxEntryBytes else {
                throw DOCXPackageReaderError.entryTooLarge(entry.path, Int64(data.count))
            }
            entryData[entry.path] = data
        }

        for entry in entries where entry.path.lowercased().hasSuffix(".rels") {
            guard let data = entryData[entry.path] else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if containsExternalRelationship(text) {
                throw DOCXPackageReaderError.externalRelationship(entry.path)
            }
        }

        for entry in entries where entry.path.lowercased().hasSuffix(".xml") {
            guard let data = entryData[entry.path] else { continue }
            let lower = String(decoding: data, as: UTF8.self).lowercased()
            if lower.contains("<!doctype") || lower.contains("<!entity") || lower.contains("system \"")
                || lower.contains("public \"") {
                throw DOCXPackageReaderError.externalEntity(entry.path)
            }
        }

        var blocks: [DocumentBlock] = []
        var partOrdinals: [String: Int] = [:]
        var totalSectionCount = 0
        var allFonts: Set<String> = []

        if let fontTableData = entryData["word/fontTable.xml"] {
            let fontTableFonts = try parseFontTable(fontTableData)
            allFonts.formUnion(fontTableFonts)
        }

        let documentParts = entries
            .map(\.path)
            .filter(Self.isDocumentPart)
            .sorted { lhs, rhs in
                let pL = Self.partSortPriority(for: lhs)
                let pR = Self.partSortPriority(for: rhs)
                if pL != pR { return pL < pR }
                return lhs < rhs
            }

        for path in documentParts {
            guard let data = entryData[path] else { continue }
            let defaultPart = Self.documentPart(for: path)
            let (parsedParagraphs, sectionCount, fontNames) = try parseParagraphs(
                data,
                entryName: path,
                defaultPart: defaultPart
            )
            totalSectionCount += sectionCount
            allFonts.formUnion(fontNames)

            for paragraph in parsedParagraphs {
                let part = paragraph.part
                let partKey = part.rawValue
                let ordinal = partOrdinals[partKey, default: 0]
                partOrdinals[partKey] = ordinal + 1

                let normalizedText = paragraph.text.precomposedStringWithCanonicalMapping
                let tableTag = paragraph.tablePath?.map(String.init).joined(separator: "_") ?? "p"
                let blockID = stableID(seed: "\(path)#\(tableTag)#\(ordinal)#\(normalizedText)")

                let spans = paragraph.runs.enumerated().map { index, run in
                    RichTextSpan(
                        id: stableID(seed: "\(blockID)#span#\(index)"),
                        text: run.text.precomposedStringWithCanonicalMapping,
                        styleKey: run.styleXML.isEmpty ? run.formatting.key : run.styleXML,
                        traits: run.formatting.traits,
                        translationPolicy: run.formatting.isProtected ? .protect : .translate,
                        foregroundColorHex: run.formatting.color
                    )
                }

                let propertiesFingerprint = paragraph.paragraphPropertiesXML.isEmpty
                    ? ""
                    : stableID(seed: paragraph.paragraphPropertiesXML)

                let kind = Self.blockKind(
                    styleID: paragraph.styleID,
                    hasNumbering: paragraph.hasNumbering,
                    text: normalizedText
                )

                let sourceHash = stableID(seed: "\(normalizedText)|\(propertiesFingerprint)|\(spans.map(\.text).joined())")

                let xmlPath: String
                if let tablePath = paragraph.tablePath, tablePath.count >= 3 {
                    let t = tablePath[0] + 1
                    let r = tablePath[1] + 1
                    let c = tablePath[2] + 1
                    xmlPath = "/\(path)/w:tbl[\(t)]/w:tr[\(r)]/w:tc[\(c)]/w:p[\(ordinal + 1)]"
                } else if part == .textBox {
                    xmlPath = "/\(path)/w:txbxContent/w:p[\(ordinal + 1)]"
                } else {
                    xmlPath = "/\(path)/w:p[\(ordinal + 1)]"
                }

                let isBlockProtected = kind == .verse || (!spans.isEmpty && spans.allSatisfy { $0.translationPolicy == .protect })

                blocks.append(
                    DocumentBlock(
                        id: blockID,
                        location: DocumentLocation(
                            part: part,
                            paragraphOrdinal: ordinal,
                            tablePath: paragraph.tablePath,
                            xmlPath: xmlPath
                        ),
                        kind: kind,
                        styleID: paragraph.styleID,
                        paragraphPropertiesFingerprint: propertiesFingerprint,
                        spans: spans,
                        sourceHash: sourceHash,
                        translationPolicy: isBlockProtected ? .protect : .translate
                    )
                )
            }
        }

        let appProps = try parseAppProperties(entryData["docProps/app.xml"] ?? entryData["docProps/extended.xml"])
        let fontWarnings = Self.checkFontAvailability(fontNames: allFonts)

        let extractedWordCount = blocks.reduce(0) { count, block in
            count + block.spans.reduce(0) { spanCount, span in
                spanCount + span.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        let effectiveWords = appProps.words > 0 ? appProps.words : extractedWordCount
        let effectivePages = appProps.pages > 0 ? appProps.pages : max(1, (effectiveWords + 299) / 300)
        let effectiveSections = max(1, totalSectionCount)
        let blockCount = blocks.count
        let protectedGroupCount = blocks.filter {
            $0.translationPolicy == .protect || $0.spans.contains { $0.translationPolicy == .protect }
        }.count

        let preflight = DocumentPreflight(
            pageCount: effectivePages,
            wordCount: effectiveWords,
            sectionCount: effectiveSections,
            blockCount: blockCount,
            protectedGroupCount: protectedGroupCount,
            fontWarnings: fontWarnings
        )

        var metadata = try parseMetadata(entryData["docProps/core.xml"])
        metadata.pageCount = preflight.pageCount
        metadata.wordCount = preflight.wordCount
        metadata.sectionCount = preflight.sectionCount
        metadata.blockCount = preflight.blockCount
        metadata.protectedGroupCount = preflight.protectedGroupCount
        metadata.fontWarnings = preflight.fontWarnings

        let sourceHash = sha256(packageData)
        return ParsedDocument(
            blocks: blocks,
            metadata: metadata,
            preflight: preflight,
            sourceHash: sourceHash,
            entryNames: entries.map(\.path)
        )
    }

    static func read(from url: URL, limits: Limits = .default) throws -> ParsedDocument {
        try DOCXPackageReader(limits: limits).read(from: url)
    }

    static func read(url: URL, limits: Limits = .default) throws -> ParsedDocument {
        try read(from: url, limits: limits)
    }

    private func parseEntries(_ data: Data) throws -> [ZIPEntry] {
        guard data.count >= 22 else { throw DOCXPackageReaderError.invalidZip("archive is truncated") }
        let minimumOffset = max(0, data.count - 65_557)

        struct ValidatedEOCD {
            let offset: Int
            let totalEntries: Int
            let centralSize: Int64
            let rawCentralOffset: Int64
            let archiveOffset: Int
            let actualCentralOffset: Int
            let exactCommentMatch: Bool
        }

        var candidates: [ValidatedEOCD] = []

        for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
            guard readUInt32(data, offset) == 0x06054b50 else { continue }

            let diskNumber = readUInt16(data, offset + 4)
            let centralDisk = readUInt16(data, offset + 6)
            let entriesOnDisk = readUInt16(data, offset + 8)
            let totalEntries = readUInt16(data, offset + 10)
            let centralSize = Int64(readUInt32(data, offset + 12))
            let rawCentralOffset = Int64(readUInt32(data, offset + 16))
            let commentLength = Int(readUInt16(data, offset + 20))

            guard diskNumber == 0, centralDisk == 0, entriesOnDisk == totalEntries else {
                continue
            }
            guard centralSize >= 0, rawCentralOffset >= 0 else {
                continue
            }
            guard offset + 22 + commentLength <= data.count else {
                continue
            }
            if totalEntries == .max || centralSize == Int64(UInt32.max) || rawCentralOffset == Int64(UInt32.max) {
                throw DOCXPackageReaderError.invalidZip("ZIP64 archives are not supported by this importer")
            }

            let exactMatch = (offset + 22 + commentLength == data.count)

            var resolvedArchiveOffset: Int?
            var resolvedCentralOffset: Int?

            // 1. Standard (no prefix / absolute 0-based offset)
            if rawCentralOffset + centralSize <= Int64(offset) {
                let cdOffset = Int(rawCentralOffset)
                if totalEntries == 0 && centralSize == 0 {
                    resolvedArchiveOffset = 0
                    resolvedCentralOffset = cdOffset
                } else if totalEntries > 0 && cdOffset + 46 <= offset && readUInt32(data, cdOffset) == 0x02014b50 {
                    resolvedArchiveOffset = 0
                    resolvedCentralOffset = cdOffset
                }
            }

            // 2. Prefixed archive (offset relative to start of embedded zip stream)
            if resolvedCentralOffset == nil {
                let computedCDOffset = offset - Int(centralSize)
                let computedArchiveOffset = computedCDOffset - Int(rawCentralOffset)
                if computedArchiveOffset > 0 && computedCDOffset >= 0 {
                    if totalEntries == 0 && centralSize == 0 {
                        resolvedArchiveOffset = computedArchiveOffset
                        resolvedCentralOffset = computedCDOffset
                    } else if totalEntries > 0 && computedCDOffset + 46 <= offset && readUInt32(data, computedCDOffset) == 0x02014b50 {
                        resolvedArchiveOffset = computedArchiveOffset
                        resolvedCentralOffset = computedCDOffset
                    }
                }
            }

            guard let archiveOffset = resolvedArchiveOffset,
                  let actualCentralOffset = resolvedCentralOffset else {
                continue
            }

            // Verify central directory entry chain
            var cursor = actualCentralOffset
            var chainValid = true
            for _ in 0..<Int(totalEntries) {
                guard cursor + 46 <= data.count, readUInt32(data, cursor) == 0x02014b50 else {
                    chainValid = false
                    break
                }
                let nameLength = Int(readUInt16(data, cursor + 28))
                let extraLength = Int(readUInt16(data, cursor + 30))
                let commentLen = Int(readUInt16(data, cursor + 32))
                let recordLength = 46 + nameLength + extraLength + commentLen
                guard cursor + recordLength <= data.count else {
                    chainValid = false
                    break
                }
                cursor += recordLength
            }

            guard chainValid else { continue }

            let candidate = ValidatedEOCD(
                offset: offset,
                totalEntries: Int(totalEntries),
                centralSize: centralSize,
                rawCentralOffset: rawCentralOffset,
                archiveOffset: archiveOffset,
                actualCentralOffset: actualCentralOffset,
                exactCommentMatch: exactMatch
            )

            if exactMatch {
                candidates = [candidate]
                break
            } else {
                candidates.append(candidate)
            }
        }

        guard let selectedEOCD = candidates.first else {
            throw DOCXPackageReaderError.invalidZip("end-of-central-directory record is missing")
        }

        var entries: [ZIPEntry] = []
        entries.reserveCapacity(selectedEOCD.totalEntries)
        var cursor = selectedEOCD.actualCentralOffset
        for _ in 0..<selectedEOCD.totalEntries {
            guard cursor + 46 <= data.count, readUInt32(data, cursor) == 0x02014b50 else {
                throw DOCXPackageReaderError.invalidZip("central directory entry is malformed")
            }
            let flags = readUInt16(data, cursor + 8)
            let compressionMethod = readUInt16(data, cursor + 10)
            let compressedSize = Int64(readUInt32(data, cursor + 20))
            let uncompressedSize = Int64(readUInt32(data, cursor + 24))
            let nameLength = Int(readUInt16(data, cursor + 28))
            let extraLength = Int(readUInt16(data, cursor + 30))
            let commentLength = Int(readUInt16(data, cursor + 32))
            let rawLocalHeaderOffset = Int64(readUInt32(data, cursor + 42))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard cursor + recordLength <= data.count else {
                throw DOCXPackageReaderError.invalidZip("central directory entry is truncated")
            }
            guard compressedSize >= 0, uncompressedSize >= 0,
                  compressedSize <= limits.maxEntryBytes,
                  uncompressedSize <= limits.maxEntryBytes else {
                let nameStart = data.startIndex + cursor + 46
                let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
                let name = String(data: nameData, encoding: .utf8) ?? "<invalid name>"
                throw DOCXPackageReaderError.entryTooLarge(name, uncompressedSize)
            }
            let nameStart = data.startIndex + cursor + 46
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                throw DOCXPackageReaderError.invalidZip("entry has an invalid UTF-8 name")
            }
            try validateEntryPath(name)
            guard flags & 0x1 == 0 else { throw DOCXPackageReaderError.encryptedEntry(name) }
            guard compressionMethod == 0 || compressionMethod == 8 else {
                throw DOCXPackageReaderError.unsupportedCompression(name)
            }
            let localHeaderOffset = rawLocalHeaderOffset + Int64(selectedEOCD.archiveOffset)
            guard localHeaderOffset >= 0, localHeaderOffset + 30 <= Int64(data.count) else {
                throw DOCXPackageReaderError.invalidZip("local header is outside the archive")
            }
            entries.append(
                ZIPEntry(
                    path: name,
                    flags: flags,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            cursor += recordLength
        }
        return entries
    }

    private func readEntry(_ entry: ZIPEntry, from packageData: Data, archiveURL: URL) throws -> Data {
        if entry.compressionMethod == 0 {
            let dataStart = try localDataStart(entry, in: packageData)
            let end = dataStart + Int(entry.compressedSize)
            guard dataStart >= 0, end <= packageData.count else {
                throw DOCXPackageReaderError.cannotReadEntry(entry.path)
            }
            let data = packageData.subdata(in: dataStart..<end)
            guard Int64(data.count) == entry.uncompressedSize else {
                throw DOCXPackageReaderError.cannotReadEntry(entry.path)
            }
            return data
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archiveURL.path, escapedUnzipPattern(entry.path)]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            throw DOCXPackageReaderError.cannotReadEntry(entry.path)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard (process.terminationStatus == 0 || process.terminationStatus == 1),
              Int64(data.count) == entry.uncompressedSize else {
            throw DOCXPackageReaderError.cannotReadEntry(entry.path)
        }
        return data
    }

    private func localDataStart(_ entry: ZIPEntry, in data: Data) throws -> Int {
        let offset = Int(entry.localHeaderOffset)
        guard offset >= 0, offset + 30 <= data.count, readUInt32(data, offset) == 0x04034b50 else {
            throw DOCXPackageReaderError.cannotReadEntry(entry.path)
        }
        let nameLength = Int(readUInt16(data, offset + 26))
        let extraLength = Int(readUInt16(data, offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start <= data.count else { throw DOCXPackageReaderError.cannotReadEntry(entry.path) }
        return start
    }

    private func parseParagraphs(
        _ data: Data,
        entryName: String,
        defaultPart: DocumentPart
    ) throws -> (paragraphs: [ParagraphRecord], sectionCount: Int, fontNames: Set<String>) {
        guard !containsForbiddenXML(data) else {
            throw DOCXPackageReaderError.externalEntity(entryName)
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let delegate = ParagraphXMLDelegate(defaultPart: defaultPart)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXPackageReaderError.invalidXML(entryName)
        }
        return (delegate.paragraphs, delegate.sectionCount, delegate.fontNames)
    }

    private func parseAppProperties(_ data: Data?) throws -> AppPropertiesDelegate {
        let delegate = AppPropertiesDelegate()
        guard let data else { return delegate }
        guard !containsForbiddenXML(data) else {
            throw DOCXPackageReaderError.externalEntity("docProps/app.xml")
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        return delegate
    }

    private func parseFontTable(_ data: Data?) throws -> Set<String> {
        guard let data else { return [] }
        guard !containsForbiddenXML(data) else {
            throw DOCXPackageReaderError.externalEntity("word/fontTable.xml")
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let delegate = FontTableDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            return []
        }
        return delegate.fontNames
    }

    private static func checkFontAvailability(fontNames: Set<String>) -> [String] {
        var warnings: [String] = []
        for font in fontNames.sorted() {
            if !isFontAvailable(font) {
                warnings.append("Font '\(font)' is referenced in the document but is not installed locally; fallback substitution may occur in external viewers.")
            }
        }
        return warnings
    }

    private static func isFontAvailable(_ name: String) -> Bool {
        let lower = name.lowercased()
        if ["times new roman", "arial", "calibri", "cambria", "helvetica", "georgia", "courier new", "verdana", "tahoma", "system font", "courier", "menlo", "monaco"].contains(lower) {
            return true
        }
        if NSFont(name: name, size: 12) != nil {
            return true
        }
        let fontNameCF = name as CFString
        let descriptor = CTFontDescriptorCreateWithNameAndSize(fontNameCF, 12.0)
        let matching = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor]
        return !(matching?.isEmpty ?? true)
    }

    private static func partSortPriority(for path: String) -> Int {
        let lower = path.lowercased()
        if lower == "word/document.xml" { return 0 }
        if lower.contains("header") { return 1 }
        if lower.contains("footer") { return 2 }
        if lower.contains("footnote") { return 3 }
        if lower.contains("endnote") { return 4 }
        return 5
    }

    private func parseMetadata(_ data: Data?) throws -> DocumentMetadata {
        guard let data else { return DocumentMetadata() }
        guard !containsForbiddenXML(data) else {
            throw DOCXPackageReaderError.externalEntity("docProps/core.xml")
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let delegate = CoreMetadataDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw DOCXPackageReaderError.invalidXML("docProps/core.xml") }
        return DocumentMetadata(
            title: delegate.values["title"].flatMap(Self.nonEmpty),
            author: delegate.values["creator"].flatMap(Self.nonEmpty),
            subject: delegate.values["subject"].flatMap(Self.nonEmpty),
            createdAt: delegate.values["created"].flatMap(Self.nonEmpty),
            modifiedAt: delegate.values["modified"].flatMap(Self.nonEmpty)
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func isDocumentPart(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasPrefix("word/"), lower.hasSuffix(".xml") else { return false }
        return lower == "word/document.xml"
            || lower.contains("header")
            || lower.contains("footer")
            || lower.contains("footnotes")
            || lower.contains("endnotes")
    }

    private static func documentPart(for path: String) -> DocumentPart {
        let lower = path.lowercased()
        if lower.contains("header") { return .header }
        if lower.contains("footer") { return .footer }
        if lower.contains("footnote") { return .footnote }
        if lower.contains("endnote") { return .endnote }
        return .mainBody
    }

    private static func blockKind(styleID: String?, hasNumbering: Bool, text: String) -> DocumentBlockKind {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        let style = styleID?.lowercased() ?? ""
        if hasNumbering || style.contains("list") { return .listItem }
        if style.contains("quote") { return .quote }
        if style.contains("heading") || style.contains("title") || style.contains("chapter") {
            return .heading
        }
        return .paragraph
    }

    private static func stableID(seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func stableID(seed: String) -> String {
        Self.stableID(seed: seed)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func containsForbiddenXML(_ data: Data) -> Bool {
        let lower = String(decoding: data, as: UTF8.self).lowercased()
        return lower.contains("<!doctype") || lower.contains("<!entity") || lower.contains("system \"")
            || lower.contains("public \"")
    }

    private func containsExternalRelationship(_ xml: String) -> Bool {
        let lower = xml.lowercased()
        let compact = lower.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if compact.contains("targetmode=\"external\"") || compact.contains("targetmode='external'") {
            return true
        }
        return compact
            .components(separatedBy: "<relationship")
            .dropFirst()
            .contains { fragment in
                guard let marker = fragment.range(of: "target=\"") else {
                    return false
                }
                let targetStart = marker.upperBound
                guard let targetEnd = fragment[targetStart...].firstIndex(of: "\"") else {
                    return false
                }
                let target = String(fragment[targetStart..<targetEnd])
                return target.hasPrefix("http://")
                    || target.hasPrefix("https://")
                    || target.hasPrefix("ftp://")
                    || target.hasPrefix("file://")
                    || target.hasPrefix("mailto:")
            }
    }

    private func validateEntryPath(_ path: String) throws {
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains(":"), !path.contains("\0") else {
            throw DOCXPackageReaderError.unsafeEntryPath(path)
        }
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard !components.contains(".."), !components.contains(where: { $0.isEmpty }) else {
            throw DOCXPackageReaderError.unsafeEntryPath(path)
        }
    }

    private func escapedUnzipPattern(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
    }

    private func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }
}
