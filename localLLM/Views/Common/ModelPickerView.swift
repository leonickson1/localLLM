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
    @Binding var selectedModel: AIModel
    @State private var navigateToModels = false

    var downloadedModels: [AIModel] {
        modelManager.downloadedModels
    }

    var isUsingOllama: Bool {
        ollamaService.isEnabled && ollamaService.isConnected
    }

    var body: some View {
        Menu {
            // Ollama models (if connected)
            if isUsingOllama {
                Section("Ollama (\(ollamaService.serverURL.replacingOccurrences(of: "http://", with: "")))") {
                    ForEach(ollamaService.availableModels, id: \.self) { model in
                        Button {
                            ollamaService.selectedModel = model
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
                            Task { await inferenceManager.loadModel(model) }
                        } label: {
                            HStack {
                                Text(model.displayName)
                                Text(model.formattedSize)
                                if !isUsingOllama && inferenceManager.currentModelId == model.id {
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

                if isUsingOllama {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                    Text(ollamaService.selectedModel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else if downloadedModels.isEmpty {
                    Text("No Model")
                        .font(.system(size: 13, weight: .semibold))
                } else if inferenceManager.loadingModelId != nil {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Text(inferenceManager.isModelLoaded ? selectedModel.displayName : "Select Model")
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
        if isUsingOllama { return .green }
        if downloadedModels.isEmpty { return .red }
        if inferenceManager.isModelLoaded { return .green }
        return .orange
    }
}
