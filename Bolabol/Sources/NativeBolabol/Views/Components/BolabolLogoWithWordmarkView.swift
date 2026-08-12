import SwiftUI

struct BolabolLogoWithWordmarkView: View {
    var height: CGFloat = 24
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            BolabolLogoView(size: height)
            BolabolWordmarkView(height: height * 0.75)
        }
        .accessibilityHidden(true)
    }
}
