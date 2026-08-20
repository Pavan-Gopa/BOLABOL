import Foundation

/// Reason why an update operation/termination is currently blocked.
public enum UpdateBlockingReason: Hashable, CustomStringConvertible, Sendable {
    case recordingAudio
    case preparingRecordingPreview
    case savingRecording
    case processingSegment
    case exportingShorts
    case addingTranscriptTranslation
    case addingShortsTranslation
    case planningShorts
    case documentTranslationActive
    case unsavedChanges(String)
    case custom(String)

    public var description: String {
        switch self {
        case .recordingAudio:
            return "System audio recording is in progress."
        case .preparingRecordingPreview:
            return "Preparing recording preview."
        case .savingRecording:
            return "Saving audio recording."
        case .processingSegment:
            return "Segment processing is in progress."
        case .exportingShorts:
            return "Shorts/Reels video export is in progress."
        case .addingTranscriptTranslation:
            return "Transcript translation is in progress."
        case .addingShortsTranslation:
            return "Shorts translation is in progress."
        case .planningShorts:
            return "Shorts/Reels planning is in progress."
        case .documentTranslationActive:
            return "Document translation is in progress."
        case .unsavedChanges(let details):
            return "Unsaved changes pending save: \(details)"
        case .custom(let message):
            return message
        }
    }
}

/// A point-in-time snapshot of update readiness.
public struct UpdateReadinessSnapshot: Equatable, Sendable {
    public let isReady: Bool
    public let blockingReasons: [UpdateBlockingReason]

    public init(isReady: Bool, blockingReasons: [UpdateBlockingReason]) {
        self.isReady = isReady
        self.blockingReasons = blockingReasons
    }

    public static let ready = UpdateReadinessSnapshot(isReady: true, blockingReasons: [])

    public static func blocked(by reasons: [UpdateBlockingReason]) -> UpdateReadinessSnapshot {
        UpdateReadinessSnapshot(isReady: false, blockingReasons: reasons)
    }
}

/// Protocol through which update system queries WorkflowStore readiness and triggers pre-update save/freeze.
@MainActor
public protocol UpdateReadinessProviding: AnyObject {
    /// Returns snapshot of readiness state and active blockers.
    var updateReadinessSnapshot: UpdateReadinessSnapshot { get }

    /// Returns true if app is ready for update termination without unpersisted work or active operations.
    var isReadyForUpdateTermination: Bool { get }

    /// Returns current project revision string or session fingerprint.
    var currentProjectRevision: String { get }

    /// Performs immediate synchronous save of all pending project and settings state.
    /// Returns true on success, false if save failed.
    func prepareForUpdateTermination() -> Bool

    /// Freezes user editing UI before termination.
    func freezeEditingForUpdate()
}
