//
//  AuditResult.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
import SwiftData

@Model
final class AuditResult {
    var id: UUID
    var auditDate: Date
    var overallRiskScore: Int  // 0-100
    var totalEstimatedOvercharge: Decimal
    var summary: String
    var recommendsDispute: Bool
    
    @Relationship(deleteRule: .cascade)
    var flags: [AuditFlag] = []
    
    var bill: MedicalBill? = nil
    
    init() {
        self.id = UUID()
        self.auditDate = Date()
        self.overallRiskScore = 0
        self.totalEstimatedOvercharge = 0
        self.summary = ""
        self.recommendsDispute = false
    }
    
    var flagsBySeverity: [FlagSeverity: [AuditFlag]] {
        Dictionary(grouping: flags, by: \.severity)
    }
    
    var criticalCount: Int {
        flags.filter { $0.severity == .critical }.count
    }
}
