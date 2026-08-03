//
//  ModelManager.swift
//  LocalLLM
//

import Foundation
import SwiftletCore
import Combine
import UIKit

class ModelManager: NSObject, ObservableObject {
    @Published var availableModels: [AIModel] = []
    @Published var downloadedModels: [AIModel] = []
    @Published var isLoadingAllowlist = false
    @Published var tasks: [AITask] = AITask.sampleTasks
    @Published var downloadError: String?

    /// User's preferred default model id, persisted to UserDefaults.
    /// Set whenever the user actively picks a model. Falls back to first downloaded if missing or deleted.
    @Published var preferredModelId: String? {
        didSet {
            if let id = preferredModelId {
                UserDefaults.standard.set(id, forKey: Self.preferredModelKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.preferredModelKey)
            }
        }
    }

    private static let preferredModelKey = "preferred_model_id"

    /// The model the app should default to: user's preferred (if downloaded) else first downloaded else first sample.
    var defaultModel: AIModel {
        if let id = preferredModelId, let m = downloadedModels.first(where: { $0.id == id }) {
            return m
        }
        return downloadedModels.first ?? AIModel.sampleModels[0]
    }

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadSessions: [String: URLSession] = [:]

    private static let modelsDirectoryName = "Models"

    override init() {
        // Restore the user's preferred model id (if set previously)
        self.preferredModelId = UserDefaults.standard.string(forKey: Self.preferredModelKey)
        super.init()
        ensureModelsDirectory()
        loadModelAllowlist()
    }

