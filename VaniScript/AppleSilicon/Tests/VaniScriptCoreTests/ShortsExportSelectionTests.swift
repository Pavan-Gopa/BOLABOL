import Testing
@testable import VaniScriptCore

@Suite("Shorts export selection")
struct ShortsExportSelectionTests {
    @Test("tracks source and target selections independently for the same clip")
    func tracksSourceAndTargetSelectionsIndependently() {
        var selection = ShortsExportSelection()

        selection.toggle(index: 0, language: .source)
        #expect(selection.selectedCount(validClipCount: 1) == 1)
        #expect(selection.contains(index: 0, language: .source))
        #expect(!selection.contains(index: 0, language: .target))

        selection.toggle(index: 0, language: .target)
        #expect(selection.selectedCount(validClipCount: 1) == 2)
        #expect(selection.jobs(validClipCount: 1) == [
            ShortsExportJob(index: 0, language: .source),
            ShortsExportJob(index: 0, language: .target)
        ])

        selection.toggle(index: 0, language: .target)
        #expect(selection.selectedCount(validClipCount: 1) == 1)
        #expect(selection.jobs(validClipCount: 1) == [
            ShortsExportJob(index: 0, language: .source)
        ])
    }

    @Test("ignores stale clip indexes when plans are removed")
    func ignoresStaleClipIndexesWhenPlansAreRemoved() {
        var selection = ShortsExportSelection()

        selection.toggle(index: 0, language: .source)
        selection.toggle(index: 3, language: .target)

        #expect(selection.selectedCount(validClipCount: 1) == 1)
        #expect(selection.jobs(validClipCount: 1) == [
            ShortsExportJob(index: 0, language: .source)
        ])
    }
}
