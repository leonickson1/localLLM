//
//  EmbeddedChatView.swift
//  LocalLLM
//
//
//

import SwiftUI

struct FloatingChatPanel: View {
    let context: String
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.indigo)
                    Text("AI Assistant")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button {
                        withAnimation(.spring()) {
                            isExpanded = false
                            isFocused = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 20))
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if messages.isEmpty {
                                EmptyStateView(context: context)
                                    .padding(.vertical, 40)
                            } else {
                                ForEach(messages) { message in
                                    EmbeddedMessageRow(message: message)
                                }
                            }
                            
                            if isGenerating {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Analyzing...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color(uiColor: .systemBackground).opacity(0.9))
            }
            
            // Input Area (Always visible)
            HStack(spacing: 12) {
                if !isExpanded {
                    Button {
                        withAnimation(.spring()) {
                            isExpanded = true
                            isFocused = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Ask AI about \(context)...")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    TextField("Ask a question...", text: $inputText)
                        .font(.system(size: 14))
                        .focused($isFocused)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                
                if isExpanded {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(!inputText.isEmpty && !isGenerating ? Color.indigo : Color.secondary.opacity(0.3))
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        let userMsg = ChatMessage(content: inputText, isUser: true, timestamp: Date())
        withAnimation {
            messages.append(userMsg)
        }
        
        let query = inputText
        inputText = ""
        isGenerating = true
        
        // Mock response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let response = generateMockResponse(for: query, context: context)
            let aiMsg = ChatMessage(content: response, isUser: false, timestamp: Date())
            withAnimation {
                messages.append(aiMsg)
                isGenerating = false
            }
        }
    }
    
    private func generateMockResponse(for query: String, context: String) -> String {
        if context == "Finance" {
            return "Based on your transaction history, you've spent 15% more on dining out this month compared to last month. The split for the Mario's dinner is $41.50 per person."
        } else {
            return "Your step count is trending upwards. You're averaging 8,500 steps this week, which is consistent with your goal of improving cardiovascular health."
        }
    }
}

// Keep the old view for compatibility or refactoring
struct EmbeddedChatView: View {
    let context: String
    var body: some View {
        FloatingChatPanel(context: context)
    }
}

// Reuse existing helper views
struct EmptyStateView: View {
    let context: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Ask AI about your \(context.lowercased())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmbeddedMessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
            } else {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.indigo.opacity(0.1)))
            }
            
            Text((try? AttributedString(
                markdown: message.content,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message.content))
                .font(.system(size: 14))
                .foregroundStyle(message.isUser ? .white : .primary)
                .padding(12)
                .background(
                    message.isUser ? Color.indigo : Color(uiColor: .secondarySystemBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            if message.isUser {
                Spacer()
            }
        }
    }
}
