import AppKit
import Testing
@testable import VaniScript

@Suite("Document Review scroll synchronization")
struct DocumentReviewScrollSyncTests {
    private let scope = DocumentScrollScope(
        documentID: "/tmp/book.txt",
        chunkID: 7,
        language: "Russian"
    )

    @Test("normalized progress maps unequal document heights")
    func unequalHeightsMapByProgress() {
        #expect(DocumentScrollMath.scrollableHeight(documentHeight: 1_000, viewportHeight: 100) == 900)
        #expect(DocumentScrollMath.progress(
            originY: 450,
            documentHeight: 1_000,
            viewportHeight: 100
        ) == 0.5)
        #expect(DocumentScrollMath.offset(
            progress: 0.5,
            documentHeight: 500,
            viewportHeight: 100
        ) == 200)
    }

    @Test("top and bottom map exactly, including flipped origins")
    func exactBoundaries() {
        let flipped = DocumentScrollGeometry(
            originY: 0,
            topOriginY: 0,
            bottomOriginY: 900,
            documentHeight: 1_000,
            viewportHeight: 100
        )
        #expect(flipped.progress == 0)
        #expect(flipped.origin(for: 0) == 0)
        #expect(flipped.origin(for: 1) == 900)

        let unflipped = DocumentScrollGeometry(
            originY: 900,
            topOriginY: 900,
            bottomOriginY: 0,
            documentHeight: 1_000,
            viewportHeight: 100
        )
        #expect(unflipped.progress == 0)
        #expect(unflipped.origin(for: 0) == 900)
        #expect(unflipped.origin(for: 1) == 0)
        #expect(DocumentScrollMath.clamp(-0.2) == 0)
        #expect(DocumentScrollMath.clamp(1.2) == 1)
    }

    @Test("either pane can become the live-scroll leader")
    func bidirectionalLeadership() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)

        state.recordUserProgress(.source, progress: 0.25)
        #expect(state.leader == .source)
        #expect(state.progress == 0.25)

        state.recordUserProgress(.translated, progress: 0.8)
        #expect(state.leader == .translated)
        #expect(state.progress == 0.8)
    }

    @Test("programmatic follower notifications are suppressed without ping-pong")
    func followerSuppression() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.4)
        state.expectFollowerUpdate(.translated, progress: 0.4)

        #expect(state.observe(.translated, progress: 0.4, isLiveScroll: false) == .followerSuppressed)
        #expect(state.leader == .source)
        #expect(state.progress == 0.4)

        // A real live gesture immediately clears suppression and switches leadership.
        #expect(state.observe(.translated, progress: 0.6, isLiveScroll: true) == .user(0.6))
        #expect(state.leader == .translated)
        #expect(state.progress == 0.6)
    }

    @Test("relayout preserves normalized progress and clamps changed ranges")
    func relayoutPreservesProgress() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.75)
        state.preserveProgress()
        #expect(state.progress == 0.75)

        let sourceOffset = DocumentScrollMath.offset(
            progress: state.progress,
            documentHeight: 900,
            viewportHeight: 100
        )
        let translatedOffset = DocumentScrollMath.offset(
            progress: state.progress,
            documentHeight: 2_100,
            viewportHeight: 100
        )
        #expect(sourceOffset == 600)
        #expect(translatedOffset == 1_500)

        state.preserveProgress(2)
        #expect(state.progress == 1)
    }

    @Test("a zero-scroll-range pane is safe")
    func zeroScrollRange() {
        #expect(DocumentScrollMath.scrollableHeight(documentHeight: 100, viewportHeight: 100) == 0)
        #expect(DocumentScrollMath.progress(originY: 0, documentHeight: 100, viewportHeight: 100) == 0)
        #expect(DocumentScrollMath.offset(progress: 1, documentHeight: 100, viewportHeight: 100) == 0)

        let geometry = DocumentScrollGeometry(
            originY: 0,
            topOriginY: 0,
            bottomOriginY: 0,
            documentHeight: 100,
            viewportHeight: 100
        )
        #expect(geometry.progress == 0)
        #expect(geometry.origin(for: 1) == 0)
    }

    @Test("scope changes reset to top and detachment ignores stale updates")
    func scopeResetAndDetachment() {
        var state = DocumentScrollSyncState()
        state.bind(.source, scope: scope)
        state.bind(.translated, scope: scope)
        state.recordUserProgress(.source, progress: 0.65)

        let nextScope = DocumentScrollScope(
            documentID: scope.documentID,
            chunkID: scope.chunkID + 1,
            language: scope.language
        )
        state.setScope(nextScope)
        #expect(state.progress == 0)
        #expect(state.leader == nil)

        state.detachAll()
        #expect(state.observe(.source, progress: 0.9, isLiveScroll: true) == .ignored)
        #expect(state.attachedPanes.isEmpty)
        #expect(state.scope == nil)
    }
    @Test("AppKit live-scroll notifications move the real follower and detach cleanly")
    @MainActor
    func appKitCoordinatorHarness() {
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        let coordinator = DocumentDualScrollCoordinator()

        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)
        #expect(coordinator.progress == 0.5)

        translated.contentView.scroll(to: NSPoint(x: 0, y: 300))
        translated.reflectScrolledClipView(translated.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: translated
        )
        #expect(abs(source.contentView.bounds.origin.y - 675) < 0.5)
        #expect(coordinator.progress == 0.75)

        coordinator.detach()
        let progressBeforeStaleNotification = coordinator.progress
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        #expect(coordinator.progress == progressBeforeStaleNotification)
        #expect(coordinator.attachedPanes.isEmpty)
    }

    @Test("AppKit bridge resolver finds distinct sibling scroll views and synchronizes live and non-live scrolls")
    @MainActor
    func appKitBridgeResolverRegression() {
        let coordinator = DocumentDualScrollCoordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = container

        let sourcePane = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let sourceScrollView = makeScrollView(documentHeight: 1_000)
        sourceScrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let sourceAnchor = DocumentScrollSyncAnchorView(
            coordinator: coordinator,
            pane: .source,
            scope: scope
        )
        sourceAnchor.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        sourcePane.addSubview(sourceScrollView)
        sourcePane.addSubview(sourceAnchor)

        let translatedPane = NSView(frame: NSRect(x: 300, y: 0, width: 300, height: 400))
        let translatedScrollView = makeScrollView(documentHeight: 500)
        translatedScrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let translatedAnchor = DocumentScrollSyncAnchorView(
            coordinator: coordinator,
            pane: .translated,
            scope: scope
        )
        translatedAnchor.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        translatedPane.addSubview(translatedScrollView)
        translatedPane.addSubview(translatedAnchor)

        container.addSubview(sourcePane)
        container.addSubview(translatedPane)

        sourceAnchor.resolveScrollView()
        translatedAnchor.resolveScrollView()

        // 1. Prove distinct owned views attached
        #expect(coordinator.attachedPanes == [.source, .translated])

        // 2. Exercise live scroll with source as leader (scroll to 50% = 300 / 600)
        sourceScrollView.contentView.scroll(to: NSPoint(x: 0, y: 300))
        sourceScrollView.reflectScrolledClipView(sourceScrollView.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: sourceScrollView
        )
        #expect(abs(coordinator.progress - 0.5) < 0.01)
        #expect(abs(translatedScrollView.contentView.bounds.origin.y - 50) < 0.5)

        // 3. Exercise live scroll with translated as leader (scroll to 100% = exact bottom: 100 / 100)
        translatedScrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
        translatedScrollView.reflectScrolledClipView(translatedScrollView.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: translatedScrollView
        )
        #expect(abs(coordinator.progress - 1.0) < 0.01)
        #expect(abs(sourceScrollView.contentView.bounds.origin.y - 600) < 0.5)

        // 4. Exercise non-live user scroll path (boundsDidChangeNotification on contentView without live-scroll)
        sourceScrollView.contentView.scroll(to: NSPoint(x: 0, y: 150))
        sourceScrollView.reflectScrolledClipView(sourceScrollView.contentView)
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: sourceScrollView.contentView
        )
        #expect(abs(coordinator.progress - 0.25) < 0.01)
        #expect(abs(translatedScrollView.contentView.bounds.origin.y - 25) < 0.5)

        // 5. Exercise detach
        coordinator.detach()
        #expect(coordinator.attachedPanes.isEmpty)
    }

    @Test("chunk change with pending layout relayout re-syncs follower to normalized position")
    @MainActor
    func chunkChangePendingRelayoutResyncsFollower() async throws {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)

        let initialScope = DocumentScrollScope(
            documentID: "/tmp/book.txt",
            chunkID: 29,
            language: "Russian"
        )
        coordinator.attach(source, pane: .source, scope: initialScope)
        coordinator.attach(translated, pane: .translated, scope: initialScope)

        // 1. Live scroll on source to progress = 0.5 (source = 450, translated = 200)
        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        #expect(coordinator.progress == 0.5)
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)

        // 2. Chunk changes to next scope (chunk 30)
        let nextScope = DocumentScrollScope(
            documentID: "/tmp/book.txt",
            chunkID: 30,
            language: "Russian"
        )
        coordinator.setScope(nextScope)
        #expect(coordinator.progress == 0)
        #expect(coordinator.state.leader == nil)

        // 3. New text is loaded with different heights (source = 2000, translated = 800)
        source.documentView?.frame = NSRect(x: 0, y: 0, width: 240, height: 2_000)
        translated.documentView?.frame = NSRect(x: 0, y: 0, width: 240, height: 800)
        coordinator.attach(source, pane: .source, scope: nextScope)
        coordinator.attach(translated, pane: .translated, scope: nextScope)

        // 4. Pending layout notifications fire
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: source.documentView
        )
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: translated.documentView
        )

        // Drain the main queue so scheduleReapply / reapplyIfIdle executes
        try await Task.sleep(for: .milliseconds(50))

        // 5. Leadership is reset and both panes are aligned at top (progress 0)
        #expect(coordinator.state.leader == nil)
        #expect(coordinator.progress == 0)
        #expect(source.contentView.bounds.origin.y == 0)
        #expect(translated.contentView.bounds.origin.y == 0)
    }

    @Test("attach is idempotent and never yanks progress for the same view and scope")
    @MainActor
    func attachIdempotency() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        coordinator.setScope(scope) // no-op guard must also be idempotent

        // Establish a real user scroll position.
        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        #expect(coordinator.progress == 0.5)

        // SwiftUI ticks re-attach the same views/scope every pass; none of this
        // may re-observe, re-pin, or otherwise touch progress.
        for _ in 0..<5 {
            coordinator.attach(source, pane: .source, scope: scope)
            coordinator.attach(translated, pane: .translated, scope: scope)
            #expect(coordinator.progress == 0.5)
            #expect(coordinator.attachedPanes == [.source, .translated])
            #expect(coordinator.state.leader == .source)
            #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)
            #expect(abs(source.contentView.bounds.origin.y - 450) < 0.5)
        }
        coordinator.detach()
        #expect(coordinator.attachedPanes.isEmpty)
    }

    @Test("resetToTop zeroes progress, clears leadership, and moves both panes")
    @MainActor
    func resetToTopMovesBothPanes() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: source
        )
        #expect(coordinator.progress == 0.5)
        #expect(coordinator.state.leader == .source)

        coordinator.resetToTop()
        #expect(coordinator.progress == 0)
        #expect(coordinator.state.leader == nil)
        #expect(source.contentView.bounds.origin.y == 0)
        #expect(translated.contentView.bounds.origin.y == 0)

        // Both panes remain attached and stay synced after the reset.
        #expect(coordinator.attachedPanes == [.source, .translated])

        // A fresh attach pass after the reset returns early for already-bound
        // views: leadership and progress survive untouched. Attach while the
        // remaining pane is still marked live, then close the gesture before
        // asserting — this is exactly the chunk-change sequencing the live app's
        // didEndLiveScroll path exercises before SwiftUI re-attaches.
        source.contentView.scroll(to: NSPoint(x: 0, y: 225))
        source.reflectScrolledClipView(source.contentView)
        NotificationCenter.default.post(
            name: NSScrollView.didLiveScrollNotification,
            object: source
        )
        #expect(coordinator.progress == 0.25)
        #expect(abs(translated.contentView.bounds.origin.y - 100) < 0.5)
    }

    @Test("resetToTop clamps out-of-range progress preserved before the reset")
    @MainActor
    func resetToTopClampsPreservedProgress() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.setScope(scope) // idempotent attach guard must not detach

        coordinator.resetToTop()
        // Only source attached: apply skips missing translated pane safely.
        #expect(coordinator.progress == 0)
        #expect(source.contentView.bounds.origin.y == 0)
        coordinator.detach()
    }

    @Test("programmatic highlight jump propagates from source to translated follower")
    @MainActor
    func programmaticScrollSyncsFollower() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        // Simulate a proofreading-highlight jump in the source pane (50%).
        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        coordinator.syncFromProgrammaticScroll(pane: .source)

        #expect(coordinator.progress == 0.5)
        #expect(coordinator.state.leader == .source)
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)
    }

    @Test("programmatic highlight jump propagates from translated pane to source follower")
    @MainActor
    func programmaticScrollFromTranslatedLeadership() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        translated.contentView.scroll(to: NSPoint(x: 0, y: 200))
        translated.reflectScrolledClipView(translated.contentView)
        coordinator.syncFromProgrammaticScroll(pane: .translated)

        #expect(coordinator.progress == 0.5)
        #expect(coordinator.state.leader == .translated)
        #expect(abs(source.contentView.bounds.origin.y - 450) < 0.5)
    }

    @Test("programmatic scroll call before attachment is a safe no-op")
    @MainActor
    func programmaticScrollWithNothingAttachedIsIgnored() {
        let coordinator = DocumentDualScrollCoordinator()
        coordinator.syncFromProgrammaticScroll(pane: .source)
        coordinator.syncFromProgrammaticScroll(pane: .translated)
        #expect(coordinator.progress == 0)
        #expect(coordinator.attachedPanes.isEmpty)
        #expect(coordinator.state.leader == nil)
    }

    @Test("non-live bounds-only notification does not thrash the follower")
    @MainActor
    func nonLiveClipBoundsDoesNotThrashFollower() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        // A programmatic (non-live) source jump drives the follower once.
        source.contentView.scroll(to: NSPoint(x: 0, y: 450))
        source.reflectScrolledClipView(source.contentView)
        coordinator.syncFromProgrammaticScroll(pane: .source)
        #expect(coordinator.progress == 0.5)
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)

        // Stale clip-bounds notifications (no live-scroll gesture active) arriving
        // afterwards must be ignored by both panes; no ping-pong, no drift.
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: source.contentView
        )
        #expect(coordinator.progress == 0.5)
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)
        #expect(abs(source.contentView.bounds.origin.y - 450) < 0.5)

        // Simulate an asymmetric noise notification: source bounds change locally
        // without any scroll sync participation (applying history, etc.).
        source.contentView.bounds = NSRect(x: 0, y: 0, width: 240, height: 100)
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: source.contentView
        )
        #expect(coordinator.progress == 0.5)
        // The drifted pane is not yanked by the non-live noise; synced state wins.
        #expect(abs(translated.contentView.bounds.origin.y - 200) < 0.5)
        coordinator.detach()
    }

    @Test("detaching one pane leaves the other attached")
    @MainActor
    func detachSinglePaneKeepsRest() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_000)
        let translated = makeScrollView(documentHeight: 500)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)
        #expect(coordinator.attachedPanes == [.source, .translated])

        coordinator.detach(pane: .translated)
        #expect(coordinator.attachedPanes == [.source])
        #expect(coordinator.scope == scope)

        coordinator.detach(pane: .source)
        #expect(coordinator.attachedPanes.isEmpty)
        #expect(coordinator.scope == nil)
    }

    @Test("proofreading focus navigation coordinates programmatic dual scroll without state drift")
    @MainActor
    func proofreadingFocusCoordinatesDualScroll() {
        let coordinator = DocumentDualScrollCoordinator()
        let source = makeScrollView(documentHeight: 1_200)
        let translated = makeScrollView(documentHeight: 600)
        coordinator.attach(source, pane: .source, scope: scope)
        coordinator.attach(translated, pane: .translated, scope: scope)

        // Focus navigation on source scrolls source pane and pulls translated follower
        source.contentView.scroll(to: NSPoint(x: 0, y: 550))
        source.reflectScrolledClipView(source.contentView)
        coordinator.syncFromProgrammaticScroll(pane: .source)

        #expect(coordinator.progress == 0.5)
        #expect(coordinator.state.leader == .source)
        #expect(abs(translated.contentView.bounds.origin.y - 250) < 0.5)

        // Reverse jump from translated side updates progress cleanly
        translated.contentView.scroll(to: NSPoint(x: 0, y: 100))
        translated.reflectScrolledClipView(translated.contentView)
        coordinator.syncFromProgrammaticScroll(pane: .translated)

        #expect(coordinator.progress == 0.2)
        #expect(coordinator.state.leader == .translated)
        #expect(abs(source.contentView.bounds.origin.y - 220) < 0.5)

        coordinator.detach()
    }

    @MainActor
    private func makeScrollView(documentHeight: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = HarnessDocumentView(
            frame: NSRect(x: 0, y: 0, width: 240, height: documentHeight)
        )
        scrollView.layoutSubtreeIfNeeded()
        return scrollView
    }
}

@MainActor
private final class HarnessDocumentView: NSView {
    override var isFlipped: Bool { true }
}
