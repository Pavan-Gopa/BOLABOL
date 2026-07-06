import AVFoundation
import Foundation
import NativeSmartScribeCore

enum AudioFileImporter {
    static func recording(from url: URL) throws -> AudioRecording {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? NSNumber
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            NativeSmartScribeLog.transcription.warning("Audio import is not supported by AVFoundation for \(url.lastPathComponent, privacy: .public). error=\(error.localizedDescription, privacy: .public)")
            throw NSError(
                domain: "NativeSmartScribeAudioImport",
                code: 415,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(.unsupportedAudioFormat, language: .english)
                ]
            )
        }
        let format = file.processingFormat
        let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0

        return AudioRecording(
            fileURL: url,
            duration: duration,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            fileSizeBytes: fileSize?.int64Value,
            suggestedTitle: url.deletingPathExtension().lastPathComponent,
            source: .importedFile
        )
    }
}
