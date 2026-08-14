import CryptoKit
import Foundation
import VaniScriptCore

struct DocumentImportResult: Sendable, Equatable {
    let originalURL: URL
    let importedFileURL: URL
    let originalFileName: String
    let sourceKind: WorkflowSourceKind
    let documentState: DocumentState
    let sha256: String

    var fileURL: URL { importedFileURL }
}

enum DocumentImportServiceError: LocalizedError, Equatable {
    case sourceNotFound
    case sourceIsNotAFile
    case unsupportedDocumentFormat(String)
    case invalidTextEncoding(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "The selected document could not be found."
        case .sourceIsNotAFile:
            return "Choose a document file, not a folder."
        case let .unsupportedDocumentFormat(extensionName):
            return "\(extensionName.uppercased()) import is not available yet. DOCX, TXT, and Markdown are supported in this release."
        case let .invalidTextEncoding(fileName):
            return "The text document \(fileName) is not valid UTF-8 and could not be imported safely."
        case let .copyFailed(message):
            return "The document could not be copied into the project store: \(message)"
        }
    }
}

enum DocumentImportService {
    /// Imports a document into a private project directory. The source file is
    /// never edited; all parsing happens against the copied project asset.
    static func importDocument(
        from sourceURL: URL,
        projectDirectory: URL? = nil,
        limits: DOCXPackageReader.Limits = .default,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
            throw DocumentImportServiceError.sourceNotFound
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw DocumentImportServiceError.sourceIsNotAFile
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
        guard ["docx", "txt", "md", "markdown"].contains(extensionName) else {
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
        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw DocumentImportServiceError.copyFailed(error.localizedDescription)
        }

        do {
            let copiedData = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
            let hash = sha256(copiedData)
            let documentState: DocumentState
            switch extensionName {
            case "docx":
                let parsed = try DOCXPackageReader(limits: limits).read(from: destinationURL)
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
                    size: Int64(copiedData.count)
                )
            case "md", "markdown":
                documentState = try makeTextState(
                    data: copiedData,
                    format: .markdown,
                    originalFileName: sourceURL.lastPathComponent,
                    sha256: hash,
                    size: Int64(copiedData.count)
                )
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

    static func importDocument(
        from sourceURL: URL,
        to projectDirectory: URL,
        limits: DOCXPackageReader.Limits = .default,
        fileManager: FileManager = .default
    ) throws -> DocumentImportResult {
        try importDocument(
            from: sourceURL,
            projectDirectory: projectDirectory,
            limits: limits,
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
            limits: limits,
            fileManager: fileManager
        )
    }

    private static func makeTextState(
        data: Data,
        format: DocumentFormat,
        originalFileName: String,
        sha256: String,
        size: Int64
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
        let blocks = lines.enumerated().map { index, line in
            let kind: DocumentBlockKind
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                kind = .empty
            } else if format == .markdown && trimmed.hasPrefix(">") {
                kind = .quote
            } else if format == .markdown && trimmed.first == "#" {
                kind = .heading
            } else if format == .markdown && (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: "^\\d+[.)] ", options: .regularExpression) != nil) {
                kind = .listItem
            } else {
                kind = .paragraph
            }
            let sourceHash = sha256String(line)
            let spans = line.isEmpty
                ? []
                : [RichTextSpan(id: sha256String("span-\(index)-\(line)"), text: line)]
            return DocumentBlock(
                id: sha256String("\(originalFileName)#\(index)#\(line)"),
                location: DocumentLocation(part: .mainBody, paragraphOrdinal: index, xmlPath: "/text/paragraph[\(index + 1)]"),
                kind: kind,
                styleID: nil,
                paragraphPropertiesFingerprint: "",
                spans: spans,
                sourceHash: sourceHash,
                translationPolicy: .translate
            )
        }
        let title = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
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
            metadata: DocumentMetadata(title: title.isEmpty ? nil : title),
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256String(_ text: String) -> String {
        sha256(Data(text.utf8))
    }
}
