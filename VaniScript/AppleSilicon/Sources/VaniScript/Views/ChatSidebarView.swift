import SwiftUI
import VaniScriptCore

struct MessageItem: Identifiable, Equatable {
    let id = UUID()
    let sender: String // "user" or "assistant" or "system"
    let text: String
    let timestamp = Date()
    var runningTool: String?
}

struct ChatSidebarView: View {
    @EnvironmentObject private var workflowStore: WorkflowStore
    @State private var messages: [MessageItem] = [
        MessageItem(sender: "assistant", text: "Hare Krsna! I am your VaniScript AI Assistant. How can I help you style subtitles, approve segments, or inspect project state today?")
    ]
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var activeToolName: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Main Drawer Panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.accent)
                    
                    Text("AI Assistant")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            workflowStore.showChatSidebar = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.2))
                .overlay(
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1),
                    alignment: .bottom
                )

                // Message List
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.sender == "user" {
                                        Spacer()
                                        Text(msg.text)
                                            .font(.system(size: 13.5))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                LinearGradient(
                                                    colors: [VaniScriptTheme.accent, Color.orange],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else if msg.sender == "system" {
                                        Text(msg.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.red.opacity(0.8))
                                            .padding(10)
                                            .background(Color.red.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(msg.text)
                                                .font(.system(size: 13.5))
                                                .foregroundStyle(.white.opacity(0.9))
                                            
                                            if let tool = msg.runningTool {
                                                HStack(spacing: 6) {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                    Text("Running: \(tool)")
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundStyle(VaniScriptTheme.accent)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.05))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                        Spacer()
                                    }
                                }
                                .id(msg.id)
                            }

                            if isLoading && activeToolName == nil {
                                HStack {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.white.opacity(0.5)).frame(width: 6, height: 6)
                                        Circle().fill(Color.white.opacity(0.5)).frame(width: 6, height: 6)
                                        Circle().fill(Color.white.opacity(0.5)).frame(width: 6, height: 6)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Spacer()
                                }
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: messages) { _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Field
                HStack(spacing: 10) {
                    TextField("Message AI...", text: $inputText, onCommit: sendMessage)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .disabled(isLoading)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.1) : VaniScriptTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding(16)
                .background(Color.black.opacity(0.3))
                .overlay(
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1),
                    alignment: .top
                )
            }
            .frame(width: 380)
            .background(
                Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
                    .opacity(0.85)
            )
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1),
                alignment: .trailing
            )
            .transition(.move(edge: .leading))
            
            // Backdrop dismissal trigger
            Color.black.opacity(0.1)
                .onTapGesture {
                    withAnimation {
                        workflowStore.showChatSidebar = false
                    }
                }
        }
        .ignoresSafeArea()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        
        let userMessage = MessageItem(sender: "user", text: text)
        messages.append(userMessage)
        
        isLoading = true
        
        let key = workflowStore.settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            messages.append(MessageItem(sender: "system", text: "Error: Gemini Key is missing in Settings."))
            isLoading = false
            return
        }
        
        Task {
            do {
                // Initial prompt contents
                var contents: [GeminiChatContent] = []
                for msg in messages {
                    if msg.sender == "user" {
                        contents.append(GeminiChatContent(role: "user", parts: [GeminiChatPart(text: msg.text)]))
                    } else if msg.sender == "assistant" {
                        contents.append(GeminiChatContent(role: "model", parts: [GeminiChatPart(text: msg.text)]))
                    }
                }
                
                var loop = 0
                var finalText = "I have processed your request."
                
                while loop < 8 {
                    let requestBody = GeminiChatRequest(
                        contents: contents,
                        systemInstruction: GeminiSystemInstruction(
                            parts: [GeminiChatPart(text: "You are the VaniScript AI Chat Assistant. Assist users by calling local tools to view state, edit translations, update subtitle styling, and structure vertical video shorts. Confirm the success of executed tools clearly.")]
                        ),
                        tools: [
                            GeminiChatTool(
                                functionDeclarations: [
                                    GeminiToolDecl(
                                        name: "get_project_state",
                                        description: "Get the active VaniScript project state (session, settings, screen, etc.)",
                                        parameters: GeminiToolParams(type: "object", properties: [:])
                                    ),
                                    GeminiToolDecl(
                                        name: "update_chunk_text",
                                        description: "Update the transcription or translation text of a segment",
                                        parameters: GeminiToolParams(
                                            type: "object",
                                            properties: [
                                                "chunkIndex": ["type": "number", "description": "Index of the segment (0-based)"],
                                                "original": ["type": "string", "description": "New original transcript text (optional)"],
                                                "translated": ["type": "string", "description": "New translation text (optional)"]
                                            ]
                                        )
                                    ),
                                    GeminiToolDecl(
                                        name: "approve_chunk",
                                        description: "Approve or revoke approval for a specific segment",
                                        parameters: GeminiToolParams(
                                            type: "object",
                                            properties: [
                                                "chunkIndex": ["type": "number", "description": "Index of the segment (0-based)"],
                                                "approved": ["type": "boolean", "description": "True to approve, false to revoke"]
                                            ]
                                        )
                                    ),
                                    GeminiToolDecl(
                                        name: "get_subtitle_style",
                                        description: "Get active subtitle style settings",
                                        parameters: GeminiToolParams(type: "object", properties: [:])
                                    ),
                                    GeminiToolDecl(
                                        name: "update_subtitle_style",
                                        description: "Update the style properties for video subtitles",
                                        parameters: GeminiToolParams(
                                            type: "object",
                                            properties: [
                                                "stylePatch": [
                                                    "type": "object",
                                                    "description": "Partial patch for subtitle style parameters"
                                                ]
                                            ]
                                        )
                                    )
                                ]
                            )
                        ],
                        generationConfig: GeminiChatGenConfig(temperature: 0.1)
                    )
                    
                    var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
                    components?.queryItems = [URLQueryItem(name: "key", value: key)]
                    guard let url = components?.url else { return }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(requestBody)
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP Request failed"])
                    }
                    
                    let decoded = try JSONDecoder().decode(GeminiChatResponse.self, from: data)
                    let responseParts = decoded.candidates?.first?.content?.parts ?? []
                    
                    // Collect text
                    let txt = responseParts.compactMap(\.text).joined(separator: "\n")
                    if !txt.isEmpty {
                        finalText = txt
                    }
                    
                    // Check for function calls
                    let functionCalls = responseParts.compactMap(\.functionCall)
                    if functionCalls.isEmpty {
                        break
                    }
                    
                    // Push model response to history
                    contents.append(GeminiChatContent(role: "model", parts: responseParts))
                    
                    var toolResponseParts: [GeminiChatPart] = []
                    for call in functionCalls {
                        await MainActor.run {
                            self.activeToolName = call.name
                            if !self.messages.isEmpty {
                                self.messages[self.messages.count - 1].runningTool = call.name
                            }
                        }
                        
                        let result: [String: Any]
                        do {
                            result = try await workflowStore.executeMcpTool(name: call.name, arguments: call.args ?? [:])
                        } catch {
                            result = ["error": error.localizedDescription]
                        }
                        
                        toolResponseParts.append(GeminiChatPart(
                            functionResponse: GeminiChatFunctionResponse(
                                name: call.name,
                                response: result
                            )
                        ))
                    }
                    
                    await MainActor.run {
                        self.activeToolName = nil
                        if !self.messages.isEmpty {
                            self.messages[self.messages.count - 1].runningTool = nil
                        }
                    }
                    
                    // Push tool responses to history
                    contents.append(GeminiChatContent(role: "user", parts: toolResponseParts))
                    loop += 1
                }
                
                await MainActor.run {
                    self.messages.append(MessageItem(sender: "assistant", text: finalText))
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.messages.append(MessageItem(sender: "system", text: "Error: \(error.localizedDescription)"))
                    self.isLoading = false
                }
            }
        }
    }
}

