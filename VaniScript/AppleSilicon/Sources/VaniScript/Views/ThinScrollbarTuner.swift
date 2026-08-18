import SwiftUI
import AppKit

struct ThinScrollbarTuner: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollbarTuningView {
        ScrollbarTuningView()
    }

    func updateNSView(_ nsView: ScrollbarTuningView, context: Context) {
        DispatchQueue.main.async {
            nsView.tuneEnclosingScrollView()
        }
    }

    final class ScrollbarTuningView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.tuneEnclosingScrollView()
            }
        }

        func tuneEnclosingScrollView() {
            if let scrollView = enclosingScrollView {
                Self.tune(scrollView)
                return
            }

            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    Self.tune(scrollView)
                }
                Self.tuneDescendantScrollViews(in: view)
                ancestor = view.superview
            }
        }

        private static func tuneDescendantScrollViews(in view: NSView) {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView {
                    tune(scrollView)
                }
                tuneDescendantScrollViews(in: subview)
            }
        }

        private static func tune(_ scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            if !(scrollView.verticalScroller is ThinReviewScroller) {
                scrollView.verticalScroller = ThinReviewScroller()
            }
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
        }
    }
}

private final class ThinReviewScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        4
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.height > 0 else { return }
        let width: CGFloat = 3
        let centered = NSRect(
            x: knobRect.midX - width / 2,
            y: knobRect.minY + 2,
            width: width,
            height: max(12, knobRect.height - 4)
        )
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: centered, xRadius: width / 2, yRadius: width / 2).fill()
    }
}
struct DocumentScrollScope: Hashable {
    let documentID: String
    let chunkID: Int
    let language: String

    init(documentID: String, chunkID: Int, language: String) {
        self.documentID = documentID
        self.chunkID = chunkID
        self.language = language
    }
}

enum DocumentScrollPane: Hashable {
    case source
    case translated

    var opposite: DocumentScrollPane {
        switch self {
        case .source:
            .translated
        case .translated:
            .source
        }
    }
}

struct DocumentScrollGeometry: Equatable {
    let originY: CGFloat
    let topOriginY: CGFloat
    let bottomOriginY: CGFloat
    let documentHeight: CGFloat
    let viewportHeight: CGFloat

    var scrollableHeight: CGFloat {
        max(0, abs(bottomOriginY - topOriginY))
    }

    var progress: CGFloat {
        guard scrollableHeight > .leastNonzeroMagnitude else { return 0 }
        return DocumentScrollMath.clamp(
            (originY - topOriginY) / (bottomOriginY - topOriginY)
        )
    }

    func origin(for progress: CGFloat) -> CGFloat {
        topOriginY + (DocumentScrollMath.clamp(progress) * (bottomOriginY - topOriginY))
    }
}

enum DocumentScrollMath {
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value.isFinite ? value : 0))
    }

    static func scrollableHeight(documentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, documentHeight - viewportHeight)
    }

    static func progress(
        originY: CGFloat,
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        topOriginY: CGFloat = 0,
        direction: CGFloat = 1
    ) -> CGFloat {
        let range = scrollableHeight(documentHeight: documentHeight, viewportHeight: viewportHeight)
        guard range > .leastNonzeroMagnitude else { return 0 }
        return clamp(((originY - topOriginY) * direction) / range)
    }

    static func offset(
        progress: CGFloat,
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        topOriginY: CGFloat = 0,
        direction: CGFloat = 1
    ) -> CGFloat {
        topOriginY + (clamp(progress) * scrollableHeight(
            documentHeight: documentHeight,
            viewportHeight: viewportHeight
        ) * direction)
    }
}

enum DocumentScrollObservation: Equatable {
    case ignored
    case user(CGFloat)
    case followerSuppressed
    case relayout
}

struct DocumentScrollSyncState: Equatable {
    private(set) var scope: DocumentScrollScope?
    private(set) var progress: CGFloat = 0
    private(set) var leader: DocumentScrollPane?
    private(set) var attachedPanes: Set<DocumentScrollPane> = []

    private var expectedFollowerProgress: [DocumentScrollPane: CGFloat] = [:]

