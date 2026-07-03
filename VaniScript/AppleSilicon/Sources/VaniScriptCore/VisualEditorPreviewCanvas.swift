import Foundation
import CoreGraphics

public enum VisualEditorPreviewCanvas {
    public static func size(for sourceSize: CGSize, exportResolution: String) -> (width: Int, height: Int) {
        let height: Double
        if exportResolution.contains("4K") {
            height = 3840
        } else if exportResolution.contains("2K") {
            height = 2560
        } else if exportResolution.contains("1080") || exportResolution.contains("Full HD") {
            height = 1920
        } else {
            height = max(16.0, sourceSize.height.rounded(.toNearestOrAwayFromZero))
        }

        let sourceAspect = max(0.2, min(5.0, sourceSize.width / max(1.0, sourceSize.height)))
        let width = max(16.0, (height * sourceAspect / 2.0).rounded(.toNearestOrAwayFromZero) * 2.0)
        return (Int(width), Int(height))
    }
}

public enum OnboardingCompletionPolicy {
    public static func needsOnboarding(settings: AppSettings, currentBuildID: String) -> Bool {
        normalized(settings.completedOnboardingBuildID) != normalized(currentBuildID)
    }

    public static func markCompleted(settings: inout AppSettings, currentBuildID: String) {
        settings.hasCompletedOnboarding = true
        settings.completedOnboardingBuildID = normalized(currentBuildID)
    }

    private static func normalized(_ value: String?) -> String {
        let cleaned = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "unknown-build" : cleaned
    }
}
