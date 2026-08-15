import Testing
@testable import VaniScriptCore

@Suite("Timeline cut time mapper adversarial boundaries")
struct TimelineCutTimeMapperAdversarialTests {
    @Test("overlapping and touching cuts merge before duration subtraction")
    func mergesCuts() {
        let cuts = [
            TimelineCut(startSec: 2, endSec: 5),
            TimelineCut(startSec: 4, endSec: 8),
            TimelineCut(startSec: 8.005, endSec: 10)
        ]
        let normalized = TimelineCutTimeMapper.normalizedCuts(cuts, clipDuration: 20, trim: .zero)
        #expect(normalized == [TimelineCut(startSec: 2, endSec: 10)])
        #expect(TimelineCutTimeMapper.activeOutputDuration(clipDuration: 20, trim: .zero, cuts: cuts) == 12)
    }

    @Test("cuts outside trim window clamp or disappear")
    func cutsClampToTrim() {
        let trim = TimelineTrim(trimStartSec: 3, trimEndSec: 4)
        let cuts = [
            TimelineCut(startSec: -100, endSec: 2),
            TimelineCut(startSec: 1, endSec: 5),
            TimelineCut(startSec: 15, endSec: 100),
            TimelineCut(startSec: 17, endSec: 19)
        ]
        #expect(TimelineCutTimeMapper.normalizedCuts(cuts, clipDuration: 20, trim: trim) == [
            TimelineCut(startSec: 3, endSec: 5),
            TimelineCut(startSec: 15, endSec: 16)
        ])
    }

    @Test("sub-centisecond cuts are ignored")
    func tinyCutsIgnored() {
        let cuts = [
            TimelineCut(startSec: 1, endSec: 1.005),
            TimelineCut(startSec: 2, endSec: 2.011)
        ]
        let normalized = TimelineCutTimeMapper.normalizedCuts(cuts, clipDuration: 10, trim: .zero)
        #expect(normalized.count == 1)
        #expect(normalized[0] == TimelineCut(startSec: 2, endSec: 2.011))
    }

    @Test("nonfinite trim and cut values fail closed into finite geometry")
    func nonFiniteGeometry() {
        let trim = TimelineTrim(trimStartSec: .infinity, trimEndSec: .nan)
        let cuts = [TimelineCut(startSec: -.infinity, endSec: .infinity)]
        #expect(TimelineCutTimeMapper.activeOutputDuration(clipDuration: 30, trim: trim, cuts: cuts) == 30)
        #expect(TimelineCutTimeMapper.normalizedCuts(cuts, clipDuration: 30, trim: trim).isEmpty)
    }

    @Test("negative clip intro outro and trim cannot create negative virtual duration")
    func negativeInputs() {
        #expect(TimelineCutTimeMapper.virtualDuration(
            clipDuration: -10,
            trim: TimelineTrim(trimStartSec: -5, trimEndSec: -6),
            cuts: [],
            introDuration: -3,
            outroDuration: -4
        ) == 0)
    }

    @Test("virtual mapping freezes on intro and outro inserts")
    func introOutroFreezePhysicalTime() {
        let trim = TimelineTrim(trimStartSec: 2, trimEndSec: 3)
        #expect(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 2.5,
            clipDuration: 20,
            trim: trim,
            cuts: [],
            introDuration: 2,
            outroDuration: 4
        ) == 2)
        #expect(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 20,
            clipDuration: 20,
            trim: trim,
            cuts: [],
            introDuration: 2,
            outroDuration: 4
        ) == 17)
    }

    @Test("mapping jumps across removed cut without emitting removed physical time")
    func virtualSkipsRemovedCut() {
        let cut = TimelineCut(startSec: 4, endSec: 8)
        #expect(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 4,
            clipDuration: 12,
            trim: .zero,
            cuts: [cut],
            introDuration: 0,
            outroDuration: 0
        ) == 4)
        let after = TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 4.001,
            clipDuration: 12,
            trim: .zero,
            cuts: [cut],
            introDuration: 0,
            outroDuration: 0
        )
        #expect(after > 8)
        #expect(after < 8.01)
    }

    @Test("physical points inside a cut collapse to the same output timestamp")
    func physicalInsideCutCollapses() {
        let cut = TimelineCut(startSec: 4, endSec: 8)
        let values = [4.0, 5.0, 7.999, 8.0].map {
            TimelineCutTimeMapper.mapPhysicalToVirtual(
                physicalSec: $0,
                clipDuration: 12,
                trim: .zero,
                cuts: [cut],
                introDuration: 0,
                outroDuration: 0
            )
        }
        #expect(values.allSatisfy { abs($0 - 4) < 0.000_001 })
    }

    @Test("round trip is exact for retained physical points inside the active trim interval")
    func retainedRoundTrip() {
        let trim = TimelineTrim(trimStartSec: 1, trimEndSec: 2)
        let cuts = [TimelineCut(startSec: 4, endSec: 6), TimelineCut(startSec: 9, endSec: 10)]
        for physical in [1.5, 3.0, 6.5, 8.5] {
            let virtual = TimelineCutTimeMapper.mapPhysicalToVirtual(
                physicalSec: physical,
                clipDuration: 12,
                trim: trim,
                cuts: cuts,
                introDuration: 1.25,
                outroDuration: 0.75
            )
            let roundTrip = TimelineCutTimeMapper.mapVirtualToPhysical(
                virtualSec: virtual,
                clipDuration: 12,
                trim: trim,
                cuts: cuts,
                introDuration: 1.25,
                outroDuration: 0.75
            )
            #expect(abs(roundTrip - physical) < 0.000_001)
        }
    }

    @Test("incremental cut fragments subtract existing coverage and preserve holes")
    func incrementalFragments() {
        let fragments = TimelineCutTimeMapper.incrementalCutFragments(
            existingCuts: [
                TimelineCut(startSec: 3, endSec: 5),
                TimelineCut(startSec: 7, endSec: 9)
            ],
            newCut: TimelineCut(startSec: 2, endSec: 10),
            clipDuration: 12
        )
        #expect(fragments == [
            TimelineCut(startSec: 2, endSec: 3),
            TimelineCut(startSec: 5, endSec: 7),
            TimelineCut(startSec: 9, endSec: 10)
        ])
    }

    @Test("incremental cut fully covered by existing cuts produces no fragments")
    func incrementalFullyCovered() {
        #expect(TimelineCutTimeMapper.incrementalCutFragments(
            existingCuts: [TimelineCut(startSec: 1, endSec: 10)],
            newCut: TimelineCut(startSec: 3, endSec: 4),
            clipDuration: 12
        ).isEmpty)
    }
}