    mutating func setScope(_ newScope: DocumentScrollScope?) {
        guard scope != newScope else { return }
        scope = newScope
        progress = 0
        leader = nil
        expectedFollowerProgress.removeAll()
    }

    mutating func bind(_ pane: DocumentScrollPane, scope newScope: DocumentScrollScope) {
        if scope != newScope {
            setScope(newScope)
        }
        attachedPanes.insert(pane)
    }

    mutating func detach(_ pane: DocumentScrollPane) {
        attachedPanes.remove(pane)
        expectedFollowerProgress[pane] = nil
        if attachedPanes.isEmpty {
            scope = nil
            progress = 0
            leader = nil
            expectedFollowerProgress.removeAll()
        }
    }

    mutating func detachAll() {
        scope = nil
        progress = 0
        leader = nil
        attachedPanes.removeAll()
        expectedFollowerProgress.removeAll()
    }

    mutating func recordUserProgress(_ pane: DocumentScrollPane, progress newProgress: CGFloat) {
        guard attachedPanes.contains(pane) else { return }
        expectedFollowerProgress[pane] = nil
        leader = pane
        progress = DocumentScrollMath.clamp(newProgress)
    }

    mutating func resetLeader() {
        leader = nil
    }

    mutating func preserveProgress(_ newProgress: CGFloat? = nil) {
        progress = DocumentScrollMath.clamp(newProgress ?? progress)
    }

    mutating func expectFollowerUpdate(_ pane: DocumentScrollPane, progress: CGFloat) {
        guard attachedPanes.contains(pane) else { return }
        expectedFollowerProgress[pane] = DocumentScrollMath.clamp(progress)
    }

    mutating func clearExpectedFollower(_ pane: DocumentScrollPane) {
        expectedFollowerProgress[pane] = nil
    }

    mutating func observe(
        _ pane: DocumentScrollPane,
        progress observedProgress: CGFloat,
        isLiveScroll: Bool
    ) -> DocumentScrollObservation {
        guard attachedPanes.contains(pane) else { return .ignored }
        if isLiveScroll {
            recordUserProgress(pane, progress: observedProgress)
            return .user(self.progress)
        }

        if let expected = expectedFollowerProgress[pane] {
            expectedFollowerProgress[pane] = nil
            if abs(expected - DocumentScrollMath.clamp(observedProgress)) < 0.002 {
                return .followerSuppressed
            }
        }
        // Genuine non-live user scroll (e.g. scrollbar knob/track, keyboard Page Up/Down)
        recordUserProgress(pane, progress: observedProgress)
        return .user(self.progress)
    }
}

@MainActor
final class DocumentDualScrollCoordinator {
    private(set) var state = DocumentScrollSyncState()

    private weak var sourceScrollView: NSScrollView?
    private weak var translatedScrollView: NSScrollView?
    private var observers: [DocumentScrollPane: [NSObjectProtocol]] = [:]
    private var livePanes: Set<DocumentScrollPane> = []
    private var reapplyScheduled = false

    var progress: CGFloat {
        state.progress
    }

    var scope: DocumentScrollScope? {
        state.scope
    }

    var attachedPanes: Set<DocumentScrollPane> {
        state.attachedPanes
    }


    func setScope(_ newScope: DocumentScrollScope?) {
        guard state.scope != newScope else { return }
        disconnectScrollViews()
        state.detachAll()
        state.setScope(newScope)
        scheduleReapply()
    }

    func attach(
        _ scrollView: NSScrollView,
        pane: DocumentScrollPane,
        scope newScope: DocumentScrollScope
    ) {
        // Idempotent: same scroll view + scope already bound → no re-observe,
        // no scheduleReapply. updateNSView calls attach every SwiftUI tick.
        if state.scope == newScope,
           currentScrollView(for: pane) === scrollView,
           state.attachedPanes.contains(pane),
           observers[pane] != nil {
            return
        }

        if state.scope != newScope {
            setScope(newScope)
        }

        if currentScrollView(for: pane) !== scrollView {
            disconnect(pane: pane)
            assign(scrollView, to: pane)
            observe(scrollView: scrollView, pane: pane)
        } else if observers[pane] == nil {
            observe(scrollView: scrollView, pane: pane)
        }

        state.bind(pane, scope: newScope)
        // Only pin once both panes exist; avoid yanking a single pane to 0.
        if state.attachedPanes.count == 2 {
            scheduleReapply()
        }
    }

