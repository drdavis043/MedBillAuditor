//
//  PriceChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Compares each line item's charged amount against Medicare fair market pricing.
/// Flags items where the charge exceeds the typical commercial rate.
struct PriceChecker {
    let pricingService: PricingService
    func check(_ lineItems: [LineItem], facilityType: FacilityType) async -> [AuditFlag] {
        var flags: [AuditFlag] = []
        for item in lineItems {
            guard let code = item.cptCode ?? item.hcpcsCode else { continue }
            
            let evaluation = pricingService.evaluate(
                chargedAmount: item.chargedAmount,
                cptCode: code,
                facilityType: facilityType
            )
            
            switch evaluation.status {
            case .elevated:
                let flag = AuditFlag(
                    flagType: .priceOutlier,
                    severity: .warning,
                    title: "Above Average Price",
                    explanation: evaluation.explanation,
                    recommendation: "Request an itemized bill and ask the provider to justify this charge. Reference Medicare rate of \(formatCurrency(evaluation.medicareRate)) for CPT \(code)."
                )
                flag.estimatedImpact = evaluation.overchargeEstimate
                flag.affectedLineItemID = item.id
                flags.append(flag)
                
            case .outlier:
                let flag = AuditFlag(
                    flagType: .priceOutlier,
                    severity: .critical,
                    title: "Significant Overcharge Detected",
                    explanation: evaluation.explanation,
                    recommendation: "Strongly recommend disputing this charge. The Medicare rate for CPT \(code) is \(formatCurrency(evaluation.medicareRate)), and typical commercial rates are around \(formatCurrency(evaluation.typicalRate)). You were charged \(formatCurrency(evaluation.chargedAmount))."
                )
                flag.estimatedImpact = evaluation.overchargeEstimate
                flag.affectedLineItemID = item.id
                flags.append(flag)
                
            case .fair, .typical, .unknown:
                break
            }
        }
        return flags
    }
    private func formatCurrency(_ value: Decimal?) -> String {
        guard let value else { return "N/A" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
