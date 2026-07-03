import Foundation

enum AppBuildIdentity {
    static var current: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VaniScriptBuildID") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let url = Bundle.main.executableURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modifiedAt = attributes[.modificationDate] as? Date {
            return "dev-\(Int(modifiedAt.timeIntervalSince1970))"
        }
        return "development"
    }
}
