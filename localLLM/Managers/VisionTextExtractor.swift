//
//  VisionTextExtractor.swift
//  LocalLLM
//
//  Extracts text from images using Apple's Vision framework (on-device OCR).
//

import Foundation
import Vision
import UIKit

struct VisionTextExtractor {

    static func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detect basic image features (face count, text presence) for non-OCR image description
    static func describeImage(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        var descriptions: [String] = []

        // Detect faces
        let faceCount = try await detectFaces(in: cgImage)
        if faceCount > 0 {
            descriptions.append("\(faceCount) face(s) detected")
        }

        // Detect text
        let hasText = try await detectText(in: cgImage)
        if hasText {
            descriptions.append("Contains text")
        }

        // Image dimensions
        descriptions.append("Image size: \(cgImage.width)x\(cgImage.height)")

        return descriptions.isEmpty ? "No notable features detected" : descriptions.joined(separator: ". ")
    }

    private static func detectFaces(in cgImage: CGImage) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: request.results?.count ?? 0)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private static func detectText(in cgImage: CGImage) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectTextRectanglesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (request.results?.count ?? 0) > 0)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

enum VisionError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image"
        }
    }
}
