//
//  TranscriptionManager.swift
//  LocalLLM
//
//  On-device speech transcription using Apple's Speech framework.
//

import Foundation
import Speech
import Combine

@MainActor
class TranscriptionManager: ObservableObject {
    @Published var transcription = ""
    @Published var isTranscribing = false
    @Published var error: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL) async {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "Speech recognition is not available on this device"
            return
        }

        isTranscribing = true
        error = nil
        transcription = ""

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true // Privacy: on-device only
        request.shouldReportPartialResults = false

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result, result.isFinal {
                        continuation.resume(returning: result)
                    }
                }
            }

            transcription = result.bestTranscription.formattedString
        } catch {
            self.error = "Transcription failed: \(error.localizedDescription)"
            // Fallback: try without on-device requirement
            await transcribeFallback(audioURL: audioURL, recognizer: recognizer)
        }

        isTranscribing = false
    }

    private func transcribeFallback(audioURL: URL, recognizer: SFSpeechRecognizer) async {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result, result.isFinal {
                        continuation.resume(returning: result)
                    }
                }
            }
            transcription = result.bestTranscription.formattedString
            self.error = nil
        } catch {
            self.error = "Transcription failed: \(error.localizedDescription)"
        }
    }
}
