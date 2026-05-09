//
//  PromptLabView.swift
//  LocalLLM
//

import SwiftUI

enum PromptTemplate: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case rewrite = "Rewrite"
    case generateCode = "Generate Code"
    case translate = "Translate"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .generateCode: return "chevron.left.forwardslash.chevron.right"
        case .translate: return "character.bubble"
        case .custom: return "wand.and.stars"
        }
    }

    var placeholder: String {
        switch self {
        case .summarize: return "Enter text to summarize..."
        case .rewrite: return "Enter text to rewrite..."
        case .generateCode: return "Describe the code you want to generate..."
        case .translate: return "Enter text to translate..."
        case .custom: return "Enter your custom prompt..."
        }
    }

}

struct PromptLabView: View {
    @State var model: AIModel
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @State private var selectedTemplate: PromptTemplate = .custom
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isGenerating = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Template Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose a Template")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PromptTemplate.allCases) { template in
                                TemplateChip(
                                    template: template,
                                    isSelected: selectedTemplate == template
                                ) {
                                    selectedTemplate = template
                                    outputText = ""
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Input")
                        .font(.headline)

                    TextEditor(text: $inputText)
                        .focused($isInputFocused)
                        .frame(minHeight: 150)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            Group {
                                if inputText.isEmpty {
                                    Text(selectedTemplate.placeholder)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 16)
                                        .padding(.top, 20)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .allowsHitTesting(false)
                                }
                            }
                        )
                }
                .padding(.horizontal)

                // Generate Button
                Button {
                    generateResponse()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGenerating ? "Generating..." : "Generate")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(inputText.isEmpty || isGenerating)
                .padding(.horizontal)

                // Stop Button
                if isGenerating {
                    Button {
                        inferenceManager.cancel()
                        isGenerating = false
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                    }
                }

                // Output Section
                if !outputText.isEmpty || isGenerating {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Output")
                                .font(.headline)

                            Spacer()

                            if inferenceManager.tokensPerSecond > 0 {
                                Text("\(String(format: "%.1f", inferenceManager.tokensPerSecond)) tok/s")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if !outputText.isEmpty {
                                Button {
                                    UIPasteboard.general.string = outputText
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.subheadline)
                                }
                            }
                        }

                        ScrollView {
                            Text(outputText.isEmpty ? " " : outputText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .frame(minHeight: 150)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Prompt Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerView(selectedModel: $model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
        .task {
            if inferenceManager.currentModelId != model.id && model.isDownloaded {
                await inferenceManager.loadModel(model)
            }
        }
    }

    private func generateResponse() {
        isInputFocused = false
        isGenerating = true
        outputText = ""

        guard inferenceManager.isModelLoaded else {
            outputText = "Model is not loaded. Please download and load a model first."
            isGenerating = false
            return
        }

        let fullPrompt = PromptFormatter.format(
            systemPrompt: .promptLab(selectedTemplate),
            messages: [MessageTurn(role: "user", content: inputText)],
            template: model.chatTemplate
        )

        Task {
            let stream = inferenceManager.generate(
                prompt: fullPrompt,
                parameters: parameterStore.asModelParameters
            )

            for await token in stream {
                withAnimation(.none) {
                    outputText += token
                }
            }

            isGenerating = false
        }
    }
}

struct TemplateChip: View {
    let template: PromptTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: template.icon)
                Text(template.rawValue)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isSelected ?
                AnyView(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )) :
                AnyView(Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

#Preview {
    NavigationStack {
        PromptLabView(model: AIModel.sampleModels[0])
    }
}
