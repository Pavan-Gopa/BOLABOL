import Foundation
import VaniScriptCore

private struct CobaltErrorInfo: Codable {
    let code: String?
    let message: String?
}

private struct CobaltResponse: Codable {
    let status: String
    let url: String?
    let filename: String?
    let text: String?
    let error: CobaltErrorInfo?
}

struct DirectMediaImportResult: Sendable {
    let fileURL: URL
    let title: String?
}

enum DirectMediaImporter {
    static func importMedia(
        from rawURL: String,
        resolverEndpoint: String = "",
        resolverToken: String = "",
        audioOnly: Bool = false,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        try await importMediaWithMetadata(
            from: rawURL,
            resolverEndpoint: resolverEndpoint,
            resolverToken: resolverToken,
            audioOnly: audioOnly,
            onProgress: onProgress
        ).fileURL
    }

    static func importMediaWithMetadata(
        from rawURL: String,
        resolverEndpoint: String = "",
        resolverToken: String = "",
        audioOnly: Bool = false,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in },
        onMessage: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> DirectMediaImportResult {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if MediaSource.isWebVideoOrAudioLink(trimmedURL) {
            do {
                let downloaded = try await MediaDownloader.download(from: trimmedURL, audioOnly: audioOnly) { event in
                    switch event {
                    case .message(let message):
                        onMessage(message)
                    case .progress(let progress):
                        onProgress(progress.fraction)
                        let percent = Int((progress.fraction * 100).rounded())
                        let speed = progress.speed.map { " at \($0)" } ?? ""
                        let eta = progress.eta.map { ", ETA \($0)" } ?? ""
                        onMessage("Downloading media (\(percent)%)\(speed)\(eta)")
                    }
                }
                return DirectMediaImportResult(fileURL: downloaded.fileURL, title: downloaded.title)
            } catch {
                let endpointText = resolverEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !endpointText.isEmpty else {
                    throw DirectMediaImportError.downloaderFailed(error.localizedDescription)
                }
                onMessage("Local downloader failed. Trying fallback resolver...")
                let fallbackURL = try await fallbackExtractAndDownloadWebMedia(
                    from: trimmedURL,
                    resolverEndpoint: endpointText,
                    resolverToken: resolverToken,
                    audioOnly: audioOnly,
                    onProgress: onProgress
                )
                return DirectMediaImportResult(fileURL: fallbackURL, title: fallbackURL.deletingPathExtension().lastPathComponent)
            }
        }

        guard let url = MediaSource.directMediaURL(from: trimmedURL) else {
            throw DirectMediaImportError.unsupportedURL
        }

        if url.isFileURL {
            return DirectMediaImportResult(fileURL: url, title: url.deletingPathExtension().lastPathComponent)
        }

        onMessage("Downloading direct media link...")
        let downloadedURL = try await downloadWithProgress(from: url, onProgress: onProgress)
        let finalURL = try moveDownloadedFile(downloadedURL, sourceURL: url)
        return DirectMediaImportResult(fileURL: finalURL, title: finalURL.deletingPathExtension().lastPathComponent)
    }

    private static func fallbackExtractAndDownloadWebMedia(
        from rawURL: String,
        resolverEndpoint: String,
        resolverToken: String,
        audioOnly: Bool,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let endpointText = resolverEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpointText.isEmpty else {
            throw DirectMediaImportError.resolverRejected("Fallback media resolver is not configured.")
        }
        guard let endpointURL = normalizeResolverEndpoint(endpointText) else {
            throw DirectMediaImportError.invalidResolverEndpoint(endpointText)
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VaniScript/1.0", forHTTPHeaderField: "User-Agent")

        let token = resolverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "url": rawURL,
            "downloadMode": audioOnly ? "audio" : "auto",
            "videoQuality": "max",
            "youtubeVideoContainer": "mp4",
            "youtubeVideoCodec": "h264",
            "audioFormat": "best",
            "audioBitrate": "320",
            "youtubeBetterAudio": true,
            "youtubeHLS": true,
            "filenameStyle": "pretty"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DirectMediaImportError.resolverRejected("Media resolver did not return an HTTP response.")
            }

            let cobalt = try? JSONDecoder().decode(CobaltResponse.self, from: data)
            if http.statusCode == 401 || http.statusCode == 403 {
                throw DirectMediaImportError.resolverRequiresAuth(resolverErrorMessage(from: cobalt) ?? "Media resolver requires a token.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = resolverErrorMessage(from: cobalt) ?? "Media resolver returned HTTP \(http.statusCode)."
                throw DirectMediaImportError.resolverRejected(message)
            }
            guard let cobalt else {
                throw DirectMediaImportError.resolverRejected("Media resolver returned a response VaniScript could not parse.")
            }

            switch cobalt.status.lowercased() {
            case "redirect", "stream", "tunnel":
                guard let mediaURLString = cobalt.url,
                      let mediaURL = URL(string: mediaURLString) else {
                    throw DirectMediaImportError.resolverReturnedNoMedia("Media resolver succeeded, but did not provide a downloadable URL.")
                }
                let downloadedURL = try await downloadWithProgress(from: mediaURL, onProgress: onProgress)
                let finalName = finalMediaFileName(response: cobalt, sourceURL: mediaURL)
                return try moveDownloadedFile(downloadedURL, targetName: finalName)

            case "picker":
                throw DirectMediaImportError.resolverReturnedNoMedia("Media resolver returned multiple choices. Choose a direct media file URL or configure a resolver that returns a single audio stream.")

            case "error":
                let message = resolverErrorMessage(from: cobalt) ?? "Media resolver rejected this link."
                if message.lowercased().contains("jwt") || message.lowercased().contains("auth") {
                    throw DirectMediaImportError.resolverRequiresAuth(message)
                }
                throw DirectMediaImportError.resolverRejected(message)

            default:
                throw DirectMediaImportError.resolverReturnedNoMedia("Media resolver returned unsupported status '\(cobalt.status)'.")
            }
        } catch let error as DirectMediaImportError {
            throw error
        } catch {
            throw DirectMediaImportError.resolverRejected(friendlyNetworkMessage(error))
        }
    }

