//
//  PricingService.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Provides fair market pricing for medical procedures.
/// Compares billed amounts against Medicare rates and flags outliers.
struct PricingService {
    private let feeLoader = MedicareFeeLoader.shared
    
    /// Medicare rates are typically the floor. Commercial insurance
    /// pays a multiplier above Medicare. These are industry averages.
    private let commercialMultiplier: Decimal = 2.5  // 250% of Medicare
    private let highOutlierThreshold: Decimal = 4.0  // >400% of Medicare
    
    /// Looks up the fair price range for a CPT code.
    func fairPriceRange(
        for cptCode: String,
        facilityType: FacilityType = .unknown
    ) -> PriceRange? {
        guard let entry = feeLoader.lookup(cptCode) else { return nil }
        
        // Choose the appropriate base rate
        let baseRate: Decimal
        switch facilityType {
        case .hospital, .emergency, .ambulatory:
            baseRate = entry.facilityRate ?? entry.nonFacilityRate ?? 0
        default:
            baseRate = entry.nonFacilityRate ?? entry.facilityRate ?? 0
        }
        
        guard baseRate > 0 else { return nil }
        
        return PriceRange(
            medicareRate: baseRate,
            typicalCommercialRate: baseRate * commercialMultiplier,
            highOutlierThreshold: baseRate * highOutlierThreshold,
            description: entry.description,
            workRVU: entry.workRVU,
            totalRVU: entry.totalRVU
        )
    }
    
    /// Evaluates a billed charge against the fair price range.
    func evaluate(
        chargedAmount: Decimal,
        cptCode: String,
        facilityType: FacilityType = .unknown
    ) -> PriceEvaluation {
        guard let range = fairPriceRange(for: cptCode, facilityType: facilityType) else {
            return PriceEvaluation(
                status: .unknown,
                chargedAmount: chargedAmount,
                medicareRate: nil,
                typicalRate: nil,
                overchargeEstimate: nil,
                percentAboveMedicare: nil,
                explanation: "No pricing data available for code \(cptCode)."
            )
        }
        
        let percentAboveMedicare = range.medicareRate > 0
            ? ((chargedAmount - range.medicareRate) / range.medicareRate) * 100
            : nil
        
        let status: PriceStatus
        let overcharge: Decimal?
        let explanation: String
        
        if chargedAmount <= range.medicareRate * 1.1 {
            // Within 10% of Medicare — very fair
            status = .fair
            overcharge = nil
            explanation = "This charge is at or near the Medicare rate. This is a fair price."
        } else if chargedAmount <= range.typicalCommercialRate {
            // Within typical commercial range
            status = .typical
            overcharge = nil
            explanation = "This charge is within the typical range for commercial insurance (\(formatPercent(percentAboveMedicare))% above Medicare)."
        } else if chargedAmount <= range.highOutlierThreshold {
            // Above typical but not extreme
            status = .elevated
            overcharge = chargedAmount - range.typicalCommercialRate
            explanation = "This charge is above the typical commercial rate. You may be overcharged by approximately \(formatCurrency(overcharge ?? 0))."
        } else {
            // Extreme outlier
            status = .outlier
            overcharge = chargedAmount - range.typicalCommercialRate
            explanation = "This charge is significantly above normal rates (\(formatPercent(percentAboveMedicare))% above Medicare). Strongly recommend disputing."
        }
        
        return PriceEvaluation(
            status: status,
            chargedAmount: chargedAmount,
            medicareRate: range.medicareRate,
            typicalRate: range.typicalCommercialRate,
            overchargeEstimate: overcharge,
            percentAboveMedicare: percentAboveMedicare,
            explanation: explanation
        )
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
    
    private func formatPercent(_ value: Decimal?) -> String {
        guard let value else { return "N/A" }
        return "\(NSDecimalNumber(decimal: value).intValue)"
    }
}
// MARK: - Types
struct PriceRange {
    let medicareRate: Decimal
    let typicalCommercialRate: Decimal
    let highOutlierThreshold: Decimal
    let description: String
    let workRVU: Decimal?
    let totalRVU: Decimal?
}
enum PriceStatus: String {
    case fair       // At or near Medicare rate
    case typical    // Within normal commercial range
    case elevated   // Above typical, possible overcharge
    case outlier    // Significantly above normal
    case unknown    // No data to compare
    
    var label: String {
        switch self {
        case .fair:     return "Fair Price"
        case .typical:  return "Typical Range"
        case .elevated: return "Above Average"
        case .outlier:  return "Price Outlier"
        case .unknown:  return "Unknown"
        }
    }
}
struct PriceEvaluation {
    let status: PriceStatus
    let chargedAmount: Decimal
    let medicareRate: Decimal?
    let typicalRate: Decimal?
    let overchargeEstimate: Decimal?
    let percentAboveMedicare: Decimal?
    let explanation: String
}

