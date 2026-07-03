import Foundation

public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.vaniscript.logger", qos: .utility)

    private var logFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("VaniScript/logs", isDirectory: true)
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        return logDir.appendingPathComponent("app.log")
    }

    private init() {}

    public func log(_ message: String, level: LogLevel, settings: AppSettings? = nil) {
        let currentSettings = settings ?? AppSettings.defaults
        let settingsLevel = currentSettings.logLevel

        guard shouldLog(level, settingsLevel: settingsLevel) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        // Print to console
        print(line, terminator: "")

        // Keep crash diagnostics durable before entering long native model calls.
        let url = logFileURL
        logQueue.sync {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public func debug(_ message: String, settings: AppSettings? = nil) { log(message, level: .debug, settings: settings) }
    public func info(_ message: String, settings: AppSettings? = nil) { log(message, level: .info, settings: settings) }
    public func warn(_ message: String, settings: AppSettings? = nil) { log(message, level: .warn, settings: settings) }
    public func error(_ message: String, settings: AppSettings? = nil) { log(message, level: .error, settings: settings) }

    private func shouldLog(_ level: LogLevel, settingsLevel: LogLevel) -> Bool {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warn: 2, .error: 3]
        let levelVal = order[level] ?? 1
        let settingsVal = order[settingsLevel] ?? 1
        return levelVal >= settingsVal
    }

    public func getLogFileURL() -> URL {
        return logFileURL
    }

    public func getLogContents() -> String {
        var contents = ""
        logQueue.sync {
            contents = (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
        }
        return contents
    }

    public func clearLogs() {
        logQueue.sync {
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
    }
}
