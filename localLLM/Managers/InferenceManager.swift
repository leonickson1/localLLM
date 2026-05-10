//
//  InferenceManager.swift
//  LocalLLM
//
//  ObservableObject bridge between InferenceEngine (actor) and SwiftUI views.
//  Handles safety: memory warnings, app lifecycle, battery, thermal state.
//

import Foundation
import SwiftUI
import Combine
import os.log

@MainActor
class InferenceManager: ObservableObject {
    // MARK: - Published State

    @Published var isModelLoaded = false
    @Published var isGenerating = false
    @Published var currentModelId: String?
    @Published var loadingModelId: String?
    @Published var loadError: String?

    // Benchmark metrics
    @Published var tokensPerSecond: Double = 0
    @Published var timeToFirstToken: TimeInterval = 0
    @Published var totalTokens: Int = 0

    // Context window (tokens) - updated after model load, or set for Ollama
    @Published var activeContextWindow: Int = 2048

    /// Call when using Ollama (larger models = bigger context)
    func setOllamaContext() {
        activeContextWindow = 8192 // Ollama models typically support 8k+
    }

    // Safety state
    @Published var safetyWarning: SafetyWarning?
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = 1.0
    @Published var isLowPowerMode = false
    @Published var wasUnloadedForMemory = false

    // MARK: - Private

    private let engine = InferenceEngine()
    private var generationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastLoadedModelId: String?  // Remember model for auto-reload
    private var lastLoadedModel: AIModel?

    // MARK: - Safety Types

    enum SafetyWarning: Equatable {
        case lowBattery(Int)                // battery percentage
        case thermalCritical               // device too hot
        case thermalSerious                // device getting hot
        case memoryPressure                // system wants RAM back
        case contextTruncated(Int, Int)    // (prompt tokens, max context)
        case lowPowerMode                  // iOS low power mode active
        case generationTimeout             // generation took too long
    }

    /// Total memory budget iOS gives this app on the current device.
    /// Captured once at launch using os_proc_available_memory + current resident memory.
    /// More accurate than guessing 50% of physicalMemory because it is the actual measured value for this iOS version + device.
    let deviceMemoryBudgetMB: Int

    // MARK: - Init

    init() {
        // Capture the device's effective memory budget for this app at launch.
        let available = os_proc_available_memory()
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let usedBytes: UInt64 = result == KERN_SUCCESS ? info.resident_size : 0
        let totalBytes = UInt64(available) + usedBytes
        self.deviceMemoryBudgetMB = Int(totalBytes / (1024 * 1024))

        setupLifecycleObservers()
        setupBatteryMonitoring()
        setupThermalMonitoring()
    }

    // MARK: - Compatibility

    enum Compatibility {
        case green   // fits comfortably
        case yellow  // tight, may slow down
        case red     // will not fit, do not download
    }

    struct CompatibilityReport {
        let status: Compatibility
        let label: String                // e.g. "Recommended"
        let reason: String               // e.g. "Fits comfortably on your device"
        let modelSizeMB: Int
        let inferenceOverheadMB: Int
        let requiredMB: Int
        let deviceBudgetMB: Int
        let percentOfBudget: Int          // 0...100+
    }

    /// Compute compatibility for a given model on this device.
    /// Stable for the session because deviceMemoryBudgetMB is captured at launch.
    func compatibility(for model: AIModel) -> CompatibilityReport {
        let modelSizeMB = Int(model.modelSize / (1024 * 1024))
        let overheadMB = max(800, modelSizeMB / 2)
        let requiredMB = modelSizeMB + overheadMB
        let percent = deviceMemoryBudgetMB > 0 ? (requiredMB * 100 / deviceMemoryBudgetMB) : 0

        let status: Compatibility
        let label: String
        let reason: String

        if requiredMB >= deviceMemoryBudgetMB * 85 / 100 {
            status = .red
            label = "Not recommended"
            reason = "This model needs about \(requiredMB) MB but your device only allows this app about \(deviceMemoryBudgetMB) MB. It will likely crash on load."
        } else if requiredMB >= deviceMemoryBudgetMB * 60 / 100 {
            status = .yellow
            label = "Might be tight"
            reason = "This model needs about \(requiredMB) MB out of about \(deviceMemoryBudgetMB) MB available to this app. It should load but may slow down or unload under memory pressure."
        } else {
            status = .green
            label = "Recommended"
            reason = "This model needs about \(requiredMB) MB out of about \(deviceMemoryBudgetMB) MB available to this app. Fits comfortably."
        }

        return CompatibilityReport(
            status: status,
            label: label,
            reason: reason,
            modelSizeMB: modelSizeMB,
            inferenceOverheadMB: overheadMB,
            requiredMB: requiredMB,
            deviceBudgetMB: deviceMemoryBudgetMB,
            percentOfBudget: percent
        )
    }