    // MARK: - Directory Management

    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(modelsDirectoryName)
    }

    private func ensureModelsDirectory() {
        let dir = Self.modelsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load Models

    func loadModelAllowlist() {
        isLoadingAllowlist = true

        var models = AIModel.sampleModels

        // Load any custom imported models from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "custom_models"),
           let customModels = try? JSONDecoder().decode([AIModel].self, from: data) {
            print("[ModelManager] Loaded \(customModels.count) custom models from UserDefaults")
            models.append(contentsOf: customModels)
        }

        // Log the Models directory contents
        let modelsDir = Self.modelsDirectory
        print("[ModelManager] Models directory: \(modelsDir.path)")
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey]) {
            print("[ModelManager] Files on disk (\(contents.count)):")
            for file in contents {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                print("  - \(file.lastPathComponent): \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
            }
        } else {
            print("[ModelManager] Models directory is empty or doesn't exist")
        }

        // Check which models are actually downloaded on disk
        for i in 0..<models.count {
            let localPath = models[i].localPath
            var exists = FileManager.default.fileExists(atPath: localPath.path)
            // Container models: the folder appears the moment a download
            // starts. Only count it downloaded when the manifest exists —
            // the installer writes it last, after every byte is in place.
            if exists, models[i].engineFormat == .swiftlet {
                exists = FileManager.default.fileExists(
                    atPath: localPath.appendingPathComponent("manifest.json").path)
            }
            models[i].isDownloaded = exists
            models[i].downloadProgress = exists ? 1.0 : 0.0
            if exists {
                print("[ModelManager] \(models[i].displayName) -> FOUND at \(localPath.path)")
            }
        }

        self.availableModels = models
        self.downloadedModels = models.filter { $0.isDownloaded }
        print("[ModelManager] Total: \(models.count) available, \(downloadedModels.count) downloaded")
        self.isLoadingAllowlist = false
        self.updateTaskModels()
    }

    private func updateTaskModels() {
        for i in 0..<tasks.count {
            let taskId = tasks[i].id
            let modelsForTask = availableModels.filter { model in
                model.taskIds.contains(taskId)
            }
            tasks[i].models = modelsForTask
        }
    }

    // MARK: - Download

    func downloadModel(_ model: AIModel) {
        guard let index = availableModels.firstIndex(where: { $0.id == model.id }) else { return }
        guard !availableModels[index].isDownloading else { return }

        // Streamed (Swiftlet) models install via the streaming installer:
        // bytes route from Hugging Face straight into the on-device container,
        // resumable if interrupted (tap Download again to continue).
        if model.engineFormat == .swiftlet {
            downloadSwiftletModel(model, at: index)
            return
        }

        downloadError = nil

        // Check available disk space
        let requiredSpace = model.modelSize
        if let availableSpace = availableDiskSpace(), availableSpace < requiredSpace + 500_000_000 {
            let needed = ByteCountFormatter.string(fromByteCount: requiredSpace + 500_000_000, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
            downloadError = "Not enough storage. Need \(needed), have \(available)."
            return
        }

        guard let url = URL(string: model.modelUrl), !model.modelUrl.isEmpty else {
            downloadError = "No download URL for this model."
            return
        }

        availableModels[index].isDownloading = true
        availableModels[index].downloadProgress = 0

        // Use default session with background task protection
        // Background URLSession is unreliable on simulator and has complex reconnection requirements
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 1800 // 30 minutes max
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = true

        let downloadTask = session.downloadTask(with: request)
        downloadTask.taskDescription = model.id

        downloadTasks[model.id] = downloadTask
        downloadSessions[model.id] = session

        // Request extended background execution time so downloads survive app backgrounding
        beginBackgroundDownload(modelId: model.id)

        downloadTask.resume()
    }

    static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    /// Streaming install for directory-container models. Progress comes from
    /// the installer's own byte accounting; re-invoking resumes.
    private func downloadSwiftletModel(_ model: AIModel, at index: Int) {
        // HF repos rate-limit anonymous downloads; any other host (e.g. an
        // R2/CDN mirror) is fetched directly at full speed.
        let source: StreamingInstaller.Source
        if model.modelUrl.contains("huggingface.co/"),
           let repo = model.modelUrl.components(separatedBy: "huggingface.co/").last, !repo.isEmpty {
            source = .huggingFace(repo: repo)
        } else if model.modelUrl.hasPrefix("http") {
            source = .baseURL(model.modelUrl)
        } else {
            downloadError = "Invalid model source."
            return
        }
        if let availableSpace = availableDiskSpace(), availableSpace < model.modelSize + 2_000_000_000 {
            downloadError = "Not enough free space: this model needs about \(ByteCountFormatter.string(fromByteCount: model.modelSize, countStyle: .file)) plus headroom."
            return
        }
        downloadError = nil
        availableModels[index].isDownloading = true
        availableModels[index].downloadProgress = 0

        let cancelFlag = CancelFlag()
        swiftletCancelFlags[model.id] = cancelFlag
        let expectedBytes = Double(model.modelSize)
        let dest = model.localPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installer = StreamingInstaller(
                source: source,
                outputDir: dest
            )
            installer.shouldCancel = { cancelFlag.isSet }
            // Smooth progress: resumed bytes already on disk + bytes this run.
            let startingBytes = Double(Self.directorySize(dest))
            installer.onBytes = { newBytes in
                DispatchQueue.main.async {
                    guard let self, let i = self.availableModels.firstIndex(where: { $0.id == model.id }) else { return }
                    self.availableModels[i].downloadProgress = min(0.99, (startingBytes + Double(newBytes)) / expectedBytes)
                }
            }
            installer.log = { print("[SwiftletInstall] \($0)") }
            do {
                try installer.install()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.swiftletCancelFlags.removeValue(forKey: model.id)
                    if let i = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                        self.availableModels[i].isDownloading = false
                        self.availableModels[i].downloadProgress = 1.0
                        self.availableModels[i].isDownloaded = true
                    }
                    self.downloadedModels.append(model)
                    print("[ModelManager] streamed install complete: \(model.id)")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.swiftletCancelFlags.removeValue(forKey: model.id)
                    if let i = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                        self.availableModels[i].isDownloading = false
                    }
                    if case StreamingInstaller.Error.cancelled = error {
                        print("[ModelManager] streamed install cancelled: \(model.id)")
                    } else {
                        self.downloadError = "Download interrupted (\(error.localizedDescription)). Tap Download again to resume; progress is kept."
                    }
                }
            }
        }
    }

    /// Thread-safe cancellation flag polled by the streaming installer.
    private final class CancelFlag {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func set() {
            lock.lock(); defer { lock.unlock() }
            value = true
        }
    }
    private var swiftletCancelFlags: [String: CancelFlag] = [:]

    /// First downloaded model that can serve Health/Finance/Journal features.
    /// The experimental streamed 35B is chat-only, so it never qualifies.
    var firstAssistCapableModel: AIModel? {
        downloadedModels.first { $0.engineFormat != .swiftlet }
    }

    /// True when models are installed but every one of them is chat-only —
    /// the state where assist features should say "download another model".
    var onlyChatOnlyModelsInstalled: Bool {
        firstAssistCapableModel == nil && !downloadedModels.isEmpty
    }

    func cancelDownload(_ model: AIModel) {
        downloadTasks[model.id]?.cancel()
        downloadTasks.removeValue(forKey: model.id)
        downloadSessions[model.id]?.invalidateAndCancel()
        downloadSessions.removeValue(forKey: model.id)
        swiftletCancelFlags[model.id]?.set()

        if let index = availableModels.firstIndex(where: { $0.id == model.id }) {
            availableModels[index].isDownloading = false
            availableModels[index].downloadProgress = 0
        }
    }

    // MARK: - Delete

    func deleteModel(_ model: AIModel) {
        let localPath = model.localPath
        print("[ModelManager] Deleting \(model.displayName) at \(localPath.path)")

        // A loaded Swiftlet session mmaps files inside this directory —
        // unload before removing so the engine can't serve a deleted model.
        if model.engineFormat == .swiftlet {
            Task { @MainActor in
                if SwiftletEngine.shared.currentModelId == model.id {
                    SwiftletEngine.shared.unload()
                }
            }
        }

        do {
            if FileManager.default.fileExists(atPath: localPath.path) {
                try FileManager.default.removeItem(at: localPath)
                print("[ModelManager] Successfully deleted \(model.displayName)")
            } else {
                print("[ModelManager] File not found at \(localPath.path) - marking as not downloaded")
            }
        } catch {
            print("[ModelManager] Delete error: \(error)")
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }

        if let index = availableModels.firstIndex(where: { $0.id == model.id }) {
            availableModels[index].isDownloaded = false
            availableModels[index].downloadProgress = 0
        }

        downloadedModels.removeAll { $0.id == model.id }

        // If the deleted model was the user's preferred default, clear it so we fall back to the next available.
        if preferredModelId == model.id {
            preferredModelId = nil
        }

        updateTaskModels()
    }

    // MARK: - Import

    func importModel(from url: URL, name: String, displayName: String) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let modelId = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let destination = Self.modelsDirectory.appendingPathComponent("\(modelId).gguf")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0

            var newModel = AIModel(
                id: modelId,
                name: name,
                displayName: displayName,
                description: "Imported model",
                modelUrl: "",
                modelSize: fileSize,
                taskIds: [
                    BuiltInTaskID.llmChat.rawValue,
                ],
                huggingFaceUrl: nil,
                parameters: AIModel.ModelParameters(
                    temperature: 0.7, topK: 40, topP: 0.95, maxTokens: 1024, randomSeed: 42
                ),
                chatTemplate: .chatml
            )
            newModel.isDownloaded = true
            newModel.downloadProgress = 1.0

            availableModels.append(newModel)
            downloadedModels.append(newModel)
            updateTaskModels()
            saveCustomModels()
        } catch {
            print("Error importing model: \(error)")
        }
    }

    // MARK: - Storage

    func calculateCacheSize() -> Int64 {
        let dir = Self.modelsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in contents {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func clearCache() {
        let dir = Self.modelsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in contents {
                try? FileManager.default.removeItem(at: file)
            }
        }
        loadModelAllowlist()
    }

    func formattedCacheSize() -> String {
        let size = calculateCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    func availableDiskSpace() -> Int64? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let path = paths.first else { return nil }
        guard let values = try? path.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    private func saveCustomModels() {
        let sampleIds = Set(AIModel.sampleModels.map { $0.id })
        let customModels = availableModels.filter { !sampleIds.contains($0.id) }
        if let data = try? JSONEncoder().encode(customModels) {
            UserDefaults.standard.set(data, forKey: "custom_models")
        }
    }

    // Request extended background time so downloads survive when user switches apps
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundDownload(modelId: String) {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "model-download-\(modelId)") { [weak self] in
            self?.endBackgroundDownload()
        }
    }

    private func endBackgroundDownload() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelId = downloadTask.taskDescription else { return }
        guard let index = availableModels.firstIndex(where: { $0.id == modelId }) else { return }

        let destination = availableModels[index].localPath

        // Validate GGUF magic bytes before accepting the file
        if !Self.isValidGGUF(at: location) {
            availableModels[index].isDownloading = false
            availableModels[index].downloadProgress = 0
            downloadError = "Download corrupted (invalid GGUF file). Please try again."
            try? FileManager.default.removeItem(at: location)
            downloadTasks.removeValue(forKey: modelId)
            downloadSessions.removeValue(forKey: modelId)
            endBackgroundDownload()
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)

            availableModels[index].isDownloading = false
            availableModels[index].isDownloaded = true
            availableModels[index].downloadProgress = 1.0
            downloadedModels.append(availableModels[index])
            updateTaskModels()
            saveCustomModels()
        } catch {
            availableModels[index].isDownloading = false
            availableModels[index].downloadProgress = 0
            downloadError = "Failed to save model: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: location) // Clean up temp file
        }

        downloadTasks.removeValue(forKey: modelId)
        downloadSessions.removeValue(forKey: modelId)
        endBackgroundDownload()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let modelId = downloadTask.taskDescription else { return }
        guard let index = availableModels.firstIndex(where: { $0.id == modelId }) else { return }

        if totalBytesExpectedToWrite > 0 {
            let newProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            // Only update UI when progress changes by >1% to reduce re-renders
            if abs(newProgress - availableModels[index].downloadProgress) > 0.01 {
                availableModels[index].downloadProgress = newProgress
            }
        }

        // Periodically check disk space during download (every ~50MB)
        if totalBytesWritten % (50 * 1024 * 1024) < bytesWritten {
            if let available = availableDiskSpace(), available < 200_000_000 {
                downloadTask.cancel()
                availableModels[index].isDownloading = false
                availableModels[index].downloadProgress = 0
                downloadError = "Disk space too low. Download cancelled to prevent storage issues."
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let modelId = task.taskDescription else { return }

        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            downloadError = "Download failed: \(error.localizedDescription)"
            if let index = availableModels.firstIndex(where: { $0.id == modelId }) {
                availableModels[index].isDownloading = false
                availableModels[index].downloadProgress = 0
                // Clean up any partial file on failure
                let path = availableModels[index].localPath
                if FileManager.default.fileExists(atPath: path.path) {
                    try? FileManager.default.removeItem(at: path)
                }
            }
        }

        downloadTasks.removeValue(forKey: modelId)
        downloadSessions.removeValue(forKey: modelId)
        endBackgroundDownload()
    }

    /// Validate GGUF magic bytes (0x47475546 = "GGUF")
    static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        return data[0] == 0x47 && data[1] == 0x47 && data[2] == 0x55 && data[3] == 0x46
    }
}
