//
//  InferenceEngine.swift
//  LocalLLM
//
//  Core llama.cpp wrapper. All on-device inference runs through this actor.
//

import Foundation
import LlamaSwift

actor InferenceEngine {
    private var model: OpaquePointer?       // llama_model *
    private var context: OpaquePointer?     // llama_context *
    private var vocab: OpaquePointer?       // llama_vocab *
    private var cancelled = false

    var modelLoaded: Bool { model != nil && context != nil }

    var contextSize: Int {
        guard let context else { return 0 }
        return Int(llama_n_ctx(context))
    }

    // MARK: - Load / Unload

    func loadModel(at path: String, contextSize: Int = 2048) throws {
        unloadModel()

        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.use_mmap = true

        guard let m = llama_model_load_from_file(path, modelParams) else {
            throw InferenceError.failedToLoadModel(path)
        }
        model = m

        // Use the model's native context or the requested size, whichever is smaller
        // This avoids requesting more context than the model was trained for
        let nativeCtx = Int(llama_model_n_ctx_train(m))
        let effectiveCtx = nativeCtx > 0 ? min(contextSize, nativeCtx) : contextSize

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(effectiveCtx)
        ctxParams.n_batch = UInt32(min(effectiveCtx, 512))
        let threadCount = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        ctxParams.n_threads = threadCount
        ctxParams.n_threads_batch = threadCount

        guard let c = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            self.model = nil
            throw InferenceError.failedToCreateContext
        }
        context = c
        vocab = llama_model_get_vocab(m)
    }

    func unloadModel() {
        cancelGeneration()
        if let c = context { llama_free(c); context = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
    }

    func cancelGeneration() {
        cancelled = true
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        parameters: AIModel.ModelParameters
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                await self.runGeneration(prompt: prompt, parameters: parameters, continuation: continuation)
            }
        }
    }

    private func runGeneration(
        prompt: String,
        parameters: AIModel.ModelParameters,
        continuation: AsyncStream<String>.Continuation
    ) {
        guard let _ = model, let context, let vocab else {
            continuation.finish()
            return
        }

        cancelled = false

        // Tokenize the prompt
        let tokens = tokenize(text: prompt, addSpecial: true)
        guard !tokens.isEmpty else {
            continuation.finish()
            return
        }

        // Clear KV cache
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)

        // Build sampler chain
        let samplerChain = buildSampler(parameters: parameters)
        defer { llama_sampler_free(samplerChain) }

        // Process prompt tokens in batches of n_batch size to avoid assertion failure
        let nBatch = Int(llama_n_batch(context))
        var batch = llama_batch_init(Int32(max(nBatch, 1)), 0, 1)
        defer { llama_batch_free(batch) }

        var pos = 0
        while pos < tokens.count {
            batchClear(&batch)
            let end = min(pos + nBatch, tokens.count)
            for i in pos..<end {
                let isLast = (i == tokens.count - 1)
                batchAdd(&batch, tokens[i], Int32(i), [0], isLast)
            }

            if llama_decode(context, batch) != 0 {
                print("[InferenceEngine] Decode failed at position \(pos)")
                continuation.finish()
                return
            }
            pos = end
        }

        // Generate tokens one at a time
        var nCur = Int32(tokens.count)
        let nMax = Int32(parameters.maxTokens) + nCur

        while nCur < nMax && !cancelled {
            let newTokenId = llama_sampler_sample(samplerChain, context, batch.n_tokens - 1)

            if llama_vocab_is_eog(vocab, newTokenId) {
                break
            }

            let piece = tokenToString(token: newTokenId)
            if !piece.isEmpty {
                continuation.yield(piece)
            }

            batchClear(&batch)
            batchAdd(&batch, newTokenId, nCur, [0], true)

            if llama_decode(context, batch) != 0 {
                break
            }

            nCur += 1
        }

        continuation.finish()
    }

    // MARK: - Helpers

    private func tokenize(text: String, addSpecial: Bool) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = Int32(text.utf8.count)
        let maxTokens = utf8Count + 2 + 1
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))

        let nTokens = llama_tokenize(vocab, text, utf8Count, &tokens, maxTokens, addSpecial, true)

        if nTokens < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-nTokens))
            let n2 = llama_tokenize(vocab, text, utf8Count, &tokens, -nTokens, addSpecial, true)
            return Array(tokens.prefix(Int(n2)))
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    private func tokenToString(token: llama_token) -> String {
        guard let vocab else { return "" }
        var buffer = [CChar](repeating: 0, count: 256)
        let nChars = llama_token_to_piece(vocab, token, &buffer, 256, 0, true)
        if nChars > 0 {
            buffer[Int(nChars)] = 0
            return String(cString: buffer)
        }
        return ""
    }

    private func buildSampler(parameters: AIModel.ModelParameters) -> UnsafeMutablePointer<llama_sampler> {
        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)!

        if parameters.temperature > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(parameters.topK)))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(parameters.topP), 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(parameters.temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(parameters.randomSeed)))
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        }

        return chain
    }

    private func batchAdd(_ batch: inout llama_batch, _ token: llama_token, _ pos: Int32, _ seqIds: [Int32], _ logits: Bool) {
        let i = Int(batch.n_tokens)
        batch.token[i] = token
        batch.pos[i] = pos
        batch.n_seq_id[i] = Int32(seqIds.count)
        for (j, seqId) in seqIds.enumerated() {
            batch.seq_id[i]![j] = seqId
        }
        batch.logits[i] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    private func batchClear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }
}

// MARK: - Errors

enum InferenceError: LocalizedError {
    case failedToLoadModel(String)
    case failedToCreateContext
    case modelNotLoaded
    case loadTimeout

    var errorDescription: String? {
        switch self {
        case .failedToLoadModel(let path): return "Failed to load model at: \(path)"
        case .failedToCreateContext: return "Failed to create inference context"
        case .modelNotLoaded: return "No model is loaded"
        case .loadTimeout: return "Model loading timed out. The file may be corrupted."
        }
    }
}
