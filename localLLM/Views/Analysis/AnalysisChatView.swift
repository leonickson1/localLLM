//
//  AnalysisChatView.swift
//  LocalLLM
//

import SwiftUI
import Charts

struct AnalysisMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var content: String
    var attachments: [String]? = nil

    enum MessageRole {
        case user
        case assistant
    }
}

struct AnalysisChatView: View {
    let context: String
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var financeManager: FinanceManager
    @State private var messages: [AnalysisMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @FocusState private var isFocused: Bool

    var initialQuery: String?

    private var systemPrompt: SystemPrompt {
        switch context {
        case "Health":
            return .healthCoach(healthContext: healthManager.healthContextString())
        case "Finance":
            return .financeAdvisor(financeContext: financeManager.financeContextString())
        default:
            return .chat
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SafetyBannerView()
                .animation(.easeInOut, value: inferenceManager.safetyWarning)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(messages) { message in
                            AnalysisMessageRow(message: message)
                        }

                        if isGenerating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyzing data...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .padding(.top, 20)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input Area
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask follow-up questions...", text: $inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .focused($isFocused)

                    if isGenerating {
                        Button {
                            inferenceManager.cancel()
                            isGenerating = false
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(!inputText.isEmpty ? .blue : .secondary.opacity(0.3))
                        }
                        .disabled(inputText.isEmpty || isGenerating)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
        }
        .navigationTitle("\(context) Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let query = initialQuery, messages.isEmpty {
                inputText = query
                sendMessage()
            }
        }
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMsg = AnalysisMessage(role: .user, content: inputText)
        messages.append(userMsg)

        inputText = ""
        isFocused = false
        isGenerating = true

        // Check if model is loaded
        guard inferenceManager.isModelLoaded else {
            messages.append(AnalysisMessage(
                role: .assistant,
                content: "Please load a model first from the Models tab to use the AI assistant."
            ))
            isGenerating = false
            return
        }

        // Build conversation for prompt
        let conversationTurns = messages.map { msg in
            MessageTurn(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            )
        }

        let fullPrompt = PromptFormatter.format(
            systemPrompt: systemPrompt,
            messages: conversationTurns,
            template: .chatml // Default to ChatML for analysis
        )

        // Create empty assistant message for streaming
        let assistantMsg = AnalysisMessage(role: .assistant, content: "")
        let msgId = assistantMsg.id
        messages.append(assistantMsg)

        Task {
            let stream = inferenceManager.generate(
                prompt: fullPrompt,
                parameters: parameterStore.asModelParameters
            )

            for await token in stream {
                if let index = messages.firstIndex(where: { $0.id == msgId }) {
                    messages[index].content += token
                }
            }

            isGenerating = false
        }
    }
}

struct AnalysisMessageRow: View {
    let message: AnalysisMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .foregroundStyle(.indigo)
                    .frame(width: 24, height: 24)
                    .background(.indigo.opacity(0.1))
                    .clipShape(Circle())
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 12) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color(uiColor: .secondarySystemBackground))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments, id: \.self) { attachment in
                        if attachment.starts(with: "chart_") {
                            DynamicChartView(type: attachment)
                                .frame(height: 200)
                                .padding()
                                .background(Color(uiColor: .secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.fill")
                    .foregroundStyle(.gray)
                    .frame(width: 24, height: 24)
                    .background(.gray.opacity(0.1))
                    .clipShape(Circle())
            } else {
                Spacer()
            }
        }
    }
}

struct DynamicChartView: View {
    let type: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(chartTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                if type == "chart_expenses" {
                    BarMark(x: .value("Cat", "Food"), y: .value("Val", 300)).foregroundStyle(.pink)
                    BarMark(x: .value("Cat", "Transport"), y: .value("Val", 150)).foregroundStyle(.blue)
                    BarMark(x: .value("Cat", "Shopping"), y: .value("Val", 420)).foregroundStyle(.purple)
                } else if type == "chart_steps" {
                    LineMark(x: .value("Day", "Mon"), y: .value("Steps", 5000))
                    LineMark(x: .value("Day", "Tue"), y: .value("Steps", 8000))
                    LineMark(x: .value("Day", "Wed"), y: .value("Steps", 6500))
                    LineMark(x: .value("Day", "Thu"), y: .value("Steps", 10000))
                } else {
                    RuleMark(y: .value("Ref", 100))
                    LineMark(x: .value("Time", "9AM"), y: .value("Val", 100))
                    LineMark(x: .value("Time", "10AM"), y: .value("Val", 120))
                    LineMark(x: .value("Time", "11AM"), y: .value("Val", 110))
                }
            }
        }
    }

    var chartTitle: String {
        switch type {
        case "chart_expenses": return "Expense Breakdown"
        case "chart_steps": return "Activity Trend"
        default: return "Data Visualization"
        }
    }
}
