//
//  AskImageView.swift
//  LocalLLM
//

import SwiftUI
import PhotosUI

struct AskImageView: View {
    @State var model: AIModel
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @State private var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var question = ""
    @State private var answer = ""
    @State private var isGenerating = false
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Image Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select an Image")
                        .font(.headline)

                    if let image = selectedImage {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .cornerRadius(12)

                            Button {
                                selectedImage = nil
                                selectedItem = nil
                                answer = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding(8)
                        }
                    } else {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 48))
                                    .foregroundColor(.blue)

                                Text("Tap to select an image")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)

                // Question Input
                if selectedImage != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ask a Question")
                            .font(.headline)

                        TextField("What do you want to know about this image?", text: $question, axis: .vertical)
                            .focused($isQuestionFocused)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Generate Button
                    Button {
                        generateAnswer()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Analyzing..." : "Analyze Image")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(question.isEmpty || isGenerating)
                    .padding(.horizontal)
                }

                // Answer Section
                if !answer.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Answer")
                                .font(.headline)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = answer
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                        }

                        Text(answer)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Ask Image")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerView(selectedModel: $model)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") {
                    isQuestionFocused = false
                }
            }
        }
        .task {
            if inferenceManager.currentModelId != model.id && model.isDownloaded {
                await inferenceManager.loadModel(model)
            }
        }
    }

    private func generateAnswer() {
        isQuestionFocused = false
        isGenerating = true
        answer = ""

        guard inferenceManager.isModelLoaded else {
            answer = "Model is not loaded. Please download a model first."
            isGenerating = false
            return
        }

        guard let image = selectedImage else { return }

        Task {
            // Step 1: Extract text and describe image using Vision framework
            var imageContext = ""

            do {
                let ocrText = try await VisionTextExtractor.extractText(from: image)
                if !ocrText.isEmpty {
                    imageContext += "Text found in image:\n\(ocrText)\n\n"
                }

                let description = try await VisionTextExtractor.describeImage(image)
                imageContext += "Image analysis: \(description)\n"
            } catch {
                imageContext += "Could not analyze image details.\n"
            }

            // Step 2: Build prompt with image context + user question
            let fullPrompt = PromptFormatter.format(
                systemPrompt: .vision,
                messages: [
                    MessageTurn(role: "user", content: "Image context:\n\(imageContext)\n\nMy question: \(question)")
                ],
                template: model.chatTemplate
            )

            // Step 3: Generate response
            let stream = inferenceManager.generate(
                prompt: fullPrompt,
                parameters: parameterStore.asModelParameters
            )

            for await token in stream {
                answer += token
            }

            isGenerating = false
        }
    }
}

#Preview {
    NavigationStack {
        AskImageView(model: AIModel.sampleModels[0])
    }
}