    private static func normalizeResolverEndpoint(_ rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        let retiredPaths = ["/api/json", "/api/v1/simple"]
        if retiredPaths.contains(components.path.lowercased()) {
            components.path = "/"
        } else if components.path.isEmpty {
            components.path = "/"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func resolverErrorMessage(from response: CobaltResponse?) -> String? {
        guard let response else { return nil }
        if let text = response.text, !text.isEmpty {
            return text
        }
        if let message = response.error?.message, !message.isEmpty {
            return message
        }
        if let code = response.error?.code, !code.isEmpty {
            return code
        }
        return nil
    }

    private static func friendlyNetworkMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost:
                return "Fallback media resolver host could not be found."
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection is available for media link import."
            case NSURLErrorTimedOut:
                return "Media resolver timed out. Try again or use another resolver endpoint."
            case NSURLErrorCannotConnectToHost:
                return "VaniScript could not connect to the configured media resolver."
            default:
                return "Media resolver request failed: \(error.localizedDescription)"
            }
        }
        return "Media resolver request failed: \(error.localizedDescription)"
    }

    private static func downloadWithProgress(
        from url: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let downloader = FileDownloader(onProgress: onProgress, continuation: continuation)
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 60
            sessionConfig.timeoutIntervalForResource = 60 * 30
            let session = URLSession(configuration: sessionConfig, delegate: downloader, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
            session.finishTasksAndInvalidate()
        }
    }

    private static func moveDownloadedFile(_ tempURL: URL, sourceURL: URL) throws -> URL {
        let name = sanitizedFileName(sourceURL.lastPathComponent.isEmpty ? "imported-media" : sourceURL.lastPathComponent)
        return try moveDownloadedFile(tempURL, targetName: name)
    }

    private static func moveDownloadedFile(_ tempURL: URL, targetName: String) throws -> URL {
        let directory = AppStoragePaths.importsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = uniqueDestination(in: directory, requestedName: sanitizedFileName(targetName))
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private static func uniqueDestination(in directory: URL, requestedName: String) -> URL {
        let fallbackName = requestedName.isEmpty ? "imported-media" : requestedName
        let baseURL = directory.appendingPathComponent(fallbackName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let uniqueName = ext.isEmpty
            ? "\(stem)-\(UUID().uuidString.prefix(6))"
            : "\(stem)-\(UUID().uuidString.prefix(6)).\(ext)"
        return directory.appendingPathComponent(uniqueName)
    }

    private static func finalMediaFileName(response: CobaltResponse, sourceURL: URL) -> String {
        if let filename = response.filename, !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizedFileName(filename)
        }
        let extensionText = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        return "web-media-\(UUID().uuidString.prefix(6)).\(extensionText)"
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        fileName.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
    }
}

enum DirectMediaImportError: LocalizedError {
    case unsupportedURL
    case downloaderFailed(String)
    case invalidResolverEndpoint(String)
    case resolverRequiresAuth(String)
    case resolverRejected(String)
    case resolverReturnedNoMedia(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "Use a direct http(s) media link ending in MP3, WAV, M4A, FLAC, MP4, MOV, MKV, or WEBM, or a valid YouTube/SoundCloud URL."
        case .downloaderFailed(let message):
            "Local media download failed: \(message)"
        case .invalidResolverEndpoint(let endpoint):
            "Media resolver URL is invalid: \(endpoint)"
        case .resolverRequiresAuth(let message):
            "Media resolver requires authorization: \(message)"
        case .resolverRejected(let message):
            message
        case .resolverReturnedNoMedia(let message):
            message
        case .httpStatus(let status):
            "The media server returned HTTP \(status)."
        }
    }
}
