//
//  ChargeExtractor.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

/// Extracts dollar amounts from OCR text lines.
/// Handles various formats: $1,234.56, 1234.56, $1234, S 1,234.56 (OCR misread), etc.
struct ChargeExtractor {
    
    /// Extracts all dollar amounts from a line, in order of appearance.
    func extractAmounts(from text: String) -> [ExtractedAmount] {
        var amounts: [ExtractedAmount] = []
        
        // First normalize S → $ for OCR misreads
        var normalized = text
        normalized = normalized.replacingOccurrences(
            of: "S\\s?([0-9]{1,3}(?:,?[0-9]{3})*\\.[0-9]{2})",
            with: "$$$1",
            options: .regularExpression
        )
        
        // Pattern 1: Dollar sign amounts — $1,234.56
        let dollarPattern = "\\$\\s?([0-9]{1,3}(?:,?[0-9]{3})*\\.[0-9]{2})"
        amounts.append(contentsOf: findAmounts(in: normalized, pattern: dollarPattern))
        
        // Pattern 2: Bare amounts at end of line (no $) — common in table-formatted bills
        // Only use if we didn't find any $ amounts
        if amounts.isEmpty {
            let barePattern = "\\b([0-9]{1,3}(?:,?[0-9]{3})*\\.[0-9]{2})\\s*$"
            let bareAmounts = findAmounts(in: normalized, pattern: barePattern)
            // Filter out likely false positives
            for amount in bareAmounts {
                if amount.value >= 10 && amount.value < 100_000 {
                    amounts.append(amount)
                }
            }
        }
        
        return amounts
    }
    
    private func findAmounts(in text: String, pattern: String) -> [ExtractedAmount] {
        var results: [ExtractedAmount] = []
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return results
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let numRange = Range(match.range(at: 1), in: text) else { continue }
            
            let rawText = String(text[fullRange])
            let numString = String(text[numRange])
                .replacingOccurrences(of: ",", with: "")
            
            guard let value = Decimal(string: numString),
                  value > 0,
                  value < 1_000_000 else { continue }
            
            if isLikelyFalsePositive(value: value, raw: rawText, context: text) {
                continue
            }
            
            results.append(ExtractedAmount(
                value: value,
                rawText: rawText
            ))
        }
        
        return results
    }
    
    /// Quick check: does this line contain any dollar amount?
    func containsDollarAmount(_ text: String) -> Bool {
        !extractAmounts(from: text).isEmpty
    }
    
    /// Attempts to classify amounts on a line into charge categories.
    func classifyAmounts(_ amounts: [ExtractedAmount], context: String) -> ClassifiedCharges {
        var result = ClassifiedCharges()
        let lower = context.lowercased()
        
        switch amounts.count {
        case 0:
            break
        case 1:
            if lower.contains("copay") || lower.contains("co-pay") {
                result.patientOwes = amounts[0].value
            } else if lower.contains("paid") || lower.contains("payment") {
                result.insurancePaid = amounts[0].value
            } else {
                result.billed = amounts[0].value
            }
        case 2:
            result.billed = amounts[0].value
            if lower.contains("allowed") || lower.contains("approved") {
                result.allowed = amounts[1].value
            } else {
                result.patientOwes = amounts[1].value
            }
        case 3:
            result.billed = amounts[0].value
            result.allowed = amounts[1].value
            result.patientOwes = amounts[2].value
        case 4:
            result.billed = amounts[0].value
            result.allowed = amounts[1].value
            result.adjustment = amounts[2].value
            result.insurancePaid = amounts[3].value
        default:
            result.billed = amounts[0].value
            result.allowed = amounts[1].value
            result.adjustment = amounts[2].value
            result.insurancePaid = amounts[3].value
            result.patientOwes = amounts[4].value
        }
        
        return result
    }
    
    // MARK: - False Positive Detection
    
    private func isLikelyFalsePositive(value: Decimal, raw: String, context: String) -> Bool {
        let lower = context.lowercased()
        
        if lower.contains("account") || lower.contains("ref #") || lower.contains("claim #") {
            if !raw.contains("$") {
                return true
            }
        }
        
        // Phone numbers
        if lower.contains("call") || lower.contains("phone") || lower.contains("fax") {
            return true
        }
        
        return false
    }
}

// MARK: - Types

struct ExtractedAmount: Equatable {
    let value: Decimal
    let rawText: String
}

struct ClassifiedCharges {
    var billed: Decimal?
    var allowed: Decimal?
    var adjustment: Decimal?
    var insurancePaid: Decimal?
    var patientOwes: Decimal?
}










