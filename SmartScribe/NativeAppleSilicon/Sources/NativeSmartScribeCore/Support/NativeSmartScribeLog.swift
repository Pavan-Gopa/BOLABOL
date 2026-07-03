import Foundation
import os

public enum NativeSmartScribeLog {
    public static let subsystem = "com.pavan.NativeSmartScribe"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let transcription = Logger(subsystem: subsystem, category: "transcription")
    public static let polishing = Logger(subsystem: subsystem, category: "polishing")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let models = Logger(subsystem: subsystem, category: "models")
}
