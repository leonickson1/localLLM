//
//  ChatView.swift
//  LocalLLM
//
//  Unified chat interface with text, image, audio, and file capabilities.
//

import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import Speech

struct ChatMessage: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var content: String
    let isUser: Bool
    let timestamp: Date
    var imageData: Data?
    var tokensPerSecond: Double? = nil
    var timeToFirstToken: Double? = nil
    var totalTokens: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, tokensPerSecond, timeToFirstToken, totalTokens
        // imageData excluded from persistence (too large)
    }

    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date, imageData: Data? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.imageData = imageData
    }
}

struct ChatView: View {
    @State var model: AIModel
    var initialContext: ChatTag? = nil    // Set by Health/Finance "Ask AI" buttons
    var initialQuery: String? = nil

    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var financeManager: FinanceManager
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @EnvironmentObject var historyManager: ChatHistoryManager
    @StateObject private var swiftletEngine = SwiftletEngine.shared
    @State private var currentSessionId: UUID = UUID()
    @State private var messages: [ChatMessage] = []

    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showHistory = false
    @State private var modelLoadError: String?
    @State private var activeContext: ChatTag = .general
    @FocusState private var isInputFocused: Bool

    // Attachments
    @State private var isImporting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var attachedPDFName: String?
    @State private var attachedPDFText: String?
    @State private var showPDFPreview = false

    // Audio
    @StateObject private var recorder = AudioRecordingManager()
    @State private var isRecordingMode = false
    @State private var showTranscribing = false

    // Attachment menu
    @State private var showScrollToBottom = false

    // Navigation
    @State private var navigateToModels = false
    @State private var navigateToExperimental = false

