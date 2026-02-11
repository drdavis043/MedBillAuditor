//
//  UnbundlingChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Detects unbundling: when a provider bills separate codes for procedures
/// that should be billed as a single bundled code.
///
/// Example: Billing a CBC (85025) and a metabolic panel (80053) separately
/// when they were performed together and should use a comprehensive code.
struct UnbundlingChecker {
    /// Known code pairs that are commonly unbundled.
    /// In production, this would reference CCI (Correct Coding Initiative) edits.
    private let unbundlingRules: [(codes: Set<String>, bundledCode: String, description: String)] = [
        // Lab panels
        (["80048", "80053"], "80053",
         "Basic Metabolic Panel (80048) is included in Comprehensive Metabolic Panel (80053). Both should not be billed together."),
        (["85025", "85027"], "85025",
         "CBC without differential (85027) is included in CBC with differential (85025). Both should not be billed together."),
        // E&M stacking
        (["99213", "99214"], "99214",
         "Two E&M visit codes billed on the same date. Only the higher-level code should be billed."),
        (["99214", "99215"], "99215",
         "Two E&M visit codes billed on the same date. Only the higher-level code should be billed."),
        // Blood draw + lab
        (["36415", "36416"], "36415",
         "Capillary blood draw (36416) and venipuncture (36415) billed together. Typically only one collection method should be billed."),
    ]
    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        let codeSet = Set(lineItems.compactMap { $0.cptCode ?? $0.hcpcsCode })
        for rule in unbundlingRules {
            // Check if all codes in the rule are present on the bill
            if rule.codes.isSubset(of: codeSet) {
                let affectedItems = lineItems.filter {
                    guard let code = $0.cptCode ?? $0.hcpcsCode else { return false }
                    return rule.codes.contains(code)
                }
                // Only flag if they're on the same date (or no dates available)
                let dates = affectedItems.compactMap { $0.dateOfService }
                let sameDateOrNoDate = dates.isEmpty || Set(dates.map {
                    Calendar.current.startOfDay(for: $0)
                }).count == 1
                if sameDateOrNoDate {
                    let totalCharged = affectedItems.reduce(Decimal(0)) { $0 + $1.chargedAmount }
                    let codes = rule.codes.sorted().joined(separator: ", ")
                    let flag = AuditFlag(
                        flagType: .unbundling,
                        severity: .warning,
                        title: "Possible Unbundling",
                        explanation: "Codes \(codes) were billed separately. \(rule.description)",
                        recommendation: "Request that the provider rebill using the appropriate bundled code (\(rule.bundledCode)). The separate billing may result in a higher total charge."
                    )
                    // Estimate impact as the cost of the lesser code
                    let minCharge = affectedItems.map { $0.chargedAmount }.min() ?? 0
                    flag.estimatedImpact = minCharge
                    flag.affectedLineItemID = affectedItems.first?.id
                    flags.append(flag)
                }
            }
        }
        return flags
    }
}
