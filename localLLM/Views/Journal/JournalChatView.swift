//
//  JournalChatView.swift
//  LocalLLM
//
//  Chat-with-your-journal. Sends the user's recent entries as system context to the active
//  backend, then streams the response. Quick-suggested chips at the start to lower friction.
//

import SwiftUI

struct JournalChatView: View {
    @EnvironmentObject var journalManager: JournalManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @EnvironmentObject var parameterStore: ParameterStore

    @State private var inputText: String = ""
    @State private var messages: [JournalChatMessage] = []
    @State private var isStreaming = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var contextInfo: JournalContextBuilder.Build?
    @FocusState private var inputFocused: Bool

    private let suggestedQuestions = [
        "What patterns do you see in my entries?",
        "What's been on my mind lately?",
        "When did I last feel good?",
        "What topics keep coming up?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let info = contextInfo {
                contextBanner(info: info)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                        if isStreaming, messages.last?.isUser == true {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .onAppear {
            if contextInfo == nil { rebuildContext() }
        }
    }

    // MARK: - Pieces

    private func contextBanner(info: JournalContextBuilder.Build) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if info.totalCount == 0 {
                Text("No entries to chat about yet.")
            } else if info.wasTruncated {
                Text("Showing \(info.includedCount) of \(info.totalCount) entries to your model.")
            } else {
                Text("Your model sees all \(info.totalCount) entries.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat with your journal")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Ask anything about what you've written.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)

            Text("TRY ASKING")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { q in
                    Button {
                        send(text: q)
                    } label: {
                        HStack {
                            Text(q)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(BentoBackground())
                    }
                    .buttonStyle(.plain)
                    .disabled(journalManager.entries.isEmpty)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func messageBubble(_ msg: JournalChatMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }
            Text(msg.text.isEmpty ? "…" : msg.text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(msg.isUser ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    msg.isUser
                    ? AnyShapeStyle(Color.indigo)
                    : AnyShapeStyle(Color.primary.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isStreaming ? 1.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: isStreaming
                        )
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your journal", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused($inputFocused)
                .disabled(isStreaming)

            Button {
                if isStreaming {
                    streamingTask?.cancel()
                    isStreaming = false
                } else {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { send(text: text) }
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(isStreaming ? Color.red : (canSend ? Color.indigo : Color.gray)))
            }
            .disabled(!isStreaming && !canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - State

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && backendAvailable
    }

    private var backendAvailable: Bool {
        (openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty) ||
        (ollamaService.isEnabled && ollamaService.isConnected) ||
        inferenceManager.isModelLoaded
    }

    private func rebuildContext() {
        let budget = JournalContextBuilder.budget(
            openAICompatActive: openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty,
            ollamaActive: ollamaService.isEnabled && ollamaService.isConnected,
            localContextTokens: inferenceManager.activeContextWindow
        )
        contextInfo = JournalContextBuilder.build(entries: journalManager.entries, budget: budget)
    }

    // MARK: - Send

    private func send(text: String) {
        guard !text.isEmpty, !isStreaming else { return }

        if contextInfo == nil { rebuildContext() }
        let context = contextInfo?.prompt ?? "(No journal entries yet.)"

        let userMsg = JournalChatMessage(text: text, isUser: true)
        messages.append(userMsg)
        inputText = ""

        let placeholder = JournalChatMessage(text: "", isUser: false)
        messages.append(placeholder)
        let assistantId = placeholder.id

        isStreaming = true
        let systemPrompt = SystemPrompt.journalAssistant(journalContext: context).text

        streamingTask = Task {
            await streamBackend(systemPrompt: systemPrompt, userMessage: text) { token in
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].text += token
                }
            }
            await MainActor.run { self.isStreaming = false }
        }
    }

    private func streamBackend(systemPrompt: String, userMessage: String, onToken: @escaping (String) -> Void) async {
        let useOpenAI = openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty
        let useOllama = !useOpenAI && ollamaService.isEnabled && ollamaService.isConnected
        let useLocal  = !useOpenAI && !useOllama && inferenceManager.isModelLoaded

        if useOpenAI {
            let stream = openAICompat.streamChat(systemPrompt: systemPrompt, userMessage: userMessage)
            for await token in stream { onToken(token) }
        } else if useOllama {
            let stream = ollamaService.streamChat(systemPrompt: systemPrompt, userMessage: userMessage)
            for await token in stream { onToken(token) }
        } else if useLocal {
            let formatted = PromptFormatter.format(
                systemPrompt: systemPrompt,
                messages: [MessageTurn(role: "user", content: userMessage)],
                template: .chatml,
                contextTokens: inferenceManager.activeContextWindow
            )
            let stream = inferenceManager.generate(prompt: formatted, parameters: parameterStore.asModelParameters)
            for await token in stream { onToken(token) }
        } else {
            // No backend — write a hint into the assistant message
            await MainActor.run {
                if modelManager.onlyChatOnlyModelsInstalled {
                    onToken("The 35B experimental model is chat-only and can't power Journal features. Download a smaller model (like Qwen 2.5 1.5B) to use this.")
                } else {
                    onToken("No model is available. Connect Ollama, an OpenAI-compatible server, or load a local model in Settings.")
                }
            }
        }
    }
}

// MARK: - Chat message

struct JournalChatMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    let isUser: Bool
}
