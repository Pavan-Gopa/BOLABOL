import Foundation

/// Shared layout metrics for the provider quick switcher.
///
/// Used by SwiftUI list rendering and AppKit mouse hit-testing so both agree
/// on row geometry. Pure and unit-testable (no AppKit dependency).
public enum HUDQuickSwitcherLayout {
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
      + Double(promptSlotCount - 1) * promptSlotSpacing * visualScale
  }

  /// Vertical Pulse grows symmetrically around its main capsule so the full
  /// prompt row fits without shrinking its controls or masking its edges.
  static func verticalPulsePanelWidth(
    baseWidth: Double,
    scale: Double,
    showsPromptBar: Bool
  ) -> Double {
    guard showsPromptBar else { return baseWidth }
    let visualScale = overlayVisualScale(for: scale)
    return max(
      baseWidth,
      promptBarWidth(for: scale) + 2 * overlayShadowPad * visualScale
    )
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
          showsPromptBar: showsPromptBar
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
    if showsPromptBar {
      totalHeight += promptBarSpacing(for: scale) + promptBarHeight(for: scale)
    }
    if showsHumorSlider {
      totalHeight += 4 * visualScale + 24 * visualScale
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
    let humorOffset = showsHumorSlider
      ? 4 * visualScale + 24 * visualScale
      : 0
    return HUDOverlayFrame(
      x: shadow + (panelSize.width - capsuleSize.width) / 2,
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
  public static let controlButtonDiameter = 24.0

  /// Capsule content inset used to anchor controls inside the pill, scaled.
  public static func capsuleContentPad(for scale: Double) -> Double {
    4 * overlayVisualScale(for: scale)
  }

  /// Pointer forgiving margin around the visible control frame, scaled.
  /// The forgiving band stays within the approved 8–10pt range at every
  /// supported HUD visual scale so the hit area never overgrows.
  public static func controlHitMargin(for scale: Double) -> Double {
    min(10, 10 * overlayVisualScale(for: scale))
  }

  /// Diameter of a round control button, including capsule style scaling.
  public static func controlDiameter(for scale: Double, style: OverlayHUDStyle) -> Double {
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
  public static func verticalControlHitRegion(
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
    let humorOffset = showsHumorSlider
      ? 4 * visualScale + 24 * visualScale
      : 0
    let pill = overlayPanelSize(
      for: scale,
      style: style,
      isProcessing: isProcessing,
      showsPromptBar: false,
      showsHumorSlider: false
    )
    let visibleCapsuleWidth = max(1, pill.width - 2 * shadowInset)
    let visibleCapsuleHeight = max(1, pill.height - 2 * shadowInset)
    let pillOriginX = (panelSize.width - pill.width) / 2
    let pillBottom = shadowInset + humorOffset
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
  public static func verticalControlHitFrame(
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

  /// Maximum allowed width of the language picker popover. Kept compact so it
  /// does not visually overwhelm the HUD (was 280pt before the rejection).
  public static let languagePickerMaxWidth = 196.0
}

/// Which control slot a vertical-pulse hit rect belongs to.
public enum HUDVerticalControlSlot: Equatable, Sendable {
  case language
  case target
}

private extension HUDQuickSwitcherLayout {
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
