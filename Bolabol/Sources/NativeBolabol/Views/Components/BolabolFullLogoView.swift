import AppKit
import SwiftUI

struct BolabolFullLogoView: View {
    var height: CGFloat = 32

    var body: some View {
        Group {
            if let image = Self.fullLogoImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                HStack(spacing: 8) {
                    BolabolLogoView(size: height)
                    Text("BOLABOL")
                        .font(.system(size: height * 0.65, weight: .bold, design: .rounded))
                }
            }
        }
        .frame(height: height)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private static func fullLogoImage() -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: "BOLABOL_LOGO_Full",
                withExtension: "svg",
                subdirectory: "Logos"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        return image
    }
}
