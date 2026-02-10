//
//  CPTExtractor.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

/// Extracts CPT (5-digit numeric) and HCPCS (alpha + 4-digit) codes from text.
/// Also handles hospital bill formats where codes have a leading zero (e.g., 036415 → 36415).
struct CPTExtractor {
    
    /// All extracted codes from a line of text.
    func extract(from text: String) -> [ExtractedCode] {
        var codes: [ExtractedCode] = []
        
        // Hospital format: 6-digit codes with leading zero (e.g., 036415, 080053)
        let leadingZeroPattern = "\\b0(\\d{5})(?:-(\\w{2}))?\\b"
        codes.append(contentsOf: findCodes(
            in: text,
            pattern: leadingZeroPattern,
            type: .cpt,
            validator: isValidCPT
        ))
        
        // Standard CPT codes: 5 digits (e.g., 99213, 36415)
        // Only look for these if we didn't already find leading-zero versions
        if codes.isEmpty {
            let cptPattern = "\\b(\\d{5})(?:-(\\w{2}))?\\b"
            codes.append(contentsOf: findCodes(
                in: text,
                pattern: cptPattern,
                type: .cpt,
                validator: isValidCPT
            ))
        }
        
        // HCPCS Level II: letter + 4 digits (e.g., J3301, A4556)
        let hcpcsPattern = "\\b([A-Z]\\d{4})(?:-(\\w{2}))?\\b"
        codes.append(contentsOf: findCodes(
            in: text,
            pattern: hcpcsPattern,
            type: .hcpcs,
            validator: isValidHCPCS
        ))
        
        return codes
    }
    
    /// Checks if a line contains any medical billing code.
    func containsCode(_ text: String) -> Bool {
        !extract(from: text).isEmpty
    }
    
    // MARK: - Private
    
    private func findCodes(
        in text: String,
        pattern: String,
        type: CodeType,
        validator: (String) -> Bool
    ) -> [ExtractedCode] {
        var results: [ExtractedCode] = []
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return results
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        for match in matches {
            guard let codeRange = Range(match.range(at: 1), in: text) else { continue }
            let code = String(text[codeRange])
            
            guard validator(code) else { continue }
            
            // Check for modifier (group 2)
            var modifier: String?
            if match.numberOfRanges > 2,
               let modRange = Range(match.range(at: 2), in: text) {
                modifier = String(text[modRange])
            }
            
            // Avoid duplicates
            let newCode = ExtractedCode(code: code, type: type, modifier: modifier)
            if !results.contains(newCode) {
                results.append(newCode)
            }
        }
        
        return results
    }
    
    /// Validates a 5-digit code falls within known CPT ranges.
    private func isValidCPT(_ code: String) -> Bool {
        guard let num = Int(code) else { return false }
        
        // Valid CPT ranges
        let validRanges: [ClosedRange<Int>] = [
            00100...01999,  // Anesthesia
            10004...69990,  // Surgery
            70010...79999,  // Radiology
            80047...89398,  // Pathology & Lab
            90281...99607,  // Medicine
            99201...99499,  // E&M
        ]
        
        // Exclude common false positives (ZIP codes, dates, etc.)
        let falsePositives: Set<String> = [
            "10001", "10002", "10003", "10010", "10011",  // NYC ZIPs
            "90210", "90211",  // Beverly Hills ZIPs
            "12345", "11111", "00000", "99999",  // Generic numbers
            "42066",  // Mayfield KY ZIP from sample bill
        ]
        
        if falsePositives.contains(code) { return false }
        
        return validRanges.contains { $0.contains(num) }
    }
    
    /// Validates HCPCS Level II codes.
    private func isValidHCPCS(_ code: String) -> Bool {
        guard code.count == 5 else { return false }
        let prefix = code.prefix(1)
        
        // Valid HCPCS Level II prefixes
        let validPrefixes: Set<String> = [
            "A", "B", "C", "D", "E", "G", "H", "J",
            "K", "L", "M", "P", "Q", "R", "S", "T", "V"
        ]
        
        return validPrefixes.contains(String(prefix))
    }
}

// MARK: - Types

struct ExtractedCode: Equatable {
    let code: String
    let type: CodeType
    let modifier: String?
}

enum CodeType: String {
    case cpt
    case hcpcs
}
