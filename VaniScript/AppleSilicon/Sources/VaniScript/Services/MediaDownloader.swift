import Foundation
import VaniScriptCore

struct MediaDownloadResult: Sendable {
    let fileURL: URL
    let title: String?
}

enum MediaDownloadEvent: Sendable {
    case message(String)
    case progress(MediaDownloadProgress)
}

enum MediaDownloader {
    static func download(
        from rawURL: String,
        audioOnly: Bool = false,
        onEvent: @Sendable @escaping (MediaDownloadEvent) -> Void = { _ in }
    ) async throws -> MediaDownloadResult {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileManager = FileManager.default
        let importsDirectory = AppStoragePaths.importsDirectory()
        try fileManager.createDirectory(at: importsDirectory, withIntermediateDirectories: true)

        await MediaToolUpdater.refreshYtDlpIfNeeded(onEvent: onEvent)

        let ytDlpURL = try MediaToolLocator.executable(named: "yt-dlp")
        let ffmpegURL = try MediaToolLocator.executable(named: "ffmpeg")
        let outputTemplate = MediaDownloadPlan.outputTemplate(importsDirectoryPath: importsDirectory.path(percentEncoded: false))
        let strategies = MediaDownloadPlan.strategies(
            for: trimmedURL,
            ffmpegPath: ffmpegURL.path(percentEncoded: false),
            outputTemplate: outputTemplate,
            javaScriptRuntimeArgs: MediaToolLocator.javaScriptRuntimeArgs(),
            audioOnly: audioOnly
        )

        var lastError: Error?
        for strategy in strategies {
            onEvent(.message(strategy.resolveMessage))
            do {
                return try await run(
                    ytDlpURL: ytDlpURL,
                    url: trimmedURL,
                    strategy: strategy,
                    importsDirectory: importsDirectory,
                    onEvent: onEvent
                )
            } catch {
                lastError = error
                onEvent(.message("\(strategy.label) failed. Trying fallback strategy..."))
            }
        }

        throw lastError ?? MediaDownloaderError.downloadFailed("yt-dlp could not download this link.")
    }

    private static func run(
        ytDlpURL: URL,
        url: String,
        strategy: MediaDownloadStrategy,
        importsDirectory: URL,
        onEvent: @Sendable @escaping (MediaDownloadEvent) -> Void
    ) async throws -> MediaDownloadResult {
        let process = Process()
        process.executableURL = ytDlpURL
        process.arguments = strategy.args + [url]
        process.currentDirectoryURL = importsDirectory
        process.environment = mediaToolEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let collector = MediaDownloadOutputCollector()
        let startedAt = Date()
        let outputTask = Task {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                await handleOutputLine(line, collector: collector, onEvent: onEvent)
            }
        }
        let errorTask = Task {
            for try await line in stderr.fileHandleForReading.bytes.lines {
                await handleOutputLine(line, collector: collector, onEvent: onEvent)
                await collector.recordErrorLine(line)
            }
        }

