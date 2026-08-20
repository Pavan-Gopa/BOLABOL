import Foundation
import Testing
@testable import VaniScriptCore

@Suite("App Store native compliance")
struct AppStoreNativeComplianceTests {
    @Test("declares only native runtime families")
    func nativeRuntimeFamilies() {
        #expect(AppStoreNativeCompliance.allowedRuntimeFamilies == [
            "Swift",
            "SwiftUI",
            "AppKit",
            "AVFoundation",
            "Core ML",
            "Metal",
            "MLX Swift",
        ])
    }

    @Test("forbids non native bundled runtimes")
    func forbidsNonNativeBundledRuntimes() {
        #expect(AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("python"))
        #expect(AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("node"))
        #expect(AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("electron"))
        #expect(AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("chromium"))
        #expect(!AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("ffmpeg"))
        #expect(!AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("yt-dlp"))
        #expect(AppStoreNativeCompliance.forbiddenBundleNameFragments.contains("llama"))
    }

    @Test("accepts Swift package and model asset names")
    func acceptsNativeAssets() {
        #expect(AppStoreNativeCompliance.isAllowedBundlePath("Contents/MacOS/VaniScript"))
        #expect(AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/Models/WhisperKit/model.mlmodelc"))
        #expect(AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/Models/MLX/tokenizer.json"))
    }

    @Test("rejects forbidden bundle paths")
    func rejectsForbiddenBundlePaths() {
        #expect(!AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/python/bin/python3"))
        #expect(!AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/node_modules/electron/index.js"))
        #expect(AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/bin/ffmpeg"))
        #expect(AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/bin/yt-dlp"))
        #expect(!AppStoreNativeCompliance.isAllowedBundlePath("Contents/Resources/llamacpp/libllama.dylib"))
    }

    @Test("visual clip editor avoids crashing SwiftUI VideoPlayer bridge")
    func visualClipEditorAvoidsSwiftUIVideoPlayerBridge() throws {
        let source = try String(
            contentsOfFile: "Sources/VaniScript/Views/ExportWorkspaceView.swift",
            encoding: .utf8
        )

        #expect(!source.contains("VideoPlayer("))
        #expect(source.contains("AVPlayerView"))
    }

    @Test("visual clip editor is a full workspace route, not an export modal sheet")
    func visualClipEditorIsFullWorkspaceRoute() throws {
        let exportSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/ExportWorkspaceView.swift",
            encoding: .utf8
        )
        let routerSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/DetailRouterView.swift",
            encoding: .utf8
        )
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )

        #expect(!exportSource.contains("@State private var visualEditorDraft"))
        #expect(!exportSource.contains(".sheet(item: $visualEditorDraft)"))
        #expect(routerSource.contains("case .visualEditor:"))
        #expect(editorSource.contains("struct ClipVisualEditorWorkspace"))
    }

    @Test("native Shorts export page keeps Universal layout controls aligned")
    func nativeShortsExportPageKeepsUniversalLayoutControlsAligned() throws {
        let exportSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/ExportWorkspaceView.swift",
            encoding: .utf8
        )

        #expect(exportSource.contains("private var exportControlColumns: [GridItem]"))
        #expect(exportSource.contains("private var clipCardColumns: [GridItem]"))
        #expect(exportSource.contains("private func exportFooterActions()"))
        #expect(exportSource.contains("store.presentProjectSidebar()"))
        #expect(exportSource.contains("store.newSession()"))
        #expect(exportSource.contains("Menu {"))
        #expect(exportSource.contains("Image(systemName: \"chevron.down\")"))
        #expect(exportSource.contains(".frame(maxWidth: .infinity, minHeight: 32"))
        #expect(exportSource.contains("private struct ExportActionButton"))
        #expect(exportSource.contains(".frame(maxWidth: .infinity, minHeight: 36, alignment: .center)"))
        #expect(exportSource.contains(".multilineTextAlignment(.center)"))
        #expect(exportSource.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        #expect(!exportSource.contains("GridItem(.adaptive(minimum: 420, maximum: 520)"))
    }

    @Test("native onboarding copy does not mention web renderers")
    func nativeOnboardingCopyDoesNotMentionWebRenderers() throws {
        let onboardingSource = try String(
            contentsOfFile: "Sources/VaniScript/Models/OnboardingTourState.swift",
            encoding: .utf8
        )

        for forbiddenTerm in ["HyperFrames", "Electron", "Chromium", "Node.js", "node_modules"] {
            #expect(!onboardingSource.localizedCaseInsensitiveContains(forbiddenTerm), "Forbidden onboarding term: \(forbiddenTerm)")
        }
        #expect(onboardingSource.contains("native AVFoundation/Metal render pipeline"))
        #expect(onboardingSource.contains("нативным AVFoundation/Metal-рендерером"))

        let requiredExportTargets = [
            "export-documents",
            "shorts-find-moments",
            "shorts-choose-clips",
            "shorts-edit-clip",
            "shorts-export-settings",
            "shorts-export-actions",
            "export-footer-actions",
        ]
        for target in requiredExportTargets {
            #expect(onboardingSource.contains("targetSelector: \"\(target)\""), "Missing export onboarding step: \(target)")
        }
        #expect(onboardingSource.contains("Visual Editor"))
        #expect(onboardingSource.contains("визуальный редактор"))
    }

    @Test("opening a project directly to export avoids synchronous whole-project glossary rewrite")
    func exportProjectOpenAvoidsWholeProjectGlossaryRewrite() throws {
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(storeSource.contains("if openExport {"))
        #expect(storeSource.contains("workflow.screen = .export"))
        #expect(storeSource.contains("} else {\n            workflow.screen = .review"))
        #expect(!storeSource.contains("let replacements = applyGlossaryEntriesToWorkflow(workflow.settings.glossary, currentChunkOnly: false)\n        statusMessage = \"Project opened: \\(openedSession.sourceFileName)\""))
    }

    @Test("native shorts renderer uses an explicit Metal video compositor")
    func nativeShortsRendererUsesExplicitMetalVideoCompositor() throws {
        let rendererSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeShortsVideoRenderer.swift",
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(rendererSource.contains("customVideoCompositorClass = NativeMetalVideoCompositor.self"))
        #expect(compositorSource.contains("AVVideoCompositing"))
        #expect(compositorSource.contains("MTLCreateSystemDefaultDevice"))
        #expect(compositorSource.contains("makeCommandQueue"))
        #expect(compositorSource.contains("CVMetalTextureCacheCreate"))
        #expect(!compositorSource.contains("radians("))
        #expect(rendererSource.contains("compositionTrack: compositionVideoTrack"))
        #expect(!rendererSource.contains("sourceTrack: sourceVideoTrack,\n            composition: composition"))
    }

    @Test("native Metal compositor matches visual editor preview orientation and stage geometry")
    func nativeMetalCompositorMatchesVisualEditorPreviewOrientationAndStageGeometry() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("NSGraphicsContext(cgContext: context, flipped: true)"))
        #expect(compositorSource.contains("drawImageUpright"))
        #expect(compositorSource.contains("respectFlipped: true"))
        #expect(compositorSource.contains("previewStageSize"))
        #expect(compositorSource.contains("previewStagePixel"))
        #expect(compositorSource.contains("previewPlacedUV"))
        #expect(compositorSource.contains("foregroundOpacity"))
        #expect(compositorSource.contains("sourceSize.width"))
        #expect(compositorSource.contains("sourceSize.height"))
        #expect(compositorSource.contains("featherTopStrength"))
        #expect(compositorSource.contains("featherBottomStrength"))
        #expect(compositorSource.contains("shortsGuideRect(width: width, height: height)"))
        #expect(compositorSource.contains("drawFrameGuideDim(settings: settings, width: width, height: height, rect: rect)"))
        #expect(compositorSource.contains("let frameGuideScale = CGFloat(effectScale(settings, renderHeight: height))"))
        #expect(compositorSource.contains("let lineWidth = max(0, CGFloat(settings.frameGuideBorderWidth) * frameGuideScale)"))
        #expect(compositorSource.contains("let glow = max(0, CGFloat(settings.frameGuideBlur) * frameGuideScale * 2.25)"))
        #expect(compositorSource.contains("featherLeft"))
        #expect(compositorSource.contains("featherRight"))
        #expect(compositorSource.contains("style.edgeBlur"))
        #expect(compositorSource.contains("smoothCaptionCornerRadius(edgeSoftness: style.edgeSoftness"))
        #expect(compositorSource.contains("boundingRect"))
        #expect(compositorSource.contains("outlineAttrs[.strokeColor]"))
        #expect(compositorSource.contains("outlineAttrs[.strokeWidth]"))
        #expect(!compositorSource.contains("outlineSteps = 16"))
        #expect(!compositorSource.contains("float baseScale = max(outputSize.x / sourceSize.x, outputSize.y / sourceSize.y)"))
        #expect(!compositorSource.contains("(outputSize.y - scaled.y) * 0.5 - outputSize.y * (panY / 100.0)"))
    }

    @Test("visual editor render preview uses source aspect canvas with centered shorts guide")
    func visualEditorRenderPreviewUsesSourceAspectCanvasWithShortsGuide() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("editorPreviewAspectRatio"))
        #expect(editorSource.contains("let maxPreviewWidth = max(1, geometry.size.width)"))
        #expect(editorSource.contains("let frameWidth = min(maxPreviewWidth, maxPreviewHeight * previewAspect)"))
        #expect(editorSource.contains("let frameHeight = frameWidth / previewAspect"))
        #expect(!editorSource.contains("let frameWidth = frameHeight * 9 / 16"))

        #expect(compositorSource.contains("private func shortsGuideRect(width: Int, height: Int) -> CGRect"))
        #expect(compositorSource.contains("let guideWidth = min(canvasWidth, canvasHeight * 9.0 / 16.0)"))
        #expect(compositorSource.contains("NSBezierPath(rect: fullRect)"))
        #expect(compositorSource.contains("dimPath.append(NSBezierPath(rect: rect))"))
        #expect(compositorSource.contains("NSColor.black.withAlphaComponent(CGFloat(settings.frameGuideOpacity))"))
    }

    @Test("native captions are constrained to the centered shorts guide")
    func nativeCaptionsAreConstrainedToCenteredShortsGuide() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("let captionRect = shortsGuideRect(width: width, height: height)"))
        #expect(compositorSource.contains("layoutRect: captionRect"))
        #expect(compositorSource.contains("let boxWidth = layoutRect.width * CGFloat(min(max(style.boxWidth, 10), 100) / 100.0)"))
        #expect(compositorSource.contains("x: layoutRect.minX + ((layoutRect.width - boxWidth) / 2)"))
        #expect(compositorSource.contains("y: layoutRect.maxY - CGFloat(bottom) - boxHeight"))
        #expect(!compositorSource.contains("let boxWidth = width * CGFloat(min(max(style.boxWidth, 10), 100) / 100.0)"))
        #expect(!compositorSource.contains("let rect = CGRect(x: (width - boxWidth) / 2"))

        #expect(editorSource.contains("private func shortsGuideSize(frameWidth: CGFloat, frameHeight: CGFloat) -> CGSize"))
        #expect(editorSource.contains("captionOverlayText(caption, style: style, fontFactor: 1, viewportWidth: guideSize.width, viewportHeight: guideSize.height)"))
        #expect(editorSource.contains("captionOverlayText(block.text, style: blockStyle, fontFactor: 0.82, viewportWidth: guideSize.width, viewportHeight: guideSize.height)"))
    }

    @Test("native caption backgrounds do not add a dark underlay and resolve selected fonts")
    func nativeCaptionBackgroundsDoNotAddDarkUnderlayAndResolveSelectedFonts() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("drawNativeEdgeBlurredBackground("))
        #expect(compositorSource.contains("rect: rect"))
        #expect(compositorSource.contains("cornerRadius: corner"))
        #expect(compositorSource.contains("color: bgColor"))
        #expect(compositorSource.contains("clipRect: layoutRect"))
        #expect(compositorSource.contains("makeBlurredRoundedRectImage("))
        #expect(compositorSource.contains("MPSImageGaussianBlur(device: device"))
        #expect(compositorSource.contains("sourceTexture.replace("))
        #expect(compositorSource.contains("destinationTexture.getBytes("))
        #expect(compositorSource.contains("smoothCaptionCornerRadius("))
        #expect(compositorSource.contains("return min(boxHeight / 2, max(0, boxHeight / 2 * clamped))"))
        #expect(compositorSource.contains("let blurPadding = max(2, ceil(blur * 3.0))"))
        #expect(compositorSource.contains("let blurPath = CGPath("))
        #expect(compositorSource.contains("baseContext.addPath(blurPath)"))
        #expect(compositorSource.contains("drawImageUpright(image, in: drawRect, fraction: 1)"))
        #expect(!compositorSource.contains("CIFilter"))
        #expect(!compositorSource.contains("CIContext"))
        #expect(!compositorSource.contains("import CoreImage"))
        #expect(!compositorSource.contains("style.edgeSoftness >= 0.95"))
        #expect(!compositorSource.contains("style.edgeSoftness * 80.0"))
        #expect(!compositorSource.contains("pow(clamped"))
        #expect(!compositorSource.contains("let coreInset"))
        #expect(!compositorSource.contains("let corePath"))
        #expect(!compositorSource.contains("let basePath = CGPath("))
        #expect(!compositorSource.contains("finalContext.addPath(basePath)"))
        #expect(!compositorSource.contains("let falloffSteps = max(48, min(128"))
        #expect(!compositorSource.contains("for step in 0..<falloffSteps"))
        #expect(!compositorSource.contains("color.withAlphaComponent(layerAlpha).setFill()"))
        #expect(!compositorSource.contains("edgeShadow.shadowColor = color"))
        #expect(!compositorSource.contains("edgeShadow.shadowBlurRadius = blur"))
        #expect(!compositorSource.contains("let coreInset = max(0, min(blur * 0.24"))
        #expect(!compositorSource.contains("let coreRect = rect.insetBy"))
        #expect(!compositorSource.contains("blurShadow.shadowColor = bgColor"))
        #expect(!compositorSource.contains("blurShadow.set()"))
        #expect(!compositorSource.contains("color.withAlphaComponent(0.01).setFill()"))
        #expect(compositorSource.contains("private func resolvedCaptionFont(family: String, size: CGFloat, bold: Bool) -> NSFont"))
        #expect(compositorSource.contains("NativeFontRegistry.registerVisualEditorFonts()"))
        #expect(compositorSource.contains("candidateFontNames(for: family)"))
        #expect(compositorSource.contains("NSFontDescriptor().withFamily(family)"))
    }

    @Test("native visual editor bundles and registers every selectable caption font")
    func nativeVisualEditorBundlesAndRegistersEverySelectableCaptionFont() throws {
        let packageSource = try String(
            contentsOfFile: "Package.swift",
            encoding: .utf8
        )
        let appSource = try String(
            contentsOfFile: "Sources/VaniScript/App/VaniScriptApp.swift",
            encoding: .utf8
        )
        let registrySource = (try? String(
            contentsOfFile: "Sources/VaniScript/Services/NativeFontRegistry.swift",
            encoding: .utf8
        )) ?? ""
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(packageSource.contains("resources: [.copy(\"Resources/Fonts\")]"))
        #expect(appSource.contains("NativeFontRegistry.registerVisualEditorFonts()"))
        #expect(registrySource.contains("CTFontManagerRegisterFontsForURL"))
        #expect(!registrySource.contains("Bundle.module"))
        #expect(registrySource.contains("Bundle.main.url(forResource: name, withExtension: \"ttf\", subdirectory: \"Fonts\")"))
        #expect(editorSource.contains(".font(.custom(resolvedSwiftUIFontName(style.fontFamily, bold: style.bold), size: fontSize).weight(fontWeight))"))
        #expect(compositorSource.contains("NativeFontRegistry.registerVisualEditorFonts()"))

        for font in ["Cuprum", "Oswald", "Unbounded", "Montserrat", "Inter"] {
            #expect(registrySource.contains("\"\(font)\""), "Missing font registration entry: \(font)")
            #expect(FileManager.default.fileExists(atPath: "Sources/VaniScript/Resources/Fonts/\(font).ttf"), "Missing bundled font file: \(font).ttf")
        }
    }

    @Test("native Metal overlays composite premultiplied alpha without darkening translucent colors")
    func nativeMetalOverlaysCompositePremultipliedAlphaWithoutDarkeningTranslucentColors() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("static float4 overPremultiplied(float4 fg, float4 bg)"))
        #expect(compositorSource.contains("return float4(fg.rgb + bg.rgb * (1.0 - fg.a), fg.a + bg.a * (1.0 - fg.a));"))
        #expect(compositorSource.contains("color = overPremultiplied(overlay, color);"))
        #expect(!compositorSource.contains("color = over(overlay, color);"))
    }

    @Test("native frame guide border and glow render inward from the shorts guide edge")
    func nativeFrameGuideBorderAndGlowRenderInwardFromShortsGuideEdge() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("drawInnerFrameGuideGlow(rect: rect, lineWidth: lineWidth, glow: glow, color: color)"))
        #expect(compositorSource.contains("drawInnerFrameGuideBorder(rect: rect, lineWidth: lineWidth, color: color)"))
        #expect(compositorSource.contains("private func drawInnerFrameGuideBorder(rect: CGRect, lineWidth: CGFloat, color: NSColor)"))
        #expect(compositorSource.contains("let outerPath = NSBezierPath(rect: rect)"))
        #expect(compositorSource.contains("borderPath.windingRule = .evenOdd"))
        #expect(compositorSource.contains("private func drawInnerFrameGuideGlow(rect: CGRect, lineWidth: CGFloat, glow: CGFloat, color: NSColor)"))
        #expect(compositorSource.contains("let startInset = max(0, lineWidth)"))
        #expect(compositorSource.contains("makeUnifiedFrameGlowMask"))
        #expect(compositorSource.contains("distanceToFrameGuideEdge"))
        #expect(compositorSource.contains("softMinimumDistanceToFrameGuideEdge"))
        #expect(compositorSource.contains("exp(-"))
        #expect(compositorSource.contains("smoothstep"))
        #expect(compositorSource.contains("context.clip(to: rect, mask: maskImage)"))
        #expect(compositorSource.contains("drawSmoothEdgeGlow"))
        #expect(!compositorSource.contains("min(x, y, CGFloat(width) - x, CGFloat(height) - y)"))
        #expect(!compositorSource.contains("drawSmoothEdgeGlowSide"))
        #expect(!compositorSource.contains("context.drawLinearGradient"))
        #expect(!compositorSource.contains("CIFilter"))
        #expect(!compositorSource.contains("CIContext"))
        #expect(!compositorSource.contains("let steps = max(24, min(96"))
        #expect(!compositorSource.contains("for step in 0..<steps"))
        #expect(!compositorSource.contains("let borderRect = rect.insetBy(dx: inset, dy: inset)"))
        #expect(!compositorSource.contains("glowPath.stroke()"))
        #expect(!compositorSource.contains("borderPath.stroke()"))
    }

    @Test("native Metal overlay renderer caches static overlay work during export")
    func nativeMetalOverlayRendererCachesStaticOverlayWorkDuringExport() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("FrameGlowMaskCacheKey"))
        #expect(compositorSource.contains("private var frameGlowMaskCache"))
        #expect(compositorSource.contains("private var decodedImageCache"))
        #expect(compositorSource.contains("cachedFrameGlowMask("))
        #expect(compositorSource.contains("cachedImage(from:"))
        #expect(compositorSource.contains("ensureVisualEditorFontsRegistered()"))
        #expect(compositorSource.contains("private let overlayCacheLock = NSLock()"))
        #expect(compositorSource.contains("if frameGlowMaskCache.count >"))
        #expect(!compositorSource.contains("guard let maskImage = makeUnifiedFrameGlowMask(rect: rect, lineWidth: lineWidth, glowDepth: glowDepth) else { return }"))
        #expect(!compositorSource.contains("let image = image(from: logo.src)"))
        #expect(!compositorSource.contains("let image = image(from: intro.src)"))
        #expect(!compositorSource.contains("let image = image(from: outro.src)"))
    }

    @Test("native shorts export preserves source resolution and fps for source based output")
    func nativeShortsExportPreservesSourceResolutionAndFPSForSourceBasedOutput() throws {
        let rendererSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeShortsVideoRenderer.swift",
            encoding: .utf8
        )
        let previewSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/NativeMetalClipPreviewView.swift",
            encoding: .utf8
        )

        #expect(rendererSource.contains("if preset.contains(\"4K\")"))
        #expect(rendererSource.contains("if preset.contains(\"2K\")"))
        #expect(rendererSource.contains("if preset.contains(\"Source-based\")"))
        #expect(rendererSource.contains("return CGSize(width: max(1, sourceSize.width.rounded()), height: max(1, sourceSize.height.rounded()))"))
        #expect(rendererSource.contains("return max(1, Int(sourceFPS.rounded()))"))
        #expect(previewSource.contains("let width = max(1, renderPlan.width)"))
        #expect(previewSource.contains("let height = max(1, renderPlan.height)"))
        #expect(!previewSource.contains("window?.backingScaleFactor"))
    }

    @Test("native Metal overlay renderer reuses static overlay pixel buffers per cue")
    func nativeMetalOverlayRendererReusesStaticOverlayPixelBuffersPerCue() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("OverlayPixelBufferCacheKey"))
        #expect(compositorSource.contains("private var overlayPixelBufferCache"))
        #expect(compositorSource.contains("staticOverlayCacheKey("))
        #expect(compositorSource.contains("cachedOverlayPixelBuffer("))
        #expect(compositorSource.contains("renderOverlayPixelBuffer("))
        #expect(compositorSource.contains("activeIntroOutroOverlayIsTimeVarying("))
        #expect(compositorSource.contains("styleSignature("))
        #expect(compositorSource.contains("maxOverlayPixelBufferCacheEntries("))
        #expect(compositorSource.contains("overlayPixelBufferCache.removeAll(keepingCapacity: true)"))
    }

    @Test("visual editor keyframes use background color, not frame guide color")
    func visualEditorKeyframesUseBackgroundColorNotFrameGuideColor() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let exportSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/ExportWorkspaceView.swift",
            encoding: .utf8
        )
        let source = editorSource + "\n" + exportSource

        #expect(source.contains("backgroundColor: backgroundSettings.solidColor"))
        #expect(source.contains("backgroundColor: plan.backgroundSettings?.solidColor"))
        #expect(!source.contains("backgroundColor: plan.backgroundSettings?.frameGuideColor"))
        #expect(!source.contains("backgroundColor: backgroundSettings.frameGuideColor"))
    }

    @Test("native render path covers visual editor settings that affect final video")
    func nativeRenderPathCoversFinalVideoSettings() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )
        let rendererSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeShortsVideoRenderer.swift",
            encoding: .utf8
        )
        let renderPath = compositorSource + "\n" + rendererSource

        let requiredStyleFields = [
            "style.fontFamily", "style.fontSize", "style.bold", "style.textTransform",
            "style.textColor", "style.boxColor", "style.boxOpacity", "style.boxWidth",
            "style.boxHeight", "style.edgeBlur", "style.letterSpacing", "style.lineSpacing",
            "style.edgeSoftness", "style.outline", "style.outlineColor", "style.outlineOpacity",
            "style.shadow", "style.shadowColor", "style.shadowOpacity", "style.shadowBlur",
            "style.shadowDistance", "style.shadowAngle", "subtitleBottomMargin"
        ]
        for field in requiredStyleFields {
            #expect(renderPath.contains(field), "Missing native render style field: \(field)")
        }

        let requiredBackgroundFields = [
            "effectReferenceHeight", "solidEnabled", "solidColor", "blurEnabled", "blurStrength",
            "blurScale", "blurPanX", "gradientEnabled", "gradientType", "gradientColorA",
            "gradientColorB", "gradientAngle", "gradientOpacity", "featherEnabled",
            "featherTop", "featherBottom", "featherLeft", "featherRight", "frameGuideColor",
            "frameGuideBorderWidth", "frameGuideBlur", "frameGuideBorderOpacity",
            "featherTopHeight", "featherBottomHeight"
        ]
        for field in requiredBackgroundFields {
            #expect(renderPath.contains(field), "Missing native render background field: \(field)")
        }

        let requiredFrameAnimationFields = [
            "frameKeyframes", "interpolateFrameState", "frame.zoom", "frame.x",
            "frame.y", "frame.backgroundColor"
        ]
        for field in requiredFrameAnimationFields {
            #expect(renderPath.contains(field), "Missing native render frame animation field: \(field)")
        }

        let requiredLayerFields = [
            "logo.src", "logo.size", "logo.opacity", "logo.position", "logo.hidden",
            "intro.src", "intro.duration", "intro.hidden", "outro.src", "outro.duration",
            "outro.hidden", "item.x", "item.y", "item.scale", "item.animation",
            "item.speed", "transitionSec", "track.hidden", "track.muted", "track.blocks",
            "block.hidden", "block.text", "block.startSec", "block.endSec", "track.style"
        ]
        for field in requiredLayerFields {
            #expect(renderPath.contains(field), "Missing native render layer field: \(field)")
        }

        let requiredAudioFields = [
            "track.src", "track.startSec", "track.trimStartSec", "track.trimEndSec",
            "track.volume", "track.fadeInSec", "track.fadeOutSec", "track.muted"
        ]
        for field in requiredAudioFields {
            #expect(renderPath.contains(field), "Missing native render audio field: \(field)")
        }
    }

    @Test("visual editor preview is backed by the same native Metal render plan as export")
    func visualEditorPreviewUsesNativeMetalRenderPlan() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let previewSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/NativeMetalClipPreviewView.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("NativeMetalClipPreviewView("))
        #expect(editorSource.contains("liveNativeRenderPlan("))
        #expect(editorSource.contains("@AppStorage(\"shortsExportResolution\") private var exportResolution = \"Source-based\""))
        #expect(editorSource.contains("@AppStorage(\"shortsExportFrameRate\") private var exportFrameRate = \"Source-based\""))
        #expect(editorSource.contains("let previewRenderSize = visualEditorRenderSize(for: nativePreviewSourceSize)"))
        #expect(editorSource.contains("outputWidth: previewRenderSize.width"))
        #expect(editorSource.contains("outputHeight: previewRenderSize.height"))
        #expect(editorSource.contains("fps: visualEditorFrameRate(for: nativePreviewSourceFPS)"))
        #expect(editorSource.contains("private func visualEditorRenderSize(for sourceSize: CGSize) -> (width: Int, height: Int)"))
        #expect(editorSource.contains("nativePreviewTimeSec"))
        #expect(previewSource.contains("NativeMetalShortsFrameRenderer"))
        #expect(previewSource.contains("AVPlayerItemVideoOutput"))
        #expect(previewSource.contains("copyPixelBuffer"))
        #expect(!editorSource.contains("swiftVisualEditorPreview(frameWidth: frameWidth, frameHeight: frameHeight)"))
        #expect(!editorSource.contains("outputWidth: max(1, Int(frameWidth.rounded(.toNearestOrAwayFromZero)))"))
    }

    @Test("visual editor frame keyframes are mapped to physical clip time before native render plan shifting")
    func visualEditorKeyframesUsePhysicalClipTime() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)"))
        #expect(editorSource.contains("time: physicalSec"))
        #expect(editorSource.contains("let physicalSec = mapVirtualToPhysical(virtualSec: time, currentTrim: timelineTrim)"))
        #expect(editorSource.contains("interpolateFrameState(kfs, timeSec: physicalSec)"))
    }

    @Test("visual editor preserves existing style background frame and layer values before save")
    func visualEditorBacksUpVisualSettingsBeforeSave() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("VisualEditorSettingsBackupStore.capture("))
        #expect(editorSource.contains("makeVisualSettingsSnapshot()"))
        #expect(editorSource.contains("_visual-settings-backups"))
        #expect(editorSource.contains("subtitleStyle: style"))
        #expect(editorSource.contains("backgroundSettings: backgroundSettings"))
        #expect(editorSource.contains("sourceFrameKeyframes: sourceFrameKeyframes"))
        #expect(editorSource.contains("targetFrameKeyframes: targetFrameKeyframes"))
    }

    @Test("native Metal renderer keeps visual formulas and independent text track bottom margins")
    func nativeMetalRendererKeepsVisualFormulasAndIndependentTextTrackMargins() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let drawTextTracksSource = compositorSource
            .components(separatedBy: "private func drawTextTracks")
            .dropFirst()
            .first?
            .components(separatedBy: "private func drawCaption")
            .first ?? ""
        let editorOverlaySource = editorSource
            .components(separatedBy: "ForEach(activeTextOverlayBlocks())")
            .dropFirst()
            .first?
            .components(separatedBy: "if let intro = currentIntro")
            .first ?? ""
        let addTextTrackSource = editorSource
            .components(separatedBy: "private func addTextTrack()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func addTextOverlayBlock()")
            .first ?? ""
        let addTextOverlaySource = editorSource
            .components(separatedBy: "private func addTextOverlayBlock()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func trackName")
            .first ?? ""

        #expect(compositorSource.contains("textTrackBottomMargin"))
        #expect(drawTextTracksSource.contains("let bottomMargin = textTrackBottomMargin("))
        #expect(drawTextTracksSource.contains("(style.subtitleBottomMargin ?? defaultTextTrackBottomMargin(trackIndex: trackIndex)) * scale"))
        #expect(!drawTextTracksSource.contains("renderPlan.subtitleBottomMargin"))
        #expect(!compositorSource.contains("baseBottomPx + ((Double(trackIndex) + 1.0) * fontSize * scale * 1.65)"))
        #expect(editorSource.contains("private func defaultTextTrackStyle(trackIndex: Int) -> ShortsSubtitleStyle"))
        #expect(editorSource.contains("private func defaultTextTrackBottomMargin(trackIndex: Int) -> Double"))
        #expect(editorOverlaySource.contains("let blockStyle = block.style ?? defaultTextTrackStyle(trackIndex: block.trackIndex)"))
        #expect(editorOverlaySource.contains("let baseMargin = blockStyle.subtitleBottomMargin ?? defaultTextTrackBottomMargin(trackIndex: block.trackIndex)"))
        #expect(!editorOverlaySource.contains("style.subtitleBottomMargin ?? 560.0"))
        #expect(addTextTrackSource.contains("style: defaultTextTrackStyle(trackIndex: tracks.count)"))
        #expect(addTextOverlaySource.contains("tracks[0].style = defaultTextTrackStyle(trackIndex: 0)"))
        #expect(addTextOverlaySource.contains("tracks[targetTrackIndex].style = tracks[targetTrackIndex].style ?? defaultTextTrackStyle(trackIndex: targetTrackIndex)"))
        #expect(editorSource.contains("selectedStyleTab = 0"))
        #expect(editorSource.contains("selectedStyleTab = index + 1"))
        #expect(compositorSource.contains("drawFrameGuideDim"))
        #expect(compositorSource.contains("NSColor.black.withAlphaComponent(CGFloat(settings.frameGuideOpacity))"))
        #expect(compositorSource.contains("shortsGuideRect(width: width, height: height)"))
        #expect(compositorSource.contains("bounceOffset"))
        #expect(compositorSource.contains("progress < 0.4"))
    }

    @Test("native visual editor keeps logo inside the shorts guide and exposes stronger frame controls")
    func nativeVisualEditorKeepsLogoInsideGuideAndExposesStrongerFrameControls() throws {
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )

        #expect(compositorSource.contains("let logoRect = shortsGuideRect(width: width, height: height)"))
        #expect(compositorSource.contains("logoRect.maxX - margin - size"))
        #expect(compositorSource.contains("logoRect.minX + margin"))
        #expect(compositorSource.contains("logoRect.maxY - margin - size"))
        #expect(compositorSource.contains("logoRect.minY + margin"))
        #expect(!compositorSource.contains("position.hasSuffix(\"right\") ? CGFloat(width) - margin - size : margin"))
        #expect(!compositorSource.contains("position.hasPrefix(\"top\") ? margin : CGFloat(height) - margin - size"))

        #expect(editorSource.contains("SliderRow(title: \"Border\", value: $backgroundSettings.frameGuideBorderWidth, range: 0...30, step: 0.5, suffix: \"px\")"))
        #expect(editorSource.contains("SliderRow(title: \"Glow\", value: $backgroundSettings.frameGuideBlur, range: 0...160, step: 1, suffix: \"px\")"))
        #expect(!editorSource.contains("SliderRow(title: \"Border\", value: $backgroundSettings.frameGuideBorderWidth, range: 0...12"))
        #expect(!editorSource.contains("SliderRow(title: \"Glow\", value: $backgroundSettings.frameGuideBlur, range: 0...30"))
    }

    @Test("native shorts renderer has no legacy render fallback")
    func nativeShortsRendererHasNoLegacyRenderFallback() throws {
        let rendererSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeShortsVideoRenderer.swift",
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeMetalVideoCompositor.swift",
            encoding: .utf8
        )
        let combined = rendererSource + "\n" + compositorSource
        let forbiddenLegacyRenderer = ["Hyper", "Frames"].joined()
        let forbiddenBrowserProxy = ["browser", "safe"].joined(separator: "-")
        let forbiddenCoreAnimationTool = ["AVVideoComposition", "CoreAnimationTool"].joined()
        let forbiddenRasterContext = ["CI", "Context"].joined()
        let forbiddenRasterFilter = ["CI", "Filter"].joined()

        #expect(!combined.localizedCaseInsensitiveContains(forbiddenLegacyRenderer))
        #expect(!combined.localizedCaseInsensitiveContains(forbiddenBrowserProxy))
        #expect(!combined.contains(forbiddenCoreAnimationTool))
        #expect(!combined.contains(forbiddenRasterContext))
        #expect(!combined.contains(forbiddenRasterFilter))
    }

    @Test("visual editor timeline keeps one explicit selected subtitle or text block")
    func visualEditorTimelineKeepsOneExplicitSelectedBlock() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("private enum TimelineSelection: Equatable"))
        #expect(editorSource.contains("private func selectSubtitleTimelineBlock(_ id: String)"))
        #expect(editorSource.contains("private func selectTextTimelineBlock(trackID: String, blockID: String)"))
        #expect(editorSource.contains("selectSubtitleTimelineBlock(segment.id)"))
        #expect(editorSource.contains("selectTextTimelineBlock(trackID: track.id, blockID: block.id)"))
        #expect(editorSource.contains("private func splitSelectedTimelineBlock()"))
        #expect(editorSource.contains("splitSelectedTextOverlay()"))
        #expect(editorSource.contains("private func mergeNextTimelineBlock()"))
        #expect(editorSource.contains("mergeNextTextOverlay()"))
        #expect(editorSource.contains("EditorSmallButton(title: \"Split\", systemImage: \"scissors\", action: splitSelectedTimelineBlock)"))
        #expect(editorSource.contains("EditorSmallButton(title: \"Merge next\", systemImage: \"rectangle.split.2x1\", action: mergeNextTimelineBlock)"))
        #expect(!editorSource.contains("selectedSegmentID = active.id"))
    }

    @Test("visual editor timeline uses one restrained text block palette")
    func visualEditorTimelineUsesOneRestrainedTextBlockPalette() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let subtitleTimelineSource = editorSource
            .components(separatedBy: "private struct TimelineBlock: View")
            .dropFirst()
            .first?
            .components(separatedBy: "private struct TextOverlayListRow: View")
            .first ?? ""
        let textTimelineSource = editorSource
            .components(separatedBy: "private struct TimelineTextBlock: View")
            .dropFirst()
            .first?
            .components(separatedBy: "private struct EditorSmallButton: View")
            .first ?? ""

        #expect(editorSource.contains("private enum TimelineTextBlockPalette"))
        #expect(editorSource.contains("static let baseFill = Color(red: 120 / 255, green: 83 / 255, blue: 28 / 255).opacity(0.50)"))
        #expect(editorSource.contains("static let playheadFill = Color(red: 143 / 255, green: 96 / 255, blue: 27 / 255).opacity(0.66)"))
        #expect(editorSource.contains("static let selectionFill = Color(red: 168 / 255, green: 108 / 255, blue: 24 / 255).opacity(0.78)"))
        #expect(editorSource.contains("static let selectionStroke = VaniScriptTheme.accent.opacity(0.92)"))
        #expect(subtitleTimelineSource.contains("? TimelineTextBlockPalette.selectionFill"))
        #expect(subtitleTimelineSource.contains("? TimelineTextBlockPalette.playheadFill"))
        #expect(subtitleTimelineSource.contains(": TimelineTextBlockPalette.baseFill"))
        #expect(textTimelineSource.contains("? TimelineTextBlockPalette.selectionFill"))
        #expect(textTimelineSource.contains("? TimelineTextBlockPalette.playheadFill"))
        #expect(textTimelineSource.contains(": TimelineTextBlockPalette.baseFill"))
        #expect(!editorSource.contains("private let explicitSelectionFill"))
        #expect(!editorSource.contains("Color(red: 34 / 255, green: 185 / 255, blue: 176 / 255)"))
        #expect(!editorSource.contains("Color(red: 91 / 255, green: 241 / 255, blue: 225 / 255)"))
        #expect(!editorSource.contains("Color(red: 72 / 255, green: 62 / 255, blue: 116 / 255).opacity(0.88)"))
        #expect(!subtitleTimelineSource.contains("foregroundStyle(selected ? Color.black"))
        #expect(!textTimelineSource.contains("foregroundStyle(selected ? Color.black"))
    }

    @Test("visual editor edit toolbar is contextual for subtitle and text blocks")
    func visualEditorEditToolbarIsContextualForSubtitleAndTextBlocks() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let toolbarSource = editorSource
            .components(separatedBy: "private var toolbar: some View")
            .dropFirst()
            .first?
            .components(separatedBy: "private var wordChips: some View")
            .first ?? ""
        let addSubtitleSource = editorSource
            .components(separatedBy: "private func addSubtitleBlock()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func mergeNextTimelineBlock()")
            .first ?? ""
        let addTextSource = editorSource
            .components(separatedBy: "private func addTextOverlayBlock()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func trackName")
            .first ?? ""

        #expect(editorSource.contains("private let timelineMergeGapToleranceSec: Double = 0.25"))
        #expect(editorSource.contains("private var activeTextPlaceholder: String"))
        #expect(editorSource.contains("Text(activeTextPlaceholder)"))
        #expect(editorSource.contains(".allowsHitTesting(false)"))
        #expect(editorSource.contains("private var selectedTextWordCount: Int"))
        #expect(editorSource.contains("private var canSplitSelectedTimelineBlock: Bool"))
        #expect(editorSource.contains("private var canMergeNextSelectedTimelineBlock: Bool"))
        #expect(editorSource.contains("private func canMergeNextSegment() -> Bool"))
        #expect(editorSource.contains("private func canMergeNextTextOverlay() -> Bool"))
        #expect(editorSource.contains("private func mergeGapIsClose(selectedEnd: Double, nextStart: Double) -> Bool"))
        #expect(editorSource.contains("private func boundedPlayheadPhysicalSec() -> Double"))

        #expect(toolbarSource.contains("if canSplitSelectedTimelineBlock {"))
        #expect(toolbarSource.contains("if selectedSegment != nil {"))
        #expect(toolbarSource.contains("EditorSmallButton(title: \"Add Subtitle Block\", systemImage: \"captions.bubble\", action: addSubtitleBlock)"))
        #expect(toolbarSource.contains("EditorSmallButton(title: \"Add Text Block\", systemImage: \"text.badge.plus\", action: addTextOverlayBlock)"))
        #expect(toolbarSource.contains("if canMergeNextSelectedTimelineBlock {"))
        #expect(toolbarSource.contains("if timelineSelection != nil {"))
        #expect(!toolbarSource.contains("EditorSmallButton(title: \"Split\", systemImage: \"scissors\", action: splitSelectedTimelineBlock)\n            EditorSmallButton(title: \"Add Subtitle Block\""))
        #expect(!toolbarSource.contains("EditorSmallButton(title: \"Merge next\", systemImage: \"rectangle.split.2x1\", action: mergeNextTimelineBlock)\n            EditorSmallButton(title: \"Delete\""))

        #expect(addSubtitleSource.contains("boundedPlayheadPhysicalSec()"))
        #expect(addTextSource.contains("let start = min(boundedPlayheadPhysicalSec(), max(0, clipDuration - 1))"))
    }

    @Test("visual editor extra audio trim controls stay responsive while dragging")
    func visualEditorExtraAudioTrimControlsStayResponsiveWhileDragging() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let audioBlockSource = editorSource
            .components(separatedBy: "private struct TimelineAudioBlock")
            .dropFirst()
            .first?
            .components(separatedBy: "private struct TimelineTextBlock")
            .first ?? ""

        #expect(editorSource.contains("private func updateAudioTrack(id: String, syncPlayback: Bool = true, mutate: (inout ExtraAudioTrack) -> Void)"))
        #expect(editorSource.contains("if syncPlayback {\n            updateExtraAudioPlayback()\n        }"))
        #expect(editorSource.contains("syncPlayback: false"))
        #expect(editorSource.contains("onEditingChanged: { editing in"))
        #expect(editorSource.contains("if !editing { updateExtraAudioPlayback() }"))
        #expect(audioBlockSource.contains("let onCommitUpdate: () -> Void"))
        #expect(audioBlockSource.contains("onCommitUpdate()"))
        #expect(audioBlockSource.contains("private let audioTrimHandleHitWidth: CGFloat = 18"))
        #expect(audioBlockSource.contains(".frame(width: audioTrimHandleHitWidth, height: 20)"))
        #expect(audioBlockSource.contains(".contentShape(Rectangle())"))
        #expect(!audioBlockSource.contains("Rectangle()\n                        .fill(Color.white.opacity(0.08))\n                        .frame(width: 6)\n                        .overlay("))
    }

    @Test("visual editor keyboard shortcuts work outside real text input")
    func visualEditorKeyboardShortcutsWorkOutsideRealTextInput() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let monitorSource = editorSource
            .components(separatedBy: "private func installKeyboardMonitor()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func recordUndo()")
            .first ?? ""

        #expect(editorSource.contains(".onKeyPress(.space)"))
        #expect(editorSource.contains("return handleSpacebarKeyPress() ? .handled : .ignored"))
        #expect(editorSource.contains("private func handleSpacebarKeyPress() -> Bool"))
        #expect(editorSource.contains("private func shouldHandleVisualEditorShortcut(_ event: NSEvent) -> Bool"))
        #expect(editorSource.contains("private func responderIsEditableTextInput(_ responder: NSResponder) -> Bool"))
        #expect(monitorSource.contains("guard shouldHandleVisualEditorShortcut(event) else { return event }"))
        #expect(monitorSource.contains("event.modifierFlags.intersection([.command, .control, .option]).isEmpty"))
        #expect(!editorSource.contains("String(describing: type(of: responder)).contains(\"Text\")"))
    }

    @Test("visual editor cut range uses stable source timeline instead of collapsed cut timeline")
    func visualEditorCutRangeUsesStableSourceTimelineInsteadOfCollapsedCutTimeline() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let cutRangeSource = editorSource
            .components(separatedBy: "// MARK: - Cut Range Engine")
            .dropFirst()
            .first?
            .components(separatedBy: "private func commitCutRange")
            .first ?? ""
        let markerSource = editorSource
            .components(separatedBy: "// Cut range start overlay")
            .dropFirst()
            .first?
            .components(separatedBy: ".frame(width: max(baseWidth")
            .first ?? ""
        let monitorSource = editorSource
            .components(separatedBy: "private func installKeyboardMonitor()")
            .dropFirst()
            .first?
            .components(separatedBy: "private func recordUndo()")
            .first ?? ""

        #expect(cutRangeSource.contains("let physicalSec = mapVirtualToPhysical(virtualSec: virtualSec, currentTrim: timelineTrim)"))
        #expect(!cutRangeSource.contains("let physicalSec = virtualSec - introDuration"))
        #expect(markerSource.contains("let startVirtual = mapPhysicalToVirtual(physicalSec: startSec, currentTrim: timelineTrim)"))
        #expect(!markerSource.contains("let startVirtual = startSec + introDuration"))
        #expect(editorSource.contains("cuts: []"))
        #expect(editorSource.contains("TimelineCutTimeMapper.virtualDuration("))
        #expect(editorSource.contains("TimelineCutTimeMapper.activeOutputDuration("))
        #expect(editorSource.contains("cuts: timelineCuts"))
        #expect(monitorSource.contains("let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)"))
        #expect(!monitorSource.contains("let physicalSec = max(0, currentSec - introDuration)"))
        #expect(editorSource.contains("cutRangePreviewEndSec"))
        #expect(editorSource.contains("CutRangePreviewOverlay("))
        #expect(editorSource.contains("TimelineCutRegionOverlay(cuts: timelineCuts"))
        #expect(!editorSource.contains("Razor"))
        #expect(!editorSource.contains("razor"))
    }

    @Test("visual editor timeline stays on the source scale after cut ranges")
    func visualEditorTimelineStaysOnSourceScaleAfterCutRanges() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let durationSource = editorSource
            .components(separatedBy: "private var activeVideoOutputDuration")
            .dropFirst()
            .first?
            .components(separatedBy: "private var mainVideoOpacity")
            .first ?? ""
        let mapperSource = editorSource
            .components(separatedBy: "private func mapVirtualToPhysical")
            .dropFirst()
            .first?
            .components(separatedBy: "private func shouldPlayMutedBackgroundVideo")
            .first ?? ""

        #expect(durationSource.contains("cuts: []"))
        #expect(!durationSource.contains("cuts: timelineCuts"))
        #expect(mapperSource.contains("cuts: []"))
        #expect(!mapperSource.contains("cuts: timelineCuts"))
        #expect(editorSource.contains("findCut(at: physicalSec)"))
        #expect(editorSource.contains("adjustedPhysicalSec = hit.endSec"))
    }

    @Test("visual editor seek skips existing cut regions")
    func visualEditorSeekSkipsExistingCutRegions() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let seekSource = editorSource
            .components(separatedBy: "private func seek(to virtualSec: Double, autoplay: Bool)")
            .dropFirst()
            .first?
            .components(separatedBy: "private func syncMutedBackgroundVideo")
            .first ?? ""

        #expect(seekSource.contains("var adjustedPhysicalSec = physicalSec"))
        #expect(seekSource.contains("if !wantsMutedBackground, let hit = findCut(at: physicalSec)"))
        #expect(seekSource.contains("adjustedPhysicalSec = hit.endSec"))
        #expect(seekSource.contains("let adjustedVirtualSec = wantsMutedBackground"))
        #expect(seekSource.contains("mapPhysicalToVirtual(physicalSec: adjustedPhysicalSec, currentTrim: timelineTrim)"))
        #expect(seekSource.contains("currentSec = min(max(0, adjustedVirtualSec), virtualDuration)"))

        #expect(editorSource.contains("updateExtraAudioPlayback(syncToTimeline: false)"))
        #expect(editorSource.contains("private func updateExtraAudioPlayback(syncToTimeline: Bool = true)"))
        #expect(editorSource.contains("let shouldResyncExtraAudio = syncToTimeline || player.rate == 0"))
        #expect(editorSource.contains("if shouldResyncExtraAudio && abs(currentPlayerTime - desiredPlaybackTime) > 0.15"))
    }

    @Test("visual editor cut range is selected by one drag gesture on the source timeline")
    func visualEditorCutRangeIsSelectedByOneDragGestureOnTheSourceTimeline() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let trackRowSource = editorSource
            .components(separatedBy: "private struct EditorTrackRow")
            .dropFirst()
            .first?
            .components(separatedBy: "private enum TimelineTextBlockPalette")
            .first ?? ""
        let cutRangeSource = editorSource
            .components(separatedBy: "// MARK: - Cut Range Engine")
            .dropFirst()
            .first?
            .components(separatedBy: "private func addCut")
            .first ?? ""

        #expect(trackRowSource.contains(".allowsHitTesting(!cutRangeActive)"))
        #expect(trackRowSource.contains("if cutRangeActive {"))
        #expect(trackRowSource.contains("TimelineCutRangeDragSelector("))
        #expect(trackRowSource.contains("private struct TimelineCutRangeDragSelector: NSViewRepresentable"))
        #expect(trackRowSource.contains("onCutRangeBegin"))
        #expect(trackRowSource.contains("onCutRangeUpdate"))
        #expect(trackRowSource.contains("onCutRangeFinish"))
        #expect(trackRowSource.contains("onCutRangeCancel"))
        #expect(trackRowSource.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        #expect(trackRowSource.contains("override func mouseDown(with event: NSEvent)"))
        #expect(trackRowSource.contains("override func mouseDragged(with event: NSEvent)"))
        #expect(trackRowSource.contains("override func mouseUp(with event: NSEvent)"))
        #expect(trackRowSource.contains("convert(event.locationInWindow, from: nil)"))
        #expect(trackRowSource.contains("AppLogger.shared.info(\"VisualEditor CutRange AppKit drag"))
        #expect(!trackRowSource.contains("TimelineCutRangeTapCatcher"))
        #expect(!trackRowSource.contains("SpatialTapGesture()"))
        #expect(!trackRowSource.contains("value.startLocation.x"))
        #expect(!trackRowSource.contains("@State private var gestureTriggered"))
        #expect(!trackRowSource.contains("if !gestureTriggered"))
        #expect(!trackRowSource.contains("print(\"EditorTrackRow"))

        #expect(cutRangeSource.contains("private func beginCutRangeDrag(virtualSec: Double)"))
        #expect(cutRangeSource.contains("private func updateCutRangeDrag(virtualSec: Double)"))
        #expect(cutRangeSource.contains("private func finishCutRangeDrag(virtualSec: Double, wasDragged: Bool)"))
        #expect(cutRangeSource.contains("guard wasDragged else"))
        #expect(cutRangeSource.contains("boundedSourcePhysicalSec(for: virtualSec)"))
        #expect(cutRangeSource.contains("cutRangePreviewEndSec"))
        #expect(!cutRangeSource.contains("private func handleCutRangeClick"))
        #expect(cutRangeSource.contains("AppLogger.shared.info(\"VisualEditor CutRange committed"))
    }

    @Test("visual editor cut ranges expose badges deletion and timeline edge handles")
    func visualEditorCutRangesExposeBadgesDeletionAndTimelineEdgeHandles() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let playbackSource = editorSource
            .components(separatedBy: "private var playbackRow: some View")
            .dropFirst()
            .first?
            .components(separatedBy: "private var multitrackTimeline")
            .first ?? ""
        let cutOverlaySource = editorSource
            .components(separatedBy: "struct TimelineCutRegionOverlay")
            .dropFirst()
            .first?
            .components(separatedBy: "class PlayerHostingView")
            .first ?? ""

        #expect(playbackSource.contains("CutRangeBadge("))
        #expect(playbackSource.contains("title: \"Cut \\(index + 1)\""))
        #expect(playbackSource.contains("onDelete: { deleteCut(at: index) }"))
        #expect(editorSource.contains("private struct CutRangeBadge"))
        #expect(editorSource.contains("Image(systemName: \"xmark\")"))

        #expect(cutOverlaySource.contains("let onUpdateCut: (Int, TimelineCut) -> Void"))
        #expect(cutOverlaySource.contains("TimelineCutRegionHandle("))
        #expect(cutOverlaySource.contains("isStart: true"))
        #expect(cutOverlaySource.contains("isStart: false"))
        #expect(cutOverlaySource.contains(".cursorOnHover(.resizeLeftRight)"))
        #expect(cutOverlaySource.contains("onUpdateCut(index, TimelineCut("))
        #expect(editorSource.contains("private func updateCut(index: Int, cut: TimelineCut)"))
    }

    @Test("visual editor cut range toggle always clears stale start marker")
    func visualEditorCutRangeToggleAlwaysClearsStaleStartMarker() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let playbackSource = editorSource
            .components(separatedBy: "private var playbackRow: some View")
            .dropFirst()
            .first?
            .components(separatedBy: "private var multitrackTimeline")
            .first ?? ""

        #expect(playbackSource.contains("if cutRangeActive {"))
        #expect(playbackSource.contains("cutRangeActive = false"))
        #expect(playbackSource.contains("cutRangeStartSec = nil"))
        #expect(playbackSource.contains("cutRangePreviewEndSec = nil"))
        #expect(playbackSource.contains("} else {\n                    cutRangeStartSec = nil\n                    cutRangePreviewEndSec = nil\n                    cutRangeActive = true"))
        #expect(!playbackSource.contains("cutRangeActive.toggle()"))
    }

    @Test("native blur intro and outro keep moving source video silently behind graphics")
    func nativeBlurIntroOutroKeepsMovingSourceVideoSilentlyBehindGraphics() throws {
        let editorSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/VisualClipEditorView.swift",
            encoding: .utf8
        )
        let rendererSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/NativeShortsVideoRenderer.swift",
            encoding: .utf8
        )

        #expect(editorSource.contains("private func shouldPlayMutedBackgroundVideo(at virtualSec: Double) -> Bool"))
        #expect(editorSource.contains("private func blurBackgroundPhysicalSec(virtualSec: Double, currentTrim: TimelineTrim) -> Double"))
        #expect(editorSource.contains("syncMutedBackgroundVideo(to: blurBackgroundPhysicalSec"))
        #expect(editorSource.contains("player?.volume = 0"))
        #expect(rendererSource.contains("let videoSegments = videoMediaSegments(for: renderPlan)"))
        #expect(rendererSource.contains("let audioMediaSegments = renderPlan.mediaSegments"))
        #expect(rendererSource.contains("private static func videoMediaSegments(for renderPlan: NativeShortsRenderPlan) -> [NativeRenderMediaSegment]"))
        #expect(rendererSource.contains("introBackgroundMediaSegment"))
        #expect(rendererSource.contains("outroBackgroundMediaSegment"))
    }

    @Test("native link importer uses bundled yt-dlp instead of required Cobalt resolver")
    func nativeLinkImporterUsesBundledYtDlp() throws {
        let importerSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/DirectMediaImporter.swift",
            encoding: .utf8
        )

        #expect(!importerSource.contains("cobaltInstances"))
        #expect(!importerSource.contains("cobalt.api.ryley.cc"))
        #expect(!importerSource.contains("cobalt.hyper.lol"))
        #expect(!importerSource.contains("cobalt.rotur.dev"))
        #expect(!importerSource.contains("cobalt.sh/api/json"))
        #expect(importerSource.contains("MediaDownloader.download"))
        #expect(importerSource.contains("fallbackExtractAndDownloadWebMedia"))
        #expect(!importerSource.contains("webResolverNotConfigured"))
    }

    @Test("native media tools are bundled and signed by the app build script")
    func nativeMediaToolsAreBundledAndSignedByBuildScript() throws {
        let scriptSource = try String(
            contentsOfFile: "script/build_and_run.sh",
            encoding: .utf8
        )

        #expect(scriptSource.contains("VENDOR_BIN=\"$ROOT_DIR/Vendor/bin\""))
        #expect(scriptSource.contains("$VENDOR_BIN/yt-dlp"))
        #expect(scriptSource.contains("$VENDOR_BIN/ffmpeg"))
        #expect(scriptSource.contains("Contents/Resources/bin"))
        #expect(scriptSource.contains("codesign --force --sign - \"$APP_RESOURCES/bin/yt-dlp\""))
        #expect(scriptSource.contains("codesign --force --sign - \"$APP_RESOURCES/bin/ffmpeg\""))
        #expect(!scriptSource.contains("ffmpeg|yt-dlp"))
    }

    @Test("native app bundle installs side by side with Electron edition")
    func nativeAppBundleInstallsSideBySideWithElectronEdition() throws {
        let runScriptSource = try String(
            contentsOfFile: "script/build_and_run.sh",
            encoding: .utf8
        )
        let releaseScriptSource = try String(
            contentsOfFile: "script/build_release_dmg.sh",
            encoding: .utf8
        )

        for scriptSource in [runScriptSource, releaseScriptSource] {
            #expect(scriptSource.contains("APP_BUNDLE_NAME=\"VaniScript\""))
            #expect(scriptSource.contains("APP_EXECUTABLE_NAME=\"VaniScript\""))
            #expect(scriptSource.contains("APP_BUNDLE=\"$"))
            #expect(scriptSource.contains("$APP_BUNDLE_NAME.app"))
            #expect(scriptSource.contains("<string>$APP_EXECUTABLE_NAME</string>"))
            #expect(scriptSource.contains("<string>$APP_BUNDLE_NAME</string>"))
            #expect(scriptSource.contains("APPLE_SILICON_ASSETS_DIR=\"$ROOT_DIR/Assets\""))
            #expect(scriptSource.contains("$APPLE_SILICON_ASSETS_DIR/AppIconAS.icns"))
            #expect(scriptSource.contains("$APPLE_SILICON_ASSETS_DIR/AppIconAS.png"))
        }
        #expect(releaseScriptSource.contains("OUTPUT_DMG=\"$DIST_DIR/VaniScript.dmg\""))
        #expect(!releaseScriptSource.contains("VaniScript-AS.dmg"))
    }

    @Test("native release DMG embeds Swift compatibility runtime and Sparkle framework")
    func nativeReleaseDmgEmbedsSwiftCompatibilityRuntime() throws {
        let releaseScriptSource = try String(
            contentsOfFile: "script/build_release_dmg.sh",
            encoding: .utf8
        )

        #expect(releaseScriptSource.contains("APP_FRAMEWORKS=\"$APP_CONTENTS/Frameworks\""))
        #expect(releaseScriptSource.contains("xcrun swift-stdlib-tool --print"))
        #expect(releaseScriptSource.contains("cp \"$swift_library\" \"$APP_FRAMEWORKS/\""))
        #expect(releaseScriptSource.contains("@executable_path/../Frameworks/libswiftCompatibilitySpan.dylib"))
        #expect(releaseScriptSource.contains("install_name_tool -delete_rpath \"$xcode_swift62_rpath\""))
        #expect(releaseScriptSource.contains("codesign_release \"$dylib\""))
        #expect(releaseScriptSource.contains("Sparkle.framework"))
        #expect(releaseScriptSource.contains("ditto \"$SPARKLE_FRAMEWORK_SRC\" \"$APP_FRAMEWORKS/Sparkle.framework\""))
        #expect(releaseScriptSource.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\""))
    }

    @Test("release packaging rejects hardcoded user paths and enforces production signing")
    func releasePackagingRejectsHardcodedUserPathsAndEnforcesProductionSigning() throws {
        let releaseScriptSource = try String(
            contentsOfFile: "script/build_release_dmg.sh",
            encoding: .utf8
        )
        let packageSource = try String(
            contentsOfFile: "Package.swift",
            encoding: .utf8
        )

        #expect(!releaseScriptSource.contains("/Users/pavan"))
        #expect(!releaseScriptSource.contains("~/.cache"))
        #expect(releaseScriptSource.contains("error: production release packaging requires a valid Developer ID Application"))
        #expect(releaseScriptSource.contains("VANISCRIPT_VERSION"))
        #expect(releaseScriptSource.contains("VANISCRIPT_BUILD_NUMBER"))
        #expect(releaseScriptSource.contains("VaniScript-$VERSION.zip"))
        #expect(releaseScriptSource.contains("VaniScript-$VERSION.manifest.json"))
        #expect(packageSource.contains("https://github.com/sparkle-project/Sparkle"))
        #expect(packageSource.contains("2.9.4"))
    }

    @Test("web media resolver remains hidden fallback only")
    func webMediaResolverRemainsHiddenFallbackOnly() throws {
        let settingsSource = try String(
            contentsOfFile: "Sources/VaniScriptCore/AppSettings.swift",
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )
        let importerSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/DirectMediaImporter.swift",
            encoding: .utf8
        )
        let settingsViewSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/SettingsView.swift",
            encoding: .utf8
        )

        #expect(settingsSource.contains("mediaResolverEndpoint"))
        #expect(settingsSource.contains("mediaResolverToken"))
        #expect(storeSource.contains("resolverEndpoint: workflow.settings.mediaResolverEndpoint"))
        #expect(storeSource.contains("resolverToken: workflow.settings.mediaResolverToken"))
        #expect(!settingsViewSource.contains("Local Media Downloader"))
        #expect(!settingsViewSource.contains("Fallback Resolver URL"))
        #expect(!settingsViewSource.contains("Fallback Resolver Token"))
        #expect(!settingsViewSource.contains("Primary Downloader"))
        #expect(!importerSource.contains("Settings > API & Usage > Local Media Downloader"))
        #expect(!settingsViewSource.contains("require a Cobalt-compatible resolver endpoint"))
    }

    @Test("source media info refreshes technical details from file before presentation")
    func sourceMediaInfoRefreshesBeforePresentation() throws {
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(storeSource.contains("Reading source media details"))
        #expect(storeSource.contains("SourceMediaInspector.inspect("))
        #expect(storeSource.contains("fileURL: fileURL"))
        #expect(storeSource.contains("updateProjectSourceMediaInfo(refreshedInfo, for: id)"))
        #expect(storeSource.contains("presentSourceMediaInfo(refreshedInfo, id: id)"))
    }

    @Test("native onboarding starts automatically once per build and persists completion")
    func nativeOnboardingStartsAutomaticallyOncePerBuildAndPersistsCompletion() throws {
        let appSource = try String(
            contentsOfFile: "Sources/VaniScript/App/VaniScriptApp.swift",
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(appSource.contains("startFirstRunOnboardingIfNeeded()"))
        #expect(storeSource.contains("OnboardingCompletionPolicy.needsOnboarding(settings: workflow.settings, currentBuildID: buildIdentifier)"))
        #expect(storeSource.contains("OnboardingCompletionPolicy.markCompleted(settings: &workflow.settings, currentBuildID: buildIdentifier)"))
        #expect(storeSource.contains("startFirstRunOnboardingIfNeeded"))
        #expect(storeSource.contains("markOnboardingCompleted"))
        #expect(storeSource.contains("try settingsPersistence(workflow.settings)"))
        #expect(storeSource.contains("settingsPersistence: @escaping @Sendable (AppSettings) throws -> Void = {\n            try SettingsDiskStore.save($0)\n        },"))
        #expect(storeSource.contains("markOnboardingCompleted()"))
    }

    @Test("review exposes always available try transcription action")
    func reviewExposesTryTranscriptionAction() throws {
        let reviewSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/ReviewWorkspaceView.swift",
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(reviewSource.contains("Try Transcription"))
        #expect(reviewSource.contains("store.retranscribeCurrentSegment()"))
        #expect(storeSource.contains("func retranscribeCurrentSegment()"))
        #expect(storeSource.contains("statusMessage = \"Trying transcription again for current segment...\""))
    }

    @Test("native recording source uses Electron-style setup and review flow")
    func nativeRecordingSourceUsesElectronStyleSetupAndReviewFlow() throws {
        let uploadSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/UploadWorkspaceView.swift",
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(uploadSource.contains(".sheet(isPresented: $store.isRecordingWorkspacePresented)"))
        #expect(uploadSource.contains("RecordingWorkspaceSheet"))
        #expect(uploadSource.contains("Record Audio Source"))
        #expect(uploadSource.contains("Recording source"))
        #expect(uploadSource.contains("System"))
        #expect(uploadSource.contains("Mic / Virtual"))
        #expect(uploadSource.contains("Input Device"))
        #expect(uploadSource.contains("Review Recording"))
        #expect(uploadSource.contains("recordingPreviewSeek"))
        #expect(uploadSource.contains("Retake"))
        #expect(uploadSource.contains("Save & Continue"))

        #expect(storeSource.contains("@Published var isRecordingWorkspacePresented"))
        #expect(storeSource.contains("@Published var recordingDevices"))
        #expect(storeSource.contains("@Published var recordingPreviewURL"))
        #expect(storeSource.contains("@Published var recordingPreviewDurationSec"))
        #expect(storeSource.contains("func presentRecordingWorkspace()"))
        #expect(storeSource.contains("func stopAndPreviewRecording()"))
        #expect(storeSource.contains("func discardRecordingPreview()"))
        #expect(storeSource.contains("func useRecordingPreview()"))
        #expect(storeSource.contains("recordingPlayer = AVPlayer(url: url)"))
        #expect(storeSource.contains("selectSource(url: url, duration: duration, sourceMediaInfo: sourceInfo)"))
    }

    @Test("native recording meter is driven by live audio spectrum levels")
    func nativeRecordingMeterIsDrivenByLiveAudioSpectrumLevels() throws {
        let uploadSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/UploadWorkspaceView.swift",
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )
        let systemRecorderSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/SystemAudioRecorder.swift",
            encoding: .utf8
        )
        let microphoneRecorderSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/MicrophoneAudioRecorder.swift",
            encoding: .utf8
        )

        #expect(storeSource.contains("@Published var recordingAudioLevels"))
        #expect(storeSource.contains("updateRecordingAudioLevels"))
        #expect(storeSource.contains("AudioSpectrumAnalyzer.silenceLevels"))
        #expect(uploadSource.contains("store.recordingAudioLevels"))
        #expect(!uploadSource.contains("sin(phase)"))
        #expect(systemRecorderSource.contains("onLevels"))
        #expect(microphoneRecorderSource.contains("onLevels"))
        #expect(systemRecorderSource.contains("AudioSampleBufferLevels.levels"))
        #expect(microphoneRecorderSource.contains("AudioSampleBufferLevels.levels"))
    }

    @Test("MCP server is token gated and loopback only")
    func mcpServerIsTokenGatedAndLoopbackOnly() throws {
        let serverSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/McpServer.swift",
            encoding: .utf8
        )
        let bridgeSource = try String(
            contentsOfFile: "mcp_bridge.py",
            encoding: .utf8
        )
        let instructions = try String(
            contentsOfFile: "MCP_INSTRUCTIONS.md",
            encoding: .utf8
        )
        let chatSource = try String(
            contentsOfFile: "Sources/VaniScript/Views/ChatSidebarView.swift",
            encoding: .utf8
        )
        let codexAgentSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/CodexAgentService.swift",
            encoding: .utf8
        )
        let settingsStoreSource = try String(
            contentsOfFile: "Sources/VaniScript/Services/SettingsDiskStore.swift",
            encoding: .utf8
        )
        let appSource = try String(
            contentsOfFile: "Sources/VaniScript/App/VaniScriptApp.swift",
            encoding: .utf8
        )

        #expect(serverSource.contains("Darwin.bind"))
        #expect(serverSource.contains("Darwin.listen"))
        #expect(serverSource.contains("inet_addr(\"127.0.0.1\")"))
        #expect(serverSource.contains("attributes: .concurrent"))
        #expect(serverSource.contains("configuration.isAuthorized(headers: request.headers, queryItems: request.queryItems)"))
        #expect(serverSource.contains("configuration.isAllowedOrigin(request.headers[\"origin\"])"))
        #expect(serverSource.contains("request.path == \"/sse\""))
        #expect(serverSource.contains("request.method == \"POST\""))
        #expect(serverSource.contains("Mcp-Session-Id"))
        #expect(serverSource.contains("streamableSessionTimeout"))
        #expect(serverSource.contains("expireInactiveStreamableHttpSessions"))
        #expect(serverSource.contains("McpToolRegistry"))
        #expect(serverSource.contains("McpClientClassifier.profileID"))
        #expect(serverSource.contains("McpActiveClient("))
        #expect(serverSource.contains("store?.updateMcpActiveClients"))
        #expect(serverSource.contains("monitorSseClient"))
        #expect(serverSource.contains(".definitions(permissions: configuration.permissions)"))
        #expect(serverSource.contains("store.executeMcpTool(name: name, arguments: args, permissions: permissions)"))
        #expect(!serverSource.contains("Access-Control-Allow-Origin: *"))
        #expect(bridgeSource.contains("VANISCRIPT_MCP_TOKEN"))
        #expect(bridgeSource.contains("mcpAccessToken"))
        #expect(settingsStoreSource.contains("Int16(0o700)"))
        #expect(settingsStoreSource.contains("Int16(0o600)"))
        #expect(instructions.contains("The server is disabled by default"))
        #expect(!instructions.localizedCaseInsensitiveContains("Electron"))
        #expect(appSource.components(separatedBy: "workflowStore.configureMcpServer()").count >= 3)
        #expect(chatSource.contains("arguments: (call.args ?? [:]).mapValues(\\.value)"))
        #expect(chatSource.contains("case mcp"))
        #expect(chatSource.contains("case gemini"))
        #expect(chatSource.contains("executeCodexRequest"))
        #expect(!chatSource.contains("McpServer.shared.sampleMessage"))
        #expect(!serverSource.contains("sampling/createMessage"))
        #expect(codexAgentSource.contains("--ignore-user-config"))
        #expect(codexAgentSource.contains("--sandbox\", \"read-only"))
        #expect(codexAgentSource.contains("vaniscript_embedded"))
        #expect(codexAgentSource.contains("default_tools_approval_mode=\\\"approve\\\""))
        #expect(codexAgentSource.contains("VANISCRIPT_MCP_TOKEN"))
        #expect(!codexAgentSource.contains("--dangerously-bypass-approvals-and-sandbox"))
    }

    @Test("startup model scan does not block the UI or MCP main actor")
    func startupModelScanRunsOffMainActor() throws {
        let storeSource = try String(
            contentsOfFile: "Sources/VaniScript/Stores/WorkflowStore.swift",
            encoding: .utf8
        )

        #expect(storeSource.contains("Task.detached(priority: .utility)"))
        #expect(storeSource.contains("LocalModelScanner.scanForLocalModels()"))
    }

    @Test("Settings exposes alphabetized MCP agent profiles")
    func settingsExposesAlphabetizedMcpAgentProfiles() throws {
        let settingsView = try String(
            contentsOfFile: "Sources/VaniScript/Views/SettingsView.swift",
            encoding: .utf8
        )

        let orderedTabMarkers = [
            "Label(\"Agents\"",
            "Label(\"API & Usage\"",
            "Label(\"Appearance\"",
            "Label(\"Chunking\"",
            "Label(\"Glossary\"",
            "Label(\"Models\"",
            "Label(\"Prompts\"",
            "Label(\"Transcription\"",
        ]

        var previousIndex = settingsView.startIndex
        for marker in orderedTabMarkers {
            guard let range = settingsView.range(of: marker) else {
                Issue.record("Missing settings tab marker: \(marker)")
                continue
            }
            #expect(range.lowerBound >= previousIndex)
            previousIndex = range.lowerBound
        }

        #expect(settingsView.contains("McpAgentProfileCatalog.all"))
        #expect(settingsView.contains("Set Active"))
        #expect(settingsView.contains("Copy Setup"))
        #expect(settingsView.contains("title: \"Status\""))
        #expect(!settingsView.contains("Connection Status"))
    }

    @Test("Settings keeps MCP agent controls compact")
    func settingsKeepsMcpAgentControlsCompact() throws {
        let settingsView = try String(
            contentsOfFile: "Sources/VaniScript/Views/SettingsView.swift",
            encoding: .utf8
        )

        #expect(settingsView.contains("CompactMcpToggleCard("))
        #expect(settingsView.contains("McpStatusSummaryTile("))
        #expect(settingsView.contains("let mcpOverviewColumns"))
        #expect(settingsView.contains("let activeTargetColumns"))
        #expect(settingsView.contains("Text(activeClient?.displayName ?? \"Connected\")"))
        #expect(!settingsView.contains("Text(activeClient?.displayName ?? state.label)"))
    }
}
