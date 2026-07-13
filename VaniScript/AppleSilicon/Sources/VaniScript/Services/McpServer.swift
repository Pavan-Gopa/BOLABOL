import Darwin
import Foundation
import VaniScriptCore

@MainActor
final class McpServer: Sendable {
    static let shared = McpServer()

    private struct HTTPRequest: Sendable {
        var method: String
        var urlString: String
        var path: String
        var queryItems: [String: String]
        var headers: [String: String]
        var body: String
    }

    private struct SseClientSession: Sendable {
        var socket: Int32
        var profileID: String
        var displayName: String
        var connectedAt: Date
        var lastSeenAt: Date
    }

    private struct StreamableHttpSession: Sendable {
        var profileID: String
        var displayName: String
        var connectedAt: Date
        var lastSeenAt: Date
    }

    private enum RequestParseError: Error, Equatable, Sendable {
        case incomplete
        case invalidUTF8
        case invalidRequestLine
        case invalidContentLength

        var message: String {
            switch self {
            case .incomplete: "Incomplete request"
            case .invalidUTF8: "Invalid UTF-8"
            case .invalidRequestLine: "Invalid request line"
            case .invalidContentLength: "Invalid Content-Length"
            }
        }
    }

    private weak var store: WorkflowStore?
    private var configuration = McpServerConfiguration(settings: .defaults)
    private var listenSocket: Int32 = -1
    private var connections = [UUID: Int32]()
    private var sseClients = [UUID: SseClientSession]()
    private var streamableHttpSessions = [UUID: StreamableHttpSession]()
    private let streamableSessionTimeout: TimeInterval = 120
    
    var hasActiveClients: Bool {
        !sseClients.isEmpty || !streamableHttpSessions.isEmpty
    }
    
    private let serverQueue = DispatchQueue(label: "com.vaniscript.mcp.socket", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    func configure(store: WorkflowStore, configuration: McpServerConfiguration) {
        self.store = store
        self.configuration = configuration
        stop()

        guard configuration.canStart else {
            print("MCP Swift Server disabled. Enable it in VaniScript Settings and generate an access token to start.")
            return
        }

        guard startSocketListener(port: configuration.port) else {
            return
        }
        print("MCP Swift Server listening on http://127.0.0.1:\(configuration.port)")
    }

    func hasActiveClient(preferredProfileID: String) -> Bool {
        let normalizedProfileID = McpAgentProfileCatalog.normalizedProfileID(preferredProfileID)
        return sseClients.values.contains { $0.profileID == normalizedProfileID }
            || streamableHttpSessions.values.contains { $0.profileID == normalizedProfileID }
    }

    func stop() {
        if listenSocket >= 0 {
            Darwin.shutdown(listenSocket, SHUT_RDWR)
            Darwin.close(listenSocket)
            listenSocket = -1
        }

        for socket in connections.values {
            Darwin.shutdown(socket, SHUT_RDWR)
            Darwin.close(socket)
        }
        connections.removeAll()
        sseClients.removeAll()
        streamableHttpSessions.removeAll()
        publishActiveClients()
    }

    private func startSocketListener(port: UInt16) -> Bool {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            print("MCP Swift Server failed to create socket: \(errno)")
            return false
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("MCP Swift Server failed to bind 127.0.0.1:\(port): \(errno)")
            Darwin.close(socketFD)
            return false
        }

        guard Darwin.listen(socketFD, SOMAXCONN) == 0 else {
            print("MCP Swift Server failed to listen: \(errno)")
            Darwin.close(socketFD)
            return false
        }

        listenSocket = socketFD
        serverQueue.async { [weak self] in
            self?.acceptLoop(socketFD)
        }
        return true
    }

    nonisolated private func acceptLoop(_ socketFD: Int32) {
        while true {
            var clientAddress = sockaddr_storage()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.accept(socketFD, sockaddrPointer, &clientAddressLength)
                }
            }

            if clientSocket < 0 {
                if errno == EBADF || errno == EINVAL {
                    return
                }
                continue
            }

