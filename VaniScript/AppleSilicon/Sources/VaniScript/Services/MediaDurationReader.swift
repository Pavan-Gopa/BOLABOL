import AVFoundation
import Foundation

enum MediaDurationReader {
    static func durationSeconds(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return 0 }
            return seconds
        } catch {
            return 0
        }
    }
}
