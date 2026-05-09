//
//  HuggingFaceService.swift
//  LocalLLM
//
//  Fetches available GGUF models from the HuggingFace API.
//

import Foundation
import Combine

@MainActor
class HuggingFaceService: ObservableObject {
    @Published var remoteModels: [AIModel] = []
    @Published var isLoading = false
    @Published var error: String?

    private static let templateMap: [String: ChatTemplate] = [
        "llama": .llama3, "gemma": .gemma, "phi": .phi3,
        "qwen": .chatml, "smol": .chatml, "mistral": .chatml,
        "tinyllama": .chatml, "stable": .chatml, "deepseek": .chatml,
        "yi": .chatml, "openchat": .chatml, "zephyr": .chatml,
        "neural": .chatml, "rocket": .chatml,
    ]

    func fetchModels() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            // Fetch popular GGUF repos - just the listing, no per-repo API calls
            let url = URL(string: "https://huggingface.co/api/models?search=gguf+instruct&sort=downloads&direction=-1&limit=20&filter=gguf")!
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            let session = URLSession(configuration: config)
            let (data, _) = try await session.data(from: url)

            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                isLoading = false
                return
            }

            let builtInIds = Set(AIModel.sampleModels.map { $0.id })
            var results: [AIModel] = []

            for item in jsonArray {
                guard let modelId = item["modelId"] as? String else { continue }
                let lowerId = modelId.lowercased()
                guard lowerId.contains("gguf") else { continue }

                let cleanId = modelId.replacingOccurrences(of: "/", with: "-").lowercased()
                if builtInIds.contains(cleanId) { continue }

                let displayName = modelId
                    .components(separatedBy: "/").last?
                    .replacingOccurrences(of: "-GGUF", with: "")
                    .replacingOccurrences(of: "-gguf", with: "") ?? modelId

                let downloads = item["downloads"] as? Int ?? 0
                let template = guessTemplate(from: modelId)

                // Estimate size from model name (rough heuristic for display)
                let estimatedSize = estimateSize(from: displayName)

                let model = AIModel(
                    id: cleanId,
                    name: modelId,
                    displayName: displayName,
                    description: "\(downloads.formatted()) downloads on HuggingFace",
                    modelUrl: "", // Will be resolved when user taps download
                    modelSize: estimatedSize,
                    taskIds: [
                        BuiltInTaskID.llmChat.rawValue,
                    ],
                    huggingFaceUrl: "https://huggingface.co/\(modelId)",
                    parameters: AIModel.ModelParameters(
                        temperature: 0.7, topK: 40, topP: 0.95, maxTokens: 1024, randomSeed: 42
                    ),
                    chatTemplate: template
                )

                results.append(model)
                if results.count >= 20 { break }
            }

            remoteModels = results
            print("[HuggingFace] Fetched \(results.count) community models")
        } catch {
            self.error = "Failed to fetch: \(error.localizedDescription)"
            print("[HuggingFace] Error: \(error)")
        }

        isLoading = false
    }

    /// Resolve the actual GGUF download URL for a model (called when user taps download)
    func resolveDownloadURL(for model: AIModel) async -> AIModel? {
        let repo = model.name // stored the full repo id here
        print("[HuggingFace] Resolving download URL for \(repo)")

        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let siblings = json["siblings"] as? [[String: Any]] else { return nil }

            let ggufFiles = siblings.compactMap { file -> (String, Int64)? in
                guard let name = file["rfilename"] as? String,
                      name.hasSuffix(".gguf") else { return nil }
                let size = (file["size"] as? Int64) ?? (file["size"] as? Int).map { Int64($0) } ?? 0
                return (name, size)
            }

            // Prefer Q4_K_M for mobile
            let priorities = ["Q4_K_M", "q4_k_m", "Q4_K_S", "q4_k_s", "Q5_K_M", "Q4_0", "Q8_0"]
            var bestFile: (String, Int64)?

            for priority in priorities {
                if let match = ggufFiles.first(where: { $0.0.contains(priority) }) {
                    bestFile = match
                    break
                }
            }

            if bestFile == nil {
                bestFile = ggufFiles.filter { $0.1 > 0 && $0.1 < 5_000_000_000 }.min(by: { $0.1 < $1.1 })
            }

            guard let (fileName, fileSize) = bestFile else {
                print("[HuggingFace] No suitable GGUF file found in \(repo)")
                return nil
            }

            var resolved = model
            resolved = AIModel(
                id: model.id,
                name: model.name,
                displayName: model.displayName,
                description: model.description,
                modelUrl: "https://huggingface.co/\(repo)/resolve/main/\(fileName)",
                modelSize: fileSize,
                taskIds: model.taskIds,
                huggingFaceUrl: model.huggingFaceUrl,
                parameters: model.parameters,
                chatTemplate: model.chatTemplate
            )

            print("[HuggingFace] Resolved: \(fileName) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
            return resolved

        } catch {
            print("[HuggingFace] Resolve error: \(error)")
            return nil
        }
    }

    private func guessTemplate(from modelId: String) -> ChatTemplate {
        let lower = modelId.lowercased()
        for (key, template) in Self.templateMap {
            if lower.contains(key) { return template }
        }
        return .chatml
    }

    private func estimateSize(from name: String) -> Int64 {
        let lower = name.lowercased()
        if lower.contains("0.5b") { return 500_000_000 }
        if lower.contains("1b") || lower.contains("1.1b") { return 700_000_000 }
        if lower.contains("1.5b") || lower.contains("1.7b") || lower.contains("2b") { return 1_200_000_000 }
        if lower.contains("3b") { return 2_000_000_000 }
        if lower.contains("7b") || lower.contains("8b") { return 4_000_000_000 }
        return 1_500_000_000 // default guess
    }
}