    func detach(pane: DocumentScrollPane, scrollView: NSScrollView? = nil) {
        guard let current = currentScrollView(for: pane) else {
            state.detach(pane)
            return
        }
        if let scrollView, current !== scrollView {
            return
        }
        disconnect(pane: pane)
        state.detach(pane)
        scheduleReapply()
    }

    func detach() {
        disconnectScrollViews()
        state.detachAll()
    }

    /// Pin both panes to the top after a chunk change / Approve & Next / Previous.
    func resetToTop() {
        state.preserveProgress(0)
        state.resetLeader()
        if sourceScrollView != nil {
            apply(0, to: .source)
        }
        if translatedScrollView != nil {
            apply(0, to: .translated)
        }
    }

    /// After a programmatic jump (proof unit / chunk top), publish this pane's
    /// progress and pull the opposite pane so linked scroll stays coherent.
    func syncFromProgrammaticScroll(pane: DocumentScrollPane) {
        guard let scrollView = currentScrollView(for: pane),
              let geometry = geometry(for: scrollView)
        else { return }
        state.recordUserProgress(pane, progress: geometry.progress)
        applyFollower(from: pane)
    }

    private func assign(_ scrollView: NSScrollView, to pane: DocumentScrollPane) {
        switch pane {
        case .source:
            sourceScrollView = scrollView
        case .translated:
            translatedScrollView = scrollView
        }
    }

    private func currentScrollView(for pane: DocumentScrollPane) -> NSScrollView? {
        switch pane {
        case .source:
            sourceScrollView
        case .translated:
            translatedScrollView
        }
    }

