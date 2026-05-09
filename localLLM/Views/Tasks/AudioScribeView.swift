//
//  AudioScribeView.swift
//  LocalLLM
//

import SwiftUI
import AVFoundation
import Speech

struct AudioScribeView: View {
    @State var model: AIModel
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @StateObject private var recorder = AudioRecordingManager()
    @StateObject private var transcriber = TranscriptionManager()
    @State private var showPermissionAlert = false
    @State private var processedText = ""
    @State private var isProcessing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Recording Section
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: recorder.isRecording ? [.red, .orange] : [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .scaleEffect(recorder.isRecording ? 1.0 + CGFloat(recorder.audioLevel) * 2 : 1.0)
                            .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)

                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 8) {
                        Text(recorder.isRecording ? "Recording..." : "Tap to Record")
                            .font(.title3.bold())

                        if recorder.isRecording || recorder.duration > 0 {
                            Text(formatDuration(recorder.duration))
                                .font(.title2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        toggleRecording()
                    } label: {
                        Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                recorder.isRecording ?
                                AnyView(Color.red) :
                                AnyView(LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 32)

                // Transcription Button
                if recorder.duration > 0 && !recorder.isRecording {
                    Button {
                        transcribeAudio()
                    } label: {
                        HStack {
                            if transcriber.isTranscribing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "text.badge.checkmark")
                            }
                            Text(transcriber.isTranscribing ? "Transcribing..." : "Transcribe Audio")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.green, .teal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(transcriber.isTranscribing)
                    .padding(.horizontal)
                }

                // Transcription Result
                if !transcriber.transcription.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Transcription")
                                .font(.headline)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = transcriber.transcription
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                        }

                        ScrollView {
                            Text(transcriber.transcription)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .frame(minHeight: 100)

                        // Process with AI button
                        Button {
                            processWithAI()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isProcessing ? "Processing..." : "Process with AI")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessing || !inferenceManager.isModelLoaded)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // AI-Processed Result
                if !processedText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AI Summary")
                                .font(.headline)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = processedText
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                        }

                        Text(processedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Error display
                if let error = transcriber.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Audio Scribe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerView(selectedModel: $model)
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Microphone and speech recognition permissions are required. Please enable them in Settings.")
        }
        .task {
            if inferenceManager.currentModelId != model.id && model.isDownloaded {
                await inferenceManager.loadModel(model)
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            _ = recorder.stopRecording()
        } else {
            // Request microphone permission
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        do {
                            try recorder.startRecording()
                        } catch {
                            showPermissionAlert = true
                        }
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
        }
    }

    private func transcribeAudio() {
        guard let audioURL = recorder.recordingURL else { return }

        Task {
            let authorized = await transcriber.requestAuthorization()
            guard authorized else {
                showPermissionAlert = true
                return
            }
            await transcriber.transcribe(audioURL: audioURL)
        }
    }

    private func processWithAI() {
        guard inferenceManager.isModelLoaded else { return }
        isProcessing = true
        processedText = ""

        let fullPrompt = PromptFormatter.format(
            systemPrompt: .audioSummary,
            messages: [MessageTurn(role: "user", content: "Transcription:\n\(transcriber.transcription)")],
            template: model.chatTemplate
        )

        Task {
            let stream = inferenceManager.generate(
                prompt: fullPrompt,
                parameters: parameterStore.asModelParameters
            )

            for await token in stream {
                processedText += token
            }

            isProcessing = false
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}

#Preview {
    NavigationStack {
        AudioScribeView(model: AIModel.sampleModels[0])
    }
}
