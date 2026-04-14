//
//  MedicareFeeLoader.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
/// Loads the bundled Medicare Physician Fee Schedule data
/// and provides fast lookups by CPT code.
///
/// Data source: CMS CY 2026 RVU files, processed via process_cms_data.py.
/// Pricing calculated using the $33.40 conversion factor.
final class MedicareFeeLoader {

    /// Singleton for app-wide access
    static let shared = MedicareFeeLoader()

    /// Indexed by CPT code for O(1) lookup
    private var feeSchedule: [String: MedicareFeeEntry] = [:]

    /// Whether data has been loaded
    private(set) var isLoaded = false

    private init() {}

    /// Loads the fee schedule from the bundled JSON file.
    /// Call this once at app startup (e.g., in the App init).
    func load() {
        guard !isLoaded else { return }

        // Try the new comprehensive pricing file first, fall back to legacy
        let url = Bundle.main.url(forResource: "medicare_pricing", withExtension: "json")
            ?? Bundle.main.url(forResource: "medicare_fee_schedule", withExtension: "json")

        guard let url else {
            print("⚠️ Medicare pricing JSON not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)

            // Try new format first (from process_cms_data.py)
            if let entries = try? JSONDecoder().decode([NewFormatEntry].self, from: data) {
                for entry in entries {
                    let feeEntry = MedicareFeeEntry(
                        cptCode: entry.code,
                        description: CodeDescriptionDatabase.shared.description(for: entry.code) ?? "",
                        facilityRate: entry.facilityPrice > 0 ? Decimal(entry.facilityPrice) : nil,
                        nonFacilityRate: entry.nonFacilityPrice > 0 ? Decimal(entry.nonFacilityPrice) : nil,
                        workRVU: Decimal(entry.workRvu),
                        practiceExpenseRVU: nil,
                        malpracticeRVU: nil,
                        totalRVU: Decimal(entry.totalRvu),
                        globalDays: entry.globalPeriod,
                        statusCode: entry.status
                    )
                    feeSchedule[entry.code] = feeEntry
                }
            } else {
                // Fall back to legacy format
                let entries = try JSONDecoder().decode([MedicareFeeEntry].self, from: data)
                for entry in entries {
                    feeSchedule[entry.cptCode] = entry
                }
            }

            isLoaded = true
            print("✅ Loaded \(feeSchedule.count) Medicare fee entries")
        } catch {
            print("❌ Failed to load fee schedule: \(error)")
        }
    }

    /// Looks up the Medicare rate for a given CPT code.
    func lookup(_ cptCode: String) -> MedicareFeeEntry? {
        feeSchedule[cptCode]
    }

    /// Returns the national non-facility (office) price for a CPT code.
    func nationalPrice(for cptCode: String) -> Decimal? {
        feeSchedule[cptCode]?.nonFacilityRate
    }

    /// Returns the facility (hospital) price for a CPT code.
    func facilityPrice(for cptCode: String) -> Decimal? {
        feeSchedule[cptCode]?.facilityRate
    }

    /// Checks if a CPT code exists in the fee schedule.
    func isKnownCode(_ cptCode: String) -> Bool {
        feeSchedule[cptCode] != nil
    }

    /// Returns all loaded CPT codes (useful for validation).
    var allCodes: [String] {
        Array(feeSchedule.keys)
    }
}

// MARK: - New Format (from process_cms_data.py)

private struct NewFormatEntry: Decodable {
    let code: String
    let status: String
    let workRvu: Double
    let totalRvu: Double
    let nonFacilityPrice: Double
    let facilityPrice: Double
    let globalPeriod: String
}

// MARK: - Data Model

/// Represents a single entry in the Medicare fee schedule.
struct MedicareFeeEntry: Codable {
    let cptCode: String
    let description: String
    let facilityRate: Decimal?       // Hospital/ASC setting
    let nonFacilityRate: Decimal?    // Office/non-facility setting
    let workRVU: Decimal?            // Work relative value units
    let practiceExpenseRVU: Decimal? // Practice expense RVUs
    let malpracticeRVU: Decimal?     // Malpractice RVUs
    let totalRVU: Decimal?           // Total RVUs
    let globalDays: String?          // Global surgery days (000, 010, 090, etc.)
    let statusCode: String?          // A=Active, R=Restricted, etc.

    enum CodingKeys: String, CodingKey {
        case cptCode = "cpt_code"
        case description
        case facilityRate = "facility_rate"
        case nonFacilityRate = "non_facility_rate"
        case workRVU = "work_rvu"
        case practiceExpenseRVU = "pe_rvu"
        case malpracticeRVU = "mp_rvu"
        case totalRVU = "total_rvu"
        case globalDays = "global_days"
        case statusCode = "status_code"
    }
}
