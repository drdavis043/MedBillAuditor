//
//  UpcodingChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Detects potential upcoding: when a provider bills a higher-level
/// (more expensive) code than the service actually warrants.
///
/// This is pattern-based — it flags suspicious patterns for user review,
/// not definitive fraud detection.
struct UpcodingChecker {
    /// E&M code levels in order from lowest to highest
    private let emCodeLevels: [(code: String, level: Int, description: String)] = [
        ("99211", 1, "Minimal office visit"),
        ("99212", 2, "Straightforward office visit"),
        ("99213", 3, "Low complexity office visit"),
        ("99214", 4, "Moderate complexity office visit"),
        ("99215", 5, "High complexity office visit"),
    ]
    private let erCodeLevels: [(code: String, level: Int, description: String)] = [
        ("99281", 1, "Straightforward ER visit"),
        ("99282", 2, "Low complexity ER visit"),
        ("99283", 3, "Moderate complexity ER visit"),
        ("99284", 4, "Moderate-high ER visit"),
        ("99285", 5, "High complexity ER visit"),
    ]
    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        let codes = lineItems.compactMap { $0.cptCode ?? $0.hcpcsCode }
        // Check for highest-level E&M codes
        for item in lineItems {
            guard let code = item.cptCode ?? item.hcpcsCode else { continue }
            // Flag level 5 E&M visits — these should be rare
            if let emLevel = emCodeLevels.first(where: { $0.code == code }), emLevel.level == 5 {
                let flag = AuditFlag(
                    flagType: .upcoding,
                    severity: .warning,
                    title: "High-Level E&M Code",
                    explanation: "Code \(code) (\(emLevel.description)) is the highest-level office visit code. These are appropriate for very complex cases but are sometimes billed when a lower-level code (99213 or 99214) would be more accurate.",
                    recommendation: "Review the visit notes to confirm the complexity warranted a level 5 visit. If this was a routine visit, request the provider reconsider the coding level."
                )
                let level4Item = lineItems.first { ($0.cptCode ?? $0.hcpcsCode) == "99214" }
                let potentialSavings = item.chargedAmount - (level4Item?.chargedAmount ?? item.chargedAmount * 0.7)
                flag.estimatedImpact = potentialSavings > 0 ? potentialSavings : nil
                flag.affectedLineItemID = item.id
                flags.append(flag)
            }
            // Flag highest-level ER codes
            if let erLevel = erCodeLevels.first(where: { $0.code == code }), erLevel.level == 5 {
                let flag = AuditFlag(
                    flagType: .upcoding,
                    severity: .warning,
                    title: "High-Level ER Code",
                    explanation: "Code \(code) (\(erLevel.description)) is the highest-level ER visit code. Verify that the complexity of your visit warranted this level.",
                    recommendation: "Request the medical records and compare against the ER level guidelines. If your visit was for a straightforward issue, the coding level may be too high."
                )
                flag.affectedLineItemID = item.id
                flags.append(flag)
            }
        }
        // Check for multiple high-level codes on same bill (unusual pattern)
        let highLevelCodes = codes.filter { code in
            emCodeLevels.contains(where: { $0.code == code && $0.level >= 4 }) ||
            erCodeLevels.contains(where: { $0.code == code && $0.level >= 4 })
        }
        if highLevelCodes.count > 1 {
            let flag = AuditFlag(
                flagType: .upcoding,
                severity: .info,
                title: "Multiple High-Level Visit Codes",
                explanation: "This bill contains \(highLevelCodes.count) high-level visit codes (\(highLevelCodes.joined(separator: ", "))). While this can be legitimate, it's worth verifying each code reflects the actual complexity of care.",
                recommendation: "Request documentation supporting each visit code level."
            )
            flags.append(flag)
        }
        return flags
    }
}
