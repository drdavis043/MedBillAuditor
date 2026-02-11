//
//  BalanceBillingChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Detects potential balance billing violations.
/// Balance billing occurs when an in-network provider bills the patient
/// for the difference between their charge and the insurance allowed amount.
///
/// Under the No Surprises Act (2022), this is illegal for:
/// - Emergency services
/// - Non-emergency services at in-network facilities by out-of-network providers
/// - Air ambulance services
struct BalanceBillingChecker {
    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        for item in lineItems {
            // Check if there's both a charged amount and an allowed amount
            guard let allowed = item.allowedAmount,
                  allowed > 0,
                  item.chargedAmount > allowed else { continue }
            let difference = item.chargedAmount - allowed
            let code = item.cptCode ?? item.hcpcsCode ?? "unknown"
            // If the patient responsibility exceeds the typical copay/coinsurance
            // range, it might be balance billing
            let ratio = difference / item.chargedAmount
            
            if ratio > 0.3 {  // Patient being charged more than 30% above allowed
                let flag = AuditFlag(
                    flagType: .balanceBilling,
                    severity: .critical,
                    title: "Possible Balance Billing",
                    explanation: "For CPT \(code), you were charged $\(item.chargedAmount) but the allowed amount is $\(allowed). The difference of $\(difference) may be improper balance billing, especially if the provider is in-network.",
                    recommendation: "Under the No Surprises Act, in-network providers cannot balance bill you beyond your copay, coinsurance, and deductible. Contact your insurance company to verify the allowed amount, and dispute this charge if the provider is in-network."
                )
                flag.estimatedImpact = difference
                flag.affectedLineItemID = item.id
                flags.append(flag)
            }
        }
        return flags
    }
}
