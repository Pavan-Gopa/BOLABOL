import AppKit
import CoreText
import Foundation

/// Runtime outline correction in points from a glyph's advance center to its
/// measured ink center.
public struct HUDGlyphOutlineCorrection: Equatable, Sendable {
  public let dx: Double
  public let dy: Double

  public init(dx: Double, dy: Double) {
    self.dx = dx
    self.dy = dy
  }

  public static let zero = HUDGlyphOutlineCorrection(dx: 0, dy: 0)
}

/// Shared layout metrics for the provider quick switcher.
///
/// Used by SwiftUI list rendering and AppKit mouse hit-testing so both agree
/// row geometry. The outline helper also uses the native AppKit/CoreText
/// font metrics used by the rendered HUD labels.
public enum HUDQuickSwitcherLayout {
  private struct OutlineCorrectionKey: Hashable {
    let label: String
    let fontSize: Double
  }

  private struct GlyphRasterImageKey: Hashable {
    let label: String
    let fontSize: Double
    let width: Double
    let height: Double
    let backingScale: Double
  }

  /// All access to glyph caches is serialized through `glyphCacheLock`.
  private static let glyphCacheLock = NSLock()
  nonisolated(unsafe) private static var outlineCorrectionCache:
    [OutlineCorrectionKey: HUDGlyphOutlineCorrection] = [:]
  nonisolated(unsafe) private static var glyphRasterImageCache:
    [GlyphRasterImageKey: CGImage] = [:]
  public static let rowHeight: CGFloat = 24
  public static let rowSpacing: CGFloat = 2
  public static let verticalPadding: CGFloat = 6
  public static let horizontalPadding: CGFloat = 10
  public static let width: CGFloat = 190
  public static let dividerHeight: CGFloat = 7
  public static let localEngineID = HUDProviderListComposer.defaultLocalEngineID

  public static func hasDivider(providers: [ProviderQuickSwitcherModel.Provider]) -> Bool {
    providers.count > 1 && providers.first?.id == localEngineID
  }

  public static func contentHeight(providers: [ProviderQuickSwitcherModel.Provider]) -> CGFloat {
    let rowCount = providers.count
    guard rowCount > 0 else { return 0 }
    let base =
      verticalPadding * 2
      + CGFloat(rowCount) * rowHeight
      + CGFloat(max(0, rowCount - 1)) * rowSpacing
    return hasDivider(providers: providers) ? base + dividerHeight : base
  }

  /// Maps a point (content-view coordinates, origin bottom-left) to a
  /// top-to-bottom row index. Returns `nil` for spacing gaps or the divider.
  public static func rowIndex(
    forY y: CGFloat,
    providers: [ProviderQuickSwitcherModel.Provider]
  ) -> Int? {
    let rowCount = providers.count
    guard rowCount > 0 else { return nil }
    let height = contentHeight(providers: providers)
    var fromTop = height - y - verticalPadding
    guard fromTop >= 0 else { return nil }

    let withDivider = hasDivider(providers: providers)

    if fromTop <= rowHeight {
      return 0
    }

    if withDivider {
      if fromTop <= rowHeight + dividerHeight + rowSpacing {
        return nil
      }
      fromTop -= dividerHeight
    }

    let stride = rowHeight + rowSpacing
    let index = Int(fromTop / stride)
    let withinRow = fromTop - CGFloat(index) * stride
    guard index >= 0, index < rowCount, withinRow <= rowHeight else { return nil }
    return index
  }
}

/// Scalar geometry values keep the testable overlay policy independent from
/// AppKit/CoreFoundation geometry types at the executable target boundary.
public struct HUDOverlaySize: Equatable, Sendable {
  public let width: Double
  public let height: Double

  public init(width: Double, height: Double) {
    self.width = width.isFinite ? max(0, width) : 0
    self.height = height.isFinite ? max(0, height) : 0
  }
}

public struct HUDOverlayFrame: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x.isFinite ? x : 0
    self.y = y.isFinite ? y : 0
    self.width = width.isFinite ? max(0, width) : 0
    self.height = height.isFinite ? max(0, height) : 0
  }
}

/// Exact interactive shape for a vertical-pulse control: the visible circle
/// expanded by the forgiving pointer margin. Both the AppKit interactive guard
/// and the SwiftUI Button hit shape must be governed by this single circle so
/// that no point accepted by one surface is inert in the other.
public struct HUDVerticalControlHitRegion: Equatable, Sendable {
  public let centerX: Double
  public let centerY: Double
  public let radius: Double

  public init(centerX: Double, centerY: Double, radius: Double) {
    self.centerX = centerX.isFinite ? centerX : 0
    self.centerY = centerY.isFinite ? centerY : 0
    self.radius = radius.isFinite ? max(0, radius) : 0
  }

  public func contains(pointX: Double, pointY: Double) -> Bool {
    let dx = pointX - centerX
    let dy = pointY - centerY
    return dx * dx + dy * dy <= radius * radius
  }

  /// Bounding square; same geometry as `verticalControlHitFrame`.
  public var boundingFrame: HUDOverlayFrame {
    HUDOverlayFrame(
      x: centerX - radius,
      y: centerY - radius,
      width: 2 * radius,
      height: 2 * radius
    )
  }
}

