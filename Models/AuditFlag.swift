//
//  AuditFlag.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation
import SwiftData

@Model
final class AuditFlag {
    var id: UUID
    var flagType: FlagType
    var severity: FlagSeverity
    var title: String
    var explanation: String
    var estimatedImpact: Decimal?
    var recommendation: String
    var affectedLineItemID: UUID?
    
    var auditResult: AuditResult? = nil
    
    init(
        flagType: FlagType,
        severity: FlagSeverity,
        title: String,
        explanation: String,
        recommendation: String
    ) {
        self.id = UUID()
        self.flagType = flagType
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.recommendation = recommendation
    }
}
