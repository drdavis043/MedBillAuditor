//
//  PriceChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation

/// Compares billed charges against Medicare national average prices.
/// Flags items that exceed Medicare rates by significant margins.
struct PriceChecker {
    let pricingService: PricingService

    /// Threshold multiplier: flag if billed > this × Medicare rate
    private let warningMultiplier: Decimal = 2.5
    private let criticalMultiplier: Decimal = 5.0

    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []

        for item in lineItems {
            guard let code = item.primaryCode,
                  let medicarePrice = pricingService.price(for: code),
                  medicarePrice > 0 else {
                continue
            }

            // Store the Medicare rate on the line item for display
            item.medicareRate = medicarePrice

            let ratio = item.chargedAmount / medicarePrice

            if ratio >= criticalMultiplier {
                let overcharge = item.chargedAmount - medicarePrice
                let flag = AuditFlag(
                    flagType: .priceOutlier,
                    severity: .critical,
                    title: "Charge is \(NSDecimalNumber(decimal: ratio).intValue)× Medicare Rate",
                    explanation: "The billed amount of $\(item.chargedAmount) for code \(code) is \(NSDecimalNumber(decimal: ratio).intValue) times the Medicare national average of $\(medicarePrice). This is an extreme markup.",
                    recommendation: "Request an itemized bill and ask the provider to justify the charge. The Medicare fair price for this service is $\(medicarePrice)."
                )
                flag.affectedLineItemID = item.id
                flag.estimatedImpact = overcharge
                flags.append(flag)
            } else if ratio >= warningMultiplier {
                let overcharge = item.chargedAmount - medicarePrice
                let flag = AuditFlag(
                    flagType: .priceOutlier,
                    severity: .warning,
                    title: "Charge Exceeds Medicare Rate by \(NSDecimalNumber(decimal: ratio).intValue)×",
                    explanation: "The billed amount of $\(item.chargedAmount) for code \(code) is \(NSDecimalNumber(decimal: ratio).intValue) times the Medicare national average of $\(medicarePrice). While some markup over Medicare is normal, this exceeds typical ranges.",
                    recommendation: "Compare with other providers in your area. The Medicare fair price for this service is $\(medicarePrice)."
                )
                flag.affectedLineItemID = item.id
                flag.estimatedImpact = overcharge
                flags.append(flag)
            }
        }

        return flags
    }
}
