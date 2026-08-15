import AppKit
import CryptoKit
import Foundation
import VaniScriptCore

struct DocumentImportLimits: Sendable, Equatable {
    var maxDOCXBytes: Int64
    var maxPDFBytes: Int64
    var maxRTFBytes: Int64
    var maxTextBytes: Int64
    var maxPDFPages: Int
    var docxLimits: DOCXPackageReader.Limits

    static let `default` = DocumentImportLimits()

    init(
        maxDOCXBytes: Int64 = 64 * 1024 * 1024,
        maxPDFBytes: Int64 = 100 * 1024 * 1024,
        maxRTFBytes: Int64 = 32 * 1024 * 1024,
        maxTextBytes: Int64 = 32 * 1024 * 1024,
        maxPDFPages: Int = 2_000,
        docxLimits: DOCXPackageReader.Limits = .default
    ) {
        self.maxDOCXBytes = maxDOCXBytes
        self.maxPDFBytes = maxPDFBytes
        self.maxRTFBytes = maxRTFBytes
        self.maxTextBytes = maxTextBytes
        self.maxPDFPages = maxPDFPages
        self.docxLimits = docxLimits
    }
}

struct DocumentImportResult: Sendable, Equatable {
    let originalURL: URL
    let importedFileURL: URL
    let originalFileName: String
    let sourceKind: WorkflowSourceKind
    let documentState: DocumentState
    let sha256: String

    var fileURL: URL { importedFileURL }
    var accuracyBadge: String { documentState.format.accuracyBadge }
}

extension DocumentFormat {
    public var accuracyBadge: String {
        switch self {
        case .docx:
            return "DOCX — round-trip preservation."
        case .txt:
            return "Plain text — paragraph structure preserved."
        case .markdown:
            return "Markdown — structural import."
        case .rtf:
            return "RTF — structural import, formatting may be simplified."
        case .pdf:
            return "PDF — text reconstruction, layout may vary."
        }
    }
}

enum DocumentImportServiceError: LocalizedError, Equatable {
    case sourceNotFound
    case sourceIsNotAFile
    case unsupportedDocumentFormat(String)
    case invalidTextEncoding(String)
    case copyFailed(String)
    case fileSizeExceedsLimit(format: String, size: Int64, limit: Int64)
    case scannedPDFNotSupported
    case pdfParsingFailed(String)
    case rtfParsingFailed(String)
    case importCancelled

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "The selected document could not be found."
        case .sourceIsNotAFile:
            return "Choose a document file, not a folder."
        case let .unsupportedDocumentFormat(extensionName):
            return "\(extensionName.uppercased()) import is not available yet. DOCX, PDF, RTF, TXT, and Markdown are supported in this release."
        case let .invalidTextEncoding(fileName):
            return "The text document \(fileName) is not valid UTF-8 and could not be imported safely."
        case let .copyFailed(message):
            return "The document could not be copied into the project store: \(message)"
        case let .fileSizeExceedsLimit(format, size, limit):
            return "The \(format.uppercased()) document size (\(size) bytes) exceeds the safety limit of \(limit) bytes."
        case .scannedPDFNotSupported:
            return "This PDF contains no text layer and appears to be scanned. Optical Character Recognition (OCR) is not supported in this release."
        case let .pdfParsingFailed(message):
            return "The PDF document could not be read: \(message)"
        case let .rtfParsingFailed(message):
            return "The RTF document could not be read: \(message)"
        case .importCancelled:
            return "The document import was cancelled."
        }
    }
}

enum DocumentImportService {
    /// Imports a document into a private project directory. The source file is
    /// never edited; all parsing happens against the copied project asset.
    static func importDocument(
        from sourceURL: URL,
        projectDirectory: URL? = nil,
        limits: DocumentImportLimits = .default,
        cancellationCheck: (@Sendable () -> Bool)? = nil,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
            throw DocumentImportServiceError.sourceNotFound
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw DocumentImportServiceError.sourceIsNotAFile
        }

        if let cancellationCheck, cancellationCheck() {
            throw DocumentImportServiceError.importCancelled
        }
        if Task.isCancelled {
            throw DocumentImportServiceError.importCancelled
        }

        let sourceKind: WorkflowSourceKind
        do {
            sourceKind = try SourceClassifier.classification(for: sourceURL)
        } catch let error as SourceClassifierError {
            throw error
        }
        guard sourceKind == .document else {
            throw DocumentImportServiceError.unsupportedDocumentFormat(sourceURL.pathExtension)
        }

