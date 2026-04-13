//
//  MedicareFeeLoader.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation

/// Loads Medicare pricing data from medicare_pricing.json.
/// Data is derived from CY 2026 RVU files using the $33.40 conversion factor.
struct MedicareFeeLoader {

    struct MedicareCode: Decodable {
        let code: String
        let status: String
        let workRvu: Double
        let totalRvu: Double
        let nonFacilityPrice: Double
        let facilityPrice: Double
        let globalPeriod: String
    }

    static func load() -> [String: MedicareCode] {
        guard let url = Bundle.main.url(forResource: "medicare_pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let codes = try? JSONDecoder().decode([MedicareCode].self, from: data) else {
            return [:]
        }

        var lookup: [String: MedicareCode] = [:]
        lookup.reserveCapacity(codes.count)
        for code in codes {
            lookup[code.code] = code
        }
        return lookup
    }
}
