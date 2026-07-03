import AppKit
@preconcurrency import AVFoundation
import CoreVideo
import Metal
import MetalPerformanceShaders
import simd
import VaniScriptCore

final class NativeMetalVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let sourceTrackID: CMPersistentTrackID
    let sourceSize: CGSize
    let renderPlan: NativeShortsRenderPlan

    init(sourceTrackID: CMPersistentTrackID, sourceSize: CGSize, renderPlan: NativeShortsRenderPlan) {
        self.sourceTrackID = sourceTrackID
        self.sourceSize = sourceSize
        self.renderPlan = renderPlan
        self.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: renderPlan.durationSec, preferredTimescale: 600)
        )
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
    }
}

final class NativeMetalVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderer = NativeMetalShortsFrameRenderer()
    private var renderContext: AVVideoCompositionRenderContext?
    private let lock = NSLock()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock()
        renderContext = newRenderContext
        lock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? NativeMetalVideoCompositionInstruction else {
                request.finish(with: NativeMetalVideoCompositorError.invalidInstruction)
                return
            }

            lock.lock()
            let context = renderContext
            lock.unlock()

            guard let outputPixelBuffer = context?.newPixelBuffer() else {
                request.finish(with: NativeMetalVideoCompositorError.cannotCreateOutputPixelBuffer)
                return
            }

            let sourcePixelBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID)
            do {
                guard let renderer else {
                    throw NativeMetalVideoCompositorError.metalUnavailable
                }
                try renderer.render(
                    sourcePixelBuffer: sourcePixelBuffer,
                    outputPixelBuffer: outputPixelBuffer,
                    sourceSize: instruction.sourceSize,
                    renderPlan: instruction.renderPlan,
                    timeSec: request.compositionTime.seconds
                )
                request.finish(withComposedVideoFrame: outputPixelBuffer)
            } catch {
                request.finish(with: error)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

enum NativeMetalVideoCompositorError: LocalizedError {
    case metalUnavailable
    case invalidInstruction
    case cannotCreateOutputPixelBuffer
    case cannotCreateTexture
    case cannotCreateCommandBuffer
    case cannotCreateOverlayPixelBuffer
    case cannotCreatePreviewImage

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is unavailable on this Mac."
        case .invalidInstruction:
            return "Native Metal video compositor received an invalid render instruction."
        case .cannotCreateOutputPixelBuffer:
            return "Native Metal video compositor could not allocate an output frame."
        case .cannotCreateTexture:
            return "Native Metal video compositor could not create a GPU texture."
        case .cannotCreateCommandBuffer:
            return "Native Metal video compositor could not create a command buffer."
        case .cannotCreateOverlayPixelBuffer:
            return "Native Metal video compositor could not allocate an overlay texture."
        case .cannotCreatePreviewImage:
            return "Native Metal video compositor could not create a preview image."
        }
    }
}

private struct NativeMetalShortsUniforms {
    var width: UInt32
    var height: UInt32
    var sourceWidth: UInt32
    var sourceHeight: UInt32
    var backgroundColor: SIMD4<Float>
    var gradientColorA: SIMD4<Float>
    var gradientColorB: SIMD4<Float>
    var hasSource: UInt32
    var blurEnabled: UInt32
    var gradientEnabled: UInt32
    var radialGradient: UInt32
    var gradientAngle: Float
    var gradientOpacity: Float
    var frameZoom: Float
    var framePanX: Float
    var framePanY: Float
    var blurScale: Float
    var blurPanX: Float
    var foregroundOpacity: Float
    var featherTop: Float
    var featherBottom: Float
    var featherTopStrength: Float
    var featherBottomStrength: Float
    var featherLeft: Float
    var featherRight: Float
    var featherEnabled: UInt32
    var _pad0: UInt32 = 0
    var _pad1: UInt32 = 0
    var _pad2: UInt32 = 0
}

final class NativeMetalShortsFrameRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?
    private let overlayRenderer: NativeMetalOverlayRenderer
    private let transparentTexture: MTLTexture

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: NativeMetalShortsFrameRenderer.shaderSource, options: nil),
              let function = library.makeFunction(name: "shortsCompositeKernel"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else {
            return nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.textureCache = cache
        self.overlayRenderer = NativeMetalOverlayRenderer(device: device, commandQueue: commandQueue)
        self.transparentTexture = NativeMetalShortsFrameRenderer.makeSolidTexture(device: device, color: SIMD4<UInt8>(0, 0, 0, 0))
    }

    func render(
        sourcePixelBuffer: CVPixelBuffer?,
        outputPixelBuffer: CVPixelBuffer,
        sourceSize: CGSize,
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw NativeMetalVideoCompositorError.cannotCreateCommandBuffer
        }

        let outputTexture = try texture(from: outputPixelBuffer, usage: [.shaderWrite, .shaderRead])
        let sourceTexture = try sourcePixelBuffer.map { try texture(from: $0, usage: [.shaderRead]) } ?? transparentTexture
        let blurTexture = try blurTextureIfNeeded(
            sourceTexture: sourceTexture,
            sourcePixelBuffer: sourcePixelBuffer,
            renderPlan: renderPlan,
            commandBuffer: commandBuffer
        ) ?? sourceTexture
        let overlayTexture = try overlayTextureIfNeeded(
            renderPlan: renderPlan,
            timeSec: timeSec,
            width: outputTexture.width,
            height: outputTexture.height
        ) ?? transparentTexture
        let frame = NativeShortsRenderPlanBuilder.interpolateFrameState(renderPlan.frameKeyframes, timeSec: timeSec)
        let orientedSourceWidth = UInt32(max(1, Int(sourceSize.width.rounded())))
        let orientedSourceHeight = UInt32(max(1, Int(sourceSize.height.rounded())))
        var uniforms = NativeMetalShortsUniforms(
            width: UInt32(outputTexture.width),
            height: UInt32(outputTexture.height),
            sourceWidth: orientedSourceWidth,
            sourceHeight: orientedSourceHeight,
            backgroundColor: rgba(renderPlan.backgroundSettings.solidEnabled ? renderPlan.backgroundSettings.solidColor : (frame.backgroundColor ?? renderPlan.backgroundSettings.solidColor)),
            gradientColorA: rgba(renderPlan.backgroundSettings.gradientColorA, alpha: renderPlan.backgroundSettings.gradientOpacity),
            gradientColorB: rgba(renderPlan.backgroundSettings.gradientColorB, alpha: renderPlan.backgroundSettings.gradientOpacity),
            hasSource: sourcePixelBuffer == nil ? 0 : 1,
            blurEnabled: renderPlan.backgroundSettings.blurEnabled ? 1 : 0,
            gradientEnabled: renderPlan.backgroundSettings.gradientEnabled ? 1 : 0,
            radialGradient: renderPlan.backgroundSettings.gradientType == "radial" ? 1 : 0,
            gradientAngle: Float(renderPlan.backgroundSettings.gradientAngle),
            gradientOpacity: Float(renderPlan.backgroundSettings.gradientOpacity),
            frameZoom: Float(max(0.05, frame.zoom)),
            framePanX: Float(frame.x),
            framePanY: Float(frame.y),
            blurScale: Float(max(1.0, renderPlan.backgroundSettings.blurScale)),
            blurPanX: Float(renderPlan.backgroundSettings.blurPanX ?? 0),
            foregroundOpacity: Float(foregroundOpacity(renderPlan: renderPlan, timeSec: timeSec)),
            featherTop: Float(renderPlan.backgroundSettings.featherTop * effectScale(renderPlan.backgroundSettings, renderHeight: renderPlan.height)),
            featherBottom: Float(renderPlan.backgroundSettings.featherBottom * effectScale(renderPlan.backgroundSettings, renderHeight: renderPlan.height)),
            featherTopStrength: Float(featherStrength(renderPlan.backgroundSettings.featherTopHeight)),
            featherBottomStrength: Float(featherStrength(renderPlan.backgroundSettings.featherBottomHeight)),
            featherLeft: Float(renderPlan.backgroundSettings.featherLeft * effectScale(renderPlan.backgroundSettings, renderHeight: renderPlan.height)),
            featherRight: Float(renderPlan.backgroundSettings.featherRight * effectScale(renderPlan.backgroundSettings, renderHeight: renderPlan.height)),
            featherEnabled: renderPlan.backgroundSettings.featherEnabled ? 1 : 0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NativeMetalVideoCompositorError.cannotCreateCommandBuffer
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(blurTexture, index: 1)
        encoder.setTexture(overlayTexture, index: 2)
        encoder.setTexture(outputTexture, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<NativeMetalShortsUniforms>.stride, index: 0)

        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let groupSize = MTLSize(width: width, height: height, depth: 1)
        let gridSize = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func renderPreviewImage(
        sourcePixelBuffer: CVPixelBuffer?,
        sourceSize: CGSize,
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double,
        width: Int,
        height: Int
    ) throws -> CGImage {
        var outputPixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            nil,
            max(1, width),
            max(1, height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputPixelBuffer
        )
        guard status == kCVReturnSuccess, let outputPixelBuffer else {
            throw NativeMetalVideoCompositorError.cannotCreateOutputPixelBuffer
        }

        try render(
            sourcePixelBuffer: sourcePixelBuffer,
            outputPixelBuffer: outputPixelBuffer,
            sourceSize: sourceSize,
            renderPlan: renderPlan,
            timeSec: timeSec
        )
        return try cgImage(from: outputPixelBuffer)
    }

    private func blurTextureIfNeeded(
        sourceTexture: MTLTexture,
        sourcePixelBuffer: CVPixelBuffer?,
        renderPlan: NativeShortsRenderPlan,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture? {
        guard sourcePixelBuffer != nil, renderPlan.backgroundSettings.blurEnabled else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceTexture.pixelFormat,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let destination = device.makeTexture(descriptor: descriptor) else {
            throw NativeMetalVideoCompositorError.cannotCreateTexture
        }
        let radius = Float(max(0, renderPlan.backgroundSettings.blurStrength * effectScale(renderPlan.backgroundSettings, renderHeight: renderPlan.height)))
        let blur = MPSImageGaussianBlur(device: device, sigma: max(0.01, radius))
        blur.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: destination)
        return destination
    }

    private func overlayTextureIfNeeded(
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double,
        width: Int,
        height: Int
    ) throws -> MTLTexture? {
        guard let overlayBuffer = try overlayRenderer.makeOverlayPixelBuffer(
            renderPlan: renderPlan,
            timeSec: timeSec,
            width: width,
            height: height
        ) else { return nil }
        return try texture(from: overlayBuffer, usage: [.shaderRead])
    }

    private func texture(from pixelBuffer: CVPixelBuffer, usage: MTLTextureUsage) throws -> MTLTexture {
        guard let textureCache else {
            throw NativeMetalVideoCompositorError.cannotCreateTexture
        }
        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &textureRef
        )
        guard status == kCVReturnSuccess, let texture = textureRef.flatMap(CVMetalTextureGetTexture) else {
            throw NativeMetalVideoCompositorError.cannotCreateTexture
        }
        return texture
    }

    private static func makeSolidTexture(device: MTLDevice, color: SIMD4<UInt8>) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixel = color
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }

    private func cgImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NativeMetalVideoCompositorError.cannotCreatePreviewImage
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let byteCount = bytesPerRow * height
        let data = Data(bytes: baseAddress, count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw NativeMetalVideoCompositorError.cannotCreatePreviewImage
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw NativeMetalVideoCompositorError.cannotCreatePreviewImage
        }
        return image
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct NativeMetalShortsUniforms {
        uint width;
        uint height;
        uint sourceWidth;
        uint sourceHeight;
        float4 backgroundColor;
        float4 gradientColorA;
        float4 gradientColorB;
        uint hasSource;
        uint blurEnabled;
        uint gradientEnabled;
        uint radialGradient;
        float gradientAngle;
        float gradientOpacity;
        float frameZoom;
        float framePanX;
        float framePanY;
        float blurScale;
        float blurPanX;
        float foregroundOpacity;
        float featherTop;
        float featherBottom;
        float featherTopStrength;
        float featherBottomStrength;
        float featherLeft;
        float featherRight;
        uint featherEnabled;
        uint _pad0;
        uint _pad1;
        uint _pad2;
    };

    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    static float4 over(float4 fg, float4 bg) {
        return float4(fg.rgb * fg.a + bg.rgb * (1.0 - fg.a), fg.a + bg.a * (1.0 - fg.a));
    }

    static float4 overPremultiplied(float4 fg, float4 bg) {
        return float4(fg.rgb + bg.rgb * (1.0 - fg.a), fg.a + bg.a * (1.0 - fg.a));
    }

    static float2 previewStageSize(float2 outputSize, float2 sourceSize) {
        float sourceAspect = sourceSize.x / max(1.0, sourceSize.y);
        return float2(max(outputSize.x, outputSize.y * sourceAspect), outputSize.y);
    }

    static float2 previewStagePixel(float2 pixel, float2 outputSize, float2 stageSize) {
        return float2(pixel.x + ((stageSize.x - outputSize.x) * 0.5), pixel.y);
    }

    static float2 previewPlacedUV(float2 pixel, float2 outputSize, float2 sourceSize, float zoom, float panX, float panY) {
        float2 stageSize = previewStageSize(outputSize, sourceSize);
        float2 stagePixel = previewStagePixel(pixel, outputSize, stageSize);
        float baseScale = (stageSize.y / max(1.0, sourceSize.y)) * max(0.05, zoom);
        float2 scaled = sourceSize * baseScale;
        float2 origin = ((stageSize - scaled) * 0.5) + float2(stageSize.x * (panX / 100.0),
                                                             stageSize.y * (panY / 100.0));
        return (stagePixel - origin) / scaled;
    }

    static float gradientAmount(float2 uv, constant NativeMetalShortsUniforms &u) {
        if (u.radialGradient == 1) {
            return clamp(distance(uv, float2(0.5, 0.5)) * 1.42, 0.0, 1.0);
        }
        float angle = (u.gradientAngle - 90.0) * 0.017453292519943295;
        float2 dir = normalize(float2(cos(angle), sin(angle)));
        return clamp(dot(uv - 0.5, dir) + 0.5, 0.0, 1.0);
    }

    static float featherAlpha(float2 pixel, float2 outputSize, constant NativeMetalShortsUniforms &u) {
        float alpha = 1.0;
        if (u.featherTop > 0.0) {
            float topEnd = min(outputSize.y * 0.5, max(0.0, u.featherTop));
            float topStart = topEnd * (1.0 - clamp(u.featherTopStrength, 0.0, 1.0));
            alpha = min(alpha, clamp((pixel.y - topStart) / max(0.001, topEnd - topStart), 0.0, 1.0));
        }
        if (u.featherBottom > 0.0) {
            float bottomStart = max(0.0, outputSize.y - max(0.0, u.featherBottom));
            float bottomEnd = bottomStart + (outputSize.y - bottomStart) * (1.0 - clamp(u.featherBottomStrength, 0.0, 1.0));
            alpha = min(alpha, 1.0 - clamp((pixel.y - bottomStart) / max(0.001, bottomEnd - bottomStart), 0.0, 1.0));
        }
        if (u.featherLeft > 0.0) {
            alpha = min(alpha, clamp(pixel.x / max(0.001, u.featherLeft), 0.0, 1.0));
        }
        if (u.featherRight > 0.0) {
            alpha = min(alpha, clamp((outputSize.x - pixel.x) / max(0.001, u.featherRight), 0.0, 1.0));
        }
        return alpha;
    }

    kernel void shortsCompositeKernel(
        texture2d<float, access::sample> sourceTexture [[texture(0)]],
        texture2d<float, access::sample> blurTexture [[texture(1)]],
        texture2d<float, access::sample> overlayTexture [[texture(2)]],
        texture2d<float, access::write> outputTexture [[texture(3)]],
        constant NativeMetalShortsUniforms &u [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= u.width || gid.y >= u.height) { return; }
        float2 outputSize = float2((float)u.width, (float)u.height);
        float2 sourceSize = float2(max(1.0, (float)u.sourceWidth), max(1.0, (float)u.sourceHeight));
        float2 pixel = float2((float)gid.x + 0.5, (float)gid.y + 0.5);
        float2 uv = pixel / outputSize;
        float4 color = u.backgroundColor;

        if (u.hasSource == 1 && u.blurEnabled == 1) {
            float2 blurUV = previewPlacedUV(pixel, outputSize, sourceSize, u.blurScale, u.blurPanX, 0.0);
            if (all(blurUV >= 0.0) && all(blurUV <= 1.0)) {
                color = blurTexture.sample(linearSampler, blurUV);
            }
        }

        if (u.gradientEnabled == 1) {
            float amount = gradientAmount(uv, u);
            float4 gradient = mix(u.gradientColorA, u.gradientColorB, amount);
            gradient.a *= u.gradientOpacity;
            color = over(gradient, color);
        }

        if (u.hasSource == 1) {
            float2 foregroundUV = previewPlacedUV(pixel, outputSize, sourceSize, u.frameZoom, u.framePanX, u.framePanY);
            if (all(foregroundUV >= 0.0) && all(foregroundUV <= 1.0)) {
                float4 foreground = sourceTexture.sample(linearSampler, foregroundUV);
                if (u.featherEnabled == 1) {
                    foreground.a *= featherAlpha(pixel, outputSize, u);
                }
                foreground.a *= clamp(u.foregroundOpacity, 0.0, 1.0);
                color = over(foreground, color);
            }
        }

        float4 overlay = overlayTexture.sample(linearSampler, uv);
        color = overPremultiplied(overlay, color);
        outputTexture.write(float4(color.rgb, 1.0), gid);
    }
    """
}

private final class NativeMetalOverlayRenderer: @unchecked Sendable {
    private struct OverlayPixelBufferCacheKey: Hashable {
        let width: Int
        let height: Int
        let signature: String
    }

    private struct FrameGlowMaskCacheKey: Hashable {
        let width: Int
        let height: Int
        let lineWidth: Int
        let glowDepth: Int
    }

    private struct CaptionBackgroundCacheKey: Hashable {
        let width: Int
        let height: Int
        let cornerRadius: Int
        let blurRadius: Int
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let overlayCacheLock = NSLock()
    private var overlayPixelBufferCache: [OverlayPixelBufferCacheKey: CVPixelBuffer] = [:]
    private var frameGlowMaskCache: [FrameGlowMaskCacheKey: CGImage] = [:]
    private var captionBackgroundImageCache: [CaptionBackgroundCacheKey: NSImage] = [:]
    private var decodedImageCache: [String: NSImage] = [:]
    private var visualEditorFontsRegistered = false

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    func makeOverlayPixelBuffer(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) throws -> CVPixelBuffer? {
        guard hasVisibleOverlay(renderPlan: renderPlan, timeSec: timeSec) else { return nil }
        if let cacheKey = staticOverlayCacheKey(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height) {
            return try cachedOverlayPixelBuffer(
                cacheKey: cacheKey,
                renderPlan: renderPlan,
                timeSec: timeSec,
                width: width,
                height: height
            )
        }
        return try renderOverlayPixelBuffer(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)
    }

    private func staticOverlayCacheKey(
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double,
        width: Int,
        height: Int
    ) -> OverlayPixelBufferCacheKey? {
        guard !activeIntroOutroOverlayIsTimeVarying(renderPlan: renderPlan, timeSec: timeSec) else {
            return nil
        }

        var parts: [String] = ["overlay-v2"]
        let settings = renderPlan.backgroundSettings
        if settings.frameGuideOpacity > 0 ||
            (settings.frameGuideBorderOpacity > 0 &&
             (settings.frameGuideBorderWidth > 0 || settings.frameGuideBlur > 0)) {
            parts.append("guide:\(backgroundGuideSignature(settings))")
        }

        let introDuration = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.duration ?? 0
        let outroDuration = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.duration ?? 0
        let activeVideoEnd = max(introDuration, renderPlan.durationSec - outroDuration)
        if let logo = renderPlan.logo,
           logo.hidden != true,
           !logo.src.isEmpty,
           timeSec >= introDuration,
           timeSec <= activeVideoEnd {
            parts.append("logo:\(logoSignature(logo))")
        }

        if let cue = activeSubtitle(renderPlan: renderPlan, timeSec: timeSec) {
            parts.append([
                "subtitle",
                cue.id,
                signatureNumber(cue.startSec),
                signatureNumber(cue.endSec),
                cue.text,
                signatureNumber(renderPlan.subtitleBottomMargin),
                styleSignature(renderPlan.captionStyle)
            ].joined(separator: ":"))
        }

        for block in activeTextBlocks(renderPlan: renderPlan, timeSec: timeSec) {
            let style = block.style ?? defaultTextTrackStyle(trackIndex: block.trackIndex, baseStyle: renderPlan.captionStyle)
            parts.append([
                "text",
                "\(block.trackIndex)",
                block.text,
                styleSignature(style)
            ].joined(separator: ":"))
        }

        guard parts.count > 1 else { return nil }
        return OverlayPixelBufferCacheKey(width: width, height: height, signature: parts.joined(separator: "|"))
    }

    private func activeIntroOutroOverlayIsTimeVarying(renderPlan: NativeShortsRenderPlan, timeSec: Double) -> Bool {
        if let intro = renderPlan.intro,
           intro.hidden != true,
           timeSec >= 0,
           timeSec <= intro.duration {
            return true
        }

        if let outro = renderPlan.outro,
           outro.hidden != true {
            let start = max(0, renderPlan.durationSec - outro.duration)
            if timeSec >= start, timeSec <= renderPlan.durationSec {
                return true
            }
        }

        return false
    }

    private func backgroundGuideSignature(_ settings: ShortsBackgroundSettings) -> String {
        [
            settings.frameGuideColor,
            signatureNumber(settings.frameGuideOpacity),
            signatureNumber(settings.frameGuideBorderWidth),
            signatureNumber(settings.frameGuideBlur),
            signatureNumber(settings.frameGuideBorderOpacity),
            signatureNumber(settings.effectReferenceHeight)
        ].joined(separator: ",")
    }

    private func logoSignature(_ logo: LogoOverlaySettings) -> String {
        [
            logo.id,
            imageCacheKey(for: logo.src),
            logo.position ?? "top-left",
            signatureNumber(logo.size),
            signatureNumber(logo.opacity)
        ].joined(separator: ",")
    }

    private func styleSignature(_ style: ShortsSubtitleStyle) -> String {
        [
            style.fontFamily,
            signatureNumber(style.fontSize),
            style.bold ? "bold" : "regular",
            style.textTransform.rawValue,
            style.textColor,
            style.boxColor,
            signatureNumber(style.boxOpacity),
            signatureNumber(style.boxWidth),
            signatureNumber(style.boxHeight),
            signatureNumber(style.edgeBlur),
            signatureNumber(style.letterSpacing),
            signatureNumber(style.lineSpacing),
            signatureNumber(style.edgeSoftness),
            signatureNumber(style.outline),
            style.outlineColor ?? "",
            signatureNumber(style.outlineOpacity),
            signatureNumber(style.shadow),
            style.shadowColor ?? "",
            signatureNumber(style.shadowOpacity),
            signatureNumber(style.shadowBlur),
            signatureNumber(style.shadowDistance),
            signatureNumber(style.shadowAngle),
            signatureNumber(style.subtitleBottomMargin)
        ].joined(separator: ",")
    }

    private func signatureNumber(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.4f", value)
    }

    private func cachedOverlayPixelBuffer(
        cacheKey: OverlayPixelBufferCacheKey,
        renderPlan: NativeShortsRenderPlan,
        timeSec: Double,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        overlayCacheLock.lock()
        if let cached = overlayPixelBufferCache[cacheKey] {
            overlayCacheLock.unlock()
            return cached
        }
        overlayCacheLock.unlock()

        let rendered = try renderOverlayPixelBuffer(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)

        overlayCacheLock.lock()
        if overlayPixelBufferCache.count > maxOverlayPixelBufferCacheEntries(width: width, height: height) {
            overlayPixelBufferCache.removeAll(keepingCapacity: true)
        }
        overlayPixelBufferCache[cacheKey] = rendered
        overlayCacheLock.unlock()
        return rendered
    }

    private func renderOverlayPixelBuffer(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NativeMetalVideoCompositorError.cannotCreateOverlayPixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            throw NativeMetalVideoCompositorError.cannotCreateOverlayPixelBuffer
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawFrameGuide(renderPlan: renderPlan, width: width, height: height)
        drawLogo(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)
        drawIntroOutro(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)
        drawTextTracks(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)
        drawSubtitles(renderPlan: renderPlan, timeSec: timeSec, width: width, height: height)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        return pixelBuffer
    }

    private func maxOverlayPixelBufferCacheEntries(width: Int, height: Int) -> Int {
        width * height > 4_000_000 ? 3 : 8
    }

    private func hasVisibleOverlay(renderPlan: NativeShortsRenderPlan, timeSec: Double) -> Bool {
        if renderPlan.backgroundSettings.frameGuideOpacity > 0 {
            return true
        }
        if renderPlan.backgroundSettings.frameGuideBorderWidth > 0,
           renderPlan.backgroundSettings.frameGuideBorderOpacity > 0 {
            return true
        }
        if renderPlan.backgroundSettings.frameGuideBlur > 0,
           renderPlan.backgroundSettings.frameGuideBorderOpacity > 0 {
            return true
        }
        if activeSubtitle(renderPlan: renderPlan, timeSec: timeSec) != nil { return true }
        if !activeTextBlocks(renderPlan: renderPlan, timeSec: timeSec).isEmpty { return true }
        let introDuration = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.duration ?? 0
        let outroDuration = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.duration ?? 0
        let activeVideoEnd = max(introDuration, renderPlan.durationSec - outroDuration)
        if let logo = renderPlan.logo, logo.hidden != true, !logo.src.isEmpty, timeSec >= introDuration, timeSec <= activeVideoEnd { return true }
        if let intro = renderPlan.intro, intro.hidden != true, timeSec >= 0, timeSec <= intro.duration { return true }
        if let outro = renderPlan.outro, outro.hidden != true, timeSec >= activeVideoEnd, timeSec <= renderPlan.durationSec { return true }
        return false
    }

    private func drawFrameGuide(renderPlan: NativeShortsRenderPlan, width: Int, height: Int) {
        let settings = renderPlan.backgroundSettings
        guard settings.frameGuideOpacity > 0 ||
              (settings.frameGuideBorderOpacity > 0 &&
               (settings.frameGuideBorderWidth > 0 || settings.frameGuideBlur > 0))
        else { return }

        let frameGuideScale = CGFloat(effectScale(settings, renderHeight: height))
        let lineWidth = max(0, CGFloat(settings.frameGuideBorderWidth) * frameGuideScale)
        let glow = max(0, CGFloat(settings.frameGuideBlur) * frameGuideScale * 2.25)
        let rect = shortsGuideRect(width: width, height: height)
        let color = NSColor(cgColor: cgColor(settings.frameGuideColor, alpha: settings.frameGuideBorderOpacity)) ?? .orange

        drawFrameGuideDim(settings: settings, width: width, height: height, rect: rect)
        drawInnerFrameGuideGlow(rect: rect, lineWidth: lineWidth, glow: glow, color: color)
        drawInnerFrameGuideBorder(rect: rect, lineWidth: lineWidth, color: color)
    }

    private func drawInnerFrameGuideBorder(rect: CGRect, lineWidth: CGFloat, color: NSColor) {
        guard lineWidth > 0, rect.width > lineWidth * 2, rect.height > lineWidth * 2 else { return }
        let innerRect = rect.insetBy(dx: lineWidth, dy: lineWidth)
        let innerCorner = max(0, lineWidth)
        let outerPath = NSBezierPath(rect: rect)
        let borderPath = NSBezierPath()
        borderPath.append(outerPath)
        borderPath.append(NSBezierPath(roundedRect: innerRect, xRadius: innerCorner, yRadius: innerCorner))
        borderPath.windingRule = .evenOdd
        color.setFill()
        borderPath.fill()
    }

    private func drawInnerFrameGuideGlow(rect: CGRect, lineWidth: CGFloat, glow: CGFloat, color: NSColor) {
        guard glow > 0, rect.width > 2, rect.height > 2 else { return }
        let startInset = max(0, lineWidth)
        let maxDepth = max(0, min(glow, min(rect.width, rect.height) / 2 - startInset - 1))
        guard maxDepth > 0 else { return }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawSmoothEdgeGlow(context: context, rect: rect, lineWidth: startInset, glowDepth: maxDepth, color: color)
    }

    private func drawSmoothEdgeGlow(context: CGContext, rect: CGRect, lineWidth: CGFloat, glowDepth: CGFloat, color: NSColor) {
        guard let maskImage = cachedFrameGlowMask(rect: rect, lineWidth: lineWidth, glowDepth: glowDepth) else { return }
        let deviceColor = color.usingColorSpace(.deviceRGB) ?? color
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.clip(to: rect, mask: maskImage)
        context.setFillColor(deviceColor.withAlphaComponent(deviceColor.alphaComponent * 0.82).cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private func cachedFrameGlowMask(rect: CGRect, lineWidth: CGFloat, glowDepth: CGFloat) -> CGImage? {
        let key = FrameGlowMaskCacheKey(
            width: max(1, Int(ceil(rect.width))),
            height: max(1, Int(ceil(rect.height))),
            lineWidth: Int((max(0, lineWidth) * 2).rounded(.toNearestOrAwayFromZero)),
            glowDepth: Int((max(1, glowDepth) * 2).rounded(.toNearestOrAwayFromZero))
        )

        overlayCacheLock.lock()
        if let cached = frameGlowMaskCache[key] {
            overlayCacheLock.unlock()
            return cached
        }
        overlayCacheLock.unlock()

        guard let mask = makeUnifiedFrameGlowMask(rect: rect, lineWidth: lineWidth, glowDepth: glowDepth) else {
            return nil
        }

        overlayCacheLock.lock()
        if frameGlowMaskCache.count > 12 {
            frameGlowMaskCache.removeAll(keepingCapacity: true)
        }
        frameGlowMaskCache[key] = mask
        overlayCacheLock.unlock()
        return mask
    }

    private func makeUnifiedFrameGlowMask(rect: CGRect, lineWidth: CGFloat, glowDepth: CGFloat) -> CGImage? {
        let width = max(1, Int(ceil(rect.width)))
        let height = max(1, Int(ceil(rect.height)))
        let bytesPerRow = width
        var alpha = [UInt8](repeating: 0, count: bytesPerRow * height)

        func smoothstep(_ value: CGFloat) -> CGFloat {
            let x = max(0, min(1, value))
            return x * x * (3 - 2 * x)
        }

        func softMinimumDistanceToFrameGuideEdge(_ distances: [CGFloat], softness: CGFloat) -> CGFloat {
            guard let smallest = distances.min() else { return 0 }
            let safeSoftness = max(0.001, softness)
            let weightedSum = distances.reduce(CGFloat(0)) { partial, distance in
                partial + CGFloat(exp(-Double((distance - smallest) / safeSoftness)))
            }
            return max(0, smallest - safeSoftness * CGFloat(log(Double(max(0.000_001, weightedSum)))))
        }

        func distanceToFrameGuideEdge(x: CGFloat, y: CGFloat) -> CGFloat {
            softMinimumDistanceToFrameGuideEdge(
                [
                    x,
                    y,
                    CGFloat(width) - x,
                    CGFloat(height) - y
                ],
                softness: max(4, glowDepth * 0.18)
            )
        }

        let safeGlowDepth = max(1, glowDepth)
        for row in 0..<height {
            for column in 0..<width {
                let x = CGFloat(column) + 0.5
                let y = CGFloat(row) + 0.5
                let distanceFromEdge = distanceToFrameGuideEdge(x: x, y: y)
                let distanceInsideGlow = distanceFromEdge - lineWidth
                let normalized = 1 - (max(0, distanceInsideGlow) / safeGlowDepth)
                let glowAlpha = distanceInsideGlow <= safeGlowDepth ? smoothstep(normalized) : 0
                alpha[row * bytesPerRow + column] = UInt8(max(0, min(255, round(glowAlpha * 255))))
            }
        }

        guard let provider = CGDataProvider(data: Data(alpha) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func shortsGuideRect(width: Int, height: Int) -> CGRect {
        let canvasWidth = CGFloat(max(1, width))
        let canvasHeight = CGFloat(max(1, height))
        let guideWidth = min(canvasWidth, canvasHeight * 9.0 / 16.0)
        let guideHeight = min(canvasHeight, guideWidth * 16.0 / 9.0)
        return CGRect(
            x: (canvasWidth - guideWidth) / 2.0,
            y: (canvasHeight - guideHeight) / 2.0,
            width: guideWidth,
            height: guideHeight
        )
    }

    private func drawFrameGuideDim(settings: ShortsBackgroundSettings, width: Int, height: Int, rect: CGRect) {
        guard settings.frameGuideOpacity > 0 else { return }

        let fullRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let dimPath = NSBezierPath(rect: fullRect)
        dimPath.append(NSBezierPath(rect: rect))
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(CGFloat(settings.frameGuideOpacity)).setFill()
        dimPath.fill()
    }

    private func drawSubtitles(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) {
        guard let cue = activeSubtitle(renderPlan: renderPlan, timeSec: timeSec) else { return }
        let captionRect = shortsGuideRect(width: width, height: height)
        drawCaption(
            transform(cue.text, style: renderPlan.captionStyle),
            style: renderPlan.captionStyle,
            bottom: renderPlan.subtitleBottomMargin * (Double(height) / 1920.0),
            layoutRect: captionRect,
            canvasHeight: CGFloat(height),
            fontSizeFactor: 1.0
        )
    }

    private func drawTextTracks(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) {
        let scale = Double(height) / 1920.0
        let blocks = activeTextBlocks(renderPlan: renderPlan, timeSec: timeSec)
        let captionRect = shortsGuideRect(width: width, height: height)
        for block in blocks {
            let style = block.style ?? defaultTextTrackStyle(trackIndex: block.trackIndex, baseStyle: renderPlan.captionStyle)
            let bottomMargin = textTrackBottomMargin(
                trackIndex: block.trackIndex,
                style: style,
                scale: scale
            )
            drawCaption(
                transform(block.text, style: style),
                style: style,
                bottom: bottomMargin,
                layoutRect: captionRect,
                canvasHeight: CGFloat(height),
                fontSizeFactor: 0.82
            )
        }
    }

    private func textTrackBottomMargin(trackIndex: Int, style: ShortsSubtitleStyle, scale: Double) -> Double {
        (style.subtitleBottomMargin ?? defaultTextTrackBottomMargin(trackIndex: trackIndex)) * scale
    }

    private func defaultTextTrackStyle(trackIndex: Int, baseStyle: ShortsSubtitleStyle) -> ShortsSubtitleStyle {
        var style = baseStyle
        style.subtitleBottomMargin = defaultTextTrackBottomMargin(trackIndex: trackIndex)
        return style
    }

    private func defaultTextTrackBottomMargin(trackIndex: Int) -> Double {
        min(1780, 700.0 + Double(trackIndex) * 140.0)
    }

    private func drawCaption(_ text: String, style: ShortsSubtitleStyle, bottom: Double, layoutRect: CGRect, canvasHeight: CGFloat, fontSizeFactor: Double) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let renderScale = canvasHeight / 1920.0
        let fontSize = CGFloat(style.fontSize) * renderScale * CGFloat(fontSizeFactor)
        let boxWidth = layoutRect.width * CGFloat(min(max(style.boxWidth, 10), 100) / 100.0)
        let paddingY = max(1, fontSize * 0.12 * CGFloat(style.boxHeight))
        let paddingX = max(1, paddingY * 1.45)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = CGFloat((style.lineSpacing - 1.0) * Double(fontSize))
        let font = resolvedCaptionFont(family: style.fontFamily, size: fontSize, bold: style.bold)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: cgColor(style.textColor)) ?? .white,
            .paragraphStyle: paragraph,
            .kern: style.letterSpacing * Double(renderScale) * fontSizeFactor
        ]
        let attributed = NSAttributedString(string: text, attributes: baseAttrs)
        let textMaxWidth = max(1, boxWidth - paddingX * 2)
        let measured = attributed.boundingRect(
            with: CGSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textHeight = max(fontSize, ceil(measured.height))
        let boxHeight = max(fontSize + paddingY * 2, textHeight + paddingY * 2)
        let rect = CGRect(
            x: layoutRect.minX + ((layoutRect.width - boxWidth) / 2),
            y: layoutRect.maxY - CGFloat(bottom) - boxHeight,
            width: boxWidth,
            height: boxHeight
        )

        let bgColor = NSColor(cgColor: cgColor(style.boxColor, alpha: style.boxOpacity)) ?? .orange
        let corner = smoothCaptionCornerRadius(edgeSoftness: style.edgeSoftness, boxHeight: boxHeight, renderScale: renderScale)
        let clipPath = NSBezierPath(rect: layoutRect)
        NSGraphicsContext.saveGraphicsState()
        clipPath.setClip()
        if style.edgeBlur > 0 {
            drawNativeEdgeBlurredBackground(
                rect: rect,
                cornerRadius: corner,
                color: bgColor,
                blur: CGFloat(style.edgeBlur) * renderScale * CGFloat(fontSizeFactor),
                clipRect: layoutRect
            )
        } else {
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
            bgColor.setFill()
            bgPath.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let textRect = CGRect(
            x: rect.minX + paddingX,
            y: rect.minY + max(0, (boxHeight - textHeight) / 2),
            width: textMaxWidth,
            height: textHeight + 2
        )
        let drawOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(cgColor: cgColor(style.shadowColor ?? "#000000", alpha: style.shadowOpacity ?? 0.72)) ?? .black
        shadow.shadowBlurRadius = CGFloat(style.shadowBlur ?? 3) * renderScale * CGFloat(fontSizeFactor)
        let distance = CGFloat(style.shadowDistance ?? style.shadow) * renderScale * CGFloat(fontSizeFactor)
        let shadowAngle = CGFloat((style.shadowAngle ?? 90.0) * .pi / 180.0)
        shadow.shadowOffset = CGSize(width: cos(shadowAngle) * distance, height: sin(shadowAngle) * distance)
        var shadowAttrs = baseAttrs
        shadowAttrs[.shadow] = shadow
        NSAttributedString(string: text, attributes: shadowAttrs).draw(with: textRect, options: drawOptions)

        let outlineWidth = CGFloat(max(0, style.outline)) * renderScale * CGFloat(fontSizeFactor)
        if outlineWidth > 0 {
            var outlineAttrs = baseAttrs
            outlineAttrs[.strokeColor] = NSColor(cgColor: cgColor(style.outlineColor ?? "#000000", alpha: style.outlineOpacity ?? 0.58)) ?? .black
            outlineAttrs[.strokeWidth] = -max(0.1, (outlineWidth / max(1, fontSize)) * 100.0)
            NSAttributedString(string: text, attributes: outlineAttrs).draw(with: textRect, options: drawOptions)
        } else {
            attributed.draw(with: textRect, options: drawOptions)
        }
    }

    private func smoothCaptionCornerRadius(edgeSoftness: Double, boxHeight: CGFloat, renderScale: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, CGFloat(edgeSoftness)))
        _ = renderScale
        return min(boxHeight / 2, max(0, boxHeight / 2 * clamped))
    }

    private func drawNativeEdgeBlurredBackground(rect: CGRect, cornerRadius: CGFloat, color: NSColor, blur: CGFloat, clipRect: CGRect) {
        guard blur > 0, rect.width > 0, rect.height > 0 else { return }
        let blurPadding = max(2, ceil(blur * 3.0))
        let drawRect = rect.insetBy(dx: -blurPadding, dy: -blurPadding)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clipRect).setClip()

        if let image = makeBlurredRoundedRectImage(
            size: rect.size,
            cornerRadius: cornerRadius,
            color: color,
            blur: blur
        ) {
            drawImageUpright(image, in: drawRect, fraction: 1)
        } else {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func makeBlurredRoundedRectImage(size: CGSize, cornerRadius: CGFloat, color: NSColor, blur: CGFloat) -> NSImage? {
        let blurPadding = max(2, ceil(blur * 3.0))
        let canvasWidth = max(1, Int(ceil(size.width + blurPadding * 2)))
        let canvasHeight = max(1, Int(ceil(size.height + blurPadding * 2)))
        let key = captionBackgroundCacheKey(
            width: canvasWidth,
            height: canvasHeight,
            cornerRadius: cornerRadius,
            blur: blur,
            color: color
        )

        overlayCacheLock.lock()
        if let cached = captionBackgroundImageCache[key] {
            overlayCacheLock.unlock()
            return cached
        }
        overlayCacheLock.unlock()

        guard let rgbColor = color.usingColorSpace(.sRGB),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let bytesPerRow = canvasWidth * 4
        let byteCount = bytesPerRow * canvasHeight
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        var basePixels = Data(count: byteCount)

        let boxRect = CGRect(x: blurPadding, y: blurPadding, width: size.width, height: size.height)
        let blurPath = CGPath(
            roundedRect: boxRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let drewMask = basePixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let baseContext = CGContext(
                    data: baseAddress,
                    width: canvasWidth,
                    height: canvasHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                  )
            else { return false }
            baseContext.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
            baseContext.setFillColor(rgbColor.cgColor)
            baseContext.addPath(blurPath)
            baseContext.fillPath()
            return true
        }
        guard drewMask else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: canvasWidth,
            height: canvasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let sourceTexture = device.makeTexture(descriptor: descriptor),
              let destinationTexture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return nil }

        basePixels.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            sourceTexture.replace(
                region: MTLRegionMake2D(0, 0, canvasWidth, canvasHeight),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }

        let blurKernel = MPSImageGaussianBlur(device: device, sigma: Float(max(0.1, blur)))
        blurKernel.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: destinationTexture)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status != .error else { return nil }

        var blurredPixels = Data(count: byteCount)
        blurredPixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            destinationTexture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, canvasWidth, canvasHeight),
                mipmapLevel: 0
            )
        }

        guard let provider = CGDataProvider(data: blurredPixels as CFData),
              let finalImage = CGImage(
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }

        let image = NSImage(cgImage: finalImage, size: CGSize(width: canvasWidth, height: canvasHeight))

        overlayCacheLock.lock()
        if captionBackgroundImageCache.count > 64 {
            captionBackgroundImageCache.removeAll(keepingCapacity: true)
        }
        captionBackgroundImageCache[key] = image
        overlayCacheLock.unlock()
        return image
    }

    private func captionBackgroundCacheKey(
        width: Int,
        height: Int,
        cornerRadius: CGFloat,
        blur: CGFloat,
        color: NSColor
    ) -> CaptionBackgroundCacheKey {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        func component(_ value: CGFloat) -> Int {
            max(0, min(255, Int((value * 255).rounded())))
        }
        return CaptionBackgroundCacheKey(
            width: width,
            height: height,
            cornerRadius: max(0, Int((cornerRadius * 10).rounded())),
            blurRadius: max(0, Int((blur * 10).rounded())),
            red: component(rgbColor.redComponent),
            green: component(rgbColor.greenComponent),
            blue: component(rgbColor.blueComponent),
            alpha: component(rgbColor.alphaComponent)
        )
    }

    private func resolvedCaptionFont(family: String, size: CGFloat, bold: Bool) -> NSFont {
        ensureVisualEditorFontsRegistered()

        if let font = NativeFontRegistry.resolvedFont(family: family, size: size, bold: bold) {
            return font
        }

        for name in candidateFontNames(for: family) {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        let descriptor = NSFontDescriptor().withFamily(family)
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }

        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private func ensureVisualEditorFontsRegistered() {
        overlayCacheLock.lock()
        defer { overlayCacheLock.unlock() }
        guard !visualEditorFontsRegistered else { return }
        NativeFontRegistry.registerVisualEditorFonts()
        visualEditorFontsRegistered = true
    }

    private func candidateFontNames(for family: String) -> [String] {
        switch family.lowercased() {
        case "oswald":
            return ["Oswald", "Oswald-Regular", "Oswald-Medium", "Oswald-SemiBold", "Oswald-Bold"]
        case "cuprum":
            return ["Cuprum", "Cuprum-Regular", "Cuprum-SemiBold", "Cuprum-Bold"]
        case "unbounded":
            return ["Unbounded", "Unbounded-Regular", "Unbounded-SemiBold", "Unbounded-Bold"]
        case "montserrat":
            return ["Montserrat", "Montserrat-Regular", "Montserrat-SemiBold", "Montserrat-Bold"]
        case "inter":
            return ["Inter", "Inter-Regular", "Inter-SemiBold", "Inter-Bold"]
        case "arial":
            return ["Arial", "ArialMT", "Arial-BoldMT"]
        default:
            return [family, "\(family)-Regular", "\(family)-SemiBold", "\(family)-Bold"]
        }
    }

    private func drawLogo(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) {
        guard let logo = renderPlan.logo, logo.hidden != true, let image = cachedImage(from: logo.src) else { return }
        let introDuration = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.duration ?? 0
        let outroDuration = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.duration ?? 0
        let activeVideoEnd = max(introDuration, renderPlan.durationSec - outroDuration)
        guard timeSec >= introDuration, timeSec <= activeVideoEnd else { return }
        let logoRect = shortsGuideRect(width: width, height: height)
        let scale = logoRect.height / 1920.0
        let size = min(
            max(46 * scale, 120 * scale * CGFloat(logo.size)),
            min(logoRect.width, logoRect.height) * 0.35
        )
        let margin = max(16 * scale, 40 * scale)
        let position = logo.position ?? "top-left"
        let x = position.hasSuffix("right") ? logoRect.maxX - margin - size : logoRect.minX + margin
        let y = position.hasPrefix("top") ? logoRect.minY + margin : logoRect.maxY - margin - size
        drawImageUpright(image, in: CGRect(x: x, y: y, width: size, height: size), fraction: CGFloat(logo.opacity))
    }

    private func drawIntroOutro(renderPlan: NativeShortsRenderPlan, timeSec: Double, width: Int, height: Int) {
        if let intro = renderPlan.intro, intro.hidden != true, timeSec >= 0, timeSec <= intro.duration, let image = cachedImage(from: intro.src) {
            drawTimedImage(image, item: intro, elapsed: timeSec, width: width, height: height)
        }
        if let outro = renderPlan.outro, outro.hidden != true {
            let start = max(0, renderPlan.durationSec - outro.duration)
            if timeSec >= start, timeSec <= renderPlan.durationSec, let image = cachedImage(from: outro.src) {
                drawTimedImage(image, item: outro, elapsed: timeSec - start, width: width, height: height)
            }
        }
    }

    private func cachedImage(from source: String) -> NSImage? {
        guard !source.isEmpty else { return nil }
        let key = imageCacheKey(for: source)

        overlayCacheLock.lock()
        if let cached = decodedImageCache[key] {
            overlayCacheLock.unlock()
            return cached
        }
        overlayCacheLock.unlock()

        guard let decoded = image(from: source) else { return nil }

        overlayCacheLock.lock()
        if decodedImageCache.count > 24 {
            decodedImageCache.removeAll(keepingCapacity: true)
        }
        decodedImageCache[key] = decoded
        overlayCacheLock.unlock()
        return decoded
    }

    private func imageCacheKey(for source: String) -> String {
        guard source.hasPrefix("data:") else { return source }
        return "data:\(source.count):\(source.prefix(96)):\(source.suffix(96))"
    }

    private func drawTimedImage(_ image: NSImage, item: IntroOutroOverlaySettings, elapsed: Double, width: Int, height: Int) {
        let scale = CGFloat(height) / 1920.0
        let fade = min(0.5, item.duration * 0.15)
        let fadeIn = fade > 0 ? min(1, max(0, elapsed / fade)) : 1
        let fadeOut = fade > 0 ? min(1, max(0, (item.duration - elapsed) / fade)) : 1
        let speed = item.speed ?? 1
        let pulse = item.animation == "pulse" ? 1 + (0.06 * sin(elapsed * speed * 4.18)) : 1
        let bounce = item.animation == "bounce" ? bounceOffset(elapsed: elapsed, speed: speed, scale: scale) : 0
        let itemWidth = max(70, 300 * scale * CGFloat(item.scale) * CGFloat(pulse))
        let rect = CGRect(
            x: CGFloat(width) * CGFloat(item.x / 100) - itemWidth / 2,
            y: CGFloat(height) * CGFloat(item.y / 100) - itemWidth / 2 + bounce,
            width: itemWidth,
            height: itemWidth
        )
        drawImageUpright(image, in: rect, fraction: CGFloat(min(fadeIn, fadeOut)))
    }

    private func bounceOffset(elapsed: Double, speed: Double, scale: CGFloat) -> CGFloat {
        let period = 1.2
        let progress = ((elapsed * speed).truncatingRemainder(dividingBy: period)) / period
        if progress < 0.4 {
            return CGFloat(15 * sin((progress / 0.4) * Double.pi)) * scale
        }
        if progress < 0.7 {
            return CGFloat(-4 * sin(((progress - 0.4) / 0.3) * Double.pi)) * scale
        }
        if progress < 0.9 {
            return CGFloat(4 * sin(((progress - 0.7) / 0.2) * Double.pi)) * scale
        }
        return 0
    }

    private func drawImageUpright(_ image: NSImage, in rect: CGRect, fraction: CGFloat) {
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: fraction,
            respectFlipped: true,
            hints: nil
        )
    }

    private func activeSubtitle(renderPlan: NativeShortsRenderPlan, timeSec: Double) -> NativeRenderSubtitleCue? {
        renderPlan.subtitles.first { timeSec >= $0.startSec && timeSec < $0.endSec }
    }

    private func activeTextBlocks(renderPlan: NativeShortsRenderPlan, timeSec: Double) -> [(text: String, trackIndex: Int, style: ShortsSubtitleStyle?)] {
        renderPlan.textTracks.enumerated().flatMap { index, track in
            guard track.hidden != true, track.muted != true else { return [(text: String, trackIndex: Int, style: ShortsSubtitleStyle?)]() }
            return track.blocks.compactMap { block in
                guard block.hidden != true,
                      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      timeSec >= block.startSec,
                      timeSec < block.endSec
                else { return nil }
                return (block.text, index, track.style)
            }
        }
    }
}

private func transform(_ text: String, style: ShortsSubtitleStyle) -> String {
    switch style.textTransform {
    case .none:
        return text
    case .uppercase:
        return text.uppercased()
    case .title:
        return text.capitalized
    }
}

private func image(from source: String) -> NSImage? {
    if source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") {
        let metadata = String(source[..<comma])
        let payload = String(source[source.index(after: comma)...])
        guard metadata.contains(";base64"), let data = Data(base64Encoded: payload) else { return nil }
        return NSImage(data: data)
    }
    if source.hasPrefix("file://"), let url = URL(string: source) {
        return NSImage(contentsOf: url)
    }
    return NSImage(contentsOfFile: source)
}

private func rgba(_ hex: String, alpha: Double = 1) -> SIMD4<Float> {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let scanner = Scanner(string: cleaned)
    var value: UInt64 = 0
    scanner.scanHexInt64(&value)
    return SIMD4<Float>(
        Float((value >> 16) & 0xFF) / 255,
        Float((value >> 8) & 0xFF) / 255,
        Float(value & 0xFF) / 255,
        Float(max(0, min(1, alpha)))
    )
}

private func cgColor(_ hex: String, alpha: Double = 1) -> CGColor {
    let color = rgba(hex, alpha: alpha)
    return NSColor(
        red: CGFloat(color.x),
        green: CGFloat(color.y),
        blue: CGFloat(color.z),
        alpha: CGFloat(color.w)
    ).cgColor
}

private func effectScale(_ settings: ShortsBackgroundSettings, renderHeight: Int) -> Double {
    Double(renderHeight) / max(1, settings.effectReferenceHeight ?? 960)
}

private func featherStrength(_ value: Double?) -> Double {
    max(0, min(1, (value ?? 100) / 100))
}

private func foregroundOpacity(renderPlan: NativeShortsRenderPlan, timeSec: Double) -> Double {
    let introDuration = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.duration ?? 0
    let outroDuration = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.duration ?? 0
    let activeStart = introDuration
    let activeEnd = max(activeStart, renderPlan.durationSec - outroDuration)
    guard timeSec >= activeStart, timeSec <= activeEnd else { return 0 }

    var opacity = 1.0
    let introTransition = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.transitionSec ?? 1.0
    if introDuration > 0, introTransition > 0, timeSec <= activeStart + introTransition {
        opacity = min(opacity, (timeSec - activeStart) / introTransition)
    }

    let outroTransition = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.transitionSec ?? 1.0
    if outroDuration > 0, outroTransition > 0, timeSec >= activeEnd - outroTransition {
        opacity = min(opacity, (activeEnd - timeSec) / outroTransition)
    }

    return max(0, min(1, opacity))
}
