//
//  OCRService.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Vision
import UIKit
/// Extracts text from bill images using Apple Vision.
/// On-device processing — no PHI ever leaves the phone.
actor OCRService {
    
    /// Extracts all recognized text from an image, preserving line order.
    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
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
                
                // Sort by vertical position (top to bottom) for correct reading order
                let sorted = observations.sorted {
                    $0.boundingBox.origin.y > $1.boundingBox.origin.y
                }
                
                let text = sorted
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            // Configure for maximum accuracy on printed text
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.automaticallyDetectsLanguage = false
            
            // Custom words that appear on medical bills
            request.customWords = [
                "CPT", "HCPCS", "ICD-10", "EOB", "NPI",
                "DEDUCTIBLE", "COPAY", "COINSURANCE",
                "ALLOWED", "BILLED", "ADJUSTMENT",
                "EXPLANATION OF BENEFITS",
                "DATE OF SERVICE", "PLACE OF SERVICE",
                "RENDERING PROVIDER", "REFERRING PROVIDER"
            ]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Extracts text with bounding box positions for structured parsing.
    /// Returns tuples of (text, normalizedRect) for spatial analysis.
    func extractTextWithPositions(from image: UIImage) async throws -> [(String, CGRect)] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results: [(String, CGRect)] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return (candidate.string, obs.boundingBox)
                }
                
                continuation.resume(returning: results)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image."
        case .recognitionFailed: return "Text recognition failed."
        }
    }
}
