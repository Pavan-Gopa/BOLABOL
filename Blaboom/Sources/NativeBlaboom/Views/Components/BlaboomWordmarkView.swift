import AppKit
import SwiftUI

struct BlaboomWordmarkView: View {
    var height: CGFloat = 20

    var body: some View {
        Group {
            if let image = Self.wordmarkImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("BLABOOM")
                    .font(.system(size: height * 0.75, weight: .bold, design: .rounded))
            }
        }
        .frame(height: height)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private static func wordmarkImage() -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: "BLABOOM_Wordmark",
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
