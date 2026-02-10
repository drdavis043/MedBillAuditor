//
//  BillParser.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

/// Orchestrates the full parsing pipeline:
/// Raw OCR text → cleaned lines → extracted line items with codes and charges.
struct BillParser {
    private let cptExtractor = CPTExtractor()
    private let chargeExtractor = ChargeExtractor()
    
    /// Main entry point: takes raw OCR text and returns structured line items.
    func parse(_ rawText: String) -> ParsedBill {
        let lines = preprocessLines(rawText)
        let sections = identifySections(lines)
        let lineItems = extractLineItems(from: sections)
        let billInfo = extractBillInfo(from: sections)
        
        return ParsedBill(
            providerName: billInfo.providerName,
            facilityType: billInfo.facilityType,
            patientName: billInfo.patientName,
            serviceDate: billInfo.serviceDate,
            totalCharged: billInfo.totalCharged,
            lineItems: lineItems
        )
    }
    
    // MARK: - Step 1: Preprocess
    
    private func preprocessLines(_ rawText: String) -> [String] {
        rawText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { normalizeText($0) }
    }
    
    private func normalizeText(_ text: String) -> String {
        var result = text
        // OCR often reads "$" as "S" before dollar amounts
        result = result.replacingOccurrences(
            of: "S\\s?([0-9]{1,3}(?:,?[0-9]{3})*\\.[0-9]{2})",
            with: "$$$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "S$", with: "$")
        result = result.replacingOccurrences(of: "$l", with: "$1")
        result = result.replacingOccurrences(of: "$I", with: "$1")
        result = result.replacingOccurrences(of: "$O", with: "$0")
        result = result.replacingOccurrences(
            of: "\\$\\s+([0-9])",
            with: "$$$1",
            options: .regularExpression
        )
        return result
    }
    
    // MARK: - Step 2: Section Identification
    
    private func identifySections(_ lines: [String]) -> BillSections {
        var sections = BillSections()
        var currentSection: SectionType = .header
        var previousLineWasSubtotal = false
        
        for line in lines {
            let lower = line.lowercased()
            
            // If previous line was "Subtotal:", this line has the amount
            if previousLineWasSubtotal {
                previousLineWasSubtotal = false
                if chargeExtractor.containsDollarAmount(line) {
                    sections.totals.append("subtotal \(line)")
                    continue
                }
            }
            
            // Check for "Subtotal:" on its own line
            if isSubtotalOrTotal(lower) && !chargeExtractor.containsDollarAmount(line) {
                previousLineWasSubtotal = true
                continue
            }
            
            // Subtotal/total with amount on same line
            if isSubtotalOrTotal(lower) && chargeExtractor.containsDollarAmount(line) {
                sections.totals.append(line)
                continue
            }
            
            if isChargeHeader(lower) {
                currentSection = .charges
                continue
            } else if isRevCodeHeader(lower) {
                if currentSection == .charges { continue }
            } else if lower.contains("insurance") || lower.contains("plan") || lower.contains("coverage") {
                currentSection = .insurance
            } else if lower.contains("patient resp") || lower.contains("amount due") || lower.contains("balance due") {
                currentSection = .patientResponsibility
            }
            
            switch currentSection {
            case .header:
                sections.header.append(line)
            case .charges:
                sections.charges.append(line)
            case .insurance:
                sections.insurance.append(line)
            case .patientResponsibility:
                sections.patientResponsibility.append(line)
            case .totals:
                sections.totals.append(line)
            }
        }
        
        return sections
    }
    
    private func isChargeHeader(_ line: String) -> Bool {
        let exactHeaders = [
            "itemization of hospital services",
            "itemization of services",
            "inpatient services",
            "outpatient services"
        ]
        if exactHeaders.contains(where: { line.contains($0) }) { return true }
        
        let headers = [
            "description", "service", "procedure",
            "cpt", "hcpcs", "hcps", "charges", "amount",
            "date of service", "dos", "rev code"
        ]
        let matchCount = headers.filter { line.contains($0) }.count
        return matchCount >= 2
    }
    
    private func isRevCodeHeader(_ line: String) -> Bool {
        line.range(of: "^0\\d{3}\\s*-\\s*[A-Z]", options: .regularExpression) != nil
    }
    
    private func isSubtotalOrTotal(_ line: String) -> Bool {
        line.contains("subtotal") || line.contains("total") ||
        line.contains("grand total") || line.contains("amount due")
    }
    
    // MARK: - Step 3: Multi-Line Item Assembly
    
    /// Assembles line items from charge lines where code, date, description,
    /// and amount may each be on separate lines.
    ///
    /// Strategy: A dollar amount marks the END of a line item.
    /// We accumulate fragments (codes, dates, descriptions) until we hit
    /// an amount, then bundle everything collected so far into one line item.
    private func extractLineItems(from sections: BillSections) -> [ParsedLineItem] {
        var items: [ParsedLineItem] = []
        
        // Accumulators for the current item being built
        var currentCodes: [ExtractedCode] = []
        var currentDate: Date?
        var currentDescriptions: [String] = []
        
        for line in sections.charges {
            let lower = line.lowercased()
            
            // Skip noise lines
            if isSubtotalOrTotal(lower) { continue }
            if lower.contains("page ") && line.contains(where: { $0.isNumber }) { continue }
            if lower.contains("prohibit") || lower.contains("insurance payment") { continue }
            if line == "--" || line == "•" || line == ":" || line.count <= 1 { continue }
            
            let codes = cptExtractor.extract(from: line)
            let amounts = chargeExtractor.extractAmounts(from: line)
            let date = extractDate(from: line)
            
            let hasCode = !codes.isEmpty
            let hasAmount = !amounts.isEmpty
            
            // If we hit an amount, that closes the current item
            if hasAmount {
                // Collect any code/date/description from this line too
                if hasCode { currentCodes.append(contentsOf: codes) }
                if let date = date { currentDate = date }
                
                let descOnThisLine = extractDescriptionFrom(line, removingCodes: codes, removingAmounts: amounts)
                if !descOnThisLine.isEmpty {
                    currentDescriptions.append(descOnThisLine)
                }
                
                // Build the line item
                let description = currentDescriptions
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let item = ParsedLineItem(
                    cptCode: currentCodes.first(where: { $0.type == .cpt })?.code,
                    hcpcsCode: currentCodes.first(where: { $0.type == .hcpcs })?.code,
                    description: description.isEmpty ? "Unknown Service" : description,
                    chargedAmount: amounts.first?.value ?? 0,
                    allowedAmount: nil,
                    adjustmentAmount: nil,
                    paidAmount: nil,
                    dateOfService: currentDate,
                    modifier: currentCodes.first?.modifier
                )
                items.append(item)
                
                // Reset accumulators
                currentCodes = []
                currentDate = nil
                currentDescriptions = []
                
            } else {
                // No amount — accumulate fragments for the next item
                if hasCode { currentCodes.append(contentsOf: codes) }
                if let date = date { currentDate = date }
                
                // Only add as description if it's not just a date or just a code
                if !isJustADate(line) && !isJustANumber(line) {
                    let cleaned = extractDescriptionFrom(line, removingCodes: codes, removingAmounts: [])
                    if !cleaned.isEmpty {
                        currentDescriptions.append(cleaned)
                    }
                }
            }
        }
        
        return items
    }
    
    /// Extracts just the description text from a line, removing codes, amounts, dates, and noise.
    private func extractDescriptionFrom(
        _ line: String,
        removingCodes codes: [ExtractedCode],
        removingAmounts amounts: [ExtractedAmount]
    ) -> String {
        var desc = line
        
        // Remove codes (both with and without leading zero)
        for code in codes {
            desc = desc.replacingOccurrences(of: "0" + code.code, with: "")
            desc = desc.replacingOccurrences(of: code.code, with: "")
        }
        
        // Remove amounts
        for amount in amounts {
            desc = desc.replacingOccurrences(of: amount.rawText, with: "")
        }
        
        // Remove dates
        desc = desc.replacingOccurrences(
            of: "\\d{1,2}/\\d{1,2}/\\d{2,4}\\.?",
            with: "",
            options: .regularExpression
        )
        
        // Remove standalone 6-digit codes that might not have been caught
        desc = desc.replacingOccurrences(
            of: "\\b0\\d{5}\\b",
            with: "",
            options: .regularExpression
        )
        
        // Remove revenue codes
        desc = desc.replacingOccurrences(
            of: "\\b0\\d{3}\\b",
            with: "",
            options: .regularExpression
        )
        
        // Remove dollar signs
        desc = desc.replacingOccurrences(of: "$", with: "")
        
        // Clean up
        desc = desc
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-•:,")))
        
        return desc
    }
    
    private func isJustADate(_ line: String) -> Bool {
        let stripped = line
            .replacingOccurrences(of: "\\d{1,2}/\\d{1,2}/\\d{2,4}\\.?", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty || stripped.count <= 2
    }
    
    private func isJustANumber(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 3 && trimmed.allSatisfy({ $0.isNumber })
    }
    
    // MARK: - Step 4: Bill Info Extraction
    
    private func extractBillInfo(from sections: BillSections) -> BillInfo {
        var info = BillInfo()
        
        for line in sections.header {
            let lower = line.lowercased()
            
            if lower.contains("creation date") || lower.contains("print date") ||
               lower.contains("statement date") || lower.contains("billing date") { continue }
            if lower.contains("patient name") || lower.contains("patient number") ||
               lower.contains("patient type") || lower.contains("medical record") ||
               lower.contains("hospital number") || lower.contains("dates of service") { continue }
            
            // Provider name
            if info.providerName == nil && !chargeExtractor.containsDollarAmount(line) {
                let hasAddress = lower.contains("street") || lower.contains("ave") ||
                                lower.contains("blvd") || lower.contains("suite") ||
                                lower.contains("po box") || lower.contains("p.o. box")
                let hasPhone = line.filter({ $0.isNumber }).count >= 7 && line.contains("-")
                let isDate = line.range(of: "\\d{1,2}/\\d{1,2}/\\d{2,4}", options: .regularExpression) != nil
                let isNumber = line.filter({ $0.isNumber }).count > line.filter({ $0.isLetter }).count
                let isZipLine = line.range(of: "\\d{5}-\\d{4}", options: .regularExpression) != nil
                
                if !hasAddress && !hasPhone && !isDate && !isNumber && !isZipLine &&
                   line.count > 3 && line.count < 80 {
                    info.providerName = line
                }
            }
            
            // Facility type
            if lower.contains("hospital") || lower.contains("med cir") || lower.contains("medical center") {
                info.facilityType = .hospital
            } else if lower.contains("urgent care") { info.facilityType = .urgentCare }
            else if lower.contains("laboratory") || lower.contains("lab ") { info.facilityType = .laboratory }
            else if lower.contains("imaging") || lower.contains("radiology") { info.facilityType = .imagingCenter }
            else if lower.contains("emergency") || lower.contains("er ") { info.facilityType = .emergency }
            
            // Service date
            if lower.contains("service") || lower.contains("dos") {
                if let date = extractDate(from: line) {
                    info.serviceDate = date
                }
            }
            if let date = extractDate(from: line), info.serviceDate == nil {
                info.serviceDate = date
            }
        }
        
        // Patient name: line after "Patient Name"
        let allLines = sections.header
        for (index, line) in allLines.enumerated() {
            if line.lowercased().contains("patient name") && index + 1 < allLines.count {
                let nextLine = allLines[index + 1]
                let letterCount = nextLine.filter({ $0.isLetter || $0 == " " }).count
                if letterCount > nextLine.count / 2 && nextLine.count > 2 && nextLine.count < 60 {
                    info.patientName = nextLine
                }
            }
        }
        
        // Calculate total from subtotals
        var runningTotal: Decimal = 0
        for line in sections.totals {
            let lower = line.lowercased()
            if lower.contains("grand total") || lower.contains("total charge") ||
               lower.contains("total amount") {
                let amounts = chargeExtractor.extractAmounts(from: line)
                if let amount = amounts.last {
                    info.totalCharged = amount.value
                    return info
                }
            }
            if lower.contains("subtotal") {
                let amounts = chargeExtractor.extractAmounts(from: line)
                if let amount = amounts.last {
                    runningTotal += amount.value
                }
            }
        }
        
        if runningTotal > 0 {
            info.totalCharged = runningTotal
        }
        
        return info
    }
    
    // MARK: - Helpers
    
    private func extractDate(from line: String) -> Date? {
        let patterns = [
            "\\d{1,2}/\\d{1,2}/\\d{2,4}",
            "\\d{1,2}-\\d{1,2}-\\d{2,4}",
            "\\d{4}-\\d{2}-\\d{2}",
        ]
        
        let formatters: [String: String] = [
            "\\d{1,2}/\\d{1,2}/\\d{4}": "M/d/yyyy",
            "\\d{1,2}/\\d{1,2}/\\d{2}": "M/d/yy",
            "\\d{1,2}-\\d{1,2}-\\d{4}": "M-d-yyyy",
            "\\d{4}-\\d{2}-\\d{2}": "yyyy-MM-dd",
        ]
        
        for pattern in patterns {
            if let range = line.range(of: pattern, options: .regularExpression) {
                let dateString = String(line[range])
                for (regexPattern, dateFormat) in formatters {
                    if dateString.range(of: regexPattern, options: .regularExpression) != nil {
                        let formatter = DateFormatter()
                        formatter.dateFormat = dateFormat
                        if let date = formatter.date(from: dateString) {
                            return date
                        }
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Supporting Types

struct ParsedBill {
    let providerName: String?
    let facilityType: FacilityType
    let patientName: String?
    let serviceDate: Date?
    let totalCharged: Decimal
    let lineItems: [ParsedLineItem]
}

struct ParsedLineItem {
    let cptCode: String?
    let hcpcsCode: String?
    let description: String
    let chargedAmount: Decimal
    let allowedAmount: Decimal?
    let adjustmentAmount: Decimal?
    let paidAmount: Decimal?
    let dateOfService: Date?
    let modifier: String?
}

struct BillSections {
    var header: [String] = []
    var charges: [String] = []
    var insurance: [String] = []
    var patientResponsibility: [String] = []
    var totals: [String] = []
}

enum SectionType {
    case header, charges, insurance, patientResponsibility, totals
}

struct BillInfo {
    var providerName: String?
    var facilityType: FacilityType = .unknown
    var patientName: String?
    var serviceDate: Date?
    var totalCharged: Decimal = 0
}