    // MARK: - Lifecycle Observers

    private func setupLifecycleObservers() {
        // Memory warning - unload model to prevent crash
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleMemoryWarning()
                }
            }
            .store(in: &cancellables)

        // App going to background - unload model to be a good citizen
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleEnterBackground()
                }
            }
            .store(in: &cancellables)

        // App returning to foreground - reload if we unloaded
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleEnterForeground()
                }
            }
            .store(in: &cancellables)

        // Low power mode changes
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                if self.isLowPowerMode {
                    self.safetyWarning = .lowPowerMode
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Battery Monitoring

    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.batteryLevel = UIDevice.current.batteryLevel
                if self.batteryLevel > 0 && self.batteryLevel <= 0.10 {
                    self.safetyWarning = .lowBattery(Int(self.batteryLevel * 100))
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Thermal Monitoring

    private func setupThermalMonitoring() {
        thermalState = ProcessInfo.processInfo.thermalState

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.thermalState = ProcessInfo.processInfo.thermalState

                switch self.thermalState {
                case .critical:
                    self.safetyWarning = .thermalCritical
                    // Cancel generation if running - device is too hot
                    if self.isGenerating {
                        self.cancel()
                    }
                case .serious:
                    self.safetyWarning = .thermalSerious
                default:
                    if self.safetyWarning == .thermalCritical || self.safetyWarning == .thermalSerious {
                        self.safetyWarning = nil
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle Handlers

    private func handleMemoryWarning() async {
        safetyWarning = .memoryPressure
        if isGenerating {
            cancel()
        }
        if isModelLoaded {
            lastLoadedModelId = currentModelId
            wasUnloadedForMemory = true
            await engine.unloadModel()
            isModelLoaded = false
            currentModelId = nil
        }
    }

    private func handleEnterBackground() async {
        if isGenerating {
            cancel()
        }
        // Unload model to reduce memory footprint in background
        if isModelLoaded {
            lastLoadedModelId = currentModelId
            await engine.unloadModel()
            isModelLoaded = false
            currentModelId = nil
        }
    }

    private func handleEnterForeground() async {
        wasUnloadedForMemory = false
        // Auto-reload will happen when user navigates to a view that needs inference
        // We don't auto-reload here to avoid slow foreground transition
        safetyWarning = nil
    }

    // MARK: - Pre-flight Safety Checks

    /// Returns a warning if conditions aren't great for inference, nil if OK
    func preflightCheck() -> SafetyWarning? {
        if thermalState == .critical {
            return .thermalCritical
        }
        if batteryLevel > 0 && batteryLevel <= 0.05 && UIDevice.current.batteryState != .charging {
            return .lowBattery(Int(batteryLevel * 100))
        }
        return nil
    }

    /// Check if we should warn but still allow (non-blocking)
    func advisoryCheck() -> SafetyWarning? {
        if thermalState == .serious {
            return .thermalSerious
        }
        if batteryLevel > 0 && batteryLevel <= 0.15 && UIDevice.current.batteryState != .charging {
            return .lowBattery(Int(batteryLevel * 100))
        }
        if isLowPowerMode {
            return .lowPowerMode
        }
        return nil
    }

    // MARK: - Model Loading

    /// Whether the model needs a user confirmation before loading (high memory usage)
    @Published var pendingLoadConfirmation: ModelLoadConfirmation?
    @Published var blockedLoad: ModelLoadConfirmation?

    struct ModelLoadConfirmation: Identifiable {
        let id = UUID()
        let model: AIModel
        let modelSizeMB: Int
        let availableMB: Int
    }

    func loadModel(_ model: AIModel, forceLoad: Bool = false) async {
        guard model.id != currentModelId else { return }

        loadingModelId = model.id
        loadError = nil
        wasUnloadedForMemory = false

        let path = model.localPath.path

        guard FileManager.default.fileExists(atPath: path) else {
            loadError = "Model file not found. Please download it first."
            loadingModelId = nil
            return
        }

        // Validate GGUF before attempting load
        guard Self.isValidGGUF(at: model.localPath) else {
            loadError = "Model file is corrupted. Please delete and re-download."
            loadingModelId = nil
            return
        }

        // Check available memory before loading.
        // Real overhead for inference is roughly 50% of model size (KV cache for 8K context + compute buffers + Metal allocations).
        let modelSizeMB = Int(model.modelSize / (1024 * 1024))
        let availableMB = availableMemoryInMB()
        let inferenceOverheadMB = max(800, modelSizeMB / 2) // at least 800MB, scales with model size
        let requiredMB = modelSizeMB + inferenceOverheadMB

        if availableMB > 0 {
            // Hard warning: model very likely won't fit. Offer "Try Anyway" but warn clearly.
            if !forceLoad && availableMB < requiredMB {
                blockedLoad = ModelLoadConfirmation(
                    model: model, modelSizeMB: requiredMB, availableMB: availableMB
                )
                loadingModelId = nil
                return
            }

            // Soft warning: total need is more than 75% of available memory, ask for confirmation
            if !forceLoad && requiredMB > (availableMB * 75 / 100) {
                pendingLoadConfirmation = ModelLoadConfirmation(
                    model: model, modelSizeMB: requiredMB, availableMB: availableMB
                )
                loadingModelId = nil
                return
            }
        }

        // Request up to 8192 tokens - the engine will cap at the model's native context
        let ctxSize = 8192

        // Load with timeout
        do {
            try await loadModelWithTimeout(at: path, contextSize: ctxSize, timeout: 30)
            currentModelId = model.id
            lastLoadedModel = model
            isModelLoaded = true
            loadError = nil
            // Query actual context size from loaded model
            activeContextWindow = await engine.contextSize
        } catch is CancellationError {
            loadError = "Model loading was cancelled."
            isModelLoaded = false
            currentModelId = nil
        } catch let error as InferenceError {
            if case .loadTimeout = error {
                loadError = "Model took too long to load. It may be corrupted. Try re-downloading."
            } else {
                loadError = error.localizedDescription
            }
            isModelLoaded = false
            currentModelId = nil
        } catch {
            loadError = error.localizedDescription
            isModelLoaded = false
            currentModelId = nil
        }

        loadingModelId = nil
    }

    func cancelPendingLoad() {
        pendingLoadConfirmation = nil
        loadingModelId = nil
    }

    func confirmLoad() async {
        guard let confirmation = pendingLoadConfirmation else { return }
        pendingLoadConfirmation = nil
        await loadModel(confirmation.model, forceLoad: true)
    }

    private func loadModelWithTimeout(at path: String, contextSize: Int = 2048, timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.engine.loadModel(at: path, contextSize: contextSize)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw InferenceError.loadTimeout
            }
            // First to complete wins; cancel the other
            if let result = try await group.nextResult() {
                group.cancelAll()
                try result.get()
            }
        }
    }

    /// GGUF magic bytes: "GGUF" = 0x47 0x47 0x55 0x46
    static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        return data[0] == 0x47 && data[1] == 0x47 && data[2] == 0x55 && data[3] == 0x46
    }

    func unloadModel() async {
        await engine.unloadModel()
        isModelLoaded = false
        currentModelId = nil
        lastLoadedModelId = nil
        lastLoadedModel = nil
        resetMetrics()
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        parameters: AIModel.ModelParameters
    ) -> AsyncStream<String> {

        // Pre-flight: block on critical conditions
        if let critical = preflightCheck() {
            safetyWarning = critical
            return AsyncStream { $0.finish() }
        }

        // Advisory: warn but proceed
        if let advisory = advisoryCheck() {
            safetyWarning = advisory
        }

        isGenerating = true
        resetMetrics()

        let startTime = Date()
        var firstTokenReceived = false
        var tokenCount = 0

        let maxGenerationTime: TimeInterval = 300 // 5 minute timeout

        let engineStream = AsyncStream<String> { continuation in
            generationTask = Task {
                let stream = await engine.generate(prompt: prompt, parameters: parameters)

                for await token in stream {
                    if Task.isCancelled { break }

                    // Generation timeout check
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > maxGenerationTime {
                        await MainActor.run {
                            self.safetyWarning = .generationTimeout
                        }
                        break
                    }

                    tokenCount += 1

                    if !firstTokenReceived {
                        firstTokenReceived = true
                        let ttft = Date().timeIntervalSince(startTime)
                        await MainActor.run {
                            self.timeToFirstToken = ttft
                        }
                    }

                    if elapsed > 0 && tokenCount % 5 == 0 {
                        let tps = Double(tokenCount) / elapsed
                        await MainActor.run {
                            self.tokensPerSecond = tps
                            self.totalTokens = tokenCount
                        }
                    }

                    continuation.yield(token)
                }

                let finalElapsed = Date().timeIntervalSince(startTime)
                let finalTps = finalElapsed > 0 ? Double(tokenCount) / finalElapsed : 0

                await MainActor.run {
                    self.isGenerating = false
                    self.totalTokens = tokenCount
                    self.tokensPerSecond = finalTps
                }
                continuation.finish()
            }
        }

        return engineStream
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        Task {
            await engine.cancelGeneration()
        }
        isGenerating = false
    }

    // MARK: - Helpers

    private func resetMetrics() {
        tokensPerSecond = 0
        timeToFirstToken = 0
        totalTokens = 0
    }

    /// Available memory in MB using os_proc_available_memory (accurate on iOS)
    private func availableMemoryInMB() -> Int {
        let available = os_proc_available_memory()
        if available > 0 {
            return Int(available / (1024 * 1024))
        }
        // Fallback: rough estimate
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 } // -1 = unknown, don't skip check
        let usedMB = Int(info.resident_size / (1024 * 1024))
        let totalMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        return max(0, totalMB - usedMB)
    }
}