    private func removeObservers(for pane: DocumentScrollPane) {
        guard let paneObservers = observers.removeValue(forKey: pane) else { return }
        for observer in paneObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func disconnect(pane: DocumentScrollPane) {
        removeObservers(for: pane)
        livePanes.remove(pane)
        state.clearExpectedFollower(pane)
        switch pane {
        case .source:
            sourceScrollView = nil
        case .translated:
            translatedScrollView = nil
        }
    }

    private func disconnectScrollViews() {
        disconnect(pane: .source)
        disconnect(pane: .translated)
    }

    private enum ObservedEvent: Sendable {
        case willStartLiveScroll
        case didLiveScroll
        case didEndLiveScroll
        case clipBoundsDidChange
        case documentBoundsDidChange
    }

    private func observe(scrollView: NSScrollView, pane: DocumentScrollPane) {
        let center = NotificationCenter.default
        var paneObservers: [NSObjectProtocol] = []

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsBoundsChangedNotifications = true

        let registrations: [(Notification.Name, AnyObject?, ObservedEvent)] = [
            (NSScrollView.willStartLiveScrollNotification, scrollView, .willStartLiveScroll),
            (NSScrollView.didLiveScrollNotification, scrollView, .didLiveScroll),
            (NSScrollView.didEndLiveScrollNotification, scrollView, .didEndLiveScroll),
            (NSView.boundsDidChangeNotification, scrollView.contentView, .clipBoundsDidChange),
            (NSView.boundsDidChangeNotification, scrollView.documentView, .documentBoundsDidChange)
        ]

        for (name, object, event) in registrations {
            guard let object else { continue }
            let observer = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handle(event: event, pane: pane)
                }
            }
            paneObservers.append(observer)
        }
        observers[pane] = paneObservers
    }

    private func handle(event: ObservedEvent, pane: DocumentScrollPane) {
        guard let scrollView = currentScrollView(for: pane),
              let geometry = geometry(for: scrollView)
        else {
            scheduleReapply()
            return
        }

        switch event {
        case .willStartLiveScroll:
            livePanes.insert(pane)
            state.clearExpectedFollower(pane)

        case .didLiveScroll:
            livePanes.insert(pane)
            state.recordUserProgress(pane, progress: geometry.progress)
            applyFollower(from: pane)

        case .didEndLiveScroll:
            livePanes.remove(pane)
            // Do not scheduleReapply here — that yanks both panes after every
            // gesture and feels like blink/jump on long dual documents.

        case .clipBoundsDidChange:
            // Follow only during live user scroll (trackpad/wheel/knob drag).
            guard livePanes.contains(pane) else { return }
            state.recordUserProgress(pane, progress: geometry.progress)
            applyFollower(from: pane)

        case .documentBoundsDidChange:
            // Ignore layout-only bounds noise (highlight temp attrs, font, etc.).
            break
        }
    }

    private func geometry(for scrollView: NSScrollView) -> DocumentScrollGeometry? {
        guard let documentView = scrollView.documentView else { return nil }
        let contentView = scrollView.contentView
        let visibleRect = contentView.convert(contentView.bounds, to: documentView)
        let documentBounds = documentView.bounds
        let viewportHeight = max(0, visibleRect.height)
        let documentHeight = max(documentBounds.height, documentView.frame.height)
        let scrollableHeight = max(0, documentHeight - viewportHeight)
        let minimumOrigin = documentBounds.minY
        let maximumOrigin = minimumOrigin + scrollableHeight
        let topOrigin = documentView.isFlipped ? minimumOrigin : maximumOrigin
        let bottomOrigin = documentView.isFlipped ? maximumOrigin : minimumOrigin
        return DocumentScrollGeometry(
            originY: visibleRect.minY,
            topOriginY: topOrigin,
            bottomOriginY: bottomOrigin,
            documentHeight: documentHeight,
            viewportHeight: viewportHeight
        )
    }

    private func applyFollower(from leader: DocumentScrollPane) {
        apply(state.progress, to: leader.opposite)
    }

    private func apply(_ progress: CGFloat, to pane: DocumentScrollPane) {
        guard state.attachedPanes.contains(pane),
              let scrollView = currentScrollView(for: pane),
              let currentGeometry = geometry(for: scrollView)
        else {
            return
        }

        let clampedProgress = DocumentScrollMath.clamp(progress)
        let targetOrigin = currentGeometry.origin(for: clampedProgress)
        let currentOrigin = currentGeometry.originY
        if abs(targetOrigin - currentOrigin) < 0.25 {
            state.clearExpectedFollower(pane)
            return
        }

        guard let documentView = scrollView.documentView else { return }
        state.expectFollowerUpdate(pane, progress: clampedProgress)
        let targetPoint = NSPoint(x: documentView.bounds.minX, y: targetOrigin)
        scrollView.contentView.scroll(to: targetPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // AppKit may clamp the requested origin to a changed content range.
        if let actual = self.geometry(for: scrollView)?.progress {
            state.expectFollowerUpdate(pane, progress: actual)
        }
    }

    private func scheduleReapply() {
        guard !reapplyScheduled else { return }
        reapplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reapplyScheduled = false
            self.reapplyIfIdle()
        }
    }

    private func reapplyIfIdle() {
        guard livePanes.isEmpty else { return }
        state.resetLeader()
        state.preserveProgress()
        if sourceScrollView != nil {
            apply(state.progress, to: .source)
        }
        if translatedScrollView != nil {
            apply(state.progress, to: .translated)
        }
    }
}

struct DocumentScrollSyncBridge: NSViewRepresentable {
    let coordinator: DocumentDualScrollCoordinator
    let pane: DocumentScrollPane
    let scope: DocumentScrollScope

    func makeNSView(context: Context) -> DocumentScrollSyncAnchorView {
        DocumentScrollSyncAnchorView(
            coordinator: coordinator,
            pane: pane,
            scope: scope
        )
    }

    func updateNSView(_ nsView: DocumentScrollSyncAnchorView, context: Context) {
        nsView.configure(coordinator: coordinator, pane: pane, scope: scope)
        nsView.resolveScrollView()
    }
}

final class DocumentScrollSyncAnchorView: NSView {
    private weak var coordinator: DocumentDualScrollCoordinator?
    private var pane: DocumentScrollPane
    private var scope: DocumentScrollScope
    private weak var attachedScrollView: NSScrollView?

    init(
        coordinator: DocumentDualScrollCoordinator,
        pane: DocumentScrollPane,
        scope: DocumentScrollScope
    ) {
        self.coordinator = coordinator
        self.pane = pane
        self.scope = scope
        super.init(frame: .zero)
    }
    private func detach() {
        coordinator?.detach(pane: pane, scrollView: attachedScrollView)
        attachedScrollView = nil
    }