    var body: some View {
        ZStack {
            TechBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SafetyBannerView()
                    .animation(.easeInOut, value: inferenceManager.safetyWarning)


                if messages.isEmpty && !isRecordingMode {
                    // Empty state
                    Spacer()
                    VStack(spacing: 32) {
                        VStack(spacing: 8) {
                            HStack(spacing: 0) {
                                Text("Local").font(.system(size: 42, weight: .thin))
                                Text(" Intelligence").font(.system(size: 42, weight: .bold))
                            }
                            .foregroundStyle(.primary)
                        }

                        // Experimental-model promo
                        Button {
                            navigateToExperimental = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Experimental: run a 35B model on your iPhone")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(modelManager.downloadedModels.contains(where: { $0.engineFormat == .swiftlet })
                                         ? "Qwen 3.6 35B is ready. Pick it in the model menu. First reply takes about 30 seconds."
                                         : "Runs from storage in ~2.5 GB of RAM. Tap to learn more and download.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.purple.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.purple.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        if modelManager.downloadedModels.isEmpty && !(ollamaService.isEnabled && ollamaService.isConnected) && !(openAICompat.isEnabled && openAICompat.isConnected) {
                            NoModelView(navigateToModels: $navigateToModels)
                        } else {
                            VStack(spacing: 8) {
                                // PDF preview on empty state
                                if let pdfName = attachedPDFName {
                                    PDFAttachmentCard(name: pdfName, charCount: attachedPDFText?.count ?? 0, isTruncated: attachedPDFText?.contains("[Truncated") ?? false, onTap: { showPDFPreview = true }) {
                                        attachedPDFName = nil
                                        attachedPDFText = nil
                                    }
                                    .padding(.horizontal, 24)
                                }

                                // Image preview on empty state
                                if let image = selectedImage {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(uiImage: image)
                                            .resizable().scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                            )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Image attached")
                                                .font(.system(size: 13, weight: .medium))
                                            Text("Will be analyzed with OCR")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Button {
                                            selectedImage = nil
                                            selectedItem = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    )
                                    .padding(.horizontal, 24)
                                }

                                UnifiedInputBar(
                                    text: $inputText,
                                    isGenerating: $isGenerating,
                                    selectedImage: $selectedImage,
                                    activeContext: $activeContext,
                                    chatOnlyModel: model.engineFormat == .swiftlet,
                                    isFocused: $isInputFocused,
                                    onPhotoPick: { showPhotoPicker = true },
                                    onDocumentPick: { isImporting = true },
                                    onAudioRecord: { isRecordingMode = true },
                                    onSend: sendMessage
                                )
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    Spacer()
                } else if isRecordingMode {
                    // Audio recording overlay
                    AudioRecordingOverlay(
                        recorder: recorder,
                        onDone: { transcription in
                            isRecordingMode = false
                            if !transcription.isEmpty {
                                inputText = transcription
                            }
                        },
                        onCancel: {
                            isRecordingMode = false
                        }
                    )
                } else {
                    // Citations banner
                    if activeContext == .health && !messages.isEmpty {
                        HealthCitationsBanner()
                    } else if activeContext == .finance && !messages.isEmpty {
                        FinanceCitationsBanner()
                    }

                    // Chat messages
                    ZStack(alignment: .bottom) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 24) {
                                    ForEach(messages) { message in
                                        MessageRow(message: message)
                                            .id(message.id)
                                    }

                                    if isGenerating {
                                        TypingIndicator()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 16)
                                    }

                                    if isGenerating && parameterStore.showBenchmarks && inferenceManager.tokensPerSecond > 0 {
                                        HStack(spacing: 16) {
                                            if parameterStore.showTokensPerSecond {
                                                Label("\(String(format: "%.1f", inferenceManager.tokensPerSecond)) tok/s", systemImage: "speedometer")
                                            }
                                            if parameterStore.showTTFT && inferenceManager.timeToFirstToken > 0 {
                                                Label("\(String(format: "%.2f", inferenceManager.timeToFirstToken))s TTFT", systemImage: "clock")
                                            }
                                        }
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .padding(.leading, 16)
                                    }

                                    // Anchor for scroll detection
                                    Color.clear.frame(height: 1).id("bottom_anchor")
                                }
                                .padding(.vertical, 24)
                                .padding(.bottom, 120)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("chatScroll")).maxY
                                        )
                                    }
                                )
                            }
                            .coordinateSpace(name: "chatScroll")
                            .scrollIndicators(.hidden)
                            .onPreferenceChange(ScrollOffsetKey.self) { maxY in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showScrollToBottom = maxY > 900
                                }
                            }
                            .onChange(of: messages.count) { _, _ in
                                if let last = messages.last {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if showScrollToBottom && !messages.isEmpty {
                                    Button {
                                        withAnimation {
                                            proxy.scrollTo("bottom_anchor", anchor: .bottom)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Circle().fill(Color(uiColor: .darkGray)))
                                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 130)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }

                        VStack(spacing: 8) {
                            if isGenerating {
                                Button {
                                    inferenceManager.cancel()
                                    isGenerating = false
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "stop.fill")
                                        Text("Stop")
                                    }
                                    .font(.caption.bold()).foregroundStyle(.red)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(.ultraThinMaterial).clipShape(Capsule())
                                }
                            }

                            // PDF preview (above input bar)
                            if let pdfName = attachedPDFName {
                                PDFAttachmentCard(name: pdfName, charCount: attachedPDFText?.count ?? 0, isTruncated: attachedPDFText?.contains("[Truncated") ?? false, onTap: { showPDFPreview = true }) {
                                    attachedPDFName = nil
                                    attachedPDFText = nil
                                }
                                .padding(.horizontal, 16)
                            }

                            // Image preview (above input bar)
                            if let image = selectedImage {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Image attached")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Will be analyzed with OCR")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Button {
                                        selectedImage = nil
                                        selectedItem = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                )
                                .padding(.horizontal, 16)
                            }

                            UnifiedInputBar(
                                text: $inputText,
                                isGenerating: $isGenerating,
                                selectedImage: $selectedImage,
                                activeContext: $activeContext,
                                chatOnlyModel: model.engineFormat == .swiftlet,
                                isFocused: $isInputFocused,
                                onPhotoPick: { showPhotoPicker = true },
                                onDocumentPick: { isImporting = true },
                                onAudioRecord: { isRecordingMode = true },
                                onSend: sendMessage
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerView(selectedModel: $model)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createNewChat() } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(manager: historyManager, currentSessionId: currentSessionId) { session in
                loadSession(session)
                showHistory = false
            } onDeleteCurrent: {
                currentSessionId = UUID()
                messages = []
                activeContext = .general
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.pdf, UTType.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        // Attachment menu handled by Menu in UnifiedInputBar
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showPDFPreview) {
            PDFTextPreviewSheet(name: attachedPDFName ?? "Document", text: attachedPDFText ?? "")
        }
        .navigationDestination(isPresented: $navigateToModels) {
            ModelsView()
        }
        .task { await loadModelIfNeeded() }
        .navigationDestination(isPresented: $navigateToExperimental) { ExperimentalModelsView() }
        .onChange(of: model.id) { _, _ in
            // The experimental model is chat-only: force the General context.
            if model.engineFormat == .swiftlet { activeContext = .general }
        }
        .onAppear {
            if let ctx = initialContext {
                activeContext = ctx
            }
            if let query = initialQuery, !query.isEmpty, messages.isEmpty {
                inputText = query
                sendMessage()
            }
        }
        .onDisappear {
            if inferenceManager.isGenerating { inferenceManager.cancel() }
            saveCurrentSession()
        }
    }

    // MARK: - Photo picker
    @State private var showPhotoPicker = false

    private func showImagePicker() {
        showPhotoPicker = true
    }

    // MARK: - Model Loading

    private func loadModelIfNeeded() async {
        // Streamed MoE models load through the Swiftlet engine; the llama.cpp
        // RAM-fit gate doesn't apply (they run bigger-than-RAM by design).
        if model.engineFormat == .swiftlet {
            guard swiftletEngine.currentModelId != model.id || !swiftletEngine.isModelLoaded else { return }
            if FileManager.default.fileExists(atPath: model.localPath.path) {
                await swiftletEngine.loadModel(model)
                if let error = swiftletEngine.loadError { modelLoadError = error }
            }
            return
        }

        // If already loaded, skip
        guard inferenceManager.currentModelId != model.id else { return }

        // Try to find a downloaded model to load
        if let downloaded = modelManager.downloadedModels.first(where: { $0.engineFormat == .gguf }) {
            // Use the first downloaded model if current selection isn't downloaded
            let modelToLoad = FileManager.default.fileExists(atPath: model.localPath.path) ? model : downloaded
            model = modelToLoad
            await inferenceManager.loadModel(modelToLoad)
            if let error = inferenceManager.loadError { modelLoadError = error }
        } else {
            // No models downloaded at all
            modelLoadError = nil // Don't show error, the NoModelView handles this
        }
    }

    // MARK: - Chat Management

    private func createNewChat() {
        saveCurrentSession()
        currentSessionId = UUID()
        withAnimation {
            messages = []
            inputText = ""
            isGenerating = false
            selectedImage = nil
            attachedPDFName = nil
            attachedPDFText = nil
        }
    }

    private func loadSession(_ session: ChatSession) {
        saveCurrentSession()
        currentSessionId = session.id
        activeContext = session.tag
        withAnimation { messages = session.messages }
    }

    private func saveCurrentSession() {
        guard !messages.isEmpty else { return }
        let session = ChatSession(
            id: currentSessionId,
            title: messages.first?.content.prefix(30).trimmingCharacters(in: .whitespacesAndNewlines) ?? "New Chat",
            messages: messages,
            timestamp: Date(),
            isPinned: false,
            tag: activeContext
        )
        historyManager.saveSession(session)
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }

            // MUST access security-scoped resource BEFORE reading any file properties
            guard selectedFile.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access this file. Try saving it to your device first, then importing from Files."
                showError = true
                return
            }
            defer { selectedFile.stopAccessingSecurityScopedResource() }

            let resources = try selectedFile.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = resources.fileSize ?? 0
            if fileSize > 10 * 1024 * 1024 {
                errorMessage = "File too large (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Maximum is 10 MB."
                showError = true
                return
            }

            if selectedFile.pathExtension.lowercased() == "pdf" {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(selectedFile.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.copyItem(at: selectedFile, to: tempURL)
                let fileName = selectedFile.lastPathComponent

                Task {
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    if let text = try? await PDFTextExtractor.extractText(from: tempURL), !text.isEmpty {
                        await MainActor.run {
                            attachedPDFName = fileName
                            // Dynamic truncation based on model's context window
                            let maxChars = PromptFormatter.charsForTokens(inferenceManager.activeContextWindow) - 1000 // leave room for prompt + response
                            let limit = max(2000, maxChars)
                            if text.count > limit {
                                attachedPDFText = String(text.prefix(limit)) + "\n\n[Truncated - PDF was \(text.count.formatted()) characters, showing first \(limit.formatted()) for this model's context window]"
                            } else {
                                attachedPDFText = text
                            }
                        }
                    } else {
                        await MainActor.run {
                            errorMessage = "Could not read PDF. It may be password-protected or image-only."
                            showError = true
                        }
                    }
                }
            } else {
                if let data = try? Data(contentsOf: selectedFile),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            showError = true
        }
    }

    private func extractPDFText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            text += doc.page(at: i)?.string ?? ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Send Message (Unified: text + image + audio context)

    private var contextDisclaimer: String? {
        switch activeContext {
        case .health:
            return "This is not medical advice. Health insights are generated by a local AI model for informational purposes only. Always consult a qualified healthcare provider for medical decisions."
        case .finance:
            return "This is not financial advice. Spending analysis is generated by a local AI model for personal tracking only. Consult a qualified financial advisor for financial decisions."
        case .journal, .general:
            return nil
        }
    }

    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || selectedImage != nil else { return }

        // Add disclaimer + connection nudge as first message if health/finance context
        if messages.isEmpty {
            var firstMessages: [String] = []

            if let disclaimer = contextDisclaimer {
                firstMessages.append(disclaimer)
            }

            // Nudge user to connect data if not available
            if activeContext == .health && !healthManager.isAuthorized {
                firstMessages.append("You haven't connected Apple Health yet. Go to the Health tab and tap \"Sync Health Data\" so I can give you personalized insights.")
            } else if activeContext == .finance && financeManager.transactions.isEmpty {
                firstMessages.append("No financial data loaded yet. Go to the Finance tab and upload a bank statement so I can analyze your spending.")
            }

            for text in firstMessages {
                messages.append(ChatMessage(content: text, isUser: false, timestamp: Date()))
            }
        }

        // Build user message
        var userContent = trimmedText
        let attachedImage = selectedImage
        let pdfContext = attachedPDFText
        let pdfName = attachedPDFName

        // If image attached, add OCR context
        if attachedImage != nil {
            if userContent.isEmpty {
                userContent = "Analyze this image."
            }
        }

        // If PDF attached, prepend as context
        if let pdfText = pdfContext, let name = pdfName {
            if userContent.isEmpty {
                userContent = "Analyze this document."
            }
            userContent = "[Document: \(name)]\n\(pdfText)\n\nUser question: \(userContent)"
            attachedPDFName = nil
            attachedPDFText = nil
        }

        let userMessage = ChatMessage(
            content: userContent,
            isUser: true,
            timestamp: Date(),
            imageData: attachedImage?.jpegData(compressionQuality: 0.3)
        )
        withAnimation { messages.append(userMessage) }

        isInputFocused = false
        inputText = ""
        selectedImage = nil
        selectedItem = nil
        isGenerating = true

        // Route to whichever backend the user has selected.
        // Priority: explicit OpenAI-compat selection > explicit Ollama selection > on-device.
        let useOpenAICompat = openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty
        let useOllama = !useOpenAICompat && ollamaService.isEnabled && ollamaService.isConnected && !ollamaService.selectedModel.isEmpty
        let useSwiftlet = !useOpenAICompat && !useOllama && model.engineFormat == .swiftlet
        if useSwiftlet && activeContext != .general {
            let notice = ChatMessage(
                content: "Health, Finance, and Journal contexts aren't available with this experimental model. It supports general chat only. Switch the context back to General, or download a smaller model (like Qwen 2.5 1.5B) for those features.",
                isUser: false, timestamp: Date()
            )
            withAnimation { messages.append(notice); isGenerating = false }
            return
        }
        if useOpenAICompat || useOllama { inferenceManager.setOllamaContext() }

        guard inferenceManager.isModelLoaded || useOllama || useOpenAICompat
                || (useSwiftlet && swiftletEngine.isModelLoaded) else {
            let errorMsg = ChatMessage(
                content: "No model available. Download a local model, or connect to Ollama / an OpenAI-compatible server in Settings.",
                isUser: false, timestamp: Date()
            )
            withAnimation { messages.append(errorMsg); isGenerating = false }
            return
        }

        Task {
            // Process image context
            var imageContext = ""
            if let image = attachedImage {
                do {
                    let ocrText = try await VisionTextExtractor.extractText(from: image)
                    if !ocrText.isEmpty { imageContext += "Text found in image:\n\(ocrText)\n\n" }
                    let description = try await VisionTextExtractor.describeImage(image)
                    imageContext += "Image analysis: \(description)\n"
                } catch {
                    imageContext += "Could not analyze image.\n"
                }
            }

            // Build conversation
            var conversationTurns = messages.map { msg in
                MessageTurn(role: msg.isUser ? "user" : "assistant", content: msg.content)
            }

            if !imageContext.isEmpty, let lastIndex = conversationTurns.indices.last {
                let original = conversationTurns[lastIndex].content
                conversationTurns[lastIndex] = MessageTurn(
                    role: "user", content: "Image context:\n\(imageContext)\nUser question: \(original)"
                )
            }

            // System prompt
            let systemPrompt: SystemPrompt
            if attachedImage != nil {
                systemPrompt = .vision
            } else {
                switch activeContext {
                case .health: systemPrompt = .healthCoach(healthContext: healthManager.healthContextString())
                case .finance: systemPrompt = .financeAdvisor(financeContext: financeManager.financeContextString())
                case .journal, .general: systemPrompt = .chat
                }
            }

            // Create empty assistant message for streaming
            let assistantMessage = ChatMessage(content: "", isUser: false, timestamp: Date())
            let messageId = assistantMessage.id
            await MainActor.run {
                withAnimation { messages.append(assistantMessage) }
            }

            if useOpenAICompat {
                let userText = conversationTurns.last?.content ?? ""
                let stream = openAICompat.streamChat(
                    systemPrompt: systemPrompt.text,
                    userMessage: userText
                )
                for await token in stream {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index].content += token
                    }
                }
            } else if useOllama {
                let userText = conversationTurns.last?.content ?? ""
                let stream = ollamaService.streamChat(
                    systemPrompt: systemPrompt.text,
                    userMessage: userText
                )
                for await token in stream {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index].content += token
                    }
                }
            } else if useSwiftlet {
                // Streamed MoE path: the model's own chat template is applied
                // by the engine (tokenizer-native), not PromptFormatter, and
                // the session disables the reasoning block itself. The prompt
                // drops "Be concise" — on this quantized model it pulls EOS
                // so hard that replies stop after a couple of tokens.
                let swiftletSystem = "You are a helpful AI assistant running locally on the user's device. Answer clearly and completely. All processing happens on-device for privacy."
                var chatTurns: [[String: String]] = [["role": "system", "content": swiftletSystem]]
                chatTurns += conversationTurns.map { ["role": $0.role, "content": $0.content] }
                let stream = swiftletEngine.streamChat(
                    messages: chatTurns,
                    maxTokens: parameterStore.asModelParameters.maxTokens
                )
                for await token in stream {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index].content += token
                    }
                }
            } else {
                let fullPrompt = PromptFormatter.format(
                    systemPrompt: systemPrompt,
                    messages: conversationTurns,
                    template: model.chatTemplate,
                    contextTokens: inferenceManager.activeContextWindow
                )
                let stream = inferenceManager.generate(
                    prompt: fullPrompt,
                    parameters: parameterStore.asModelParameters
                )
                for await token in stream {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index].content += token
                    }
                }
            }

            // Stamp benchmark data onto the finished message
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                let tps = useSwiftlet ? swiftletEngine.tokensPerSecond : inferenceManager.tokensPerSecond
                let ttft = useSwiftlet ? swiftletEngine.timeToFirstToken : inferenceManager.timeToFirstToken
                let total = useSwiftlet ? swiftletEngine.totalTokens : inferenceManager.totalTokens
                messages[index].tokensPerSecond = tps > 0 ? tps : nil
                messages[index].timeToFirstToken = ttft > 0 ? ttft : nil
                messages[index].totalTokens = total > 0 ? total : nil
            }

            isGenerating = false
            saveCurrentSession()
        }
    }
}

