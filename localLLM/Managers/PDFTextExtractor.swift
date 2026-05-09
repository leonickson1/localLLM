//
//  PDFTextExtractor.swift
//  LocalLLM
//
//  Hybrid PDF text extraction: tries PDFKit first (fast, for digital PDFs),
//  falls back to Vision OCR (for scanned/image PDFs). Works 100% on-device.
//

import Foundation
import PDFKit
import Vision
import UIKit

struct PDFTextExtractor {

    /// Extract text page by page, returns array of per-page text
    static func extractPages(from url: URL) async throws -> [String] {
        guard let document = PDFDocument(url: url) else {
            throw PDFError.cannotOpenDocument
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if let text = page.attributedString?.string ?? page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // If PDFKit got nothing, try OCR
        if pages.isEmpty || pages.allSatisfy({ $0.count < 20 }) {
            pages = []
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i),
                      let cgImage = renderPageToImage(page: page, dpi: 300) else { continue }
                let text = try await recognizeText(in: cgImage)
                if !text.isEmpty { pages.append(text) }
            }
        }

        print("[PDFExtractor] Extracted \(pages.count) pages")
        return pages
    }

    /// Extract text from a PDF using a hybrid approach
    static func extractText(from url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw PDFError.cannotOpenDocument
        }

        print("[PDFExtractor] Opening PDF with \(document.pageCount) pages")

        // Tier 1: Try PDFKit (fast path)
        let pdfKitText = extractWithPDFKit(document: document)
        if pdfKitText.count > 50 {
            print("[PDFExtractor] PDFKit extracted \(pdfKitText.count) chars - using this")
            return pdfKitText
        }

        print("[PDFExtractor] PDFKit got \(pdfKitText.count) chars - falling back to Vision OCR")

        // Tier 2: Vision OCR (renders each page to image, then OCR)
        let ocrText = try await extractWithVisionOCR(document: document)
        print("[PDFExtractor] Vision OCR extracted \(ocrText.count) chars")
        return ocrText
    }

    // MARK: - Tier 1: PDFKit

    private static func extractWithPDFKit(document: PDFDocument) -> String {
        var fullText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            // Use attributedString for better text extraction than plain string
            if let pageText = page.attributedString?.string,
               !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n\n"
            } else if let pageText = page.string,
                      !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n\n"
            }
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tier 2: Vision OCR

    private static func extractWithVisionOCR(document: PDFDocument) async throws -> String {
        var allText = ""

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            // Render page to CGImage at 300 DPI
            guard let cgImage = renderPageToImage(page: page, dpi: 300) else {
                print("[PDFExtractor] Failed to render page \(i)")
                continue
            }

            let pageText = try await recognizeText(in: cgImage)
            if !pageText.isEmpty {
                allText += "--- Page \(i + 1) ---\n\(pageText)\n\n"
            }
        }

        return allText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Render a PDFPage to CGImage at specified DPI
    private static func renderPageToImage(page: PDFPage, dpi: CGFloat) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0 // PDF is 72 points/inch

        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            ctx.cgContext.translateBy(x: 0, y: CGFloat(height))
            ctx.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: ctx.cgContext)
        }

        return image.cgImage
    }

    /// OCR a CGImage using Vision framework
    private static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                // Sort by Y position (top to bottom) for proper reading order
                let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

                let text = sorted
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

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
}

enum PDFError: LocalizedError {
    case cannotOpenDocument

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: return "Could not open the PDF document"
        }
    }
}
