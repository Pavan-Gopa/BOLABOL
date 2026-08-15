import AppKit
import CryptoKit
import Foundation
import PDFKit
import VaniScriptCore
struct PDFDocumentImporter: Sendable {
    struct Limits: Sendable, Equatable {
        var maxFileBytes: Int64
        var maxPageCount: Int

        static let `default` = Limits(
            maxFileBytes: 100 * 1024 * 1024, // 100 MiB
            maxPageCount: 2_000
        )

        init(
            maxFileBytes: Int64 = 100 * 1024 * 1024,
            maxPageCount: Int = 2_000
        ) {
            self.maxFileBytes = maxFileBytes
            self.maxPageCount = maxPageCount
        }
    }

    enum PDFImporterError: LocalizedError, Equatable {
        case fileNotFound
        case invalidPDF(String)
        case scannedPDFNotSupported
        case fileSizeExceedsLimit(size: Int64, limit: Int64)
        case pageCountExceedsLimit(count: Int, limit: Int)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The PDF document could not be found."
            case let .invalidPDF(message):
                return "The PDF document could not be read: \(message)"
            case .scannedPDFNotSupported:
                return "This PDF contains no text layer and appears to be scanned. Optical Character Recognition (OCR) is not supported in this release."
            case let .fileSizeExceedsLimit(size, limit):
                return "The PDF document size (\(size) bytes) exceeds the safety limit of \(limit) bytes."
            case let .pageCountExceedsLimit(count, limit):
                return "The PDF contains \(count) pages, which exceeds the limit of \(limit) pages."
            case .cancelled:
                return "The PDF import was cancelled."
            }
        }
    }

    /// Reads a text-layer PDF and reconstructs structured paragraphs into a `DocumentState`.
    /// Throws `PDFImporterError.scannedPDFNotSupported` if no extractable text layer is found.
    static func read(
        from fileURL: URL,
        originalFileName: String? = nil,
        sha256: String? = nil,
        size: Int64? = nil,
        limits: Limits = .default,
        cancellationCheck: (@Sendable () -> Bool)? = nil
    ) throws -> DocumentState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PDFImporterError.fileNotFound
        }

        if let cancellationCheck, cancellationCheck() {
            throw PDFImporterError.cancelled
        }
        if Task.isCancelled {
            throw PDFImporterError.cancelled
        }

        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let actualSize = size ?? (fileAttributes?[.size] as? Int64) ?? 0
        if actualSize > limits.maxFileBytes {
            throw PDFImporterError.fileSizeExceedsLimit(size: actualSize, limit: limits.maxFileBytes)
        }

        guard let pdfDocument = PDFDocument(url: fileURL) else {
            throw PDFImporterError.invalidPDF("Could not parse PDF format.")
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFImporterError.invalidPDF("The PDF document contains 0 pages.")
        }
        guard pageCount <= limits.maxPageCount else {
            throw PDFImporterError.pageCountExceedsLimit(count: pageCount, limit: limits.maxPageCount)
        }

        var totalNonWhitespaceCharCount = 0
        var rawPagesText: [String] = []
        var rawPagesAttributed: [NSAttributedString?] = []
        rawPagesText.reserveCapacity(pageCount)
        rawPagesAttributed.reserveCapacity(pageCount)

        for pageIndex in 0..<pageCount {
            if let cancellationCheck, cancellationCheck() {
                throw PDFImporterError.cancelled
            }
            if Task.isCancelled {
                throw PDFImporterError.cancelled
            }

            guard let page = pdfDocument.page(at: pageIndex) else {
                rawPagesText.append("")
                rawPagesAttributed.append(nil)
                continue
            }

            let pageText = (page.string ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .precomposedStringWithCanonicalMapping

            let nonWs = pageText.filter { !$0.isWhitespace && !$0.isNewline }.count
            totalNonWhitespaceCharCount += nonWs
            rawPagesText.append(pageText)
            rawPagesAttributed.append(page.attributedString)
        }

        // Scanned PDF / OCR detection: If all pages together have 0 extractable non-whitespace characters,
        // it is a scanned/image-only PDF.
        guard totalNonWhitespaceCharCount > 0 else {
            throw PDFImporterError.scannedPDFNotSupported
        }

        let fileName = originalFileName ?? fileURL.lastPathComponent
        let calculatedHash: String
        if let sha256 {
            calculatedHash = sha256
        } else {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            calculatedHash = computeSHA256(data)
        }

        // Reconstruct paragraphs across pages.
        var blocks: [DocumentBlock] = []
        var blockOrdinal = 0

        for (pageIndex, pageText) in rawPagesText.enumerated() {
            let reconstructedParagraphs = reconstructParagraphs(from: pageText)
            let pageAttributed = pageIndex < rawPagesAttributed.count ? rawPagesAttributed[pageIndex] : nil

            for (pIndex, paragraph) in reconstructedParagraphs.enumerated() {
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                let kind: DocumentBlockKind
                if trimmed.isEmpty {
                    kind = .empty
                } else if isProbableHeading(trimmed) {
                    kind = .heading
                } else {
                    kind = .paragraph
                }

                let blockId = sha256String("\(fileName)#page\(pageIndex + 1)#p\(pIndex + 1)#\(paragraph)")
                let spans = extractSpans(
                    for: paragraph,
                    pageAttributed: pageAttributed,
                    pageString: pageText,
                    blockOrdinal: blockOrdinal
                )
                let blockHash = sha256String(paragraph)

                let block = DocumentBlock(
                    id: blockId,
                    location: DocumentLocation(
                        part: .mainBody,
                        paragraphOrdinal: blockOrdinal,
                        xmlPath: "/pdf/page[\(pageIndex + 1)]/paragraph[\(pIndex + 1)]"
                    ),
                    kind: kind,
                    styleID: nil,
                    paragraphPropertiesFingerprint: "",
                    spans: spans,
                    sourceHash: blockHash,
                    translationPolicy: .translate
                )
                blocks.append(block)
                blockOrdinal += 1
            }
        }

        let wordCount = blocks.reduce(0) { count, block in
            count + block.spans.reduce(0) { spanCount, span in
                spanCount + span.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }

        let preflight = DocumentPreflight(
            pageCount: pageCount,
            wordCount: wordCount,
            sectionCount: pageCount,
            blockCount: blocks.count,
            protectedGroupCount: 0,
            fontWarnings: []
        )

        let titleCandidate = (pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let docTitle = (titleCandidate != nil && !titleCandidate!.isEmpty)
            ? titleCandidate
            : URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

        let authorCandidate = (pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let metadata = DocumentMetadata(
            title: docTitle,
            author: (authorCandidate != nil && !authorCandidate!.isEmpty) ? authorCandidate : nil,
            pageCount: preflight.pageCount,
            wordCount: preflight.wordCount,
            sectionCount: preflight.sectionCount,
            blockCount: preflight.blockCount,
            protectedGroupCount: 0,
            fontWarnings: []
        )

        return DocumentState(
            format: .pdf,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: fileName,
                role: .originalSource,
                format: "pdf",
                sha256: calculatedHash,
                size: actualSize
            ),
            metadata: metadata,
            preflight: preflight,
            blocks: blocks,
            chunks: [],
            profile: .default
        )
    }

    /// Reconstructs lines into structured paragraphs.
    /// Double newlines (or blank lines) indicate separate paragraphs.
    /// Single newlines within a paragraph are unwrapped, handling hyphenation.
    private static func reconstructParagraphs(from text: String) -> [String] {
        guard !text.isEmpty else { return [""] }

        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var paragraphs: [String] = []
        var currentParagraphLines: [String] = []

        func flushCurrent() {
            guard !currentParagraphLines.isEmpty else { return }
            let joined = unwrapLines(currentParagraphLines)
            if !joined.isEmpty {
                paragraphs.append(joined)
            }
            currentParagraphLines.removeAll()
        }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flushCurrent()
                paragraphs.append("") // preserve paragraph break / empty block
            } else if isProbableHeading(trimmed) {
                flushCurrent()
                paragraphs.append(trimmed) // heading is its own paragraph block
            } else {
                if let lastLine = currentParagraphLines.last {
                    let lastTrimmed = lastLine.trimmingCharacters(in: .whitespaces)
                    if lastTrimmed.hasSuffix("-") {
                        // Hyphenated line wrap
                        currentParagraphLines.append(line)
                    } else if lastTrimmed.hasSuffix(".") || lastTrimmed.hasSuffix("!") || lastTrimmed.hasSuffix("?") || lastTrimmed.hasSuffix(":") {
                        // Sentence completed
                        if lastTrimmed.count < 60 || trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                            flushCurrent()
                            currentParagraphLines.append(line)
                        } else {
                            currentParagraphLines.append(line)
                        }
                    } else {
                        currentParagraphLines.append(line)
                    }
                } else {
                    currentParagraphLines.append(line)
                }
            }
        }
        flushCurrent()

        return paragraphs.isEmpty ? [""] : paragraphs
    }

    /// Joins lines of a single paragraph, unwrapping line breaks and resolving soft hyphens.
    private static func unwrapLines(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        var result = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index == 0 {
                result = trimmed
            } else {
                if result.hasSuffix("-") && !result.hasSuffix(" -") {
                    // Check if hyphen connects words: e.g. "de-hyphen-", "ation" -> "de-hyphenation"
                    let withoutHyphen = String(result.dropLast())
                    result = withoutHyphen + trimmed
                } else {
                    result += " " + trimmed
                }
            }
        }
        return result
    }

    /// Heuristic to detect headings in reconstructed PDF text.
    private static func isProbableHeading(_ text: String) -> Bool {
        let count = text.count
        guard count <= 120 else { return false }
        if text.hasPrefix("#") { return true }
        let upper = text.uppercased()
        if upper.hasPrefix("CHAPTER ") || upper.hasPrefix("SECTION ") || upper.hasPrefix("PART ") || upper.hasPrefix("BOOK ") {
            return true
        }
        // All uppercase and short
        let letters = text.filter { $0.isLetter }
        if letters.count >= 3 && letters.allSatisfy({ $0.isUppercase }) {
            return true
        }
        return false
    }

    private static func computeSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func extractSpans(
        for paragraph: String,
        pageAttributed: NSAttributedString?,
        pageString: String,
        blockOrdinal: Int
    ) -> [RichTextSpan] {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let pageAttributed, pageAttributed.length > 0 else {
            let spanId = sha256String("span-\(blockOrdinal)-0-\(paragraph)")
            return [RichTextSpan(id: spanId, text: paragraph)]
        }

        let nsPage = pageAttributed.string as NSString
        let searchRange = NSRange(location: 0, length: nsPage.length)
        var foundRange = nsPage.range(of: paragraph, options: [], range: searchRange)
        if foundRange.location == NSNotFound {
            foundRange = nsPage.range(of: trimmed, options: [], range: searchRange)
        }

        var spans: [RichTextSpan] = []
        if foundRange.location != NSNotFound {
            var spanIndex = 0
            pageAttributed.enumerateAttributes(in: foundRange, options: []) { attrs, range, _ in
                let runText = nsPage.substring(with: range).precomposedStringWithCanonicalMapping
                guard !runText.isEmpty else { return }

                var traits: Set<InlineTrait> = []
                if let font = attrs[.font] as? NSFont {
                    let symTraits = font.fontDescriptor.symbolicTraits
                    if symTraits.contains(.bold) { traits.insert(.bold) }
                    if symTraits.contains(.italic) { traits.insert(.italic) }
                }
                if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                    traits.insert(.underline)
                }
                if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                    traits.insert(.strikethrough)
                }

                var colorHex: String? = nil
                if let color = attrs[.foregroundColor] as? NSColor {
                    colorHex = hexColor(from: color)
                }

                let span = RichTextSpan(
                    id: sha256String("span-\(blockOrdinal)-\(spanIndex)-\(runText)"),
                    text: runText,
                    styleKey: "",
                    traits: traits,
                    translationPolicy: .translate,
                    foregroundColorHex: colorHex
                )
                spanIndex += 1

                if let last = spans.last, last.traits == traits, last.foregroundColorHex == span.foregroundColorHex {
                    spans[spans.count - 1].text += runText
                } else {
                    spans.append(span)
                }
            }
        }

        if spans.isEmpty {
            let spanId = sha256String("span-\(blockOrdinal)-0-\(paragraph)")
            return [RichTextSpan(id: spanId, text: paragraph)]
        }
        return spans
    }

    private static func hexColor(from nsColor: NSColor) -> String? {
        if nsColor == .textColor || nsColor == .controlTextColor {
            return nil
        }
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255.0))
        let g = Int(round(rgb.greenComponent * 255.0))
        let b = Int(round(rgb.blueComponent * 255.0))
        return String(format: "%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    private static func sha256String(_ text: String) -> String {
        computeSHA256(Data(text.utf8))
    }
}