        let status = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                outputTask.cancel()
                errorTask.cancel()
                continuation.resume(throwing: MediaDownloaderError.launchFailed(error.localizedDescription))
            }
        }

        _ = try? await outputTask.value
        _ = try? await errorTask.value

        guard status == 0 else {
            let message = await collector.bestErrorMessage()
            throw MediaDownloaderError.downloadFailed(message)
        }

        let downloadedTitle = await collector.title
        if let finalPath = await collector.finalPath,
           FileManager.default.fileExists(atPath: finalPath) {
            let fileURL = URL(fileURLWithPath: finalPath)
            return MediaDownloadResult(fileURL: fileURL, title: downloadedTitle ?? title(from: fileURL))
        }

        if let newestFile = newestFile(in: importsDirectory, after: startedAt) {
            return MediaDownloadResult(fileURL: newestFile, title: downloadedTitle ?? title(from: newestFile))
        }

        throw MediaDownloaderError.downloadFailed("yt-dlp finished but did not report a downloaded media file.")
    }

    private static func mediaToolEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let supportBin = AppStoragePaths.mediaToolsDirectory().path(percentEncoded: false)
        let bundleBin = Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true).path(percentEncoded: false) ?? ""
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [supportBin, bundleBin, "/opt/homebrew/bin", "/usr/local/bin", existingPath]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private static func handleOutputLine(
        _ line: String,
        collector: MediaDownloadOutputCollector,
        onEvent: @Sendable @escaping (MediaDownloadEvent) -> Void
    ) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let progress = MediaDownloadProgress.parse(trimmed) {
            await collector.recordProgress(progress)
            onEvent(.progress(progress))
            return
        }

        if let title = taggedValue("VANISCRIPT_TITLE:", in: trimmed) {
            await collector.recordTitle(title)
            onEvent(.message("Resolved title: \(title)"))
            return
        }

        if let finalPath = taggedValue("VANISCRIPT_FILEPATH:", in: trimmed) {
            await collector.recordFinalPath(finalPath)
            onEvent(.message("Saved media file: \(URL(fileURLWithPath: finalPath).lastPathComponent)"))
            return
        }

        if isLikelyFinalPath(trimmed) {
            await collector.recordFinalPath(trimmed)
            return
        }

        if let status = userFacingStatusMessage(from: trimmed) {
            onEvent(.message(status))
        }
    }

    private static func taggedValue(_ tag: String, in line: String) -> String? {
        guard let range = line.range(of: tag) else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func userFacingStatusMessage(from line: String) -> String? {
        let lower = line.lowercased()
        if line.hasPrefix("[youtube]") || line.hasPrefix("[soundcloud]") {
            if lower.contains("downloading webpage") || lower.contains("downloading ios player") || lower.contains("extracting url") {
                return "Resolving source metadata..."
            }
            if lower.contains("downloading player") {
                return "Resolving YouTube player..."
            }
        }
        if line.hasPrefix("[info]") {
            return "Selecting best available stream..."
        }
        if line.hasPrefix("[download] Destination:") {
            return "Writing media file..."
        }
        if line.hasPrefix("[download]") && lower.contains("has already been downloaded") {
            return "Using already downloaded media file..."
        }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[Fixup") {
            return "Merging video and audio into MP4..."
        }
        if line.hasPrefix("[ExtractAudio]") {
            return "Extracting best audio file..."
        }
        return nil
    }

    private static func isLikelyFinalPath(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("|"), !trimmed.hasPrefix("[") else { return false }
        let ext = URL(fileURLWithPath: trimmed).pathExtension.lowercased()
        return ["mp4", "mov", "m4a", "mp3", "webm", "mkv", "wav", "flac"].contains(ext)
    }

    private static func newestFile(in directory: URL, after date: Date) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modified = values?.contentModificationDate,
                      modified >= date.addingTimeInterval(-2) else {
                    return nil
                }
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    private static func title(from fileURL: URL) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard let underscoreIndex = stem.lastIndex(of: "_") else { return stem }
        let candidateID = stem[stem.index(after: underscoreIndex)...]
        let allowedIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        if candidateID.unicodeScalars.allSatisfy({ allowedIDCharacters.contains($0) }), candidateID.count >= 6 {
            return String(stem[..<underscoreIndex])
        }
        return stem
    }
}

