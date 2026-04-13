//
//  PricingService.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation

/// Provides Medicare fair-price lookups for CPT/HCPCS codes.
/// Uses CY 2026 national average rates calculated from RVU data.
struct PricingService {

    private let codes: [String: MedicareFeeLoader.MedicareCode]

    init() {
        self.codes = MedicareFeeLoader.load()
    }

    /// Look up the Medicare national average price for a code.
    /// Uses non-facility price by default (physician office setting).
    /// Pass `facility: true` for hospital/facility pricing.
    func price(for code: String, facility: Bool = false) -> Decimal? {
        guard let entry = codes[code] else { return nil }
        let amount = facility ? entry.facilityPrice : entry.nonFacilityPrice
        guard amount > 0 else { return nil }
        return Decimal(amount)
    }

    /// Returns both facility and non-facility prices if available.
    func prices(for code: String) -> (nonFacility: Decimal?, facility: Decimal?) {
        guard let entry = codes[code] else { return (nil, nil) }
        let nf: Decimal? = entry.nonFacilityPrice > 0 ? Decimal(entry.nonFacilityPrice) : nil
        let f: Decimal? = entry.facilityPrice > 0 ? Decimal(entry.facilityPrice) : nil
        return (nf, f)
    }

    /// Get the total RVU for a code.
    func totalRvu(for code: String) -> Double? {
        guard let entry = codes[code], entry.totalRvu > 0 else { return nil }
        return entry.totalRvu
    }

    /// Get the status indicator for a code.
    func status(for code: String) -> String? {
        codes[code]?.status
    }

    /// Get the global period for a code.
    func globalPeriod(for code: String) -> String? {
        codes[code]?.globalPeriod
    }

    /// Check if a code exists in the database.
    func hasCode(_ code: String) -> Bool {
        codes[code] != nil
    }

    /// Number of codes in the database.
    var codeCount: Int { codes.count }
}
