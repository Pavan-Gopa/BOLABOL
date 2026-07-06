import AppKit
import SwiftUI

struct SmartScribeLogoView: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = Self.logoImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private static func logoImage() -> NSImage? {
        guard
            let url = Bundle.main.url(forResource: "New_Logo", withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        return image
    }
}
