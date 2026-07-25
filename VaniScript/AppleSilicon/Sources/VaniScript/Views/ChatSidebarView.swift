import SwiftUI
import VaniScriptCore
import AVFoundation

struct MessageItem: Identifiable, Equatable {
    let id = UUID()
    let sender: String // "user" or "assistant" or "system"
    let text: String
    let timestamp = Date()
    var runningTool: String?
}

final class DictationRecorder: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }
    
    func start() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder?.delegate = self
        recorder?.record()
    }
    
    func stop() {
        recorder?.stop()
        recorder = nil
    }
}

private enum ChatRoute: String {
    case mcp
    case gemini
}

struct ChatSidebarView: View {
    @EnvironmentObject private var workflowStore: WorkflowStore
    @State private var messages: [MessageItem] = [
        MessageItem(sender: "assistant", text: "Hare Krsna! I am your VaniScript AI Assistant. How can I help you style subtitles, approve segments, or inspect project state today?")
    ]
    @State private var isLoading = false
    @State private var activeToolName: String? = nil
    
    @State private var isRecordingDictation = false
    @State private var dictationURL: URL? = nil
    @State private var dictationRecorder: DictationRecorder? = nil
    @State private var showNoModelWarning = false
    @AppStorage("vaniscript.chat.route") private var chatRouteRaw = ChatRoute.mcp.rawValue

