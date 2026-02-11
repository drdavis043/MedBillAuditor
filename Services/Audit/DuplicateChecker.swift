//
//  DuplicateChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Detects duplicate charges: same CPT code + same date + same amount.
/// Also catches near-duplicates where amounts differ slightly (OCR errors).
struct DuplicateChecker {
    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        var seen: [String: [LineItem]] = [:]  // Key: "cptCode-date" → items
        for item in lineItems {
            guard let code = item.cptCode ?? item.hcpcsCode else { continue }
            let dateKey: String
            if let date = item.dateOfService {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateKey = formatter.string(from: date)
            } else {
                dateKey = "no-date"
            }
            let key = "\(code)-\(dateKey)"
            if seen[key] == nil {
                seen[key] = []
            }
            seen[key]?.append(item)
        }
        // Flag groups with more than one item
        for (_, items) in seen where items.count > 1 {
            // Check if amounts are identical (exact duplicate) or similar
            let amounts = items.map { $0.chargedAmount }
            let firstAmount = amounts[0]
            let allSame = amounts.allSatisfy { $0 == firstAmount }
            for item in items.dropFirst() {
                let code = item.cptCode ?? item.hcpcsCode ?? "unknown"
                let flag: AuditFlag
                if allSame {
                    flag = AuditFlag(
                        flagType: .duplicateCharge,
                        severity: .critical,
                        title: "Duplicate Charge",
                        explanation: "CPT \(code) appears \(items.count) times on the same date with the same amount ($\(item.chargedAmount)). This is likely a billing error.",
                        recommendation: "Contact the billing department and request removal of the duplicate charge. Reference the specific date and CPT code."
                    )
                    flag.estimatedImpact = item.chargedAmount
                } else {
                    flag = AuditFlag(
                        flagType: .duplicateCharge,
                        severity: .warning,
                        title: "Possible Duplicate Charge",
                        explanation: "CPT \(code) appears \(items.count) times on the same date with different amounts. This may be intentional (e.g., multiple units) or a billing error.",
                        recommendation: "Request an itemized explanation for why this code was billed multiple times on the same date."
                    )
                    flag.estimatedImpact = item.chargedAmount
                }
                flag.affectedLineItemID = item.id
                flags.append(flag)
            }
        }
        return flags
    }
}
