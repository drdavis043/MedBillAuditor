//
//  UnbundlingChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation

/// Detects unbundling: when a provider bills separately for services that should
/// be billed as a single bundled code. Uses real NCCI PTP edit pairs from CMS.
struct UnbundlingChecker {

    private let db = BundlingDatabase.shared
    private let descriptions = CodeDescriptionDatabase.shared

    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        let codedItems = lineItems.filter { $0.primaryCode != nil }
        guard codedItems.count >= 2 else { return flags }

        var checked = Set<String>() // Avoid duplicate flags for same pair

        for i in 0..<codedItems.count {
            for j in (i + 1)..<codedItems.count {
                guard let code1 = codedItems[i].primaryCode,
                      let code2 = codedItems[j].primaryCode else { continue }

                let pairKey = [code1, code2].sorted().joined(separator: "-")
                guard !checked.contains(pairKey) else { continue }
                checked.insert(pairKey)

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
                let componentItem = (codedItems[i].primaryCode == componentCode) ? codedItems[i] : codedItems[j]
                let comprehensiveItem = (codedItems[i].primaryCode == comprehensiveCode) ? codedItems[i] : codedItems[j]

                let flag = AuditFlag(
                    flagType: .unbundling,
                    severity: severity,
                    title: "Unbundling: \(componentCode) included in \(comprehensiveCode)",
                    explanation: explanation,
                    recommendation: "Request that the provider remove the separate charge for \(componentCode)\(partDesc) since it is included in \(comprehensiveCode)\(compDesc). Potential savings: $\(componentItem.chargedAmount)."
                )
                flag.affectedLineItemID = componentItem.id
                flag.estimatedImpact = componentItem.chargedAmount
                flags.append(flag)
            }
        }

        return flags
    }
}
