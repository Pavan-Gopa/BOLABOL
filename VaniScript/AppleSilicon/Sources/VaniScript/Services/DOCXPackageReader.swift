import VaniScriptCore
import CryptoKit
import Foundation

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
        var styleID: String?
        var paragraphPropertiesXML: String
        var hasNumbering = false
        var runs: [RunRecord]
        var text: String
    }

    private struct RunRecord {
        var text: String
        var styleXML: String
        var traits: Set<InlineTrait>
        var hyperlink: Bool
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
        private var currentParagraph: ParagraphRecord?
        private var currentRun: RunRecord?
        private var pPrBuilder: XMLFragmentBuilder?
        private var pPrDepth = 0
        private var rPrBuilder: XMLFragmentBuilder?
        private var rPrDepth = 0
        private var textDepth = 0
        private var ignoredDepth = 0
        private var hyperlinkDepth = 0

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
                || name == "bookmarkEnd" || name == "proofErr" || name == "drawing" || name == "pict"
                || name == "object" {
                ignoredDepth = 1
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
                return
            }

            switch name {
            case "p":
                if currentParagraph != nil {
                    finishRun()
                    finishParagraph()
                }
                currentParagraph = ParagraphRecord(
                    styleID: nil,
                    paragraphPropertiesXML: "",
                    hasNumbering: false,
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
                currentRun = RunRecord(text: "", styleXML: "", traits: [], hyperlink: hyperlinkDepth > 0)
            case "rPr":
                guard currentRun != nil else { return }
                rPrBuilder = XMLFragmentBuilder()
                rPrBuilder?.start(name: name, attributes: attributes)
                rPrDepth = 1
            case "hyperlink":
                hyperlinkDepth += 1
            case "t", "delText":
                if name == "t", currentRun != nil {
                    textDepth = 1
                }
            case "tab":
                currentRun?.text.append("\t")
            case "br", "cr":
                currentRun?.text.append("\n")
            case "noBreakHyphen":
                currentRun?.text.append("\u{2011}")
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
                    currentRun?.traits = Self.traits(from: styleXML)
                    rPrBuilder = nil
                }
                return
            }

            switch name {
            case "r":
                finishRun()
            case "p":
                finishRun()
                finishParagraph()
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
            } else if textDepth > 0, ignoredDepth == 0 {
                currentRun?.text.append(string)
                currentParagraph?.text.append(string)
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

            if let previous = paragraph.runs.last,
               previous.styleXML == run.styleXML,
               previous.traits == run.traits,
               previous.hyperlink == run.hyperlink {
                paragraph.runs[paragraph.runs.count - 1].text += run.text
            } else {
                paragraph.runs.append(run)
            }
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
            hyperlinkDepth = 0
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        private static func traits(from styleXML: String) -> Set<InlineTrait> {
            let lowercased = styleXML.lowercased()
            var result: Set<InlineTrait> = []
            if lowercased.contains("<b") { result.insert(.bold) }
            if lowercased.contains("<i") { result.insert(.italic) }
            if lowercased.contains("<u") { result.insert(.underline) }
            if lowercased.contains("<strike") || lowercased.contains("<dstrike") {
                result.insert(.strikethrough)
            }
            if lowercased.contains("superscript") { result.insert(.superscript) }
            if lowercased.contains("subscript") { result.insert(.subscriptText) }
            if lowercased.contains("smallcaps") { result.insert(.smallCaps) }
            return result
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
        let documentParts = entries
            .map(\.path)
            .filter(Self.isDocumentPart)
            .sorted { lhs, rhs in
                if lhs == "word/document.xml" { return true }
                if rhs == "word/document.xml" { return false }
                return lhs < rhs
            }
        for path in documentParts {
            guard let data = entryData[path] else { continue }
            let part = Self.documentPart(for: path)
            let partKey = part.rawValue
            let parsedParagraphs = try parseParagraphs(data, entryName: path)
            for paragraph in parsedParagraphs {
                let ordinal = partOrdinals[partKey, default: 0]
                partOrdinals[partKey] = ordinal + 1
                let normalizedText = paragraph.text.precomposedStringWithCanonicalMapping
                let blockID = stableID(seed: "\(path)#\(ordinal)#\(normalizedText)")
                let spans = paragraph.runs.enumerated().map { index, run in
                    RichTextSpan(
                        id: stableID(seed: "\(blockID)#span#\(index)"),
                        text: run.text.precomposedStringWithCanonicalMapping,
                        styleKey: run.styleXML,
                        traits: run.traits,
                        translationPolicy: .translate
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
                blocks.append(
                    DocumentBlock(
                        id: blockID,
                        location: DocumentLocation(
                            part: part,
                            paragraphOrdinal: ordinal,
                            xmlPath: "/\(path)/w:p[\(ordinal + 1)]"
                        ),
                        kind: kind,
                        styleID: paragraph.styleID,
                        paragraphPropertiesFingerprint: propertiesFingerprint,
                        spans: spans,
                        sourceHash: sourceHash,
                        translationPolicy: .translate
                    )
                )
            }
        }

        let metadata = try parseMetadata(entryData["docProps/core.xml"])
        let sourceHash = sha256(packageData)
        return ParsedDocument(
            blocks: blocks,
            metadata: metadata,
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
        var endOfCentralDirectory = -1
        if data.count >= 22 {
            for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
                if readUInt32(data, offset) == 0x06054b50 {
                    endOfCentralDirectory = offset
                    break
                }
            }
        }
        guard endOfCentralDirectory >= 0 else {
            throw DOCXPackageReaderError.invalidZip("end-of-central-directory record is missing")
        }

        let diskNumber = readUInt16(data, endOfCentralDirectory + 4)
        let centralDisk = readUInt16(data, endOfCentralDirectory + 6)
        let entriesOnDisk = readUInt16(data, endOfCentralDirectory + 8)
        let totalEntries = readUInt16(data, endOfCentralDirectory + 10)
        let centralSize = Int64(readUInt32(data, endOfCentralDirectory + 12))
        let centralOffset = Int64(readUInt32(data, endOfCentralDirectory + 16))
        guard diskNumber == 0, centralDisk == 0, entriesOnDisk == totalEntries else {
            throw DOCXPackageReaderError.invalidZip("multi-disk ZIP archives are not supported")
        }
        guard centralSize >= 0, centralOffset >= 0,
              centralOffset + centralSize <= Int64(data.count) else {
            throw DOCXPackageReaderError.invalidZip("central directory is outside the archive")
        }
        if totalEntries == .max || centralSize == Int64(UInt32.max) || centralOffset == Int64(UInt32.max) {
            throw DOCXPackageReaderError.invalidZip("ZIP64 archives are not supported by this importer")
        }

        var entries: [ZIPEntry] = []
        entries.reserveCapacity(Int(totalEntries))
        var cursor = Int(centralOffset)
        for _ in 0..<Int(totalEntries) {
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
            let localHeaderOffset = Int64(readUInt32(data, cursor + 42))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard cursor + recordLength <= data.count else {
                throw DOCXPackageReaderError.invalidZip("central directory entry is truncated")
            }
            guard compressedSize >= 0, uncompressedSize >= 0,
                  compressedSize <= limits.maxEntryBytes,
                  uncompressedSize <= limits.maxEntryBytes else {
                let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
                let name = String(data: nameData, encoding: .utf8) ?? "<invalid name>"
                throw DOCXPackageReaderError.entryTooLarge(name, uncompressedSize)
            }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                throw DOCXPackageReaderError.invalidZip("entry has an invalid UTF-8 name")
            }
            try validateEntryPath(name)
            guard flags & 0x1 == 0 else { throw DOCXPackageReaderError.encryptedEntry(name) }
            guard compressionMethod == 0 || compressionMethod == 8 else {
                throw DOCXPackageReaderError.unsupportedCompression(name)
            }
            guard localHeaderOffset + 30 <= Int64(data.count) else {
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

        // Foundation does not expose a ZIP/deflate decoder. Use the system
        // unzip reader in stream-to-stdout mode: no archive paths are written
        // to disk, and every name was validated before reaching Process.
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
        guard process.terminationStatus == 0, Int64(data.count) == entry.uncompressedSize else {
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

    private func parseParagraphs(_ data: Data, entryName: String) throws -> [ParagraphRecord] {
        guard !containsForbiddenXML(data) else {
            throw DOCXPackageReaderError.externalEntity(entryName)
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let delegate = ParagraphXMLDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXPackageReaderError.invalidXML(entryName)
        }
        return delegate.paragraphs
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
            || lower.contains("/header")
            || lower.contains("/footer")
            || lower.contains("footnotes")
            || lower.contains("endnotes")
    }

    private static func documentPart(for path: String) -> DocumentPart {
        let lower = path.lowercased()
        if lower.contains("header") { return .header }
        if lower.contains("footer") { return .footer }
        if lower.contains("footnotes") { return .footnote }
        if lower.contains("endnotes") { return .endnote }
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
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
