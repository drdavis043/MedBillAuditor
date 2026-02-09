//
//  ImagePreprocessor.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
/// Prepares captured bill images for optimal OCR accuracy.
/// All processing happens on-device using Core Image filters.
struct ImagePreprocessor {
    private let context = CIContext()
    
    /// Full preprocessing pipeline: orient → resize → grayscale → contrast → sharpen
    func preprocess(_ image: UIImage) -> UIImage {
        guard var ciImage = CIImage(image: image) else { return image }
        
        // Step 1: Fix orientation
        ciImage = ciImage.oriented(forExifOrientation: orientationToExif(image.imageOrientation))
        
        // Step 2: Downscale if massive (>4000px) to speed up OCR
        ciImage = constrainSize(ciImage, maxDimension: 3000)
        
        // Step 3: Convert to grayscale
        ciImage = applyGrayscale(ciImage)
        
        // Step 4: Increase contrast for text clarity
        ciImage = applyContrastBoost(ciImage)
        
        // Step 5: Sharpen edges (helps with slightly blurry photos)
        ciImage = applySharpen(ciImage)
        
        // Step 6: Adaptive threshold for difficult lighting (optional, heavy)
        // ciImage = applyAdaptiveThreshold(ciImage)
        
        return renderToUIImage(ciImage, scale: image.scale)
    }
    
    // MARK: - Individual Filters
    
    /// Converts to grayscale, removing color noise.
    private func applyGrayscale(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorMonochrome()
        filter.inputImage = image
        filter.color = CIColor(red: 0.7, green: 0.7, blue: 0.7)
        filter.intensity = 1.0
        return filter.outputImage ?? image
    }
    
    /// Boosts contrast so text stands out against background.
    private func applyContrastBoost(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = 1.4       // Increase from default 1.0
        filter.brightness = 0.05    // Slight bump to counteract darkening
        filter.saturation = 0.0     // Fully desaturated
        return filter.outputImage ?? image
    }
    
    /// Sharpens text edges for cleaner character recognition.
    private func applySharpen(_ image: CIImage) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = image
        filter.radius = 1.5
        filter.intensity = 0.5
        return filter.outputImage ?? image
    }
    
    /// Constrains image to a max dimension while preserving aspect ratio.
    private func constrainSize(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let maxSide = max(extent.width, extent.height)
        guard maxSide > maxDimension else { return image }
        
        let scale = maxDimension / maxSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    
    // MARK: - Helpers
    
    private func renderToUIImage(_ ciImage: CIImage, scale: CGFloat) -> UIImage {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    
    private func orientationToExif(_ orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up:            return 1
        case .down:          return 3
        case .left:          return 8
        case .right:         return 6
        case .upMirrored:    return 2
        case .downMirrored:  return 4
        case .leftMirrored:  return 5
        case .rightMirrored: return 7
        @unknown default:    return 1
        }
    }
}
// MARK: - Optional: Deskew Extension
// Uses Vision to detect document edges and correct perspective.
import Vision
extension ImagePreprocessor {
    
    /// Attempts to detect and correct document skew using Vision.
    /// Returns original image if no clear document rectangle is found.
    func deskew(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumConfidence = 0.6
        request.maximumObservations = 1
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            return image
        }
        
        guard let observation = request.results?.first else { return image }
        
        let corrected = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: convertPoint(observation.topLeft, in: ciImage.extent)),
            "inputTopRight": CIVector(cgPoint: convertPoint(observation.topRight, in: ciImage.extent)),
            "inputBottomLeft": CIVector(cgPoint: convertPoint(observation.bottomLeft, in: ciImage.extent)),
            "inputBottomRight": CIVector(cgPoint: convertPoint(observation.bottomRight, in: ciImage.extent)),
        ])
        
        return renderToUIImage(corrected, scale: image.scale)
    }
    
    private func convertPoint(_ point: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: point.x * extent.width + extent.origin.x,
            y: point.y * extent.height + extent.origin.y
        )
    }
}
