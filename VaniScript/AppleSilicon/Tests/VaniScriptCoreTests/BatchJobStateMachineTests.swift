import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Batch job state machine")
struct BatchJobStateMachineTests {
    @Test("legal transitions are explicit")
    func legalTransitions() {
        let legal: Set<String> = [
            "pending-processing", "pending-cancelled", "processing-completed", "processing-failed",
            "processing-cancelled", "processing-pending", "processing-blockedOutputCollision", "failed-pending", "cancelled-pending",
            "blockedOutputCollision-pending"
        ]
        for from in BatchJobState.allCases {
            for to in BatchJobState.allCases {
                #expect(BatchJobStateMachine.canTransition(from: from, to: to) == legal.contains("\(from.rawValue)-\(to.rawValue)"))
            }
        }
    }

    @Test("transition mutates only legal state and timestamp")
    func mutation() throws {
        let original = Date(timeIntervalSince1970: 1)
        let updated = Date(timeIntervalSince1970: 2)
        var job = fixture(createdAt: original)
        try BatchJobStateMachine.transition(&job, to: .processing, at: updated)
        #expect(job.state == .processing)
        #expect(job.updatedAt == updated)
        #expect(throws: BatchJobTransitionError.illegalTransition(from: .processing, to: .processing)) {
            try BatchJobStateMachine.transition(&job, to: .processing)
        }
    }
    @Test("truthful progress presentation formats every phase accurately")
    func progressPresentationPhases() {
        var job = fixture(createdAt: Date())
        job.state = .processing

        // Planning phase (indeterminate)
        job.progressDetail = BatchProgressDetail(phase: .planning)
        #expect(!job.isDeterminateProgress)
        #expect(job.progressStageText == "Analyzing audio and planning chunks…")
        #expect(job.voiceOverProgressValue.contains("Analyzing audio and planning chunks"))

        // Loading model phase (indeterminate)
        job.progressDetail = BatchProgressDetail(phase: .loadingModel)
        #expect(!job.isDeterminateProgress)
        #expect(job.progressStageText == "Loading model…")
        #expect(job.voiceOverProgressValue.contains("Loading model"))

        // Converting audio phase (indeterminate)
        job.progressDetail = BatchProgressDetail(phase: .convertingAudio)
        #expect(!job.isDeterminateProgress)
        #expect(job.progressStageText == "Preparing audio…")
        #expect(job.voiceOverProgressValue.contains("Preparing audio"))

        // Transcribing phase (determinate with audio position and total)
        job.progress = 0.31
        job.checkpoints = []
        job.totalChunks = 1
        job.progressDetail = BatchProgressDetail(
            phase: .transcribing,
            currentChunkAudioPositionSec: 150.0,
            currentChunkDurationSec: 486.0
        )
        #expect(job.isDeterminateProgress)
        #expect(job.progressStageText == "Transcribing · 2:30 / 8:06 · chunk 1 of 1 · 31%")
        #expect(job.voiceOverProgressValue.contains("2:30 of 8:06"))
        #expect(job.voiceOverProgressValue.contains("31 percent"))

        // Finalizing phase (indeterminate)
        job.progress = 1.0
        job.progressDetail = BatchProgressDetail(phase: .finalizing)
        #expect(!job.isDeterminateProgress)
        #expect(job.progressStageText == "Saving transcript…")
        #expect(job.voiceOverProgressValue.contains("Saving transcript"))

        // Terminal states
        job.progressDetail = nil
        job.state = .completed
        #expect(job.progressStageText == "Completed")
        job.state = .failed
        #expect(job.progressStageText == "Failed")
        job.state = .blockedOutputCollision
        #expect(job.progressStageText == "Output conflict")
    }

    @Test("formatClockTime formats seconds, minutes, and hours")
    func formatClockTimeFormatting() {
        #expect(BatchJob.formatClockTime(0) == "0:00")
        #expect(BatchJob.formatClockTime(30) == "0:30")
        #expect(BatchJob.formatClockTime(60) == "1:00")
        #expect(BatchJob.formatClockTime(150) == "2:30")
        #expect(BatchJob.formatClockTime(486) == "8:06")
        #expect(BatchJob.formatClockTime(3661) == "1:01:01")
    }

    private func fixture(createdAt: Date) -> BatchJob {
        BatchJob(
            profileID: "profile", relativeSourcePath: "2026_person_story_city_us.wav",
            relativeOutputPath: "2026_person_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 2, sha256: "hash"),
            configuration: BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en"),
            createdAt: createdAt, updatedAt: createdAt
        )
    }
}
