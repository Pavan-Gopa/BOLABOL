import AppKit
@preconcurrency import AVFoundation
import SwiftUI
import VaniScriptCore

struct NativeMetalClipPreviewView: NSViewRepresentable {
    let player: AVPlayer?
    let renderPlan: NativeShortsRenderPlan
    let timeSec: Double
    let sourceSize: CGSize

    func makeNSView(context: Context) -> NativeMetalClipPreviewHostingView {
        NativeMetalClipPreviewHostingView()
    }

    func updateNSView(_ nsView: NativeMetalClipPreviewHostingView, context: Context) {
        nsView.update(
            player: player,
            renderPlan: renderPlan,
            timeSec: timeSec,
            sourceSize: sourceSize
        )
    }
}

final class NativeMetalClipPreviewHostingView: NSView {
    private let renderer = NativeMetalShortsFrameRenderer()
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var playerItem: AVPlayerItem?
    private var lastSourcePixelBuffer: CVPixelBuffer?
    private var player: AVPlayer?
    private var renderPlan: NativeShortsRenderPlan?
    private var timeSec: Double = 0
    private var sourceSize: CGSize = CGSize(width: 16, height: 9)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        renderCurrentFrame()
    }

    func update(
        player: AVPlayer?,
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double,
        sourceSize: CGSize
    ) {
        self.player = player
        self.renderPlan = renderPlan
        self.timeSec = timeSec
        self.sourceSize = sourceSize
        attachVideoOutputIfNeeded(to: player?.currentItem)
        renderCurrentFrame()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
        layer?.masksToBounds = true
    }

    private func attachVideoOutputIfNeeded(to item: AVPlayerItem?) {
        guard playerItem !== item else { return }
        if let playerItem, let videoOutput {
            playerItem.remove(videoOutput)
        }

        playerItem = item
        lastSourcePixelBuffer = nil

        guard let item else {
            videoOutput = nil
            return
        }

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ])
        item.add(output)
        videoOutput = output
    }

    private func renderCurrentFrame() {
        guard let renderer,
              let renderPlan,
              bounds.width > 2,
              bounds.height > 2
        else {
            layer?.contents = nil
            return
        }

        let sourcePixelBuffer = currentSourcePixelBuffer()
        let frameSourceSize = sourcePixelBuffer.map {
            CGSize(width: max(1, CVPixelBufferGetWidth($0)), height: max(1, CVPixelBufferGetHeight($0)))
        } ?? sourceSize
        let width = max(1, renderPlan.width)
        let height = max(1, renderPlan.height)

        do {
            let image = try renderer.renderPreviewImage(
                sourcePixelBuffer: sourcePixelBuffer,
                sourceSize: frameSourceSize,
                renderPlan: renderPlan,
                timeSec: timeSec,
                width: width,
                height: height
            )
            layer?.contents = image
        } catch {
            layer?.contents = nil
        }
    }

    private func currentSourcePixelBuffer() -> CVPixelBuffer? {
        guard let videoOutput else { return nil }
        let itemTime = player?.currentTime() ?? CMTime(seconds: timeSec, preferredTimescale: 600)
        if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastSourcePixelBuffer = pixelBuffer
            return pixelBuffer
        }
        let hostTime = CACurrentMediaTime()
        let displayTime = videoOutput.itemTime(forHostTime: hostTime)
        if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: displayTime, itemTimeForDisplay: nil) {
            lastSourcePixelBuffer = pixelBuffer
            return pixelBuffer
        }
        return lastSourcePixelBuffer
    }
}
