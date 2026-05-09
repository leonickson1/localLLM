//
//  AIModel.swift
//  LocalLLM
//

import Foundation

enum ChatTemplate: String, Codable {
    case chatml      // <|im_start|>system\n...<|im_end|>
    case llama3      // <|begin_of_text|><|start_header_id|>...
    case phi3        // <|system|>\n...<|end|>
    case qwen2       // Same as ChatML variant
    case gemma       // <start_of_turn>user\n...<end_of_turn>
}

struct AIModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let modelUrl: String
    let modelSize: Int64 // in bytes
    let taskIds: [String]
    let huggingFaceUrl: String?
    let parameters: ModelParameters
    let chatTemplate: ChatTemplate
    var contextWindow: Int = 2048 // tokens, updated after model load

    var isDownloaded: Bool = false
    var downloadProgress: Double = 0.0
    var isDownloading: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, modelUrl, modelSize
        case taskIds, huggingFaceUrl, parameters, chatTemplate
    }

    struct ModelParameters: Codable, Hashable {
        var temperature: Double
        var topK: Int
        var topP: Double
        var maxTokens: Int
        var randomSeed: Int
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: modelSize)
    }

    var localPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = docs.appendingPathComponent("Models")
        return modelsDir.appendingPathComponent("\(id).gguf")
    }

    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Default parameters

private let defaultParams = AIModel.ModelParameters(
    temperature: 0.7, topK: 40, topP: 0.95, maxTokens: 1024, randomSeed: 42
)

private let allTaskIds = [
    BuiltInTaskID.llmChat.rawValue,
    BuiltInTaskID.llmFinance.rawValue,
    BuiltInTaskID.llmHealth.rawValue,
]

// MARK: - Model Catalog

extension AIModel {
    static let sampleModels: [AIModel] = [

        // ── Tiny (< 1 GB) ───────────────────────────────────────

        AIModel(
            id: "smollm2-360m-instruct",
            name: "SmolLM2-360M-Instruct-Q8_0",
            displayName: "SmolLM2 360M",
            description: "Ultra-lightweight model. Fast responses, good for simple tasks and testing.",
            modelUrl: "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf",
            modelSize: 386_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        AIModel(
            id: "qwen2.5-0.5b-instruct",
            name: "Qwen2.5-0.5B-Instruct-Q8_0",
            displayName: "Qwen 2.5 0.5B",
            description: "Alibaba's smallest instruct model. Very fast, good for quick Q&A.",
            modelUrl: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf",
            modelSize: 531_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        // ── Small (1-2 GB) ──────────────────────────────────────

        AIModel(
            id: "smollm2-1.7b-instruct",
            name: "SmolLM2-1.7B-Instruct-Q4_K_M",
            displayName: "SmolLM2 1.7B",
            description: "Great balance of speed and quality. Recommended for most on-device use.",
            modelUrl: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
            modelSize: 1_060_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        AIModel(
            id: "qwen2.5-1.5b-instruct",
            name: "Qwen2.5-1.5B-Instruct-Q4_K_M",
            displayName: "Qwen 2.5 1.5B",
            description: "Strong reasoning and multilingual support from Alibaba.",
            modelUrl: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            modelSize: 1_050_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        AIModel(
            id: "gemma-2-2b-it",
            name: "gemma-2-2b-it-Q4_K_M",
            displayName: "Gemma 2 2B",
            description: "Google's instruction-tuned model. Good at following complex instructions.",
            modelUrl: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
            modelSize: 1_630_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF",
            parameters: defaultParams,
            chatTemplate: .gemma
        ),

        AIModel(
            id: "tinyllama-1.1b-chat",
            name: "TinyLlama-1.1B-Chat-v1.0-Q4_K_M",
            displayName: "TinyLlama 1.1B Chat",
            description: "Compact Llama architecture. Fast and efficient for chat.",
            modelUrl: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            modelSize: 669_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        AIModel(
            id: "stablelm2-1.6b-chat",
            name: "stablelm-2-1_6b-chat-Q4_K_M",
            displayName: "StableLM 2 1.6B Chat",
            description: "Stability AI's compact chat model with good general knowledge.",
            modelUrl: "https://huggingface.co/bartowski/stablelm-2-1_6b-chat-GGUF/resolve/main/stablelm-2-1_6b-chat-Q4_K_M.gguf",
            modelSize: 1_010_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/stablelm-2-1_6b-chat-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        // ── Medium (2-4 GB) ─────────────────────────────────────

        AIModel(
            id: "phi-3.5-mini-instruct",
            name: "Phi-3.5-mini-instruct-Q4_K_M",
            displayName: "Phi 3.5 Mini 3.8B",
            description: "Microsoft's powerful small model. Excellent reasoning and code generation.",
            modelUrl: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
            modelSize: 2_180_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .phi3
        ),

        AIModel(
            id: "qwen2.5-3b-instruct",
            name: "Qwen2.5-3B-Instruct-Q4_K_M",
            displayName: "Qwen 2.5 3B",
            description: "Mid-size model with strong multilingual and reasoning capabilities.",
            modelUrl: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
            modelSize: 2_020_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        AIModel(
            id: "llama-3.2-3b-instruct",
            name: "Llama-3.2-3B-Instruct-Q4_K_M",
            displayName: "Llama 3.2 3B",
            description: "Meta's latest small Llama model. Strong at following instructions.",
            modelUrl: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            modelSize: 2_020_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .llama3
        ),

        AIModel(
            id: "llama-3.2-1b-instruct",
            name: "Llama-3.2-1B-Instruct-Q8_0",
            displayName: "Llama 3.2 1B",
            description: "Meta's smallest Llama. Fast and lightweight for simple tasks.",
            modelUrl: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf",
            modelSize: 1_320_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .llama3
        ),

        AIModel(
            id: "mistral-7b-instruct-v0.3",
            name: "Mistral-7B-Instruct-v0.3-Q3_K_M",
            displayName: "Mistral 7B v0.3",
            description: "Powerful 7B model. Best quality but requires 3.5GB+ RAM. For newer devices.",
            modelUrl: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q3_K_M.gguf",
            modelSize: 3_520_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),

        // ── Gemma 4 (2026) ──────────────────────────────────────

        AIModel(
            id: "gemma-4-e2b-it",
            name: "gemma-4-E2B-it-Q4_K_M",
            displayName: "Gemma 4 E2B",
            description: "Google's latest small model (April 2026). Multimodal, strong reasoning.",
            modelUrl: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf",
            modelSize: 1_300_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF",
            parameters: defaultParams,
            chatTemplate: .gemma
        ),

        AIModel(
            id: "gemma-4-e4b-it",
            name: "gemma-4-E4B-it-Q4_K_M",
            displayName: "Gemma 4 E4B",
            description: "Google's mid-size 2026 model. Best quality for mobile.",
            modelUrl: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf",
            modelSize: 2_500_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF",
            parameters: defaultParams,
            chatTemplate: .gemma
        ),

        // ── Code Specialists ────────────────────────────────────

        AIModel(
            id: "qwen2.5-coder-1.5b-instruct",
            name: "Qwen2.5-Coder-1.5B-Instruct-Q4_K_M",
            displayName: "Qwen 2.5 Coder 1.5B",
            description: "Specialized for code generation and programming tasks.",
            modelUrl: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
            modelSize: 1_050_000_000,
            taskIds: allTaskIds,
            huggingFaceUrl: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF",
            parameters: defaultParams,
            chatTemplate: .chatml
        ),
    ]
}
