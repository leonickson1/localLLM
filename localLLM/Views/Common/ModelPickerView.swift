//
//  ModelPickerView.swift
//  LocalLLM
//
//  Model picker - shows local models AND Ollama models when connected.
//

import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @ObservedObject var swiftletEngine = SwiftletEngine.shared
    @Binding var selectedModel: AIModel
    @State private var navigateToModels = false

    var downloadedModels: [AIModel] {
        modelManager.downloadedModels
    }

    var isUsingOllama: Bool {
        ollamaService.isEnabled && ollamaService.isConnected
    }

    var isUsingOpenAICompat: Bool {
        openAICompat.isEnabled && openAICompat.isConnected
    }

    var body: some View {
        Menu {
            // OpenAI-compatible models (if connected). Listed first because users who
            // configure it usually want a specific remote model to be the active one.
            if isUsingOpenAICompat {
                Section("OpenAI-compatible") {
                    if openAICompat.availableModels.isEmpty {
                        // /v1/models returned 404 or empty — let them at least see the manually configured one
                        if !openAICompat.selectedModel.isEmpty {
                            Button {
                                ollamaService.selectedModel = ""  // deactivate ollama selection
                            } label: {
                                HStack {
                                    Text(openAICompat.selectedModel)
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } else {
                        ForEach(openAICompat.availableModels, id: \.self) { model in
                            Button {
                                openAICompat.selectedModel = model
                                ollamaService.selectedModel = ""  // deactivate ollama
                            } label: {
                                HStack {
                                    Text(model)
                                    if openAICompat.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Ollama models (if connected)
            if isUsingOllama {
                Section("Ollama (\(ollamaService.serverURL.replacingOccurrences(of: "http://", with: "")))") {
                    ForEach(ollamaService.availableModels, id: \.self) { model in
                        Button {
                            ollamaService.selectedModel = model
                            openAICompat.selectedModel = ""  // deactivate openai compat
                        } label: {
                            HStack {
                                Text(model)
                                if ollamaService.selectedModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            // Local models
            if !downloadedModels.isEmpty {
                Section("On-Device") {
                    ForEach(downloadedModels) { model in
                        Button {
                            selectedModel = model
                            modelManager.preferredModelId = model.id
                            ollamaService.selectedModel = ""    // deactivate remote backends
                            openAICompat.selectedModel = ""
                            Task {
                                // Streamed MoE models load through the Swiftlet
                                // engine; the GGUF validator would reject them.
                                if model.engineFormat == .swiftlet {
                                    await SwiftletEngine.shared.loadModel(model)
                                } else {
                                    await inferenceManager.loadModel(model)
                                }
                            }
                        } label: {
                            HStack {
                                Text(model.displayName)
                                Text(model.formattedSize)
                                if !isUsingOllama && !isUsingOpenAICompat
                                    && (inferenceManager.currentModelId == model.id
                                        || SwiftletEngine.shared.currentModelId == model.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    navigateToModels = true
                } label: {
                    Label("Download Models", systemImage: "arrow.down.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                if isUsingOpenAICompat && !openAICompat.selectedModel.isEmpty {
                    Image(systemName: "cloud")
                        .font(.system(size: 10))
                    Text(openAICompat.selectedModel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else if isUsingOllama && !ollamaService.selectedModel.isEmpty {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                    Text(ollamaService.selectedModel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else if downloadedModels.isEmpty && !isUsingOllama && !isUsingOpenAICompat {
                    Text("No Model")
                        .font(.system(size: 13, weight: .semibold))
                } else if inferenceManager.loadingModelId != nil || swiftletEngine.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else {
                    // Loaded state can come from either engine.
                    Text(inferenceManager.isModelLoaded || swiftletEngine.isModelLoaded
                         ? selectedModel.displayName : "Select Model")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .navigationDestination(isPresented: $navigateToModels) {
            ModelsView()
        }
    }

    private var statusColor: Color {
        if isUsingOpenAICompat && !openAICompat.selectedModel.isEmpty { return .green }
        if isUsingOllama && !ollamaService.selectedModel.isEmpty { return .green }
        if downloadedModels.isEmpty { return .red }
        if inferenceManager.isModelLoaded { return .green }
        return .orange
    }
}