        let extensionName = sourceURL.pathExtension.lowercased()
        guard ["docx", "txt", "md", "markdown", "rtf", "pdf"].contains(extensionName) else {
            throw DocumentImportServiceError.unsupportedDocumentFormat(extensionName)
        }

        // Security check: file size limit before copying
        let sourceAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let sourceSize = (sourceAttributes?[.size] as? Int64) ?? (sourceAttributes?[.size] as? NSNumber)?.int64Value ?? 0

        switch extensionName {
        case "docx":
            if sourceSize > limits.maxDOCXBytes {
                throw DocumentImportServiceError.fileSizeExceedsLimit(format: "docx", size: sourceSize, limit: limits.maxDOCXBytes)
            }
        case "pdf":
            if sourceSize > limits.maxPDFBytes {
                throw DocumentImportServiceError.fileSizeExceedsLimit(format: "pdf", size: sourceSize, limit: limits.maxPDFBytes)
            }
        case "rtf":
            if sourceSize > limits.maxRTFBytes {
                throw DocumentImportServiceError.fileSizeExceedsLimit(format: "rtf", size: sourceSize, limit: limits.maxRTFBytes)
            }
        case "txt", "md", "markdown":
            if sourceSize > limits.maxTextBytes {
                throw DocumentImportServiceError.fileSizeExceedsLimit(format: extensionName, size: sourceSize, limit: limits.maxTextBytes)
            }
        default:
            throw DocumentImportServiceError.unsupportedDocumentFormat(extensionName)
        }

        let projectRoot = projectDirectory ?? AppStoragePaths.projectDirectory(id: UUID().uuidString)
        let sourceDirectory = projectRoot.appendingPathComponent("source", isDirectory: true)
        do {
            try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        } catch {
            throw DocumentImportServiceError.copyFailed(error.localizedDescription)
        }

