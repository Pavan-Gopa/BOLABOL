import Foundation
import VaniScriptCore

extension WorkflowStore: UpdateReadinessProviding {
    public var currentProjectRevision: String {
        McpProjectRevision.make(workflow: workflow)
    }

    public var updateReadinessSnapshot: UpdateReadinessSnapshot {
        var reasons: [UpdateBlockingReason] = []

        if isRecordingSystemAudio {
            reasons.append(.recordingAudio)
        }
        if isPreparingRecordingPreview {
            reasons.append(.preparingRecordingPreview)
        }
        if isSavingRecording {
            reasons.append(.savingRecording)
        }
        if isProcessingSegment {
            reasons.append(.processingSegment)
        }
        if isExportingShorts {
            reasons.append(.exportingShorts)
        }
        if isAddingTranscriptTranslation {
            reasons.append(.addingTranscriptTranslation)
        }
        if isAddingShortsTranslation {
            reasons.append(.addingShortsTranslation)
        }
        if isPlanningShorts {
            reasons.append(.planningShorts)
        }
        if isDocumentTranslationActive {
            reasons.append(.documentTranslationActive)
        }
        if let saveFailure = projectSaveFailure {
            reasons.append(.unsavedChanges(saveFailure))
        }

        if reasons.isEmpty {
            return .ready
        } else {
            return .blocked(by: reasons)
        }
    }

    public var isReadyForUpdateTermination: Bool {
        updateReadinessSnapshot.isReady
    }

    public func prepareForUpdateTermination() -> Bool {
        return saveAllPendingStateSync()
    }
}
