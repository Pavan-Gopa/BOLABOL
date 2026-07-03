import Foundation

public enum TranscriptSide: String, Codable, CaseIterable, Equatable, Sendable {
    case original
    case translated
}

public enum TranscriptExportBuilder {
    public static func build(
        side: TranscriptSide,
        format: OutputFormat,
        session: SessionState,
        language: String? = nil
    ) -> String {
        switch format {
        case .txt:
            buildTXT(side: side, session: session, language: language)
        case .markdown:
            buildMarkdown(side: side, session: session, language: language)
        case .srt:
            buildSRT(side: side, session: session, language: language)
        case .vtt:
            "WEBVTT\n\n" + buildCueBlocks(side: side, session: session, separator: " --> ", timestampStyle: .vtt, language: language)
        }
    }

    public static func defaultFileName(
        side: TranscriptSide,
        format: OutputFormat,
        session: SessionState,
        language: String? = nil
    ) -> String {
        let stem = session.sourceFileName
            .replacingOccurrences(of: #"\.[^\.]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^A-Za-z0-9А-Яа-я_-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let selectedLanguage = language ?? session.selectedTranslationLanguage ?? session.targetLang
        let suffix = side == .translated ? safeSuffix(selectedLanguage) : "original"
        return "\(stem.isEmpty ? "VaniScript" : stem)_\(suffix).\(fileExtension(for: format))"
    }

    private static func buildTXT(side: TranscriptSide, session: SessionState, language: String?) -> String {
        let body = session.chunks
            .map { chunk in
                "[\(timeRange(chunk))]\n\(text(for: side, chunk: chunk, language: language ?? session.selectedTranslationLanguage))"
            }
            .joined(separator: "\n\n")
        return metadataHeader(side: side, session: session, language: language) + "\n\n" + body
    }

    private static func buildMarkdown(side: TranscriptSide, session: SessionState, language: String?) -> String {
        let selectedLanguage = language ?? session.selectedTranslationLanguage ?? session.targetLang
        let title = side == .translated ? "\(selectedLanguage) Transcript" : "Original Transcript"
        let body = session.chunks
            .map { chunk in
                "## Segment \(chunk.index + 1) · \(timeRange(chunk))\n\n\(text(for: side, chunk: chunk, language: selectedLanguage))"
            }
            .joined(separator: "\n\n")
        return "# \(title)\n\n" + metadataMarkdown(session: session, language: language) + "\n\n" + body
    }

    private static func buildSRT(side: TranscriptSide, session: SessionState, language: String?) -> String {
        buildCueBlocks(side: side, session: session, separator: " --> ", timestampStyle: .srt, language: language)
    }

    private static func buildCueBlocks(
        side: TranscriptSide,
        session: SessionState,
        separator: String,
        timestampStyle: TimestampStyle,
        language: String?
    ) -> String {
        let selectedLanguage = language ?? session.selectedTranslationLanguage
        let cueBlocks = session.chunks.flatMap { chunk -> [String] in
            let cues = cues(for: side, chunk: chunk, language: selectedLanguage)
            guard !cues.isEmpty else { return [] }
            return cues.map { cue in
                let start = formatTimestamp(cue.startSec, style: timestampStyle)
                let end = formatTimestamp(cue.endSec, style: timestampStyle)
                return "\(start)\(separator)\(end)\n\(cue.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }

        if !cueBlocks.isEmpty {
            return cueBlocks.enumerated()
                .map { index, block in "\(index + 1)\n\(block)" }
                .joined(separator: "\n\n")
        }

        return session.chunks
            .map { chunk in
                let start = formatTimestamp(chunk.startSec, style: timestampStyle)
                let end = formatTimestamp(chunk.endSec, style: timestampStyle)
                return "\(chunk.index + 1)\n\(start)\(separator)\(end)\n\(text(for: side, chunk: chunk, language: selectedLanguage))"
            }
            .joined(separator: "\n\n")
    }

    private static func text(for side: TranscriptSide, chunk: ChunkData, language: String?) -> String {
        switch side {
        case .original:
            chunk.original.trimmingCharacters(in: .whitespacesAndNewlines)
        case .translated:
            (chunk.translationText(for: language)
                ?? (TranslationArchive.isUsableTranslationText(chunk.translated) ? chunk.translated : ""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func cues(for side: TranscriptSide, chunk: ChunkData, language: String?) -> [TranscriptCue] {
        switch side {
        case .original:
            chunk.originalCues ?? []
        case .translated:
            chunk.translationCues(for: language)
        }
    }

    private static func metadataHeader(side: TranscriptSide, session: SessionState, language: String?) -> String {
        let selectedLanguage = language ?? session.selectedTranslationLanguage ?? session.targetLang
        return """
        VaniScript \(side == .translated ? "Translated" : "Original") Transcript
        Source: \(session.sourceFileName)
        Date: \(fallback(session.metadata.date))
        Location: \(fallback(session.metadata.location))
        Lecturer: \(fallback(session.metadata.lecturer))
        Participants: \(fallback(session.metadata.participants))
        Target: \(selectedLanguage)
        """
    }

    private static func metadataMarkdown(session: SessionState, language: String?) -> String {
        let selectedLanguage = language ?? session.selectedTranslationLanguage ?? session.targetLang
        return """
        - Source: \(session.sourceFileName)
        - Date: \(fallback(session.metadata.date))
        - Location: \(fallback(session.metadata.location))
        - Lecturer: \(fallback(session.metadata.lecturer))
        - Participants: \(fallback(session.metadata.participants))
        - Target: \(selectedLanguage)
        """
    }

    private static func fallback(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private static func safeSuffix(_ language: String) -> String {
        language
            .lowercased()
            .replacingOccurrences(of: #"[^A-Za-z0-9А-Яа-я_-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func timeRange(_ chunk: ChunkData) -> String {
        "\(formatClock(chunk.startSec))-\(formatClock(chunk.endSec))"
    }

    private static func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private enum TimestampStyle {
        case srt
        case vtt
    }

    private static func formatTimestamp(_ seconds: Double, style: TimestampStyle) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let millis = max(0, Int(((seconds - Double(whole)) * 1_000).rounded()))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        let separator = style == .srt ? "," : "."
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, millis)
    }

    private static func fileExtension(for format: OutputFormat) -> String {
        switch format {
        case .txt:
            "txt"
        case .srt:
            "srt"
        case .vtt:
            "vtt"
        case .markdown:
            "md"
        }
    }
}