    required init?(coder: NSCoder) {
        nil
    }


    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            resolveScrollView()
        }
    }

    func configure(
        coordinator newCoordinator: DocumentDualScrollCoordinator,
        pane newPane: DocumentScrollPane,
        scope newScope: DocumentScrollScope
    ) {
        if let oldCoordinator = coordinator,
           oldCoordinator !== newCoordinator || pane != newPane || scope != newScope {
            oldCoordinator.detach(pane: pane, scrollView: attachedScrollView)
            attachedScrollView = nil
        }
        coordinator = newCoordinator
        pane = newPane
        scope = newScope
        resolveScrollView()
    }

    func resolveScrollView() {
        guard let coordinator else { return }
        if let scrollView = findScrollView() {
            if attachedScrollView !== scrollView {
                if let attachedScrollView {
                    coordinator.detach(pane: pane, scrollView: attachedScrollView)
                }
                attachedScrollView = scrollView
            }
            coordinator.attach(scrollView, pane: pane, scope: scope)
        } else {
            DispatchQueue.main.async { @MainActor [weak self, weak coordinator] in
                guard let self, let coordinator else { return }
                guard let scrollView = self.findScrollView() else { return }
                if self.attachedScrollView !== scrollView {
                    if let attached = self.attachedScrollView {
                        coordinator.detach(pane: self.pane, scrollView: attached)
                    }
                    self.attachedScrollView = scrollView
                }
                coordinator.attach(scrollView, pane: self.pane, scope: self.scope)
            }
        }
    }

    private func findScrollView() -> NSScrollView? {
        if let enclosingScrollView {
            return enclosingScrollView
        }

        var currentChild: NSView = self
        var ancestor: NSView? = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            let candidateScrollViews = siblingScrollViews(of: currentChild, in: view)
            if !candidateScrollViews.isEmpty {
                return bestMatchingScrollView(from: candidateScrollViews, in: view)
            }
            currentChild = view
            ancestor = view.superview
        }
        return nil
    }

    private func siblingScrollViews(of child: NSView, in ancestor: NSView) -> [NSScrollView] {
        var results: [NSScrollView] = []
        for sibling in ancestor.subviews where sibling !== child {
            if let scrollView = sibling as? NSScrollView {
                results.append(scrollView)
            }
            collectScrollViews(in: sibling, into: &results)
        }
        return results
    }

    private func collectScrollViews(in view: NSView, into results: inout [NSScrollView]) {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                results.append(scrollView)
            }
            collectScrollViews(in: subview, into: &results)
        }
    }

    private func bestMatchingScrollView(from candidates: [NSScrollView], in ancestor: NSView) -> NSScrollView? {
        if candidates.count == 1 {
            return candidates[0]
        }

        let selfRect = self.convert(self.bounds, to: ancestor)
        var bestScrollView: NSScrollView?
        var largestIntersectionArea: CGFloat = -1
        var smallestDistance: CGFloat = .greatestFiniteMagnitude

        for candidate in candidates {
            let candRect = candidate.convert(candidate.bounds, to: ancestor)
            let intersection = selfRect.intersection(candRect)
            let area = (intersection.width > 0 && intersection.height > 0) ? (intersection.width * intersection.height) : 0
            let dist = hypot(candRect.midX - selfRect.midX, candRect.midY - selfRect.midY)

            if area > largestIntersectionArea && area > 0 {
                largestIntersectionArea = area
                bestScrollView = candidate
                smallestDistance = dist
            } else if largestIntersectionArea <= 0 && dist < smallestDistance {
                smallestDistance = dist
                bestScrollView = candidate
            }
        }

        if let bestScrollView {
            return bestScrollView
        }

        if pane == .source {
            return candidates.min(by: {
                $0.convert($0.bounds, to: ancestor).minX < $1.convert($1.bounds, to: ancestor).minX
            })
        } else {
            return candidates.max(by: {
                $0.convert($0.bounds, to: ancestor).minX < $1.convert($1.bounds, to: ancestor).minX
            })
        }
    }
}
