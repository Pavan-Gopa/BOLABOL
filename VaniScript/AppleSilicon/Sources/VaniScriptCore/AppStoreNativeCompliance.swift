public enum AppStoreNativeCompliance {
    public static let allowedRuntimeFamilies = [
        "Swift",
        "SwiftUI",
        "AppKit",
        "AVFoundation",
        "Core ML",
        "Metal",
        "MLX Swift",
    ]

    public static let forbiddenBundleNameFragments = [
        "python",
        "node",
        "node_modules",
        "electron",
        "chromium",
        "llama",
        "llamacpp",
    ]

    public static func isAllowedBundlePath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        return !forbiddenBundleNameFragments.contains { normalized.contains($0) }
    }
}
