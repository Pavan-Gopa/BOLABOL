import Testing
@testable import VaniScriptCore

@Suite("Universal chunk planner")
struct ChunkPlannerTests {
    @Test("creates fixed duration chunks from Universal settings")
    func createsFixedDurationChunks() {
        let chunks = ChunkPlanner.plan(
            sourcePath: "/tmp/lecture.wav",
            durationSec: 1_350,
            chunkDurationMin: 10
        )

        #expect(chunks.count == 3)
        #expect(chunks[0].startSec == 0)
        #expect(chunks[0].endSec == 600)
        #expect(chunks[1].startSec == 600)
        #expect(chunks[1].endSec == 1_200)
        #expect(chunks[2].startSec == 1_200)
        #expect(chunks[2].endSec == 1_350)
        #expect(chunks.allSatisfy { $0.status == .pending })
    }

    @Test("creates one chunk for short media")
    func createsOneChunkForShortMedia() {
        let chunks = ChunkPlanner.plan(
            sourcePath: "/tmp/short.wav",
            durationSec: 120,
            chunkDurationMin: 10
        )

        #expect(chunks.count == 1)
        #expect(chunks[0].durationSec == 120)
    }

    @Test("creates chunks from smart silence cut points")
    func createsChunksFromSmartSilenceCutPoints() {
        let chunks = ChunkPlanner.plan(
            sourcePath: "/tmp/lecture.wav",
            durationSec: 1_350,
            cutPointsSec: [603.4, 1_187.8]
        )

        #expect(chunks.count == 3)
        #expect(chunks[0].startSec == 0)
        #expect(chunks[0].endSec == 603.4)
        #expect(chunks[1].startSec == 603.4)
        #expect(chunks[1].endSec == 1_187.8)
        #expect(chunks[2].startSec == 1_187.8)
        #expect(chunks[2].endSec == 1_350)
    }
}
