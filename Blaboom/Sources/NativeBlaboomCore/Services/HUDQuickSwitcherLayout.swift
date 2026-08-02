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
