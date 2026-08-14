import Foundation
import UniformTypeIdentifiers
import VaniScriptCore

/// The upload surface accepts both the existing media formats and the first
/// document formats. Keeping classification in one place prevents the picker,
/// drag-and-drop path, and import service from drifting apart.
enum SourceClassifierError: LocalizedError, Equatable {
    case missingFileName
    case unsupportedFileType(String)
    case macroDocumentsUnsupported

    var errorDescription: String? {
        switch self {
        case .missingFileName:
            return "The selected item has no file name."
        case let .unsupportedFileType(extensionName):
            let displayName = extensionName.isEmpty ? "this file type" : ".\(extensionName) files"
            return "VaniScript does not support \(displayName) here. Choose audio, video, DOCX, TXT, Markdown, RTF, or PDF."
        case .macroDocumentsUnsupported:
            return "Macro-enabled Word documents (.docm) are not supported. Save the document as .docx before importing it."
        }
    }
}

enum SourceClassifier {
    static let documentExtensions: Set<String> = ["docx", "txt", "md", "markdown", "rtf", "pdf"]

    // These extensions mirror the media types already accepted by the native
    // media pipeline. Classification intentionally remains extension based so
    // a dropped URL does not trigger an expensive media probe before routing.
    static let mediaExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "flac", "ogg", "oga", "opus", "aiff", "aif", "caf",
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "ts"
    ]

    static var supportedFileExtensions: Set<String> {
        documentExtensions.union(mediaExtensions)
    }

    /// Returns the source kind or a user-facing error for an unsupported item.
    static func classification(for url: URL) throws -> WorkflowSourceKind {
        let extensionName = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !extensionName.isEmpty else {
            throw SourceClassifierError.missingFileName
        }
        if extensionName == "docm" {
            throw SourceClassifierError.macroDocumentsUnsupported
        }
        if mediaExtensions.contains(extensionName) {
            return .media
        }
        if documentExtensions.contains(extensionName) {
            return .document
        }
        throw SourceClassifierError.unsupportedFileType(extensionName)
    }

    /// Non-throwing convenience for callers that only need a routing decision.
    static func classify(_ url: URL) -> WorkflowSourceKind? {
        try? classification(for: url)
    }

    static func classify(url: URL) -> WorkflowSourceKind? {
        classify(url)
    }

    static func isDocument(_ url: URL) -> Bool {
        classify(url) == .document
    }

    static func isMedia(_ url: URL) -> Bool {
        classify(url) == .media
    }

    /// Content types used by NSOpenPanel. UTType(filenameExtension:) is used
    /// for document formats because older macOS releases do not expose every
    /// Office type as a static constant.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .text, .plainText, .rtf, .pdf]
        for extensionName in documentExtensions {
            if let type = UTType(filenameExtension: extensionName), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }
}
