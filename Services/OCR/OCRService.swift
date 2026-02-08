//
//  OCRService.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Vision
import UIKit

/// Extracts text from bill images using Apple Vision.
/// On-device processing — no data leaves the phone.
actor OCRService {
    
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
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                options: [:]
            )
            
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
