import Foundation
import Network
import VaniScriptCore

@MainActor
final class McpServer: Sendable {
    static let shared = McpServer()
    
    // We wrap non-Sendable properties inside a main-actor synchronized state
    private var listener: NWListener?
    private weak var store: WorkflowStore?
    private var connections = [UUID: NWConnection]()
    private var sseClients = [UUID: NWConnection]()
    
    private init() {}
    
    func start(store: WorkflowStore) {
        self.store = store
        stop()
        
        do {
            let port = NWEndpoint.Port(rawValue: 19790)!
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("MCP Swift Server listening on http://127.0.0.1:19790")
                case .failed(let error):
                    print("MCP Swift Server failed: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("Failed to start NWListener: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        sseClients.removeAll()
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .global(qos: .userInitiated))
        
        readRequest(id: id, connection: connection)
    }
    
    private func readRequest(id: UUID, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if error != nil {
                    self.closeConnection(id: id)
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    if isComplete {
                        self.closeConnection(id: id)
                    } else {
                        self.readRequest(id: id, connection: connection)
                    }
                    return
                }
                
                self.processRequest(id: id, connection: connection, data: data)
            }
        }
    }
    
    private func processRequest(id: UUID, connection: NWConnection, data: Data) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Invalid UTF-8")
            closeConnection(id: id)
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Empty Request")
            closeConnection(id: id)
            return
        }
        
        let firstLineParts = lines[0].components(separatedBy: " ")
        guard firstLineParts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Invalid Request Line")
            closeConnection(id: id)
            return
        }
        
        let method = firstLineParts[0]
        let urlString = firstLineParts[1]
        
        let path = urlString.components(separatedBy: "?").first ?? "/"
        
        if method == "OPTIONS" {
            sendOptionsResponse(connection: connection)
            closeConnection(id: id)
            return
        }
        
        if path == "/sse" && method == "GET" {
            handleSseConnection(id: id, connection: connection)
            return
        }
        
        if path == "/message" && method == "POST" {
            var sessionId = ""
            if let queryRange = urlString.range(of: "?") {
                let query = String(urlString[queryRange.upperBound...])
                let pairs = query.components(separatedBy: "&")
                for pair in pairs {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count == 2 && parts[0] == "sessionId" {
                        sessionId = parts[1]
                    }
                }
            }
            
            guard let range = requestString.range(of: "\r\n\r\n") else {
                sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "No body delimiter")
                closeConnection(id: id)
                return
            }
            
            let body = String(requestString[range.upperBound...])
            handlePostMessage(connection: connection, sessionId: sessionId, body: body)
            closeConnection(id: id)
            return
        }
        
        sendHTTPResponse(connection: connection, statusCode: 404, statusText: "Not Found", body: "Not Found")
        closeConnection(id: id)
    }
    
    private func handleSseConnection(id: UUID, connection: NWConnection) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "\r\n"
        ].joined(separator: "\r\n")
        
        guard let headerData = headers.data(using: .utf8) else { return }
        
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                if error != nil {
                    self?.closeConnection(id: id)
                    return
                }
                
                self?.sseClients[id] = connection
                
                let event = "event: endpoint\ndata: /message?sessionId=\(id.uuidString)\n\n"
                if let eventData = event.data(using: .utf8) {
                    connection.send(content: eventData, completion: .contentProcessed({ _ in }))
                }
            }
        })
    }
    
    private func handlePostMessage(connection: NWConnection, sessionId: String, body: String) {
        sendHTTPResponse(connection: connection, statusCode: 202, statusText: "Accepted", body: "")
        
        guard let sseClientUUID = UUID(uuidString: sessionId),
              let sseConnection = sseClients[sseClientUUID] else {
            return
        }
        
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String,
              let requestId = json["id"] else {
            return
        }
        
        if method == "initialize" {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestId,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "vaniscript-swift-mcp",
                        "version": "1.0.0"
                    ]
                ]
            ]
            sendSseMessage(connection: sseConnection, payload: response)
            return
        }
        
        if method == "notifications/initialized" {
            return
        }
        
        if method == "tools/list" {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestId,
                "result": [
                    "tools": [
                        [
                            "name": "get_project_state",
                            "description": "Get the active VaniScript project state (session, settings, screen, etc.)",
                            "inputSchema": ["type": "object", "properties": [:]]
                        ],
                        [
                            "name": "update_chunk_text",
                            "description": "Update the transcription or translation text of a segment",
                            "inputSchema": [
                                "type": "object",
                                "properties": [
                                    "chunkIndex": ["type": "number", "description": "Index of the segment (0-based)"],
                                    "original": ["type": "string", "description": "New original transcript text (optional)"],
                                    "translated": ["type": "string", "description": "New translation text (optional)"]
                                ],
                                "required": ["chunkIndex"]
                            ]
                        ],
                        [
                            "name": "approve_chunk",
                            "description": "Approve or revoke approval for a specific segment",
                            "inputSchema": [
                                "type": "object",
                                "properties": [
                                    "chunkIndex": ["type": "number", "description": "Index of the segment (0-based)"],
                                    "approved": ["type": "boolean", "description": "True to approve, false to revoke"]
                                ],
                                "required": ["chunkIndex", "approved"]
                            ]
                        ],
                        [
                            "name": "get_subtitle_style",
                            "description": "Get active subtitle style settings",
                            "inputSchema": ["type": "object", "properties": [:]]
                        ],
                        [
                            "name": "update_subtitle_style",
                            "description": "Update the style properties for video subtitles",
                            "inputSchema": [
                                "type": "object",
                                "properties": [
                                    "stylePatch": [
                                        "type": "object",
                                        "description": "Partial patch for subtitle style parameters"
                                    ]
                                ],
                                "required": ["stylePatch"]
                            ]
                        ],
                        [
                            "name": "get_shorts_plans",
                            "description": "List all vertical shorts clip plans planned in timeline",
                            "inputSchema": ["type": "object", "properties": [:]]
                        ]
                    ]
                ]
            ]
            sendSseMessage(connection: sseConnection, payload: response)
            return
        }
        
        if method == "tools/call" {
            guard let params = json["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                return
            }
            
            let args = params["arguments"] as? [String: Any] ?? [:]
            
            Task {
                do {
                    let result = try await executeToolOnMainActor(name: toolName, args: args)
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "result": [
                            "content": [
                                ["type": "text", "text": String(data: try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted), encoding: .utf8) ?? "{}"]
                            ]
                        ]
                    ]
                    sendSseMessage(connection: sseConnection, payload: response)
                } catch {
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "error": [
                            "code": -32603,
                            "message": error.localizedDescription
                        ]
                    ]
                    sendSseMessage(connection: sseConnection, payload: response)
                }
            }
            return
        }
    }
    
    private func executeToolOnMainActor(name: String, args: [String: Any]) async throws -> [String: Any] {
        guard let store = self.store else {
            throw NSError(domain: "McpServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "WorkflowStore is not initialized."])
        }
        return try await store.executeMcpTool(name: name, arguments: args)
    }
    
    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, statusText: String, body: String) {
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: text/plain",
            "Content-Length: \(body.utf8.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "\r\n"
        ].joined(separator: "\r\n")
        
        let response = headers + body
        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func sendOptionsResponse(connection: NWConnection) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "\r\n"
        ].joined(separator: "\r\n")
        
        if let responseData = headers.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func sendSseMessage(connection: NWConnection, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let message = "event: message\ndata: \(jsonString)\n\n"
        if let data = message.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func closeConnection(id: UUID) {
        if let conn = connections.removeValue(forKey: id) {
            conn.cancel()
        }
        sseClients.removeValue(forKey: id)
    }
}
