//
//  QuantityChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 4/12/26.
//

import Foundation

/// Checks line items against CMS MUE (Medically Unlikely Edit) quantity limits.
/// Flags items where billed quantity exceeds the maximum allowed units per day.
struct QuantityChecker {

    private struct MUELimit: Decodable {
        let code: String
        let maxUnits: Int
        let rationale: String
    }

    private var limits: [String: Int] = [:]

    init() {
        loadLimits()
    }

    private mutating func loadLimits() {
        guard let url = Bundle.main.url(forResource: "mue_limits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([MUELimit].self, from: data) else {
            return
        }
        for entry in entries {
            limits[entry.code] = entry.maxUnits
        }
    }

    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []

        for item in lineItems {
            guard let code = item.primaryCode,
                  let maxUnits = limits[code],
                  item.quantity > maxUnits else {
                continue
            }

            let flag = AuditFlag(
                flagType: .incorrectQuantity,
                severity: item.quantity > maxUnits * 2 ? .critical : .warning,
                title: "Excessive Quantity for \(code)",
                explanation: "This bill shows \(item.quantity) units of \(code), but the CMS maximum is \(maxUnits) unit(s) per day. Billing more than the allowed maximum is unusual and may indicate an error.",
                recommendation: "Ask the provider to verify the quantity billed. If more than \(maxUnits) unit(s) were medically necessary, documentation should support it."
            )
            flag.affectedLineItemID = item.id
            flag.estimatedImpact = item.chargedAmount * Decimal(item.quantity - maxUnits) / Decimal(item.quantity)
            flags.append(flag)
        }

        return flags
    }
}
