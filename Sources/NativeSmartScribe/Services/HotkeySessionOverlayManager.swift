import AppKit
import NativeSmartScribeCore
import SwiftUI

@MainActor
final class HotkeySessionOverlayManager {
    enum Mode {
        case listening
        case processing

        var tint: Color {
            switch self {
            case .listening:
                .red
            case .processing:
                .green
            }
        }
    }

    private let state = OverlayState()
    private var panel: DraggableOverlayPanel?
    private var originChangeHandler: ((OverlayHUDOrigin) -> Void)?

    func show(
        mode: Mode,
        settings: OverlayHUDSettings,
        onOriginChange: ((OverlayHUDOrigin) -> Void)? = nil
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.originChangeHandler = onOriginChange
        state.mode = mode
        state.scale = settings.scale
        panel.prepareForDisplay(settings: settings)
        panel.orderFrontRegardless()
    }

    func update(mode: Mode? = nil, spectrumBands: [Float]? = nil, settings: OverlayHUDSettings? = nil) {
        if let mode {
            state.mode = mode
        }
        if let spectrumBands, !spectrumBands.isEmpty {
            state.spectrumBands = spectrumBands
        }
        if let settings {
            state.scale = settings.scale
            state.capsuleOpacity = settings.capsuleOpacity
            panel?.updateScale(settings.scale)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func playCue(_ cue: AudioCuePlayer.Cue, settings: OverlayHUDSettings) {
        AudioCuePlayer.shared.play(cue, settings: settings)
    }

    private func makePanel() -> DraggableOverlayPanel {
        let panel = DraggableOverlayPanel(
            overlayState: state,
            initialSize: CGSize(width: 246, height: 68)
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.originDidChange = { [weak self] origin in
            self?.originChangeHandler?(origin)
        }
        return panel
    }
}

@MainActor
private final class OverlayState: ObservableObject {
    @Published var mode: HotkeySessionOverlayManager.Mode = .listening
    @Published var spectrumBands: [Float] = Array(repeating: 0.04, count: 40)
    @Published var scale: Double = 1
    @Published var capsuleOpacity: Double = 0.32
}

private final class DraggableOverlayPanel: NSPanel {
    var originDidChange: ((OverlayHUDOrigin) -> Void)?

    private let overlayState: OverlayState
    private let baseSize: CGSize
    private let rootView: OverlayRootView
    private var hasPlacedFrame = false
    private var dragStartFrameOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?

    init(overlayState: OverlayState, initialSize: CGSize) {
        self.overlayState = overlayState
        self.baseSize = initialSize
        self.rootView = OverlayRootView(state: overlayState)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = rootView
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.onMouseDown = { [weak self] screenPoint in
            self?.beginDrag(at: screenPoint)
        }
        rootView.onMouseDragged = { [weak self] screenPoint in
            self?.updateDrag(to: screenPoint)
        }
        rootView.onMouseUp = { [weak self] in
            self?.endDrag()
        }
        updateScale(overlayState.scale)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func prepareForDisplay(settings: OverlayHUDSettings) {
        overlayState.capsuleOpacity = settings.capsuleOpacity
        updateScale(settings.scale)
        guard !hasPlacedFrame else { return }

        let visibleFrame = screenVisibleFrame()
        let origin = settings.lastOrigin.map(CGPoint.init(origin:)) ?? bottomCenterOrigin(for: frame.size, visibleFrame: visibleFrame)
        setFrameOrigin(clamp(origin: origin, size: frame.size, visibleFrame: visibleFrame))
        hasPlacedFrame = true
    }

    func updateScale(_ scale: Double) {
        let newSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let previousFrame = frame
        let previousCenter = CGPoint(x: previousFrame.midX, y: previousFrame.midY)
        setContentSize(newSize)

        guard hasPlacedFrame else { return }
        let centeredOrigin = CGPoint(
            x: previousCenter.x - newSize.width / 2,
            y: previousCenter.y - newSize.height / 2
        )
        setFrameOrigin(clamp(origin: centeredOrigin, size: newSize, visibleFrame: screenVisibleFrame()))
        persistCurrentOrigin()
    }

    private func beginDrag(at screenPoint: CGPoint) {
        dragStartMouseLocation = screenPoint
        dragStartFrameOrigin = frame.origin
    }

    private func updateDrag(to screenPoint: CGPoint) {
        guard let dragStartMouseLocation, let dragStartFrameOrigin else { return }
        let visibleFrame = screenVisibleFrame()
        let delta = CGPoint(
            x: screenPoint.x - dragStartMouseLocation.x,
            y: screenPoint.y - dragStartMouseLocation.y
        )
        let proposedOrigin = CGPoint(
            x: dragStartFrameOrigin.x + delta.x,
            y: dragStartFrameOrigin.y + delta.y
        )
        setFrameOrigin(clamp(origin: proposedOrigin, size: frame.size, visibleFrame: visibleFrame))
    }

    private func endDrag() {
        dragStartMouseLocation = nil
        dragStartFrameOrigin = nil
        persistCurrentOrigin()
    }

    private func persistCurrentOrigin() {
        originDidChange?(OverlayHUDOrigin(x: Double(frame.origin.x), y: Double(frame.origin.y)))
    }

    private func screenVisibleFrame() -> CGRect {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }
}

private final class OverlayRootView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    private let hostingView: NSHostingView<HotkeySessionOverlayView>
    private let captureView = OverlayMouseCaptureView()

    init(state: OverlayState) {
        hostingView = NSHostingView(rootView: HotkeySessionOverlayView(state: state))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        captureView.translatesAutoresizingMaskIntoConstraints = false
        captureView.onMouseDown = { [weak self] point in self?.onMouseDown?(point) }
        captureView.onMouseDragged = { [weak self] point in self?.onMouseDragged?(point) }
        captureView.onMouseUp = { [weak self] in self?.onMouseUp?() }

        addSubview(hostingView)
        addSubview(captureView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            captureView.leadingAnchor.constraint(equalTo: leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: trailingAnchor),
            captureView.topAnchor.constraint(equalTo: topAnchor),
            captureView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class OverlayMouseCaptureView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}

private struct HotkeySessionOverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        let shape = Capsule(style: .continuous)

        return DotSpectrumView(
            bands: state.spectrumBands,
            color: state.mode.tint,
            isActive: true,
            isProcessing: state.mode == .processing,
            dotCount: 34,
            noiseFloor: 0.13,
            amplitude: 0.82,
            sensitivity: 0.78,
            silenceThreshold: 0.18
        )
        .frame(width: 188 * state.scale, height: 34 * state.scale)
        .padding(.horizontal, 24 * state.scale)
        .padding(.vertical, 12 * state.scale)
        .clipShape(shape)
        .background {
            ZStack {
                shape
                    .fill(.ultraThinMaterial)
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.16),
                                .white.opacity(0.035),
                                .black.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .opacity(state.capsuleOpacity)
        }
        .overlay {
            shape
                .inset(by: 0.75 * state.scale)
                .stroke(.white.opacity(0.22), lineWidth: 1.0 * state.scale)
        }
        .overlay {
            shape
                .inset(by: 2.2 * state.scale)
                .stroke(.black.opacity(0.05), lineWidth: 0.7 * state.scale)
        }
        .shadow(color: .black.opacity(0.14), radius: 18 * state.scale, x: 0, y: 8 * state.scale)
        .shadow(color: .white.opacity(0.08), radius: 1 * state.scale, x: 0, y: 0)
        .padding(5 * state.scale)
    }
}

private func bottomCenterOrigin(for size: CGSize, visibleFrame: CGRect) -> CGPoint {
    let inset: CGFloat = 18
    return CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + inset)
}

private func clamp(origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
    CGPoint(
        x: min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12),
        y: min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
    )
}

private extension CGPoint {
    init(origin: OverlayHUDOrigin) {
        self.init(x: CGFloat(origin.x), y: CGFloat(origin.y))
    }
}
