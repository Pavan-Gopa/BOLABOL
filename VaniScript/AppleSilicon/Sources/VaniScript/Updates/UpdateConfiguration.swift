import Foundation

/// Update subsystem constants and configuration values.
public enum UpdateConfiguration {
    /// The public feed URL for official VaniScript Apple Silicon updates.
    public static let defaultFeedURL = URL(string: "https://github.com/Pavan-Gopa/VaniScript/releases/latest/download/appcast.xml")!

    /// Info.plist key for the EdDSA public key.
    public static let publicKeyInfoKey = "SUPublicEDKey"

    /// Info.plist key for the update feed URL.
    public static let feedURLInfoKey = "SUFeedURL"

    /// UserDefaults key for user-configured automatic check preferences.
    public static let automaticChecksPreferenceKey = "SUEnableAutomaticChecks"
}