private actor MediaDownloadOutputCollector {
    private(set) var finalPath: String?
    private(set) var title: String?
    private var errorLines: [String] = []
    private var lastProgress: MediaDownloadProgress?

    func recordTitle(_ value: String) {
        title = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recordFinalPath(_ path: String) {
        finalPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recordErrorLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorLines.append(trimmed)
        if errorLines.count > 20 {
            errorLines.removeFirst(errorLines.count - 20)
        }
    }

    func recordProgress(_ progress: MediaDownloadProgress) {
        lastProgress = progress
    }

    func bestErrorMessage() -> String {
        if let line = errorLines.last(where: { $0.localizedCaseInsensitiveContains("error") }) {
            return line
        }
        if let line = errorLines.last {
            return line
        }
        if let lastProgress {
            let percent = Int((lastProgress.fraction * 100).rounded())
            return "yt-dlp stopped after downloading \(percent)%."
        }
        return "yt-dlp failed without a detailed error message."
    }
}

private enum MediaToolLocator {
    static func executable(named name: String) throws -> URL {
        let candidates = candidateURLs(named: name)
        if let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }) {
            return url
        }
        throw MediaDownloaderError.missingTool(name, candidates.map { $0.path(percentEncoded: false) })
    }

    private static func candidateURLs(named name: String) -> [URL] {
        var urls: [URL] = [
            AppStoragePaths.mediaToolsDirectory().appendingPathComponent(name),
        ]

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("bin", isDirectory: true).appendingPathComponent(name))
        }

        #if DEBUG
        urls.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"))
        urls.append(URL(fileURLWithPath: "/usr/local/bin/\(name)"))
        #endif

        return urls
    }

    static func javaScriptRuntimeArgs() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let denoCandidates = [
            environment["YTDLP_DENO_PATH"],
            environment["DENO_PATH"],
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno",
            "/usr/bin/deno",
        ].compactMap { $0 }

        if let denoPath = denoCandidates.first(where: isExecutableCommand) {
            return ["--js-runtimes", "deno:\(denoPath)"]
        }

        let nodeCandidates = [
            environment["YTDLP_NODE_PATH"],
            environment["NODE_PATH"],
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ].compactMap { $0 }

        if let nodePath = nodeCandidates.first(where: isExecutableCommand) {
            return ["--js-runtimes", "node:\(nodePath)"]
        }

        return []
    }

    private static func isExecutableCommand(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

private enum MediaToolUpdater {
    private static let latestYtDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private static let refreshInterval: TimeInterval = 60 * 60 * 24

    static func refreshYtDlpIfNeeded(onEvent: @Sendable @escaping (MediaDownloadEvent) -> Void) async {
        let destination = AppStoragePaths.mediaToolsDirectory().appendingPathComponent("yt-dlp")
        if !shouldRefresh(destination: destination) {
            return
        }

        do {
            onEvent(.message("Checking yt-dlp update..."))
            let directory = AppStoragePaths.mediaToolsDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let (tempURL, response) = try await URLSession.shared.download(from: latestYtDlpURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MediaDownloaderError.downloadFailed("Could not download latest yt-dlp binary.")
            }

            let stagedURL = directory.appendingPathComponent("yt-dlp.download")
            try? FileManager.default.removeItem(at: stagedURL)
            try FileManager.default.moveItem(at: tempURL, to: stagedURL)
            try makeExecutable(stagedURL)
            removeQuarantine(from: stagedURL)
            adHocSign(stagedURL)

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: stagedURL, to: destination)
            try makeExecutable(destination)
            onEvent(.message("Using updated yt-dlp."))
        } catch {
            onEvent(.message("Using bundled yt-dlp. Update check failed: \(error.localizedDescription)"))
        }
    }

    private static func shouldRefresh(destination: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            return true
        }
        guard let values = try? destination.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate else {
            return true
        }
        return Date().timeIntervalSince(modified) > refreshInterval
    }

    private static func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private static func removeQuarantine(from url: URL) {
        runUtility("/usr/bin/xattr", arguments: ["-d", "com.apple.quarantine", url.path(percentEncoded: false)])
    }

    private static func adHocSign(_ url: URL) {
        runUtility("/usr/bin/codesign", arguments: ["--force", "--sign", "-", url.path(percentEncoded: false)])
    }

    private static func runUtility(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

enum MediaDownloaderError: LocalizedError {
    case missingTool(String, [String])
    case launchFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTool(let name, let candidates):
            return "\(name) is not bundled with VaniScript. Expected executable at: \(candidates.joined(separator: ", "))"
        case .launchFailed(let message):
            return "Could not launch yt-dlp: \(message)"
        case .downloadFailed(let message):
            return message
        }
    }
}
