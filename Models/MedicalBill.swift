//
//  LineItem.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation
import SwiftData

@Model
final class MedicalBill {
    var id: UUID
    var capturedDate: Date
    var providerName: String
    var facilityType: FacilityType
    var serviceDate: Date?
    var totalCharged: Decimal
    var totalAdjusted: Decimal?
    var totalPaid: Decimal?
    var patientResponsibility: Decimal?
    var status: BillStatus
    var sourceType: BillSource
    
    // Raw data
    var rawOCRText: String?
    @Attribute(.externalStorage)
    var originalImage: Data?
    
    // Relationships
    @Relationship(deleteRule: .cascade)
    var lineItems: [LineItem] = []
    @Relationship(deleteRule: .cascade)
    var auditResult: AuditResult?
    @Relationship(deleteRule: .cascade)
    var disputeLetter: DisputeLetter?
    
    init(
        providerName: String = "",
        facilityType: FacilityType = .unknown,
        totalCharged: Decimal = 0,
        sourceType: BillSource = .camera
    ) {
        self.id = UUID()
        self.capturedDate = Date()
        self.providerName = providerName
        self.facilityType = facilityType
        self.totalCharged = totalCharged
        self.status = .captured
        self.sourceType = sourceType
    }
}
