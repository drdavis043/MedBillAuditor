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
/// Uses real NCCI PTP edit pairs from CMS (15,000+ curated pairs) loaded
/// via BundlingDatabase, replacing the previous hardcoded rules.
struct UnbundlingChecker {

    private let db = BundlingDatabase.shared
    private let descriptions = CodeDescriptionDatabase.shared

    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        let codedItems = lineItems.filter { ($0.cptCode ?? $0.hcpcsCode) != nil }
        guard codedItems.count >= 2 else { return flags }

        var checked = Set<String>() // Avoid duplicate flags for same pair

        for i in 0..<codedItems.count {
            for j in (i + 1)..<codedItems.count {
                let item1 = codedItems[i]
                let item2 = codedItems[j]

                guard let code1 = item1.cptCode ?? item1.hcpcsCode,
                      let code2 = item2.cptCode ?? item2.hcpcsCode else { continue }

                let pairKey = [code1, code2].sorted().joined(separator: "-")
                guard !checked.contains(pairKey) else { continue }
                checked.insert(pairKey)

                // Only flag if they're on the same date (or no dates available)
                let dates = [item1.dateOfService, item2.dateOfService].compactMap { $0 }
                if dates.count == 2 {
                    let cal = Calendar.current
                    if cal.startOfDay(for: dates[0]) != cal.startOfDay(for: dates[1]) {
                        continue
                    }
                }

                guard let pair = db.findBundlingPair(code1: code1, code2: code2) else {
                    continue
                }

                let comprehensiveCode = pair.col1
                let componentCode = pair.col2
                let compDesc = descriptions.description(for: comprehensiveCode)
                    .map { " (\($0))" } ?? ""
                let partDesc = descriptions.description(for: componentCode)
                    .map { " (\($0))" } ?? ""

                let severity: FlagSeverity = pair.modifier == 0 ? .critical : .warning

                let explanation: String
                if pair.modifier == 0 {
                    explanation = "Code \(componentCode)\(partDesc) is included in code \(comprehensiveCode)\(compDesc) according to CMS NCCI edits. These codes should NEVER be billed together — the component service is already part of the comprehensive service."
                } else {
                    explanation = "Code \(componentCode)\(partDesc) is typically included in code \(comprehensiveCode)\(compDesc) per CMS NCCI edits. These may be billed separately only with an appropriate modifier documenting that the services were distinct."
                }

                // The component code's charge is the potential overcharge
                let componentItem = (item1.cptCode ?? item1.hcpcsCode) == componentCode ? item1 : item2

                let flag = AuditFlag(
                    flagType: .unbundling,
                    severity: severity,
                    title: "Unbundling: \(componentCode) included in \(comprehensiveCode)",
                    explanation: explanation,
                    recommendation: "Request that the provider remove the separate charge for \(componentCode)\(partDesc) since it is included in \(comprehensiveCode)\(compDesc). Potential savings: \(formatCurrency(componentItem.chargedAmount))."
                )
                flag.affectedLineItemID = componentItem.id
                flag.estimatedImpact = componentItem.chargedAmount
                flags.append(flag)
            }
        }

        return flags
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
