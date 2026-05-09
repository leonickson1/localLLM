//
//  ParameterStore.swift
//  LocalLLM
//
//  Persists model generation parameters to UserDefaults.
//

import Foundation
import Combine

class ParameterStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var temperature: Double {
        didSet { defaults.set(temperature, forKey: "param_temperature") }
    }
    @Published var topK: Int {
        didSet { defaults.set(topK, forKey: "param_topK") }
    }
    @Published var topP: Double {
        didSet { defaults.set(topP, forKey: "param_topP") }
    }
    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: "param_maxTokens") }
    }
    @Published var randomSeed: Int {
        didSet { defaults.set(randomSeed, forKey: "param_randomSeed") }
    }

    // Benchmark display settings
    @Published var showBenchmarks: Bool {
        didSet { defaults.set(showBenchmarks, forKey: "param_showBenchmarks") }
    }
    @Published var showTTFT: Bool {
        didSet { defaults.set(showTTFT, forKey: "param_showTTFT") }
    }
    @Published var showTokensPerSecond: Bool {
        didSet { defaults.set(showTokensPerSecond, forKey: "param_showTPS") }
    }

    init() {
        let d = UserDefaults.standard
        self.temperature = d.object(forKey: "param_temperature") as? Double ?? 0.7
        self.topK = d.object(forKey: "param_topK") as? Int ?? 40
        self.topP = d.object(forKey: "param_topP") as? Double ?? 0.95
        self.maxTokens = d.object(forKey: "param_maxTokens") as? Int ?? 1024
        self.randomSeed = d.object(forKey: "param_randomSeed") as? Int ?? 42
        self.showBenchmarks = d.object(forKey: "param_showBenchmarks") as? Bool ?? true
        self.showTTFT = d.object(forKey: "param_showTTFT") as? Bool ?? true
        self.showTokensPerSecond = d.object(forKey: "param_showTPS") as? Bool ?? true
    }

    var asModelParameters: AIModel.ModelParameters {
        AIModel.ModelParameters(
            temperature: temperature,
            topK: topK,
            topP: topP,
            maxTokens: maxTokens,
            randomSeed: randomSeed
        )
    }

    func resetToDefaults() {
        temperature = 0.7
        topK = 40
        topP = 0.95
        maxTokens = 1024
        randomSeed = 42
    }
}