// MARK: - Unified Input Bar

struct UnifiedInputBar: View {
    @Binding var text: String
    @Binding var isGenerating: Bool
    @Binding var selectedImage: UIImage?
    @Binding var activeContext: ChatTag
    /// Chat-only model (the experimental 35B): Health/Finance/Journal
    /// contexts are disabled in the switcher.
    var chatOnlyModel: Bool = false
    var isFocused: FocusState<Bool>.Binding
    let onPhotoPick: () -> Void
    let onDocumentPick: () -> Void
    let onAudioRecord: () -> Void
    let onSend: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }

    private var placeholder: String {
        switch activeContext {
        case .general: return "Ask anything..."
        case .health: return "Ask about your health..."
        case .finance: return "Ask about your spending..."
        case .journal: return "Ask about your journal..."
        }
    }

    var body: some View {
        VStack(spacing: 4) {
        VStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .focused(isFocused)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .frame(minHeight: 40)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .contentShape(Rectangle())
                .onTapGesture { isFocused.wrappedValue = true }

            HStack(spacing: 12) {
                // Plus (attach) - Menu appears near button
                Menu {
                    Button { onPhotoPick() } label: {
                        Label("Photo Library", systemImage: "photo")
                    }
                    Button { onDocumentPick() } label: {
                        Label("Document (PDF)", systemImage: "doc.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selectedImage != nil ? .blue : .secondary)
                        .frame(width: 36, height: 36)
                }

                // Mic (audio)
                Button(action: onAudioRecord) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                // Context mode toggle
                Menu {
                    ForEach(ChatTag.allCases, id: \.self) { tag in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { activeContext = tag }
                        } label: {
                            Label(tag.rawValue, systemImage: tag.icon)
                            if activeContext == tag {
                                Image(systemName: "checkmark")
                            }
                        }
                        .disabled(chatOnlyModel && tag != .general)
                    }
                    if chatOnlyModel {
                        Divider()
                        // Menu rows truncate to one line; keep each short.
                        Text("This experimental model is chat-only.")
                        Text("Other features need a smaller model.")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: activeContext.icon)
                            .font(.system(size: 13, weight: .semibold))
                        if activeContext != .general {
                            Text(activeContext.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(activeContext == .general ? .secondary : activeContext.color)
                    .padding(.horizontal, activeContext == .general ? 8 : 10)
                    .padding(.vertical, 6)
                    .background(
                        activeContext == .general
                        ? Color.primary.opacity(0.05)
                        : activeContext.color.opacity(0.12)
                    )
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.2), value: activeContext)
                }

                Spacer()

                // Send
                if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.primary))
                    }
                    .disabled(isGenerating)
                }
            }
            .padding(.horizontal, 7)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                (colorScheme == .light ? Color.white.opacity(0.8) : Color.black.opacity(0.2))
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .light ? 0.1 : 0.2), radius: 20, x: 0, y: 8)
        // Typing stays available while generating (send is gated separately),
        // so the user can compose their next message during a slow reply.

            Text("AI can make mistakes. Double-check important info.")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Audio Recording Overlay

