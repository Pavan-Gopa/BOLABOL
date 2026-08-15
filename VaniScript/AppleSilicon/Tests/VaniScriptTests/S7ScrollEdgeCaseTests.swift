import AppKit
import Testing
@testable import VaniScript

@Suite("S7 scroll synchronization edge cases")
struct S7ScrollEdgeCaseTests {
    private let scope = DocumentScrollScope(documentID: "doc", chunkID: 1, language: "Russian")

    @Test("clamp converts NaN and infinities to safe top progress")
    func nonFiniteClamp() {
        #expect(DocumentScrollMath.clamp(.nan) == 0)
        #expect(DocumentScrollMath.clamp(.infinity) == 0)
        #expect(DocumentScrollMath.clamp(-.infinity) == 0)
    }

    @Test("negative geometry never creates a negative scroll range")
    func negativeGeometry() {
        #expect(DocumentScrollMath.scrollableHeight(documentHeight: -10, viewportHeight: 100) == 0)
        #expect(DocumentScrollMath.scrollableHeight(documentHeight: 50, viewportHeight: 100) == 0)
        #expect(DocumentScrollMath.progress(originY: 999, documentHeight: 50, viewportHeight: 100) == 0)
        #expect(DocumentScrollMath.offset(progress: 1, documentHeight: 50, viewportHeight: 100) == 0)
    }

    @Test("reverse direction maps top and bottom exactly")
    func reverseDirection() {
        #expect(DocumentScrollMath.progress(
            originY: 900,
            documentHeight: 1_000,
            viewportHeight: 100,
            topOriginY: 900,
            direction: -1
        ) == 0)
        #expect(DocumentScrollMath.progress(
            originY: 0,
            documentHeight: 1_000,
            viewportHeight: 100,
            topOriginY: 900,
            direction: -1
        ) == 1)
        #expect(DocumentScrollMath.offset(
            progress: 1,
            documentHeight: 1_000,
            viewportHeight: 100,
            topOriginY: 900,
            direction: -1
        ) == 0)
    }

    @Test("follower suppression is one-shot; later equal non-live motion becomes user input")
    func suppressionIsOneShot() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.4)
        state.expectFollowerUpdate(.translated, progress: 0.4)

        #expect(state.observe(.translated, progress: 0.4, isLiveScroll: false) == .followerSuppressed)
        #expect(state.leader == .source)
        #expect(state.observe(.translated, progress: 0.4, isLiveScroll: false) == .user(0.4))
        #expect(state.leader == .translated)
    }

    @Test("a mismatched expected follower position is not swallowed")
    func mismatchedFollowerPositionBecomesUserScroll() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.2)
        state.expectFollowerUpdate(.translated, progress: 0.2)

        #expect(state.observe(.translated, progress: 0.8, isLiveScroll: false) == .user(0.8))
        #expect(state.leader == .translated)
        #expect(state.progress == 0.8)
    }

    @Test("suppression tolerance accepts tiny AppKit clamp noise but not larger movement")
    func suppressionTolerance() {
        var near = DocumentScrollSyncState()
        near.bind(.source, scope: scope)
        near.bind(.translated, scope: scope)
        near.expectFollowerUpdate(.translated, progress: 0.5)
        #expect(near.observe(.translated, progress: 0.501, isLiveScroll: false) == .followerSuppressed)

        var far = DocumentScrollSyncState()
        far.bind(.source, scope: scope)
        far.bind(.translated, scope: scope)
        far.expectFollowerUpdate(.translated, progress: 0.5)
        #expect(far.observe(.translated, progress: 0.503, isLiveScroll: false) == .user(0.503))
    }

    @Test("detaching one pane does not erase shared scope or remaining pane progress")
    func partialDetachPreservesState() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.7)
        state.detach(.translated)

        #expect(state.scope == scope)
        #expect(state.attachedPanes == [.source])
        #expect(state.progress == 0.7)
        #expect(state.leader == .source)
    }

    @Test("detaching last pane clears scope, progress, leader, and stale suppression")
    func finalDetachResetsEverything() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.recordUserProgress(.source, progress: 0.9)
        state.expectFollowerUpdate(.source, progress: 0.9)
        state.detach(.source)

        #expect(state.scope == nil)
        #expect(state.attachedPanes.isEmpty)
        #expect(state.progress == 0)
        #expect(state.leader == nil)
        #expect(state.observe(.source, progress: 0.9, isLiveScroll: false) == .ignored)
    }

    @Test("rebinding a pane to a new chunk resets progress before accepting new scroll")
    func rebindNewScopeResets() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.recordUserProgress(.source, progress: 0.65)
        let next = DocumentScrollScope(documentID: "doc", chunkID: 2, language: "Russian")
        state.bind(.source, scope: next)

        #expect(state.scope == next)
        #expect(state.progress == 0)
        #expect(state.leader == nil)
        state.recordUserProgress(.source, progress: 0.3)
        #expect(state.progress == 0.3)
    }
}
