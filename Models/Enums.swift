//
//  Enums.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

enum BillStatus: String, Codable, CaseIterable {
    case captured
    case parsing
    case parsed
    case auditing
    case audited
    case disputed
    case resolved
    
    var label: String {
        switch self {
        case .captured:  return "Captured"
        case .parsing:   return "Processing"
        case .parsed:    return "Ready to Audit"
        case .auditing:  return "Auditing"
        case .audited:   return "Audit Complete"
        case .disputed:  return "Disputed"
        case .resolved:  return "Resolved"
        }
    }
}

enum BillSource: String, Codable {
    case camera, pdfImport, manual
}

enum FacilityType: String, Codable, CaseIterable {
    case hospital, physicianOffice, urgentCare
    case laboratory, imagingCenter, ambulatory
    case emergency, unknown
}

enum FlagType: String, Codable {
    case duplicateCharge
    case unbundling
    case upcoding
    case balanceBilling
    case priceOutlier
    case missingModifier
    case incorrectQuantity
    case notCovered
    case other
}

enum FlagSeverity: String, Codable, CaseIterable {
    case critical
    case warning
    case info
    
    var color: String {
        switch self {
        case .critical: return "red"
        case .warning:  return "orange"
        case .info:     return "blue"
        }
    }
}