        let fileName = safeFileName(sourceURL.lastPathComponent, fallbackExtension: extensionName)
        var destinationURL = sourceDirectory.appendingPathComponent(fileName, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            let stem = destinationURL.deletingPathExtension().lastPathComponent
            destinationURL = sourceDirectory
                .appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8))")
                .appendingPathExtension(extensionName)
        }
        let temporaryURL = sourceDirectory.appendingPathComponent(".import-\(UUID().uuidString).partial")

        if let cancellationCheck, cancellationCheck() {
            throw DocumentImportServiceError.importCancelled
        }
        if Task.isCancelled {
            throw DocumentImportServiceError.importCancelled
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)

            if let cancellationCheck, cancellationCheck() {
                try? fileManager.removeItem(at: temporaryURL)
                throw DocumentImportServiceError.importCancelled
            }
            if Task.isCancelled {
                try? fileManager.removeItem(at: temporaryURL)
                throw DocumentImportServiceError.importCancelled
            }

            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch let error as DocumentImportServiceError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw DocumentImportServiceError.copyFailed(error.localizedDescription)
        }

        if let cancellationCheck, cancellationCheck() {
            try? fileManager.removeItem(at: destinationURL)
            throw DocumentImportServiceError.importCancelled
        }
        if Task.isCancelled {
            try? fileManager.removeItem(at: destinationURL)
            throw DocumentImportServiceError.importCancelled
        }

        do {
            let copiedData = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
            let hash = sha256(copiedData)
            let documentState: DocumentState
            switch extensionName {
            case "docx":
                let parsed = try DOCXPackageReader(limits: limits.docxLimits).read(from: destinationURL)
                documentState = DocumentState(
                    format: .docx,
                    originalAsset: ProjectAssetReference(
                        key: "sourceFile",
                        originalFileName: sourceURL.lastPathComponent,
                        role: .originalSource,
                        format: "docx",
                        sha256: hash,
                        size: Int64(copiedData.count)
                    ),
                    metadata: parsed.metadata,
                    preflight: parsed.preflight,
                    blocks: parsed.blocks,
                    chunks: [],
                    profile: .default
                )
            case "txt":
                documentState = try makeTextState(
                    data: copiedData,
                    format: .txt,
                    originalFileName: sourceURL.lastPathComponent,
                    sha256: hash,
                    size: Int64(copiedData.count),
                    cancellationCheck: cancellationCheck
                )
            case "md", "markdown":
                documentState = try makeMarkdownState(
                    data: copiedData,
                    originalFileName: sourceURL.lastPathComponent,
                    sha256: hash,
                    size: Int64(copiedData.count),
                    cancellationCheck: cancellationCheck
                )
            case "rtf":
                documentState = try makeRTFState(
                    data: copiedData,
                    originalFileName: sourceURL.lastPathComponent,
                    sha256: hash,
                    size: Int64(copiedData.count),
                    cancellationCheck: cancellationCheck
                )
            case "pdf":
                do {
                    documentState = try PDFDocumentImporter.read(
                        from: destinationURL,
                        originalFileName: sourceURL.lastPathComponent,
                        sha256: hash,
                        size: Int64(copiedData.count),
                        limits: .init(maxFileBytes: limits.maxPDFBytes, maxPageCount: limits.maxPDFPages),
                        cancellationCheck: cancellationCheck
                    )
                } catch let error as PDFDocumentImporter.PDFImporterError {
                    switch error {
                    case .fileNotFound:
                        throw DocumentImportServiceError.sourceNotFound
                    case .scannedPDFNotSupported:
                        throw DocumentImportServiceError.scannedPDFNotSupported
                    case let .fileSizeExceedsLimit(size, limit):
                        throw DocumentImportServiceError.fileSizeExceedsLimit(format: "pdf", size: size, limit: limit)
                    case let .invalidPDF(message):
                        throw DocumentImportServiceError.pdfParsingFailed(message)
                    case let .pageCountExceedsLimit(count, limit):
                        throw DocumentImportServiceError.pdfParsingFailed("Page count \(count) exceeds limit \(limit)")
                    case .cancelled:
                        throw DocumentImportServiceError.importCancelled
                    }
                }
            default:
                throw DocumentImportServiceError.unsupportedDocumentFormat(extensionName)
            }
            return DocumentImportResult(
                originalURL: sourceURL,
                importedFileURL: destinationURL,
                originalFileName: sourceURL.lastPathComponent,
                sourceKind: .document,
                documentState: documentState,
                sha256: hash
            )
        } catch {
            // A failed parse must not leave a half-imported project asset that
            // could later be mistaken for a valid source.
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Backward-compatibility overload accepting `DOCXPackageReader.Limits`.
    static func importDocument(
        from sourceURL: URL,
        projectDirectory: URL? = nil,
        limits: DOCXPackageReader.Limits = .default,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: DocumentImportLimits(docxLimits: limits),
            cancellationCheck: nil,
            fileManager: fileManager
        )
    }

    static func importDocument(
        from sourceURL: URL,
        to projectDirectory: URL,
        limits: DocumentImportLimits = .default,
        cancellationCheck: (@Sendable () -> Bool)? = nil,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: limits,
            cancellationCheck: cancellationCheck,
            fileManager: fileManager
        )
    }

    static func importDocument(
        from sourceURL: URL,
        to projectDirectory: URL,
        limits: DOCXPackageReader.Limits = .default,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: DocumentImportLimits(docxLimits: limits),
            cancellationCheck: nil,
            fileManager: fileManager
        )
    }

    static func importFile(
        _ sourceURL: URL,
        into projectDirectory: URL? = nil,
        limits: DocumentImportLimits = .default,
        cancellationCheck: (@Sendable () -> Bool)? = nil,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: limits,
            cancellationCheck: cancellationCheck,
            fileManager: fileManager
        )
    }

    static func importFile(
        _ sourceURL: URL,
        into projectDirectory: URL? = nil,
        limits: DOCXPackageReader.Limits = .default,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: DocumentImportLimits(docxLimits: limits),
            cancellationCheck: nil,
            fileManager: fileManager
        )
    }

    private static func makeTextState(
        data: Data,
        format: DocumentFormat,
        originalFileName: String,
        sha256: String,
        size: Int64,
        cancellationCheck: (@Sendable () -> Bool)? = nil
    ) throws -> DocumentState {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DocumentImportServiceError.invalidTextEncoding(originalFileName)
        }
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
        let lines = normalized.isEmpty
            ? [""]
            : normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [DocumentBlock] = []
        blocks.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            if index % 500 == 0 {
                if let cancellationCheck, cancellationCheck() {
                    throw DocumentImportServiceError.importCancelled
                }
                if Task.isCancelled {
                    throw DocumentImportServiceError.importCancelled
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: DocumentBlockKind = trimmed.isEmpty ? .empty : .paragraph
            let sourceHash = sha256String(line)
            let spans = line.isEmpty
                ? []
                : [RichTextSpan(id: sha256String("span-\(index)-\(line)"), text: line)]
            blocks.append(
                DocumentBlock(
                    id: sha256String("\(originalFileName)#\(index)#\(line)"),
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: index, xmlPath: "/text/paragraph[\(index + 1)]"),
                    kind: kind,
                    styleID: nil,
                    paragraphPropertiesFingerprint: "",
                    spans: spans,
                    sourceHash: sourceHash,
                    translationPolicy: .translate
                )
            )
        }

        let wordCount = blocks.reduce(0) { count, block in
            count + block.spans.reduce(0) { spanCount, span in
                spanCount + span.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        let pageCount = max(1, (wordCount + 299) / 300)
        let preflight = DocumentPreflight(
            pageCount: pageCount,
            wordCount: wordCount,
            sectionCount: 1,
            blockCount: blocks.count,
            protectedGroupCount: 0,
            fontWarnings: []
        )
        let title = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        let metadata = DocumentMetadata(
            title: title.isEmpty ? nil : title,
            pageCount: preflight.pageCount,
            wordCount: preflight.wordCount,
            sectionCount: preflight.sectionCount,
            blockCount: preflight.blockCount,
            protectedGroupCount: preflight.protectedGroupCount,
            fontWarnings: []
        )
        return DocumentState(
            format: format,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: originalFileName,
                role: .originalSource,
                format: format.rawValue,
                sha256: sha256,
                size: size
            ),
            metadata: metadata,
            preflight: preflight,
            blocks: blocks,
            chunks: [],
            profile: .default
        )
    }

    private static func makeMarkdownState(
        data: Data,
        originalFileName: String,
        sha256: String,
        size: Int64,
        cancellationCheck: (@Sendable () -> Bool)? = nil
    ) throws -> DocumentState {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DocumentImportServiceError.invalidTextEncoding(originalFileName)
        }
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
        let lines = normalized.isEmpty
            ? [""]
            : normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [DocumentBlock] = []
        blocks.reserveCapacity(lines.count)
        var inFencedCodeBlock = false

        for (index, line) in lines.enumerated() {
            if index % 500 == 0 {
                if let cancellationCheck, cancellationCheck() {
                    throw DocumentImportServiceError.importCancelled
                }
                if Task.isCancelled {
                    throw DocumentImportServiceError.importCancelled
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: DocumentBlockKind

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFencedCodeBlock.toggle()
                kind = .other
            } else if inFencedCodeBlock {
                kind = .other
            } else if trimmed.isEmpty {
                kind = .empty
            } else if trimmed.hasPrefix(">") {
                kind = .quote
            } else if isMarkdownHeading(line: line, nextLine: (index + 1 < lines.count) ? lines[index + 1] : nil) {
                kind = .heading
            } else if isMarkdownListItem(trimmed) {
                kind = .listItem
            } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                // Indented code block
                kind = .other
            } else {
                kind = .paragraph
            }

            let sourceHash = sha256String(line)
            let spans = line.isEmpty
                ? []
                : [RichTextSpan(id: sha256String("span-\(index)-\(line)"), text: line)]
            blocks.append(
                DocumentBlock(
                    id: sha256String("\(originalFileName)#\(index)#\(line)"),
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: index, xmlPath: "/text/paragraph[\(index + 1)]"),
                    kind: kind,
                    styleID: nil,
                    paragraphPropertiesFingerprint: "",
                    spans: spans,
                    sourceHash: sourceHash,
                    translationPolicy: .translate
                )
            )
        }

        let wordCount = blocks.reduce(0) { count, block in
            count + block.spans.reduce(0) { spanCount, span in
                spanCount + span.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        let pageCount = max(1, (wordCount + 299) / 300)
        let preflight = DocumentPreflight(
            pageCount: pageCount,
            wordCount: wordCount,
            sectionCount: 1,
            blockCount: blocks.count,
            protectedGroupCount: 0,
            fontWarnings: []
        )
        let title = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        let metadata = DocumentMetadata(
            title: title.isEmpty ? nil : title,
            pageCount: preflight.pageCount,
            wordCount: preflight.wordCount,
            sectionCount: preflight.sectionCount,
            blockCount: preflight.blockCount,
            protectedGroupCount: preflight.protectedGroupCount,
            fontWarnings: []
        )
        return DocumentState(
            format: .markdown,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: originalFileName,
                role: .originalSource,
                format: DocumentFormat.markdown.rawValue,
                sha256: sha256,
                size: size
            ),
            metadata: metadata,
            preflight: preflight,
            blocks: blocks,
            chunks: [],
            profile: .default
        )
    }

    private static func isMarkdownHeading(line: String, nextLine: String?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hashCount = trimmed.prefix(while: { $0 == "#" }).count
            if hashCount >= 1 && hashCount <= 6 {
                let rest = trimmed.dropFirst(hashCount)
                if rest.isEmpty || rest.first?.isWhitespace == true {
                    return true
                }
            }
        }
        return false
    }

    private static func isMarkdownListItem(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        return trimmed.range(of: "^\\d+[.)] ", options: .regularExpression) != nil
    }

    private static func makeRTFState(
        data: Data,
        originalFileName: String,
        sha256: String,
        size: Int64,
        cancellationCheck: (@Sendable () -> Bool)? = nil
    ) throws -> DocumentState {
        let attributedString: NSAttributedString
        do {
            attributedString = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } catch {
            throw DocumentImportServiceError.rtfParsingFailed(error.localizedDescription)
        }

        let nsString = attributedString.string as NSString
        var paragraphRanges: [NSRange] = []
        var location = 0
        let totalLength = nsString.length
        if totalLength == 0 {
            paragraphRanges.append(NSRange(location: 0, length: 0))
        } else {
            while location < totalLength {
                var start = 0
                var end = 0
                var contentsEnd = 0
                nsString.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
                paragraphRanges.append(NSRange(location: start, length: contentsEnd - start))
                location = end
            }
            if totalLength > 0 {
                let lastChar = nsString.character(at: totalLength - 1)
                if lastChar == 0x0A || lastChar == 0x0D {
                    paragraphRanges.append(NSRange(location: totalLength, length: 0))
                }
            }
        }

        var blocks: [DocumentBlock] = []
        blocks.reserveCapacity(paragraphRanges.count)

        for (index, paragraphRange) in paragraphRanges.enumerated() {
            if index % 500 == 0 {
                if let cancellationCheck, cancellationCheck() {
                    throw DocumentImportServiceError.importCancelled
                }
                if Task.isCancelled {
                    throw DocumentImportServiceError.importCancelled
                }
            }

            let line = paragraphRange.length == 0 ? "" : nsString.substring(with: paragraphRange).precomposedStringWithCanonicalMapping
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: DocumentBlockKind = trimmed.isEmpty ? .empty : .paragraph
            let sourceHash = sha256String(line)

            var spans: [RichTextSpan] = []
            if paragraphRange.length > 0 {
                var spanIndex = 0
                attributedString.enumerateAttributes(in: paragraphRange, options: []) { attrs, range, _ in
                    let runText = nsString.substring(with: range).precomposedStringWithCanonicalMapping
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
                        colorHex = Self.hexColor(from: color)
                    }

                    let span = RichTextSpan(
                        id: sha256String("span-\(index)-\(spanIndex)-\(runText)"),
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

            blocks.append(
                DocumentBlock(
                    id: sha256String("\(originalFileName)#\(index)#\(line)"),
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: index, xmlPath: "/rtf/paragraph[\(index + 1)]"),
                    kind: kind,
                    styleID: nil,
                    paragraphPropertiesFingerprint: "",
                    spans: spans,
                    sourceHash: sourceHash,
                    translationPolicy: .translate
                )
            )
        }
        let wordCount = blocks.reduce(0) { count, block in
            count + block.spans.reduce(0) { spanCount, span in
                spanCount + span.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        let pageCount = max(1, (wordCount + 299) / 300)
        let preflight = DocumentPreflight(
            pageCount: pageCount,
            wordCount: wordCount,
            sectionCount: 1,
            blockCount: blocks.count,
            protectedGroupCount: 0,
            fontWarnings: []
        )
        let title = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        let metadata = DocumentMetadata(
            title: title.isEmpty ? nil : title,
            pageCount: preflight.pageCount,
            wordCount: preflight.wordCount,
            sectionCount: preflight.sectionCount,
            blockCount: preflight.blockCount,
            protectedGroupCount: preflight.protectedGroupCount,
            fontWarnings: []
        )

        return DocumentState(
            format: .rtf,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: originalFileName,
                role: .originalSource,
                format: DocumentFormat.rtf.rawValue,
                sha256: sha256,
                size: size
            ),
            metadata: metadata,
            preflight: preflight,
            blocks: blocks,
            chunks: [],
            profile: .default
        )
    }

    private static func safeFileName(_ fileName: String, fallbackExtension: String) -> String {
        let base = URL(fileURLWithPath: fileName).lastPathComponent
        guard !base.isEmpty, base != ".", base != ".." else {
            return "Imported-Document.\(fallbackExtension)"
        }
        return base
    }

    /// Computes the hex-encoded SHA-256 digest of a local file.
    public static func computeSHA256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return sha256(data)
    }

    /// Verifies whether the local file matches the expected hex SHA-256 digest.
    public static func verifySourceHash(fileURL: URL, expectedHash: String) throws -> Bool {
        guard !expectedHash.isEmpty else { return true }
        let actual = try computeSHA256(for: fileURL)
        return actual.caseInsensitiveCompare(expectedHash) == .orderedSame
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256String(_ text: String) -> String {
        sha256(Data(text.utf8))
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
}