    var body: some View {
        let micIcon = isRecordingDictation ? "stop.circle.fill" : "mic.fill"
        let micColor = isRecordingDictation ? Color.red : Color.white.opacity(0.6)

        return VStack(spacing: 0) {
            Color.clear.frame(height: 38)
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.accent)
                    
                    Text("AI Assistant")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Picker("Chat route", selection: $chatRouteRaw) {
                        Text("MCP").tag(ChatRoute.mcp.rawValue)
                        Text("API").tag(ChatRoute.gemini.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 116)
                    .help("MCP uses the embedded agent (Codex or Grok) selected in Settings > Agents. The API route is used only when selected explicitly.")

                    if chatRouteRaw == ChatRoute.mcp.rawValue {
                        agentModelMenu
                    }
                    
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
                .padding(.horizontal, VaniScriptTheme.Density.space12)
                .padding(.vertical, VaniScriptTheme.Density.space8)
                .background(Color.black.opacity(0.2))
                .overlay(
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1),
                    alignment: .bottom
                )

                if showNoModelWarning {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("No Local Whisper Model Connected")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                showNoModelWarning = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("To use voice dictation, please select and download a Whisper model in Settings -> ASR.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(VaniScriptTheme.Density.space8)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(VaniScriptTheme.Density.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, VaniScriptTheme.Density.space12)
                    .padding(.top, VaniScriptTheme.Density.space8)
                }

                // Message List
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: VaniScriptTheme.Density.space8) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.sender == "user" {
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 6) {
                                            Button {
                                                workflowStore.chatInputText = msg.text
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(msg.text, forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.white.opacity(0.4))
                                                    .frame(width: 22, height: 22)
                                                    .background(Color.white.opacity(0.08))
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy message and paste into input field")

                                            Text(msg.text)
                                                .font(.system(size: 13.5))
                                                .padding(.horizontal, VaniScriptTheme.Density.space12)
                                                .padding(.vertical, VaniScriptTheme.Density.space8)
                                                .background(
                                                    LinearGradient(
                                                        colors: [VaniScriptTheme.accent, Color.orange],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .foregroundStyle(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
                                        }
                                    } else if msg.sender == "system" {
                                        Text(msg.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.red.opacity(0.8))
                                            .padding(VaniScriptTheme.Density.space8)
                                            .background(Color.red.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .top, spacing: VaniScriptTheme.Density.space8) {
                                                Text(msg.text)
                                                    .font(.system(size: 13.5))
                                                    .foregroundStyle(.white.opacity(0.9))
                                                
                                                Spacer()
                                                
                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(msg.text, forType: .string)
                                                } label: {
                                                    Image(systemName: "doc.on.doc")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.white.opacity(0.35))
                                                        .frame(width: 20, height: 20)
                                                        .background(Color.white.opacity(0.06))
                                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                                }
                                                .buttonStyle(.plain)
                                                .help("Copy to clipboard")
                                            }
                                            
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
                                        .padding(.horizontal, VaniScriptTheme.Density.space12)
                                        .padding(.vertical, VaniScriptTheme.Density.space8)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous)
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
                                    .padding(.horizontal, VaniScriptTheme.Density.space12)
                                    .padding(.vertical, VaniScriptTheme.Density.space8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD))
                                    Spacer()
                                }
                            }
                        }
                        .padding(VaniScriptTheme.Density.space12)
                    }
                    .onChange(of: messages) { _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Field (Minimalist TextEditor with Inline Mic & Send Buttons)
                ZStack(alignment: .bottomTrailing) {
                    ZStack(alignment: .topLeading) {
                        if workflowStore.chatInputText.isEmpty {
                            Text("Message AI...")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, VaniScriptTheme.Density.space12)
                                .padding(.vertical, VaniScriptTheme.Density.space8)
                        }
                        
                        TextEditor(text: $workflowStore.chatInputText)
                            .font(.system(size: 13))
                            .tint(VaniScriptTheme.accent)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, VaniScriptTheme.Density.space8)
                            .padding(.vertical, 8)
                            .padding(.bottom, 36) // Leave space for buttons at the bottom
                            .frame(height: 100)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM))
                            .overlay(
                                RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .disabled(isLoading)
                    }
                    
                    HStack(spacing: 8) {
                        if isRecordingDictation {
                            MiniWaveformView()
                                .transition(.opacity)
                        }

                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: micIcon)
                                .font(.system(size: 14))
                                .foregroundStyle(micColor)
                                .frame(width: 28, height: 28)
                                .background(isRecordingDictation ? Color.red.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(workflowStore.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.3) : VaniScriptTheme.accent)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .disabled(workflowStore.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
                .padding(VaniScriptTheme.Density.space12)
                .background(Color.black.opacity(0.15))
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
        .ignoresSafeArea()
        .onAppear {
            checkModelPresence()
        }
    }

    private func sendMessage() {
        let text = workflowStore.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        workflowStore.chatInputText = ""
        
        let userMessage = MessageItem(sender: "user", text: text)
        messages.append(userMessage)
        
        isLoading = true

        if chatRouteRaw == ChatRoute.gemini.rawValue {
            let key = workflowStore.settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                messages.append(MessageItem(sender: "system", text: "API mode requires an API key in Settings."))
                isLoading = false
                return
            }
            Task {
                await executeGeminiRequest(text: text, key: key)
            }
            return
        }

        let preferredAgentID = workflowStore.settings.mcpPreferredAgentID
        guard preferredAgentID == McpClientProfileID.codex.rawValue
                || preferredAgentID == McpClientProfileID.grok.rawValue
                || preferredAgentID == McpClientProfileID.qwen.rawValue else {
            messages.append(MessageItem(
                sender: "system",
                text: "The MCP chat route is powered by Codex, Grok, or Qwen. Select one of them in Settings > Agents, then send the message again."
            ))
            isLoading = false
            return
        }

        if preferredAgentID == McpClientProfileID.qwen.rawValue {
            // Q2: embedded Qwen route (plain chat; MCP tools arrive in Q3).
            let history = messages.map { QwenChatHistoryItem(sender: $0.sender, text: $0.text) }
            Task {
                await executeQwenRequest(history: history)
            }
        } else if preferredAgentID == McpClientProfileID.grok.rawValue {
            let history = messages.map { GrokChatHistoryItem(sender: $0.sender, text: $0.text) }
            Task {
                await executeGrokRequest(history: history)
            }
        } else {
            let history = messages.map { CodexChatHistoryItem(sender: $0.sender, text: $0.text) }
            Task {
                await executeCodexRequest(history: history)
            }
        }
    }

    private var agentModelMenu: some View {
        if workflowStore.settings.mcpPreferredAgentID == McpClientProfileID.qwen.rawValue {
            AnyView(qwenModelMenu)
        } else if workflowStore.settings.mcpPreferredAgentID == McpClientProfileID.grok.rawValue {
            AnyView(grokModelMenu)
        } else {
            AnyView(codexModelMenu)
        }
    }

    private var codexModelMenu: some View {
        Menu {
            Section("Codex Model") {
                ForEach(CodexChatModelCatalog.options) { option in
                    Button {
                        selectCodexModel(option)
                    } label: {
                        Label(
                            option.displayName,
                            systemImage: workflowStore.settings.codexChatModelID == option.id ? "checkmark" : "cpu"
                        )
                    }
                }
            }

            Section("Reasoning") {
                let selectedModelID = CodexChatModelCatalog.normalizedModelID(workflowStore.settings.codexChatModelID)
                let selectedModel = CodexChatModelCatalog.option(id: selectedModelID) ?? CodexChatModelCatalog.options[0]
                ForEach(selectedModel.reasoningEfforts, id: \.self) { effort in
                    Button {
                        workflowStore.updateSettings { settings in
                            settings.codexChatReasoningEffort = effort
                        }
                    } label: {
                        Label(
                            effort.capitalized,
                            systemImage: workflowStore.settings.codexChatReasoningEffort == effort ? "checkmark" : "brain"
                        )
                    }
                }
            }
        } label: {
            Text(CodexChatModelCatalog.displayLabel(
                modelID: workflowStore.settings.codexChatModelID,
                effort: workflowStore.settings.codexChatReasoningEffort
            ))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Choose the Codex model and reasoning level for the next MCP chat request")
    }

    private var grokModelMenu: some View {
        Menu {
            Section("Grok Model") {
                ForEach(GrokChatModelCatalog.options) { option in
                    Button {
                        selectGrokModel(option)
                    } label: {
                        Label(
                            option.displayName,
                            systemImage: workflowStore.settings.grokChatModelID == option.id ? "checkmark" : "cpu"
                        )
                    }
                }
            }

            Section("Reasoning") {
                let selectedModelID = GrokChatModelCatalog.normalizedModelID(workflowStore.settings.grokChatModelID)
                let selectedModel = GrokChatModelCatalog.option(id: selectedModelID) ?? GrokChatModelCatalog.options[0]
                ForEach(selectedModel.reasoningEfforts, id: \.self) { effort in
                    Button {
                        workflowStore.updateSettings { settings in
                            settings.grokChatReasoningEffort = effort
                        }
                    } label: {
                        Label(
                            effort.capitalized,
                            systemImage: workflowStore.settings.grokChatReasoningEffort == effort ? "checkmark" : "brain"
                        )
                    }
                }
            }
        } label: {
            Text(GrokChatModelCatalog.displayLabel(
                modelID: workflowStore.settings.grokChatModelID,
                effort: workflowStore.settings.grokChatReasoningEffort
            ))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Choose the Grok model and reasoning level for the next MCP chat request")
    }

    // Q2: Qwen menu has no reasoning section — the Qwen CLI has no such flag.
    private var qwenModelMenu: some View {
        Menu {
            Section("Qwen Model") {
                ForEach(QwenChatModelCatalog.options) { option in
                    Button {
                        selectQwenModel(option)
                    } label: {
                        Label(
                            option.displayName,
                            systemImage: workflowStore.settings.qwenChatModelID == option.id ? "checkmark" : "cpu"
                        )
                    }
                }
            }
        } label: {
            Text(QwenChatModelCatalog.displayLabel(
                modelID: workflowStore.settings.qwenChatModelID
            ))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Choose the Qwen model for the next MCP chat request")
    }

    private func selectCodexModel(_ option: CodexChatModelOption) {
        workflowStore.updateSettings { settings in
            settings.codexChatModelID = option.id
            settings.codexChatReasoningEffort = option.defaultReasoningEffort
        }
    }

    private func selectGrokModel(_ option: GrokChatModelOption) {
        workflowStore.updateSettings { settings in
            settings.grokChatModelID = option.id
            settings.grokChatReasoningEffort = option.defaultReasoningEffort
        }
    }

    private func executeCodexRequest(history: [CodexChatHistoryItem]) async {
        do {
            let response = try await CodexAgentService.send(
                history: history,
                settings: workflowStore.settings
            )
            await MainActor.run {
                self.messages.append(MessageItem(sender: "assistant", text: response.text))
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.messages.append(MessageItem(sender: "system", text: error.localizedDescription))
                self.isLoading = false
            }
        }
    }

    private func executeGrokRequest(history: [GrokChatHistoryItem]) async {
        do {
            let response = try await GrokAgentService.send(
                history: history,
                settings: workflowStore.settings
            )
            await MainActor.run {
                self.messages.append(MessageItem(sender: "assistant", text: response.text))
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.messages.append(MessageItem(sender: "system", text: error.localizedDescription))
                self.isLoading = false
            }
        }
    }

    private func selectQwenModel(_ option: QwenChatModelOption) {
        workflowStore.updateSettings { settings in
            settings.qwenChatModelID = option.id
        }
    }

    private func executeQwenRequest(history: [QwenChatHistoryItem]) async {
        do {
            let response = try await QwenAgentService.send(
                history: history,
                settings: workflowStore.settings
            )
            await MainActor.run {
                self.messages.append(MessageItem(sender: "assistant", text: response.text))
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.messages.append(MessageItem(sender: "system", text: error.localizedDescription))
                self.isLoading = false
            }
        }
    }

    private func executeGeminiRequest(text: String, key: String) async {
        do {
            // Initial prompt contents
            var contents: [GeminiChatContent] = []
            for msg in messages {
                if msg.sender == "user" {
                    var parts: [GeminiChatPart] = [GeminiChatPart(text: msg.text)]
                    let imgPaths = self.extractImagePaths(from: msg.text)
                    for path in imgPaths {
                        var fullPath = path
                        if path.hasPrefix("~") {
                            fullPath = (path as NSString).expandingTildeInPath
                        }
                        if FileManager.default.fileExists(atPath: fullPath),
                           let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) {
                            let base64 = data.base64EncodedString()
                            let mime = fullPath.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
                            parts.append(GeminiChatPart(inlineData: GeminiInlineData(mimeType: mime, data: base64)))
                        }
                    }
                    contents.append(GeminiChatContent(role: "user", parts: parts))
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
                        parts: [GeminiChatPart(text: "You are the VaniScript AI Chat Assistant. Assist users by calling local tools to view state, edit translations, update subtitle styling, and structure vertical video shorts. Before any chunk or cue edit, call get_project_state and pass the exact numeric session.chunks[].index. Chunk indexes are zero-based: visible Chunk 5 requires chunkIndex 4. Never invent argument names such as chatindex. You are also a highly creative translation expert; suggest beautiful literary translations, rephrase subtitles, fix grammar, explain timeline cues, and converse naturally. CRITICAL: You must always respond to the user in the language they write in! If the user writes or speaks in Russian, you MUST respond in fluent Russian. If they write in English, respond in English. Do not speak English when the user addresses you in Russian. If the user provides a path to a screenshot/image, you can see and analyze it!")]
                    ),
                    tools: [
                        GeminiChatTool(
                            functionDeclarations: McpToolRegistry
                                .definitions(allowMutatingTools: true)
                                .map { GeminiToolDecl(definition: $0) }
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
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let errorMsg: String
                    if let apiError = try? JSONDecoder().decode(GeminiApiErrorResponse.self, from: data),
                       let msg = apiError.error?.message {
                        errorMsg = "API Error \(httpResponse.statusCode): \(msg)"
                    } else {
                        let bodyStr = String(data: data, encoding: .utf8) ?? ""
                        errorMsg = "HTTP Error \(httpResponse.statusCode): \(bodyStr.prefix(200))"
                    }
                    throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
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
                        result = try await workflowStore.executeMcpTool(
                            name: call.name,
                            arguments: (call.args ?? [:]).mapValues(\.value)
                        )
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

    private func checkModelPresence() {
        if NativeModelCatalog.activeWhisperKitModel(
            settings: workflowStore.settings,
            providerID: workflowStore.settings.transcriptionProvider
        ) == nil {
            showNoModelWarning = true
        } else {
            showNoModelWarning = false
        }
    }

    private func toggleDictation() {
        if isRecordingDictation {
            dictationRecorder?.stop()
            isRecordingDictation = false
            
            guard let url = dictationURL else { return }
            
            isLoading = true
            
            Task {
                do {
                    let text = try await workflowStore.transcribeDictation(url: url)
                    await MainActor.run {
                        let trimmed = self.workflowStore.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            self.workflowStore.chatInputText = text
                        } else {
                            self.workflowStore.chatInputText = trimmed + " " + text
                        }
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.messages.append(MessageItem(sender: "system", text: "Dictation failed: \(error.localizedDescription)"))
                        self.isLoading = false
                    }
                }
            }
        } else {
            if NativeModelCatalog.activeWhisperKitModel(
                settings: workflowStore.settings,
                providerID: workflowStore.settings.transcriptionProvider
            ) == nil {
                showNoModelWarning = true
                return
            }
            
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    Task { @MainActor in
                        self.messages.append(MessageItem(sender: "system", text: "Microphone permission denied. Please enable microphone access in System Settings."))
                    }
                    return
                }
                
                Task { @MainActor in
                    do {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("dictation_\(UUID().uuidString).wav")
                        self.dictationURL = tempURL
                        let rec = DictationRecorder(fileURL: tempURL)
                        try rec.start()
                        self.dictationRecorder = rec
                        self.isRecordingDictation = true
                    } catch {
                        self.messages.append(MessageItem(sender: "system", text: "Failed to start recording: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }

    private func extractImagePaths(from rawText: String) -> [String] {
        var cleanText = rawText.replacingOccurrences(of: "file://", with: "")
        var paths: [String] = []
        let extensions = [".png", ".jpg", ".jpeg", ".webp"]
        
        for ext in extensions {
            var searchRange = cleanText.startIndex..<cleanText.endIndex
            while let range = cleanText.range(of: ext, options: .caseInsensitive, range: searchRange) {
                let extEnd = range.upperBound
                var pathStart: String.Index? = nil
                
                var current = range.lowerBound
                var count = 0
                while current > cleanText.startIndex && count < 500 {
                    current = cleanText.index(before: current)
                    count += 1
                    let char = cleanText[current]
                    if char == "/" || char == "~" {
                        let candidate = String(cleanText[current..<extEnd])
                        var fullPath = candidate
                        if candidate.hasPrefix("~") {
                            fullPath = (candidate as NSString).expandingTildeInPath
                        }
                        if FileManager.default.fileExists(atPath: fullPath) {
                            pathStart = current
                            break
                        }
                    }
                }
                
                if let start = pathStart {
                    paths.append(String(cleanText[start..<extEnd]))
                }
                
                searchRange = extEnd..<cleanText.endIndex
            }
        }
        return paths
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

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String
}

struct GeminiChatPart: Codable {
    var text: String? = nil
    var functionCall: GeminiChatFunctionCall? = nil
    var functionResponse: GeminiChatFunctionResponse? = nil
    var inlineData: GeminiInlineData? = nil
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

    init(name: String, description: String, parameters: GeminiToolParams) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    init(definition: McpToolDefinition) {
        let properties = definition.inputSchema["properties"] as? [String: Any] ?? [:]
        self.init(
            name: definition.name,
            description: definition.description,
            parameters: GeminiToolParams(type: "object", properties: properties)
        )
    }
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

struct MiniWaveformView: View {
    @State private var animate = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: 2, height: animate ? CGFloat.random(in: 4...16) : 4)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.25...0.45))
                        .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(width: 18, height: 16)
        .onAppear {
            animate = true
        }
    }
}

struct GeminiApiErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }
    let error: ErrorDetail?
}