// MARK: - Safety Warning Descriptions

extension InferenceManager.SafetyWarning {
    var title: String {
        switch self {
        case .lowBattery: return "Low Battery"
        case .thermalCritical: return "Device Overheating"
        case .thermalSerious: return "Device Getting Warm"
        case .memoryPressure: return "Low Memory"
        case .contextTruncated: return "Prompt Truncated"
        case .lowPowerMode: return "Low Power Mode"
        case .generationTimeout: return "Generation Timeout"
        }
    }

    var message: String {
        switch self {
        case .lowBattery(let pct):
            return "Battery at \(pct)%. AI inference uses significant power. Consider charging your device."
        case .thermalCritical:
            return "Your device is too hot. Inference has been paused to prevent damage. Let it cool down."
        case .thermalSerious:
            return "Your device is getting warm. Inference may be slower than usual."
        case .memoryPressure:
            return "Low memory detected. The model was unloaded to prevent a crash. It will reload when needed."
        case .contextTruncated(let tokens, let max):
            return "Your conversation (\(tokens) tokens) exceeds the context limit (\(max)). Older messages were trimmed."
        case .lowPowerMode:
            return "Low Power Mode is active. Inference may be slower to conserve battery."
        case .generationTimeout:
            return "Response generation timed out after 5 minutes. Try a shorter prompt or smaller model."
        }
    }

    var icon: String {
        switch self {
        case .lowBattery: return "battery.25"
        case .thermalCritical: return "thermometer.sun.fill"
        case .thermalSerious: return "thermometer.medium"
        case .memoryPressure: return "memorychip"
        case .contextTruncated: return "text.badge.minus"
        case .lowPowerMode: return "bolt.slash.fill"
        case .generationTimeout: return "clock.badge.exclamationmark"
        }
    }

    var isBlocking: Bool {
        switch self {
        case .thermalCritical: return true
        default: return false
        }
    }
}
