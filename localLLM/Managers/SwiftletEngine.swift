//
//  SwiftletEngine.swift
//  LocalLLM
//
//  On-device engine for streamed MoE models (Swiftlet). Unlike the llama.cpp
//  path, these models are far larger than RAM by design: the dense core stays
//  resident (~1-3 GB) and the routed experts stream from storage per token,
//  so InferenceManager's RAM-fit gating deliberately does not apply here.
//

import Combine
import Foundation
import SwiftletCore
import UIKit

@MainActor
final class SwiftletEngine: ObservableObject {
    static let shared = SwiftletEngine()

    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var currentModelId: String?
    @Published var loadError: String?

    // Benchmark metrics, mirroring InferenceManager's fields.
    @Published var tokensPerSecond: Double = 0
    @Published var timeToFirstToken: TimeInterval = 0
    @Published var totalTokens: Int = 0

    private var session: SwiftletSession?
    private var memoryObserver: NSObjectProtocol?

    private init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            print("[SwiftletEngine] memory warning, shrinking expert cache")
            self?.session?.handleMemoryPressure()
        }
    }

    func loadModel(_ model: AIModel) async {
        guard model.engineFormat == .swiftlet else { return }
        guard currentModelId != model.id || !isModelLoaded else { return }
        isLoading = true
        loadError = nil
        print("[SwiftletEngine] loading \(model.id) from \(model.localPath.path)")
        let start = Date()
        do {
            // 1 GB expert cache: benchmarked at full speed on internal-SSD-class
            // storage, and keeps total footprint ~2.5 GB — safe under jetsam.
            session = try await SwiftletSession(modelDir: model.localPath, retainAllLayers: false, cacheBudgetGB: 1.0)
            currentModelId = model.id
            isModelLoaded = true
            print(String(format: "[SwiftletEngine] loaded in %.1fs (gpu: %@)",
                         -start.timeIntervalSinceNow,
                         String(describing: session?.usesGPU == true)))
        } catch {
            session = nil
            currentModelId = nil
            isModelLoaded = false
            loadError = "Couldn't load \(model.displayName): \(error.localizedDescription)"
            print("[SwiftletEngine] LOAD FAILED: \(error)")
        }
        isLoading = false
    }

    func unload() {
        session = nil
        currentModelId = nil
        isModelLoaded = false
    }

    /// Streams assistant text deltas for a chat conversation. Matches the
    /// AsyncStream shape of the other engines so ChatView consumes it the
    /// same way.
    func streamChat(messages: [[String: String]], maxTokens: Int) -> AsyncStream<String> {
        guard let session else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    // The session generates with reasoning disabled, so text
                    // streams through as-is. The only guard: if a reply still
                    // opens with a <think> block, hold it back until </think>.
                    enum FilterMode { case undecided, filteringThink, passthrough }
                    var mode = FilterMode.undecided
                    var pending = ""
                    for try await delta in session.streamChat(messages: messages, maxNew: maxTokens) {
                        switch mode {
                        case .undecided:
                            pending += delta
                            let lead = String(pending.drop(while: \.isWhitespace))
                            if lead.hasPrefix("<think>") {
                                mode = .filteringThink
                            } else if !lead.isEmpty && !"<think>".hasPrefix(lead) {
                                mode = .passthrough
                                continuation.yield(lead)
                                pending = ""
                            }
                        case .filteringThink:
                            pending += delta
                            if let r = pending.range(of: "</think>") {
                                mode = .passthrough
                                let after = String(pending[r.upperBound...])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !after.isEmpty { continuation.yield(after) }
                                pending = ""
                            }
                        case .passthrough:
                            continuation.yield(delta)
                        }
                    }
                    if mode != .passthrough, !pending.isEmpty {
                        let cleaned = pending
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { continuation.yield(cleaned) }
                    }
                } catch {
                    continuation.yield("\n[Generation error: \(error.localizedDescription)]")
                }
                let metrics = session.lastMetrics
                print(String(format: "[SwiftletEngine] generated %d tokens, %.2f tok/s, ttft %.1fs",
                             metrics.generatedTokens, metrics.tokensPerSecond, metrics.timeToFirstToken))
                await MainActor.run {
                    self.tokensPerSecond = metrics.tokensPerSecond
                    self.timeToFirstToken = metrics.timeToFirstToken
                    self.totalTokens = metrics.generatedTokens
                }
                continuation.finish()
            }
        }
    }
}
