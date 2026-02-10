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
/// Data source: CMS National Payment Amount File
/// https://www.cms.gov/medicare/payment/fee-schedules/physician/national-payment-amount-file
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
        
        guard let url = Bundle.main.url(
            forResource: "medicare_fee_schedule",
            withExtension: "json"
        ) else {
            print("⚠️ medicare_fee_schedule.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([MedicareFeeEntry].self, from: data)
            
            // Index by CPT code
            for entry in entries {
                feeSchedule[entry.cptCode] = entry
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
// MARK: - Data Model
/// Represents a single entry in the Medicare fee schedule.
/// This matches the structure of the processed JSON file
/// you'll create from the CMS national payment amount data.
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