            Task { @MainActor [weak self] in
                self?.handleAcceptedSocket(clientSocket)
            }
        }
    }

    private func handleAcceptedSocket(_ socket: Int32) {
        let id = UUID()
        connections[id] = socket
        serverQueue.async { [weak self] in
            self?.readSocketRequest(id: id, socket: socket)
        }
    }

    nonisolated private func readSocketRequest(id: UUID, socket: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while true {
            let count = Darwin.read(socket, &chunk, chunk.count)
            if count <= 0 {
                Task { @MainActor [weak self] in
                    self?.closeConnection(id: id)
                }
                return
            }

            buffer.append(chunk, count: count)
            switch Self.parseRequest(from: buffer) {
            case .success(let request):
                Task { @MainActor [weak self] in
                    self?.processRequest(id: id, socket: socket, request: request)
                }
                return
            case .failure(.incomplete):
                continue
            case .failure(let error):
                Task { @MainActor [weak self] in
                    self?.sendHTTPResponse(socket: socket, statusCode: 400, statusText: "Bad Request", body: error.message)
                    self?.closeConnection(id: id)
                }
                return
            }
        }
    }

    nonisolated private static func parseRequest(from buffer: Data) -> Result<HTTPRequest, RequestParseError> {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: delimiter) else {
            return .failure(.incomplete)
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .failure(.invalidUTF8)
        }

        let headerLines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else {
            return .failure(.invalidRequestLine)
        }
        let firstLineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard firstLineParts.count >= 2 else {
            return .failure(.invalidRequestLine)
        }

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsedLength = Int(rawLength), parsedLength >= 0 else {
                return .failure(.invalidContentLength)
            }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }

        let bodyStart = headerRange.upperBound
        let requiredLength = bodyStart + contentLength
        guard buffer.count >= requiredLength else {
            return .failure(.incomplete)
        }

        let bodyData = buffer[bodyStart..<requiredLength]
        guard let body = String(data: bodyData, encoding: .utf8) else {
            return .failure(.invalidUTF8)
        }

        let urlString = firstLineParts[1]
        let path = urlString.components(separatedBy: "?").first ?? "/"
        return .success(HTTPRequest(
            method: firstLineParts[0],
            urlString: urlString,
            path: path,
            queryItems: queryItems(from: urlString),
            headers: headers,
            body: body
        ))
    }

    private func processRequest(id: UUID, socket: Int32, request: HTTPRequest) {
        guard configuration.isAllowedOrigin(request.headers["origin"]) else {
            sendHTTPResponse(socket: socket, statusCode: 403, statusText: "Forbidden", body: "Origin is not allowed")
            closeConnection(id: id)
            return
        }

        if request.method == "OPTIONS" {
            sendOptionsResponse(socket: socket)
            closeConnection(id: id)
            return
        }

        if request.path == "/sse" {
            guard configuration.isAuthorized(headers: request.headers, queryItems: request.queryItems) else {
                sendHTTPResponse(socket: socket, statusCode: 401, statusText: "Unauthorized", body: "Unauthorized")
                closeConnection(id: id)
                return
            }

            if request.method == "GET" {
                handleSseConnection(id: id, socket: socket, headers: request.headers)
                return
            }

            if request.method == "POST" {
                handleStreamableHttpRequest(id: id, socket: socket, request: request)
                return
            }

            if request.method == "DELETE" {
                guard let rawSessionID = request.headers["mcp-session-id"],
                      let sessionID = UUID(uuidString: rawSessionID),
                      streamableHttpSessions.removeValue(forKey: sessionID) != nil
                else {
                    sendHTTPResponse(socket: socket, statusCode: 404, statusText: "Not Found", body: "Unknown MCP session")
                    closeConnection(id: id)
                    return
                }
                publishActiveClients()
                sendHTTPResponse(socket: socket, statusCode: 200, statusText: "OK", body: "")
                closeConnection(id: id)
                return
            }

            sendHTTPResponse(socket: socket, statusCode: 405, statusText: "Method Not Allowed", body: "Method Not Allowed")
            closeConnection(id: id)
            return
        }

        if request.path == "/message", request.method == "POST" {
            guard configuration.isAuthorized(headers: request.headers, queryItems: request.queryItems),
                  let sessionId = request.queryItems["sessionId"],
                  let sseClientUUID = UUID(uuidString: sessionId),
                  sseClients[sseClientUUID] != nil
            else {
                sendHTTPResponse(socket: socket, statusCode: 401, statusText: "Unauthorized", body: "Unauthorized")
                closeConnection(id: id)
                return
            }

            sendHTTPResponse(socket: socket, statusCode: 202, statusText: "Accepted", body: "")
            handlePostMessage(sessionId: sessionId, body: request.body)
            closeConnection(id: id)
            return
        }

        sendHTTPResponse(socket: socket, statusCode: 404, statusText: "Not Found", body: "Not Found")
        closeConnection(id: id)
    }

    private func handleSseConnection(id: UUID, socket: Int32, headers: [String: String]) {
        let responseHeaders = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "\r\n",
        ].joined(separator: "\r\n")

        sendRaw(socket: socket, string: responseHeaders)
        registerSseClient(id: id, socket: socket, userAgent: headers["user-agent"])
        sendRaw(socket: socket, string: "event: endpoint\ndata: /message?sessionId=\(id.uuidString)\n\n")

        serverQueue.async { [weak self] in
            self?.monitorSseClient(id: id, socket: socket)
        }
    }

    private func handleStreamableHttpRequest(id: UUID, socket: Int32, request: HTTPRequest) {
        guard let data = request.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String
        else {
            sendHTTPResponse(socket: socket, statusCode: 400, statusText: "Bad Request", body: "Invalid JSON-RPC request")
            closeConnection(id: id)
            return
        }

        if method == "initialize" {
            let sessionID = UUID()
            registerStreamableHttpSession(id: sessionID, json: json, userAgent: request.headers["user-agent"])
            let requestedProtocolVersion = ((json["params"] as? [String: Any])?["protocolVersion"] as? String) ?? "2025-03-26"
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": json["id"] ?? NSNull(),
                "result": [
                    "protocolVersion": requestedProtocolVersion,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": [
                        "name": "vaniscript-swift-mcp",
                        "version": "1.1.0",
                    ],
                ],
            ]
            sendJsonRpcHTTPResponse(
                socket: socket,
                payload: response,
                additionalHeaders: ["Mcp-Session-Id: \(sessionID.uuidString)"]
            )
            closeConnection(id: id)
            return
        }

        guard let rawSessionID = request.headers["mcp-session-id"],
              let sessionID = UUID(uuidString: rawSessionID),
              streamableHttpSessions[sessionID] != nil
        else {
            sendHTTPResponse(socket: socket, statusCode: 404, statusText: "Not Found", body: "Unknown MCP session")
            closeConnection(id: id)
            return
        }

        refreshStreamableHttpSession(id: sessionID, json: json, userAgent: request.headers["user-agent"])

        if method == "notifications/initialized" {
            sendHTTPResponse(socket: socket, statusCode: 202, statusText: "Accepted", body: "", contentType: "application/json")
            closeConnection(id: id)
            return
        }

        guard let requestID = json["id"] else {
            sendHTTPResponse(socket: socket, statusCode: 202, statusText: "Accepted", body: "", contentType: "application/json")
            closeConnection(id: id)
            return
        }

        if method == "tools/list" {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestID,
                "result": [
                    "tools": McpToolRegistry
                        .definitions(permissions: configuration.permissions)
                        .map(\.mcpDictionary),
                ],
            ]
            sendJsonRpcHTTPResponse(socket: socket, payload: response)
            closeConnection(id: id)
            return
        }

        if method == "tools/call" {
            guard let params = json["params"] as? [String: Any],
                  let toolName = params["name"] as? String
            else {
                sendJsonRpcHTTPError(socket: socket, requestID: requestID, code: -32602, message: "Missing tool name")
                closeConnection(id: id)
                return
            }
            guard McpToolRegistry.isAllowed(toolName, permissions: configuration.permissions) else {
                sendJsonRpcHTTPError(socket: socket, requestID: requestID, code: -32601, message: "Tool is not available in the current MCP policy")
                closeConnection(id: id)
                return
            }

            let args = params["arguments"] as? [String: Any] ?? [:]
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.executeToolOnMainActor(
                        name: toolName,
                        args: args,
                        permissions: self.configuration.permissions
                    )
                    self.sendJsonRpcHTTPResponse(
                        socket: socket,
                        payload: self.toolCallResponse(requestID: requestID, result: result)
                    )
                } catch {
                    self.sendJsonRpcHTTPError(socket: socket, requestID: requestID, code: -32603, message: error.localizedDescription)
                }
                self.closeConnection(id: id)
            }
            return
        }

        sendJsonRpcHTTPError(socket: socket, requestID: requestID, code: -32601, message: "Unknown method")
        closeConnection(id: id)
    }

    nonisolated private func monitorSseClient(id: UUID, socket: Int32) {
        var byte = UInt8(0)
        while true {
            let count = Darwin.read(socket, &byte, 1)
            if count <= 0 {
                Task { @MainActor [weak self] in
                    self?.closeConnection(id: id)
                }
                return
            }
        }
    }

    private func handlePostMessage(sessionId: String, body: String) {
        guard let sseClientUUID = UUID(uuidString: sessionId),
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sseSocket = sseClients[sseClientUUID]?.socket
        else {
            return
        }

        refreshSseClient(id: sseClientUUID, json: json)

        guard let method = json["method"] as? String else { return }

        if method == "notifications/initialized" {
            return
        }

        guard let requestId = json["id"] else {
            return
        }

        if method == "initialize" {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestId,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": [:],
                    ],
                    "serverInfo": [
                        "name": "vaniscript-swift-mcp",
                        "version": "1.0.0",
                    ],
                ],
            ]
            sendSseMessage(socket: sseSocket, payload: response)
            return
        }

        if method == "tools/list" {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestId,
                "result": [
                    "tools": McpToolRegistry
                        .definitions(permissions: configuration.permissions)
                        .map(\.mcpDictionary),
                ],
            ]
            sendSseMessage(socket: sseSocket, payload: response)
            return
        }

        if method == "tools/call" {
            guard let params = json["params"] as? [String: Any],
                  let toolName = params["name"] as? String
            else {
                sendJsonRpcError(socket: sseSocket, requestId: requestId, code: -32602, message: "Missing tool name")
                return
            }

            guard McpToolRegistry.isAllowed(toolName, permissions: configuration.permissions) else {
                sendJsonRpcError(socket: sseSocket, requestId: requestId, code: -32601, message: "Tool is not available in the current MCP policy")
                return
            }

            let args = params["arguments"] as? [String: Any] ?? [:]

            Task {
                do {
                    let result = try await executeToolOnMainActor(
                        name: toolName,
                        args: args,
                        permissions: configuration.permissions
                    )
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "result": [
                            "content": [
                                [
                                    "type": "text",
                                    "text": String(
                                        data: try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                                        encoding: .utf8
                                    ) ?? "{}",
                                ],
                            ],
                        ],
                    ]
                    sendSseMessage(socket: sseSocket, payload: response)
                } catch {
                    sendJsonRpcError(socket: sseSocket, requestId: requestId, code: -32603, message: error.localizedDescription)
                }
            }
            return
        }

        sendJsonRpcError(socket: sseSocket, requestId: requestId, code: -32601, message: "Unknown method")
    }

    private func executeToolOnMainActor(name: String, args: [String: Any], permissions: McpPermissionSet) async throws -> [String: Any] {
        guard let store else {
            throw NSError(domain: "McpServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "WorkflowStore is not initialized."])
        }
        return try await store.executeMcpTool(name: name, arguments: args, permissions: permissions)
    }

    private func toolCallResponse(requestID: Any, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": requestID,
            "result": [
                "content": [
                    [
                        "type": "text",
                        "text": String(
                            data: (try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)) ?? Data("{}".utf8),
                            encoding: .utf8
                        ) ?? "{}",
                    ],
                ],
            ],
        ]
    }

    private func sendHTTPResponse(
        socket: Int32,
        statusCode: Int,
        statusText: String,
        body: String,
        contentType: String = "text/plain; charset=utf-8",
        additionalHeaders: [String] = []
    ) {
        let headers = ([
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.utf8.count)",
        ] + additionalHeaders + [
            "Connection: close",
            "\r\n",
        ]).joined(separator: "\r\n")
        sendRaw(socket: socket, string: headers + body)
    }

    private func sendOptionsResponse(socket: Int32) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS",
            "Access-Control-Allow-Headers: Authorization, X-VaniScript-MCP-Token, Content-Type, Mcp-Session-Id",
            "Connection: close",
            "\r\n",
        ].joined(separator: "\r\n")
        sendRaw(socket: socket, string: headers)
    }

    private func sendJsonRpcError(socket: Int32, requestId: Any, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        sendSseMessage(socket: socket, payload: response)
    }

    private func sendJsonRpcHTTPError(socket: Int32, requestID: Any, code: Int, message: String) {
        sendJsonRpcHTTPResponse(
            socket: socket,
            payload: [
                "jsonrpc": "2.0",
                "id": requestID,
                "error": [
                    "code": code,
                    "message": message,
                ],
            ]
        )
    }

    private func sendJsonRpcHTTPResponse(socket: Int32, payload: [String: Any], additionalHeaders: [String] = []) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let body = String(data: data, encoding: .utf8)
        else {
            sendHTTPResponse(socket: socket, statusCode: 500, statusText: "Internal Server Error", body: "Failed to encode JSON-RPC response")
            return
        }
        sendHTTPResponse(
            socket: socket,
            statusCode: 200,
            statusText: "OK",
            body: body,
            contentType: "application/json",
            additionalHeaders: additionalHeaders
        )
    }

    private func sendSseMessage(socket: Int32, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return
        }

        sendRaw(socket: socket, string: "event: message\ndata: \(jsonString)\n\n")
    }

    private func sendRaw(socket: Int32, string: String) {
        guard let data = string.data(using: .utf8) else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(socket, baseAddress.advanced(by: sent), data.count - sent)
                if count <= 0 {
                    return
                }
                sent += count
            }
        }
    }

    private func closeConnection(id: UUID) {
        if let socket = connections.removeValue(forKey: id) {
            Darwin.shutdown(socket, SHUT_RDWR)
            Darwin.close(socket)
        }
        if sseClients.removeValue(forKey: id) != nil {
            publishActiveClients()
        }
    }

    private func registerSseClient(id: UUID, socket: Int32, userAgent: String?) {
        let profileID = McpClientClassifier.profileID(clientName: nil, userAgent: userAgent)
        let displayName = profileID
            .map { McpAgentProfileCatalog.profile(forRawID: $0).displayName }
            ?? "MCP Client"
        let now = Date()
        sseClients[id] = SseClientSession(
            socket: socket,
            profileID: profileID ?? "unknown",
            displayName: displayName,
            connectedAt: now,
            lastSeenAt: now
        )
        publishActiveClients()
    }

    private func refreshSseClient(id: UUID, json: [String: Any]) {
        guard var session = sseClients[id] else { return }

        let clientName = ((json["params"] as? [String: Any])?["clientInfo"] as? [String: Any])?["name"] as? String
        if let profileID = McpClientClassifier.profileID(clientName: clientName, userAgent: nil) {
            session.profileID = profileID
            session.displayName = McpAgentProfileCatalog.profile(forRawID: profileID).displayName
        } else if let clientName, !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.displayName = clientName
        }
        session.lastSeenAt = Date()
        sseClients[id] = session
        publishActiveClients()
    }

    private func registerStreamableHttpSession(id: UUID, json: [String: Any], userAgent: String?) {
        let clientName = ((json["params"] as? [String: Any])?["clientInfo"] as? [String: Any])?["name"] as? String
        let profileID = McpClientClassifier.profileID(clientName: clientName, userAgent: userAgent)
        let displayName = profileID
            .map { McpAgentProfileCatalog.profile(forRawID: $0).displayName }
            ?? clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "MCP Client"
        let now = Date()
        streamableHttpSessions[id] = StreamableHttpSession(
            profileID: profileID ?? "unknown",
            displayName: displayName,
            connectedAt: now,
            lastSeenAt: now
        )
        publishActiveClients()
        scheduleStreamableSessionExpiry()
    }

    private func refreshStreamableHttpSession(id: UUID, json: [String: Any], userAgent: String?) {
        guard var session = streamableHttpSessions[id] else { return }
        let clientName = ((json["params"] as? [String: Any])?["clientInfo"] as? [String: Any])?["name"] as? String
        if let profileID = McpClientClassifier.profileID(clientName: clientName, userAgent: userAgent) {
            session.profileID = profileID
            session.displayName = McpAgentProfileCatalog.profile(forRawID: profileID).displayName
        }
        session.lastSeenAt = Date()
        streamableHttpSessions[id] = session
        publishActiveClients()
        scheduleStreamableSessionExpiry()
    }

    private func scheduleStreamableSessionExpiry() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.streamableSessionTimeout))
            self.expireInactiveStreamableHttpSessions()
        }
    }

    private func expireInactiveStreamableHttpSessions() {
        let cutoff = Date().addingTimeInterval(-streamableSessionTimeout)
        let staleSessionIDs = streamableHttpSessions.compactMap { id, session in
            session.lastSeenAt < cutoff ? id : nil
        }
        guard !staleSessionIDs.isEmpty else { return }
        for sessionID in staleSessionIDs {
            streamableHttpSessions.removeValue(forKey: sessionID)
        }
        publishActiveClients()
    }

    private func publishActiveClients() {
        let legacyClients = sseClients.map { id, session in
            McpActiveClient(
                id: id,
                profileID: session.profileID,
                displayName: session.displayName,
                connectedAt: session.connectedAt,
                lastSeenAt: session.lastSeenAt
            )
        }
        let streamableClients = streamableHttpSessions.map { id, session in
            McpActiveClient(
                id: id,
                profileID: session.profileID,
                displayName: session.displayName,
                connectedAt: session.connectedAt,
                lastSeenAt: session.lastSeenAt
            )
        }
        store?.updateMcpActiveClients(
            legacyClients + streamableClients
        )
    }

    nonisolated private static func queryItems(from urlString: String) -> [String: String] {
        guard let queryRange = urlString.range(of: "?") else { return [:] }
        let query = String(urlString[queryRange.upperBound...])
        var output: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            output[key] = value
        }
        return output
    }
}
