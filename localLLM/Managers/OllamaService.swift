//
//  OllamaService.swift
//  LocalLLM
//
//  Connects to an Ollama instance running on the local network.
//  Enables using larger models on a Mac/PC for better extraction and inference.
//

import Foundation
import Combine

@MainActor
class OllamaService: ObservableObject {
    @Published var isConnected = false
    @Published var isChecking = false
    @Published var isGenerating = false
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = ""
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "ollama_server_url") }
    }
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "ollama_enabled") }
    }
    @Published var error: String?

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "ollama_server_url") ?? "http://192.168.1.100:11434"
        self.isEnabled = UserDefaults.standard.bool(forKey: "ollama_enabled")
        if isEnabled {
            Task { await checkConnection() }
        }
    }

    // MARK: - Connection

    func checkConnection() async {
        guard isEnabled else {
            isConnected = false
            return
        }

        isChecking = true
        defer { isChecking = false }

        let url = URL(string: "\(serverURL)/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isConnected = false
                error = "Server returned error"
                return
            }

            // Parse available models
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                availableModels = models.compactMap { $0["name"] as? String }
                if selectedModel.isEmpty, let first = availableModels.first {
                    selectedModel = first
                }
                print("[Ollama] Connected. Models: \(availableModels)")
            }

            isConnected = true
            error = nil
        } catch {
            isConnected = false
            self.error = "Cannot reach server: \(error.localizedDescription)"
            print("[Ollama] Connection failed: \(error)")
        }
    }

    // MARK: - Chat Completion

    func chat(
        systemPrompt: String,
        userMessage: String,
        model: String? = nil
    ) async -> String? {
        guard isEnabled && isConnected else { return nil }

        let modelName = model ?? selectedModel
        guard !modelName.isEmpty else { return nil }

        let url = URL(string: "\(serverURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "stream": false
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isGenerating = true
        defer { isGenerating = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Ollama] Chat response status: \(httpStatus), size: \(data.count) bytes")

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return content
                }
                // Check for error in response
                if let errorMsg = json["error"] as? String {
                    print("[Ollama] API error: \(errorMsg)")
                    self.error = errorMsg
                }
            }
        } catch {
            print("[Ollama] Chat error: \(error)")
            self.error = error.localizedDescription
        }

        return nil
    }

    // MARK: - Structured Extraction (with JSON schema)

    func extractStructured(
        systemPrompt: String,
        userMessage: String,
        model: String? = nil
    ) async -> String? {
        guard isEnabled && isConnected else { return nil }

        let modelName = model ?? selectedModel
        let url = URL(string: "\(serverURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "stream": false
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isGenerating = true
        defer { isGenerating = false }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        } catch {
            print("[Ollama] Extract error: \(error)")
        }

        return nil
    }

    // MARK: - Streaming Chat

    func streamChat(
        systemPrompt: String,
        userMessage: String,
        model: String? = nil
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard isEnabled && isConnected else {
                    continuation.finish()
                    return
                }

                let modelName = model ?? selectedModel
                let url = URL(string: "\(serverURL)/api/chat")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                let body: [String: Any] = [
                    "model": modelName,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userMessage]
                    ],
                    "stream": true
                ]

                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                } catch {
                    print("[Ollama] Stream error: \(error)")
                }

                continuation.finish()
            }
        }
    }
}
