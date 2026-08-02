import SwiftUI

struct BlaboomLogoWithWordmarkView: View {
    var height: CGFloat = 24
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            BlaboomLogoView(size: height)
            BlaboomWordmarkView(height: height * 0.75)
        }
        .accessibilityHidden(true)
    }
}
