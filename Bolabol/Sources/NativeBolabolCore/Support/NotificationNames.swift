import Foundation

// Core support: shared notification names used by app and Core stores.
// Raw values remain stable so existing retention observers keep receiving events.
public extension Notification.Name {
    static let didChangeAudioRetentionSettings = Notification.Name("didChangeAudioRetentionSettings")
}