public extension HUDQuickSwitcherLayout {

  /// Returns the exact vector-outline correction for a rounded semibold glyph.
  ///
  /// The result is the ink-center displacement from the typographic advance
  /// center. Callers subtract it from their frame center so the rendered ink
  /// lands on the control's policy center.
  static func glyphOutlineCorrection(
    for label: String,
    fontSize: Double
  ) -> HUDGlyphOutlineCorrection {
    guard fontSize.isFinite, fontSize > 0, !label.isEmpty else {
      return .zero
    }
    let key = OutlineCorrectionKey(label: label, fontSize: fontSize)
    glyphCacheLock.lock()
    defer { glyphCacheLock.unlock() }
    if let cached = outlineCorrectionCache[key] {
      return cached
    }
    let correction = measureGlyphOutlineCorrection(
      for: label,
      fontSize: fontSize
    )
    outlineCorrectionCache[key] = correction
    return correction
  }

  /// Generates a transparent, template-ready glyph image whose raster ink
  /// center is aligned to the logical frame center. The image is cached by
  /// label, font size, logical frame size, and display scale. `forceFallback`
  /// is a test seam that skips generation so callers can exercise Text fallback.
  static func glyphRasterImage(
    for label: String,
    fontSize: Double,
    frameLogicalSize: HUDOverlaySize,
    backingScale: Double,
    forceFallback: Bool = false
  ) -> CGImage? {
    guard
      !forceFallback,
      fontSize.isFinite,
      fontSize > 0,
      !label.isEmpty,
      frameLogicalSize.width.isFinite,
      frameLogicalSize.height.isFinite,
      frameLogicalSize.width > 0,
      frameLogicalSize.height > 0,
      backingScale.isFinite,
      backingScale > 0
    else {
      return nil
    }
    let normalizedScale = min(4, max(1, backingScale))
    let key = GlyphRasterImageKey(
      label: label,
      fontSize: fontSize,
      width: frameLogicalSize.width,
      height: frameLogicalSize.height,
      backingScale: normalizedScale
    )
    glyphCacheLock.lock()
    defer { glyphCacheLock.unlock() }
    if let cached = glyphRasterImageCache[key] {
      return cached
    }
    guard let image = measureGlyphRasterImage(
      for: label,
      fontSize: fontSize,
      frameLogicalSize: frameLogicalSize,
      backingScale: normalizedScale
    ) else {
      return nil
    }
    glyphRasterImageCache[key] = image
    return image
  }
  static let promptSlotCount = 5
  static let promptSlotButtonWidth = 17.0
  static let promptSlotSpacing = 3.0
  static let overlayShadowPad = 6.0

  static func localizedSpeechLanguageName(
    for code: String,
    language: UILanguagePreference,
    systemLocale: Locale
  ) -> String {
    AppText.localizedSpeechLanguageName(
      for: code,
      language: language,
      systemLocale: systemLocale
    )
  }

  static func overlayVisualScale(for scale: Double) -> Double {
    if scale <= 1 {
      return 0.88 + 0.12 * normalized(scale, from: 0.8, to: 1)
    }
    return 1 + 0.12 * smoothStep(normalized(scale, from: 1, to: 1.6))
  }

  static func promptBarHeight(for scale: Double) -> Double {
    18 * overlayVisualScale(for: scale)
  }

  static func promptBarSpacing(for scale: Double) -> Double {
    4 * overlayVisualScale(for: scale)
  }

  static func promptBarWidth(for scale: Double) -> Double {
    let visualScale = overlayVisualScale(for: scale)
    return Double(promptSlotCount) * promptSlotButtonWidth * visualScale
      + Double(promptSlotCount - 1) * promptSlotSpacing(for: scale)
  }

  /// Vertical Pulse three-zone rails, listening mode: the prompt slots form a
  /// column hugging the panel's left edge and the humor slider becomes a
  /// vertical rail on the right edge. Both rails share one height so they
  /// read as a balanced pair flanking the untouched pulse capsule.
  ///
  /// The left rail is one slot-button wide.
  static func promptRailColumnWidth(for scale: Double) -> Double {
    promptSlotButtonWidth * overlayVisualScale(for: scale)
  }

  /// The rail column fits the same five 17pt targets at 3pt spacing as the
  /// horizontal prompt row, rotated ninety degrees — so its height equals
  /// the horizontal row's width.
  static func promptRailColumnHeight(for scale: Double) -> Double {
    promptBarWidth(for: scale)
  }

  /// Thickness of the vertical humor rail.
  static func humorRailWidth(for scale: Double) -> Double {
    16 * overlayVisualScale(for: scale)
  }

  /// The humor rail's height matches the prompt rail's column height exactly:
  /// higher knob position always means a higher humor level.
  static func humorRailHeight(for scale: Double) -> Double {
    promptRailColumnHeight(for: scale)
  }

  /// Visible gap between a rail and the capsule silhouette.
  static func railGap(for scale: Double) -> Double {
    8 * overlayVisualScale(for: scale)
  }

