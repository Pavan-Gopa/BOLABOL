import Foundation

public enum SidebarLayoutMetrics {
    public static let minimumWidth: Double = 220
    public static let idealWidth: Double = 280
    public static let maximumWindowFraction: Double = 1.0 / 3.0

    public static func maximumWidth(forWindowWidth windowWidth: Double) -> Double {
        max(minimumWidth, floor(windowWidth * maximumWindowFraction))
    }
}
