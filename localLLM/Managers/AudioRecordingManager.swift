//
//  AudioRecordingManager.swift
//  LocalLLM
//
//  Handles real audio recording using AVAudioEngine.
//

import Foundation
import AVFoundation
import Combine

class AudioRecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private(set) var recordingURL: URL?
    private var timer: Timer?

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordingURL = fileURL

        // Use WAV format for Speech framework compatibility
        let wavURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).wav")
        recordingURL = wavURL

        guard let wavFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false) else {
            throw RecordingError.formatError
        }

        let file = try AVAudioFile(forWriting: wavURL, settings: wavFormat.settings)
        audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Convert to mono if needed and write
            guard let self else { return }

            // Calculate audio level for visualization
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData, frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
                let avg = sum / Float(frameLength)
                DispatchQueue.main.async {
                    self.audioLevel = avg
                }
            }

            // Write buffer to file
            do {
                try file.write(from: buffer)
            } catch {
                // Silently handle write errors during recording
            }
        }

        try engine.start()
        audioEngine = engine

        // Start duration timer
        duration = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.duration += 0.1
            }
        }
    }

    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        timer?.invalidate()
        timer = nil
        isRecording = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false)

        return recordingURL
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        duration = 0
    }
}

enum RecordingError: LocalizedError {
    case formatError
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to configure audio format"
        case .permissionDenied: return "Microphone access denied"
        }
    }
}