  /// Forgiving pointer margin expanding each rail's interactive strip beyond
  /// its visible rail. Kept small so the strips never reach the capsule's
  /// circular language/target hit regions, which stay authoritative.
  static func railStripPad(for scale: Double) -> Double {
    5 * overlayVisualScale(for: scale)
  }

  /// Left extent reserved for the prompt rail in front of the capsule
  /// silhouette: rail column width plus its separating gap.
  static func promptRailExtent(for scale: Double) -> Double {
    promptRailColumnWidth(for: scale) + railGap(for: scale)
  }

  /// Right extent reserved for the humor rail behind the capsule silhouette.
  static func humorRailExtent(for scale: Double) -> Double {
    humorRailWidth(for: scale) + railGap(for: scale)
  }

  /// Vertical Pulse grows horizontally around its main capsule so the left
  /// prompt rail and the right humor rail fit without touching the capsule's
  /// height, controls, or edges.
  static func verticalPulsePanelWidth(
    baseWidth: Double,
    scale: Double,
    showsPromptBar: Bool,
    showsHumorSlider: Bool = false
  ) -> Double {
    var width = baseWidth
    if showsPromptBar {
      width += promptRailExtent(for: scale)
    }
    if showsHumorSlider {
      width += humorRailExtent(for: scale)
    }
    return width
  }