struct AudioRecordingOverlay: View {
    @ObservedObject var recorder: AudioRecordingManager
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var transcriber = TranscriptionManager()
    @State private var showPermissionError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Recording indicator
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .scaleEffect(recorder.isRecording ? 1.0 + CGFloat(recorder.audioLevel) * 2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)

                Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(recorder.isRecording ? .red : .blue)
            }

            // Duration
            if recorder.isRecording || recorder.duration > 0 {
                Text(formatDuration(recorder.duration))
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // Status text
            if transcriber.isTranscribing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Transcribing...").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if !transcriber.transcription.isEmpty {
                Text(transcriber.transcription)
                    .font(.body)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            Spacer()

            // Controls
            HStack(spacing: 40) {
                Button { onCancel() } label: {
                    Text("Cancel").font(.headline).foregroundStyle(.red)
                        .frame(width: 100, height: 50)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if !recorder.isRecording && recorder.duration > 0 {
                    // Transcribe and send
                    Button {
                        transcribeAndSend()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Use")
                        }
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 120, height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(transcriber.isTranscribing)
                } else {
                    Button {
                        toggleRecording()
                    } label: {
                        HStack {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            Text(recorder.isRecording ? "Stop" : "Record")
                        }
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 120, height: 50)
                        .background(recorder.isRecording ? Color.red : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .alert("Permission Required", isPresented: $showPermissionError) {
            Button("OK") { onCancel() }
        } message: {
            Text("Microphone access is required for audio recording.")
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            _ = recorder.stopRecording()
        } else {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        try? recorder.startRecording()
                    } else {
                        showPermissionError = true
                    }
                }
            }
        }
    }

    private func transcribeAndSend() {
        guard let url = recorder.recordingURL else { return }
        Task {
            let authorized = await transcriber.requestAuthorization()
            guard authorized else {
                showPermissionError = true
                return
            }
            await transcriber.transcribe(audioURL: url)
            if !transcriber.transcription.isEmpty {
                onDone(transcriber.transcription)
            }
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Chat History View

// MARK: - Chat History View (with tags)

struct ChatHistoryView: View {
    @ObservedObject var manager: ChatHistoryManager
    @Environment(\.dismiss) var dismiss
    let currentSessionId: UUID
    let onSelect: (ChatSession) -> Void
    let onDeleteCurrent: () -> Void
    @State private var filterTag: ChatTag? = nil

    var filteredSessions: [ChatSession] {
        manager.sessions(for: filterTag)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tag filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPill(label: "All", isActive: filterTag == nil) {
                            filterTag = nil
                        }
                        ForEach(ChatTag.allCases, id: \.self) { tag in
                            FilterPill(label: tag.rawValue, color: tag.color, isActive: filterTag == tag) {
                                filterTag = filterTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                List {
                    ForEach(filteredSessions) { session in
                        Button { onSelect(session) } label: {
                            HStack(spacing: 12) {
                                // Tag icon
                                Image(systemName: session.tag.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(session.tag.color)
                                    .frame(width: 28, height: 28)
                                    .background(session.tag.color.opacity(0.12))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(session.tag.rawValue)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(session.tag.color)
                                        Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                if session.isPinned {
                                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { manager.togglePin(id: session.id) } label: {
                                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
                            }.tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                let wasCurrentSession = session.id == currentSessionId
                                manager.deleteSession(id: session.id)
                                if wasCurrentSession {
                                    onDeleteCurrent()
                                    dismiss()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .overlay {
                if filteredSessions.isEmpty {
                    ContentUnavailableView("No Chats", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
    }
}

struct FilterPill: View {
    let label: String
    var color: Color = .blue
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(isActive ? color.opacity(0.15) : Color.primary.opacity(0.06))
                .foregroundStyle(isActive ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isActive ? color.opacity(0.3) : .clear, lineWidth: 1))
        }
    }
}

// MARK: - No Model View

struct NoModelView: View {
    @Binding var navigateToModels: Bool
    @State private var navigateToSettings = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Get Started")
                    .font(.system(size: 20, weight: .bold))

                Text("Download a model to run AI on your device,\nor connect Ollama for larger models.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                Button {
                    navigateToModels = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.box.fill")
                        Text("Browse Models")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                }

                Button {
                    navigateToSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                        Text("Set Up Ollama")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
            }

            VStack(spacing: 6) {
                Text("Recommended to start:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("SmolLM2 360M (386 MB)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    @EnvironmentObject var parameterStore: ParameterStore
    @State private var copied = false

    // Models reply in markdown (**bold**, `code`); render it instead of
    // showing raw asterisks. Inline-only keeps line breaks and list text
    // exactly as generated.
    private var renderedContent: AttributedString {
        (try? AttributedString(
            markdown: message.content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(message.content)
                        .font(.system(size: 16)).foregroundStyle(.primary)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(uiColor: .systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)

                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(.secondary))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack {
                            Circle().fill(Color.primary).frame(width: 24, height: 24)
                            Image(systemName: "sparkles").font(.system(size: 10))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                        }
                        Text("Assistant").font(.caption.bold()).foregroundStyle(.primary)
                    }

                    Text(renderedContent)
                        .font(.system(size: 16)).foregroundStyle(.primary).lineSpacing(4)

                    // Benchmark stats + Copy button
                    HStack(spacing: 12) {
                        if parameterStore.showBenchmarks, let tps = message.tokensPerSecond {
                            if parameterStore.showTokensPerSecond {
                                Text("\(String(format: "%.1f", tps)) tok/s")
                            }
                            if parameterStore.showTTFT, let ttft = message.timeToFirstToken {
                                Text("\(String(format: "%.2f", ttft))s TTFT")
                            }
                            if let tokens = message.totalTokens {
                                Text("\(tokens) tokens")
                            }
                        }

                        Spacer()

                        Button {
                            UIPasteboard.general.string = message.content
                            withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(copied ? .green : .secondary)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: animating)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { animating = true }
    }
}

// MARK: - PDF Attachment Card

struct PDFAttachmentCard: View {
    let name: String
    let charCount: Int
    var isTruncated: Bool = false
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
                .frame(width: 48, height: 48)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text("\(charCount.formatted()) characters extracted")
                    .font(.caption2).foregroundStyle(.secondary)
                if isTruncated {
                    Text("Truncated to fit context window")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .onTapGesture(perform: onTap)
    }
}

// MARK: - PDF Text Preview Sheet

struct PDFTextPreviewSheet: View {
    let name: String
    let text: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key

// MARK: - Health Citations Banner

struct HealthCitationsBanner: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Not medical advice. Sources & disclaimers")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Health insights are AI-generated for informational purposes only. Always consult a qualified healthcare provider for medical decisions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("Sources:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Link("CDC Physical Activity Guidelines",
                         destination: URL(string: "https://www.cdc.gov/physicalactivity/basics/adults/index.htm")!)
                        .font(.system(size: 11))
                    Link("WHO Physical Activity Recommendations",
                         destination: URL(string: "https://www.who.int/news-room/fact-sheets/detail/physical-activity")!)
                        .font(.system(size: 11))
                    Link("CDC Sleep Recommendations",
                         destination: URL(string: "https://www.cdc.gov/sleep/about_sleep/how_much_sleep.html")!)
                        .font(.system(size: 11))
                    Link("AHA Target Heart Rate",
                         destination: URL(string: "https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates")!)
                        .font(.system(size: 11))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Finance Citations Banner

struct FinanceCitationsBanner: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Not financial advice. Sources & disclaimers")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI-generated insights are for personal tracking only. Consult a qualified financial advisor for financial decisions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("Sources:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Link("Consumer Financial Protection Bureau",
                         destination: URL(string: "https://www.consumerfinance.gov/")!)
                        .font(.system(size: 11))
                    Link("FTC Consumer Advice on Budgeting",
                         destination: URL(string: "https://consumer.ftc.gov/articles/making-budget")!)
                        .font(.system(size: 11))
                    Link("MyMoney.gov - Federal Resource",
                         destination: URL(string: "https://www.mymoney.gov/")!)
                        .font(.system(size: 11))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