// Codable API Structures for Gemini Function Calling
struct GeminiChatRequest: Encodable {
    let contents: [GeminiChatContent]
    let systemInstruction: GeminiSystemInstruction
    let tools: [GeminiChatTool]
    let generationConfig: GeminiChatGenConfig
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiChatPart]
}

struct GeminiChatContent: Codable {
    let role: String
    let parts: [GeminiChatPart]
}

struct GeminiChatPart: Codable {
    var text: String? = nil
    var functionCall: GeminiChatFunctionCall? = nil
    var functionResponse: GeminiChatFunctionResponse? = nil
}

struct GeminiChatFunctionCall: Codable {
    let name: String
    let args: [String: AnyCodable]?
}

struct GeminiChatFunctionResponse: Codable {
    let name: String
    let response: [String: AnyCodable]
    
    init(name: String, response: [String: Any]) {
        self.name = name
        self.response = response.mapValues { AnyCodable($0) }
    }
}

struct GeminiChatTool: Encodable {
    let functionDeclarations: [GeminiToolDecl]
}

struct GeminiToolDecl: Encodable {
    let name: String
    let description: String
    let parameters: GeminiToolParams
}

struct GeminiToolParams: Encodable {
    let type: String
    let properties: [String: AnyCodable]
    
    init(type: String, properties: [String: Any]) {
        self.type = type
        self.properties = properties.mapValues { AnyCodable($0) }
    }
}

struct GeminiChatGenConfig: Encodable {
    let temperature: Double
}

struct GeminiChatResponse: Decodable {
    let candidates: [GeminiChatCandidate]?
}

struct GeminiChatCandidate: Decodable {
    let content: GeminiChatContent?
}

// AnyCodable helper for heterogeneous JSON objects in Swift
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