  /// Computes overlay geometry with scalar values only. The app target converts
  /// these values to AppKit rectangles after it has applied its screen origin.
  static func overlayPanelSize(
    for scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDOverlaySize {
    let below = normalized(scale, from: 0.8, to: 1)
    let above = smoothStep(normalized(scale, from: 1, to: 1.6))
    let visualScale = overlayVisualScale(for: scale)

    let listeningSize: HUDOverlaySize
    switch style {
    case .capsule:
      listeningSize = scale <= 1
        ? HUDOverlaySize(width: 94 + 6 * below, height: 38 + 6 * below)
        : HUDOverlaySize(width: 100 + 54 * above, height: 44 + 8 * above)
    case .tech:
      listeningSize = scale <= 1
        ? HUDOverlaySize(width: 105 + 13 * below, height: 40 + 6 * below)
        : HUDOverlaySize(width: 118 + 42 * above, height: 46 + 8 * above)
    case .vertical:
      let baseWidth = scale <= 1 ? 52 + 2 * below : 54 + 6 * above
      let baseHeight = scale <= 1 ? 100 + 14 * below : 114 + 27 * above
      listeningSize = HUDOverlaySize(
        width: verticalPulsePanelWidth(
          baseWidth: baseWidth,
          scale: scale,
          showsPromptBar: showsPromptBar,
          showsHumorSlider: showsHumorSlider
        ),
        height: baseHeight
      )
    }

    guard !isProcessing else {
      switch style {
      case .capsule:
        return HUDOverlaySize(
          width: classicProcessingSpectrumWidth(for: scale) + 20 * visualScale,
          height: listeningSize.height
        )
      case .tech:
        return HUDOverlaySize(
          width: techProcessingSpectrumWidth(for: scale) + 22 * visualScale,
          height: listeningSize.height
        )
      case .vertical:
        return HUDOverlaySize(
          width: listeningSize.width,
          height: verticalSpectrumHeight(for: scale) + 20 * visualScale
        )
      }
    }

    var totalHeight = listeningSize.height
    if style != .vertical {
      // Capsule and tech stack accessories vertically above/below the pill.
      // Vertical Pulse parks both accessories in the horizontal rails, so
      // its rails must never inflate the panel height.
      if showsPromptBar {
        totalHeight += promptBarSpacing(for: scale) + promptBarHeight(for: scale)
      }
      if showsHumorSlider {
        totalHeight += 4 * visualScale + 24 * visualScale
      }
    }
    return HUDOverlaySize(width: listeningSize.width, height: totalHeight)
  }

  /// Returns the visible main capsule frame in panel-local bottom-left scalar
  /// coordinates. Accessories do not participate in this frame.
  static func mainCapsuleFrame(
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool
  ) -> HUDOverlayFrame {
    let visualScale = overlayVisualScale(for: scale)
    let shadow = overlayShadowPad * visualScale
    let capsuleSize = overlayPanelSize(
      for: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: false,
      showsHumorSlider: false
    )
    let width = max(1, capsuleSize.width - 2 * shadow)
    let height = max(1, capsuleSize.height - 2 * shadow)
    // Vertical Pulse moves its humor rail to the panel's right edge, so the
    // capsule is never lifted vertically; capsule and tech still raise the
    // capsule above their bottom humor band.
    let humorOffset = showsHumorSlider && style != .vertical
      ? 4 * visualScale + 24 * visualScale
      : 0
    let x: Double
    if style == .vertical {
      // Three-zone composition: the capsule silhouette sits directly behind
      // the reserved left rail extent instead of the panel center, keeping
      // shadow | rail | gap | capsule | gap | rail | shadow zone ordering.
      x = shadow + (showsPromptBar ? promptRailExtent(for: scale) : 0)
    } else {
      x = shadow + (panelSize.width - capsuleSize.width) / 2
    }
    return HUDOverlayFrame(
      x: x,
      y: shadow + humorOffset,
      width: width,
      height: height
    )
  }

  /// Reframes the transparent panel around the current screen capsule frame.
  /// The returned panel origin is exact, so the full capsule frame is invariant
  /// even when the panel gains or loses accessory rows.
  static func anchoredPanelFrame(
    previousCapsuleScreenFrame: HUDOverlayFrame,
    newPanelSize: HUDOverlaySize,
    newLocalCapsuleFrame: HUDOverlayFrame
  ) -> HUDOverlayFrame {
    HUDOverlayFrame(
      x: previousCapsuleScreenFrame.x - newLocalCapsuleFrame.x,
      y: previousCapsuleScreenFrame.y - newLocalCapsuleFrame.y,
      width: newPanelSize.width,
      height: newPanelSize.height
    )
  }

  static func screenCapsuleFrame(
    panelFrame: HUDOverlayFrame,
    localCapsuleFrame: HUDOverlayFrame
  ) -> HUDOverlayFrame {
    HUDOverlayFrame(
      x: panelFrame.x + localCapsuleFrame.x,
      y: panelFrame.y + localCapsuleFrame.y,
      width: localCapsuleFrame.width,
      height: localCapsuleFrame.height
    )
  }

  /// Base diameter of a round control button (language A / target D).
  static let controlButtonDiameter = 24.0

  /// Capsule content inset used to anchor controls inside the pill, scaled.
  static func capsuleContentPad(for scale: Double) -> Double {
    4 * overlayVisualScale(for: scale)
  }

  /// Pointer forgiving margin around the visible control frame, scaled.
  /// The forgiving band stays within the approved 8–10pt range at every
  /// supported HUD visual scale so the hit area never overgrows.
  static func controlHitMargin(for scale: Double) -> Double {
    min(10, 10 * overlayVisualScale(for: scale))
  }

  /// Diameter of a round control button, including capsule style scaling.
  static func controlDiameter(for scale: Double, style: OverlayHUDStyle) -> Double {
    switch style {
    case .capsule:
      if scale <= 1 {
        return 23.5 + 1.5 * normalized(scale, from: 0.8, to: 1)
      }
      return 25 + 3 * smoothStep(normalized(scale, from: 1, to: 1.6))
    case .tech, .vertical:
      return controlButtonDiameter * overlayVisualScale(for: scale)
    }
  }

  /// Exact circular interactive shape for a vertical-pulse control slot.
  /// Panels and SwiftUI consume this one shared circle, so their hit areas can
  /// never disagree (the bounding square alone would accept inert corners).
  static func verticalControlHitRegion(
    slot: HUDVerticalControlSlot,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDVerticalControlHitRegion {
    let visualScale = overlayVisualScale(for: scale)
    let shadowInset = overlayShadowPad * visualScale
    let pill = overlayPanelSize(
      for: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: false,
      showsHumorSlider: false
    )
    let visibleCapsuleWidth = max(1, pill.width - 2 * shadowInset)
    let visibleCapsuleHeight = max(1, pill.height - 2 * shadowInset)
    // The three-zone layout parks accessories in the side rails; the pill
    // keeps its reserved left extent and its bottom shadow seat. The shadow
    // inset is added below, when the visible capsule is derived.
    let pillOriginX = showsPromptBar ? promptRailExtent(for: scale) : 0
    let pillBottom = shadowInset
    let diameter = controlDiameter(for: scale, style: style)
    let margin = controlHitMargin(for: scale)
    let pad = capsuleContentPad(for: scale)
    let centerX = pillOriginX + shadowInset + visibleCapsuleWidth / 2
    let centerY: Double
    switch slot {
    case .language:
      centerY = pillBottom + visibleCapsuleHeight - pad - diameter / 2
    case .target:
      centerY = pillBottom + pad + diameter / 2
    }
    return HUDVerticalControlHitRegion(
      centerX: centerX,
      centerY: centerY,
      radius: diameter / 2 + margin
    )
  }

  /// Hit frame (panel-local, bottom-left origin) for a control slot in the
  /// vertical pulse layout. Both the AppKit hit-testing and the tests consume
  /// this single policy so they can never drift apart. The frame is derived
  /// from the shared circular hit region; it is the bounding square only, and
  /// point containment outside the circle must use `verticalControlHitRegion`.
  static func verticalControlHitFrame(
    slot: HUDVerticalControlSlot,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDOverlayFrame {
    verticalControlHitRegion(
      slot: slot,
      panelSize: panelSize,
      scale: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: showsPromptBar,
      showsHumorSlider: showsHumorSlider
    ).boundingFrame
  }

  /// Control circle hit region (panel-local, bottom-left origin) for any style.
  static func controlHitRegion(
    slot: HUDVerticalControlSlot,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool = false,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDVerticalControlHitRegion {
    guard style != .vertical else {
      return verticalControlHitRegion(
        slot: slot,
        panelSize: panelSize,
        scale: scale,
        style: style,
        isProcessing: isProcessing,
        showsPromptBar: showsPromptBar,
        showsHumorSlider: showsHumorSlider
      )
    }

    let visualScale = overlayVisualScale(for: scale)
    let shadowInset = overlayShadowPad * visualScale
    let pill = overlayPanelSize(
      for: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: false,
      showsHumorSlider: false
    )
    let visibleCapsuleWidth = max(1, pill.width - 2 * shadowInset)
    let visibleCapsuleHeight = max(1, pill.height - 2 * shadowInset)
    let pillOriginX = shadowInset + (panelSize.width - pill.width) / 2
    let humorOffset = showsHumorSlider ? 4 * visualScale + 24 * visualScale : 0
    let pillBottom = shadowInset + humorOffset
    let diameter = controlDiameter(for: scale, style: style)
    let margin = controlHitMargin(for: scale)
    let pad = style == .tech ? 5 * visualScale : capsuleContentPad(for: scale)

    let centerX: Double
    switch slot {
    case .language:
      centerX = pillOriginX + pad + diameter / 2
    case .target:
      centerX = pillOriginX + visibleCapsuleWidth - pad - diameter / 2
    }
    let centerY = pillBottom + visibleCapsuleHeight / 2

    return HUDVerticalControlHitRegion(
      centerX: centerX,
      centerY: centerY,
      radius: diameter / 2 + margin
    )
  }

  /// Legacy AppKit hit frame for a control in the horizontal capsule/tech
  /// layouts. The asymmetric expansion is intentional: it preserves the
  /// existing pointer band while moving the formula out of the executable
  /// target. Vertical Pulse keeps its circular hit frame.
  static func controlHitFrame(
    slot: HUDVerticalControlSlot,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool = false,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDOverlayFrame {
    guard style != .vertical else {
      return verticalControlHitFrame(
        slot: slot,
        panelSize: panelSize,
        scale: scale,
        style: style,
        isProcessing: isProcessing,
        showsPromptBar: showsPromptBar,
        showsHumorSlider: showsHumorSlider
      )
    }

    let visualScale = overlayVisualScale(for: scale)
    let shadowInset = overlayShadowPad * visualScale
    let pillSize = overlayPanelSize(
      for: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: false,
      showsHumorSlider: false
    )
    let capsuleFrame = mainCapsuleFrame(
      panelSize: panelSize,
      scale: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: showsPromptBar,
      showsHumorSlider: showsHumorSlider
    )
    let pillOriginX = capsuleFrame.x - shadowInset
    let pillBottom = capsuleFrame.y
    let diameter = controlDiameter(for: scale, style: style)
    let x: Double
    switch slot {
    case .language:
      x = pillOriginX - 4 * visualScale
    case .target:
      let targetX = pillOriginX + pillSize.width - diameter - shadowInset
      x = targetX - 4 * visualScale
    }
    return HUDOverlayFrame(
      x: x,
      y: pillBottom - 4 * visualScale,
      width: diameter + 12 * visualScale,
      height: diameter + 8 * visualScale
    )
  }


  /// Visible control frame (panel-local, bottom-left origin) for any style.
  static func controlFrame(
    slot: HUDVerticalControlSlot,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool = false,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> HUDOverlayFrame {
    let region = controlHitRegion(
      slot: slot,
      panelSize: panelSize,
      scale: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: showsPromptBar,
      showsHumorSlider: showsHumorSlider
    )
    let diameter = controlDiameter(for: scale, style: style)
    return HUDOverlayFrame(
      x: region.centerX - diameter / 2,
      y: region.centerY - diameter / 2,
      width: diameter,
      height: diameter
    )
  }

  /// Outline center for the glyph rendered inside a control button
  /// (panel-local coordinates). The hit-region geometry remains untouched.
  static func controlGlyphCenter(
    slot: HUDVerticalControlSlot,
    label: String,
    panelSize: HUDOverlaySize,
    scale: Double,
    style: OverlayHUDStyle,
    isProcessing: Bool = false,
    showsPromptBar: Bool = false,
    showsHumorSlider: Bool = false
  ) -> (x: Double, y: Double) {
    let region = controlHitRegion(
      slot: slot,
      panelSize: panelSize,
      scale: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: showsPromptBar,
      showsHumorSlider: showsHumorSlider
    )
    let correction = glyphOutlineCorrection(
      for: label,
      fontSize: controlGlyphFontSize(for: scale, style: style)
    )
    return (
      x: region.centerX - correction.dx,
      y: region.centerY - correction.dy
    )
  }

  /// Local outline center of a control glyph within its button frame.
  static func controlGlyphLocalCenter(
    for scale: Double,
    style: OverlayHUDStyle,
    label: String
  ) -> (x: Double, y: Double) {
    let diameter = controlDiameter(for: scale, style: style)
    let correction = glyphOutlineCorrection(
      for: label,
      fontSize: controlGlyphFontSize(for: scale, style: style)
    )
    return (
      x: diameter / 2 - correction.dx,
      y: diameter / 2 - correction.dy
    )
  }


  /// Spacing between adjacent prompt buttons, scaled by the shared visual
  /// scale used by both horizontal and vertical prompt rails.
  static func promptSlotSpacing(for scale: Double) -> Double {
    promptSlotSpacing * overlayVisualScale(for: scale)
  }

  /// Button size of an individual prompt slot button (width == height).
  static func promptSlotButtonSize(for scale: Double) -> Double {
    promptSlotButtonWidth * overlayVisualScale(for: scale)
  }

  /// Font size for prompt slot labels, kept beside the button-size policy.
  static func promptSlotGlyphFontSize(for scale: Double) -> Double {
    11 * overlayVisualScale(for: scale)
  }

  /// Local outline center of a prompt slot glyph within its button frame.
  static func promptSlotGlyphLocalCenter(
    for scale: Double,
    label: String
  ) -> (x: Double, y: Double) {
    let size = promptSlotButtonSize(for: scale)
    let correction = glyphOutlineCorrection(
      for: label,
      fontSize: promptSlotGlyphFontSize(for: scale)
    )
    return (
      x: size / 2 - correction.dx,
      y: size / 2 - correction.dy
    )
  }

  /// Interactive strip (panel-local, bottom-left origin) for the left prompt
  /// rail in the vertical three-zone layout. The strip is the visible rail
  /// column expanded by the forgiving strip pad, vertically centered on the
  /// capsule, and never crossing into the capsule silhouette. The AppKit
  /// interactive guard consults it only while the prompt rail is presented;
  /// SwiftUI renders the rail's buttons inside the same band, so the two
  /// surfaces stay coherent by construction.
  static func verticalPromptRailStripFrame(
    panelSize: HUDOverlaySize,
    scale: Double
  ) -> HUDOverlayFrame {
    let visualScale = overlayVisualScale(for: scale)
    let shadow = overlayShadowPad * visualScale
    let pad = railStripPad(for: scale)
    let railWidth = promptRailColumnWidth(for: scale)
    let silhouetteLeft = shadow + promptRailExtent(for: scale)
    let stripHeight = promptRailColumnHeight(for: scale) + 8 * visualScale
    let x = max(0, shadow - pad)
    let right = min(shadow + railWidth + pad, silhouetteLeft)
    return HUDOverlayFrame(
      x: x,
      y: max(0, (panelSize.height - stripHeight) / 2),
      width: max(0, right - x),
      height: min(stripHeight, panelSize.height)
    )
  }

  /// Interactive strip (panel-local, bottom-left origin) for the right humor
  /// rail. It mirrors `verticalPromptRailStripFrame` exactly — same height,
  /// same vertical center — so the two rails stay a balanced pair, and the
  /// slider height equals the prompt column height by construction.
  static func verticalHumorRailStripFrame(
    panelSize: HUDOverlaySize,
    scale: Double
  ) -> HUDOverlayFrame {
    let visualScale = overlayVisualScale(for: scale)
    let shadow = overlayShadowPad * visualScale
    let pad = railStripPad(for: scale)
    let railWidth = humorRailWidth(for: scale)
    let silhouetteRight = max(shadow, panelSize.width - shadow - humorRailExtent(for: scale))
    let stripHeight = humorRailHeight(for: scale) + 8 * visualScale
    let left = max(silhouetteRight, panelSize.width - shadow - railWidth - pad)
    let right = min(panelSize.width, panelSize.width - shadow + pad)
    return HUDOverlayFrame(
      x: left,
      y: max(0, (panelSize.height - stripHeight) / 2),
      width: max(0, right - left),
      height: min(stripHeight, panelSize.height)
    )
  }

  /// Maximum allowed width of the language picker popover. Kept compact so it
  /// does not visually overwhelm the HUD.
  static let languagePickerMaxWidth = 196.0
}

/// Which control slot a vertical-pulse hit rect belongs to.
public enum HUDVerticalControlSlot: Equatable, Sendable {
  case language
  case target
}

private extension HUDQuickSwitcherLayout {
  static func controlGlyphFontSize(
    for scale: Double,
    style: OverlayHUDStyle
  ) -> Double {
    12 * controlDiameter(for: scale, style: style) / controlButtonDiameter
  }

  static func measureGlyphOutlineCorrection(
    for label: String,
    fontSize: Double
  ) -> HUDGlyphOutlineCorrection {
    let pointSize = CGFloat(fontSize)
    guard pointSize.isFinite, pointSize > 0 else {
      return .zero
    }

    let baseDescriptor = NSFont.systemFont(ofSize: pointSize, weight: .semibold).fontDescriptor
    let roundedDescriptor = baseDescriptor.withDesign(.rounded) ?? baseDescriptor
    let ctFont = CTFontCreateWithFontDescriptor(roundedDescriptor, pointSize, nil)
#if DEBUG
    assert(
      (CTFontCopyPostScriptName(ctFont) as String).contains("Rounded"),
      "HUD outline metrics require the rounded SF font"
    )
#endif

    var characters = Array(label.utf16)
    guard !characters.isEmpty else {
      return .zero
    }

    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    let resolved = characters.withUnsafeMutableBufferPointer { charactersBuffer in
      glyphs.withUnsafeMutableBufferPointer { glyphsBuffer in
        guard
          let charactersBase = charactersBuffer.baseAddress,
          let glyphsBase = glyphsBuffer.baseAddress
        else {
          return false
        }
        return CTFontGetGlyphsForCharacters(
          ctFont,
          charactersBase,
          glyphsBase,
          charactersBuffer.count
        )
      }
    }
    guard resolved, !glyphs.contains(0) else {
      return .zero
    }

    guard let metrics = glyphs.withUnsafeBufferPointer({
      glyphsBuffer -> (CGRect, Double)? in
      guard let glyphsBase = glyphsBuffer.baseAddress else {
        return nil
      }
      var outlineRects = [CGRect](repeating: .zero, count: glyphsBuffer.count)
      guard let outline = outlineRects.withUnsafeMutableBufferPointer({
        rectsBuffer -> CGRect? in
        guard let rectsBase = rectsBuffer.baseAddress else {
          return nil
        }
        return CTFontGetBoundingRectsForGlyphs(
          ctFont,
          .horizontal,
          glyphsBase,
          rectsBase,
          glyphsBuffer.count
        )
      }) else {
        return nil
      }
      let success =
        outline.width.isFinite
        && outline.height.isFinite
        && outline.width > 0
        && outline.height > 0
      guard success else {
        return nil
      }
      let advance = CTFontGetAdvancesForGlyphs(
        ctFont,
        .horizontal,
        glyphsBase,
        nil,
        glyphsBuffer.count
      )
      guard advance.isFinite else {
        return nil
      }
      return (outline, advance)
    }) else {
      return .zero
    }

    let (outline, advance) = metrics
    let dx = Double(outline.midX) - advance / 2
    let dy = (
      (Double(CTFontGetAscent(ctFont)) - Double(CTFontGetDescent(ctFont))) / 2
    ) - Double(outline.midY)
    guard dx.isFinite, dy.isFinite else {
      return .zero
    }
    return HUDGlyphOutlineCorrection(dx: dx, dy: dy)
  }

  static func measureGlyphRasterImage(
    for label: String,
    fontSize: Double,
    frameLogicalSize: HUDOverlaySize,
    backingScale: Double
  ) -> CGImage? {
    let pointSize = CGFloat(fontSize)
    guard pointSize.isFinite, pointSize > 0 else {
      return nil
    }
    let baseDescriptor = NSFont.systemFont(ofSize: pointSize, weight: .semibold).fontDescriptor
    let roundedDescriptor = baseDescriptor.withDesign(.rounded) ?? baseDescriptor
    let ctFont = CTFontCreateWithFontDescriptor(roundedDescriptor, pointSize, nil)
#if DEBUG
    assert(
      (CTFontCopyPostScriptName(ctFont) as String).contains("Rounded"),
      "HUD raster glyphs require the rounded SF font"
    )
#endif
    var characters = Array(label.utf16)
    guard !characters.isEmpty else {
      return nil
    }
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    let resolved = characters.withUnsafeMutableBufferPointer { charactersBuffer in
      glyphs.withUnsafeMutableBufferPointer { glyphsBuffer in
        guard
          let charactersBase = charactersBuffer.baseAddress,
          let glyphsBase = glyphsBuffer.baseAddress
        else {
          return false
        }
        return CTFontGetGlyphsForCharacters(
          ctFont,
          charactersBase,
          glyphsBase,
          charactersBuffer.count
        )
      }
    }
    guard resolved, glyphs.count == 1, !glyphs.contains(0) else {
      return nil
    }
    guard let metrics = glyphs.withUnsafeBufferPointer({
      glyphsBuffer -> (CGRect, Double)? in
      guard let glyphsBase = glyphsBuffer.baseAddress else {
        return nil
      }
      var outlineRects = [CGRect](repeating: .zero, count: glyphsBuffer.count)
      guard let outline = outlineRects.withUnsafeMutableBufferPointer({
        rectsBuffer -> CGRect? in
        guard let rectsBase = rectsBuffer.baseAddress else {
          return nil
        }
        return CTFontGetBoundingRectsForGlyphs(
          ctFont,
          .horizontal,
          glyphsBase,
          rectsBase,
          glyphsBuffer.count
        )
      }) else {
        return nil
      }
      guard
        outline.width.isFinite,
        outline.height.isFinite,
        outline.width > 0,
        outline.height > 0
      else {
        return nil
      }
      let advance = CTFontGetAdvancesForGlyphs(
        ctFont,
        .horizontal,
        glyphsBase,
        nil,
        glyphsBuffer.count
      )
      guard advance.isFinite else {
        return nil
      }
      return (outline, advance)
    }) else {
      return nil
    }

    let (outline, advance) = metrics
    let vectorCorrection = HUDGlyphOutlineCorrection(
      dx: Double(outline.midX) - advance / 2,
      dy: (
        (Double(CTFontGetAscent(ctFont)) - Double(CTFontGetDescent(ctFont))) / 2
      ) - Double(outline.midY)
    )
    let pixelWidth = Int((frameLogicalSize.width * backingScale).rounded())
    let pixelHeight = Int((frameLogicalSize.height * backingScale).rounded())
    guard
      pixelWidth > 0,
      pixelHeight > 0,
      pixelWidth <= 4096,
      pixelHeight <= 4096
    else {
      return nil
    }

    let targetX = Double(pixelWidth - 1) / (2 * backingScale)
    let targetY = Double(pixelHeight - 1) / (2 * backingScale)
    let lineBoxCenter = (
      Double(CTFontGetAscent(ctFont)) - Double(CTFontGetDescent(ctFont))
    ) / 2
    let thresholds: [UInt8] = [16, 51, 102, 153]
    let targetPixelY = Double(pixelHeight - 1) - targetY * backingScale
    let pixelStep = 0.5 / backingScale
    func render(
      correction: HUDGlyphOutlineCorrection
    ) -> (CGContext, [HUDGlyphOutlineCorrection])? {
      guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: pixelWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
        return nil
      }
      context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.saveGState()
      context.scaleBy(x: backingScale, y: backingScale)
      var glyph = glyphs[0]
      var position = CGPoint(
        x: targetX - advance / 2 - correction.dx,
        y: targetY - lineBoxCenter + correction.dy
      )
      CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)
      context.restoreGState()
      guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }

      var residuals: [HUDGlyphOutlineCorrection] = []
      residuals.reserveCapacity(thresholds.count + 1)
      for threshold in thresholds {
        var minX = pixelWidth
        var minY = pixelHeight
        var maxX = -1
        var maxY = -1
        for y in 0..<pixelHeight {
          for x in 0..<pixelWidth {
            let alpha = data[y * pixelWidth * 4 + x * 4 + 3]
            guard alpha > threshold else {
              continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
          }
        }
        guard maxX >= minX, maxY >= minY else {
          return nil
        }
        residuals.append(
          HUDGlyphOutlineCorrection(
            dx: (Double(minX + maxX) / 2 - targetX * backingScale) / backingScale,
            dy: (Double(minY + maxY) / 2 - targetPixelY) / backingScale
          )
        )
      }
      var total = 0.0
      var weightedX = 0.0
      var weightedY = 0.0
      for y in 0..<pixelHeight {
        for x in 0..<pixelWidth {
          let weight = Double(data[y * pixelWidth * 4 + x * 4 + 3])
          guard weight > 16 else {
            continue
          }
          total += weight
          weightedX += Double(x) * weight
          weightedY += Double(y) * weight
        }
      }
      guard total > 0 else {
        return nil
      }
      residuals.append(
        HUDGlyphOutlineCorrection(
          dx: (weightedX / total - targetX * backingScale) / backingScale,
          dy: (weightedY / total - targetPixelY) / backingScale
        )
      )
      return (context, residuals)
    }

    var bestContext: CGContext?
    var bestBboxScore = Double.greatestFiniteMagnitude
    var bestWeightedScore = Double.greatestFiniteMagnitude
    for horizontal in -6...6 {
      for vertical in -6...6 {
        let candidate = HUDGlyphOutlineCorrection(
          dx: vectorCorrection.dx + Double(horizontal) * pixelStep,
          dy: vectorCorrection.dy + Double(vertical) * pixelStep
        )
        guard let (context, residuals) = render(correction: candidate) else {
          continue
        }
        let bboxScore = residuals.dropLast().reduce(0.0) { partial, residual in
          max(
            partial,
            abs(residual.dx * backingScale),
            abs(residual.dy * backingScale)
          )
        }
        let weightedScore = residuals.last.map {
          max(
            abs($0.dx * backingScale),
            abs($0.dy * backingScale)
          )
        } ?? Double.greatestFiniteMagnitude
        if weightedScore < bestWeightedScore
          || (weightedScore == bestWeightedScore && bboxScore < bestBboxScore)
        {
          bestBboxScore = bboxScore
          bestWeightedScore = weightedScore
          bestContext = context
        }
      }
    }
    return bestContext?.makeImage()
  }

  static func classicProcessingSpectrumWidth(for scale: Double) -> Double {
    if scale <= 1 {
      return 44 + 4 * normalized(scale, from: 0.8, to: 1)
    }
    return 48 + 28 * smoothStep(normalized(scale, from: 1, to: 1.6))
  }

  static func techProcessingSpectrumWidth(for scale: Double) -> Double {
    if scale <= 1 {
      return 38 + 4 * normalized(scale, from: 0.8, to: 1)
    }
    return 42 + 30 * smoothStep(normalized(scale, from: 1, to: 1.6))
  }

  static func verticalSpectrumHeight(for scale: Double) -> Double {
    if scale <= 1 {
      return 34 + 6 * normalized(scale, from: 0.8, to: 1)
    }
    return 40 + 18 * smoothStep(normalized(scale, from: 1, to: 1.6))
  }

  static func normalized(_ value: Double, from lower: Double, to upper: Double) -> Double {
    guard upper > lower else { return 0 }
    return min(1, max(0, (value - lower) / (upper - lower)))
  }

  static func smoothStep(_ value: Double) -> Double {
    value * value * (3 - 2 * value)
  }
}
