//
//  DisputeLetter.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
import SwiftData

@Model
final class DisputeLetter {
    var id: UUID
    var createdDate: Date
    var recipientType: RecipientType
    var recipientName: String
    var recipientAddress: String
    var subject: String
    var body: String
    var status: LetterStatus
    
    @Attribute(.externalStorage)
    var pdfData: Data?
    
    var bill: MedicalBill? = nil
    
    init(
        recipientType: RecipientType = .provider,
        recipientName: String = "",
        subject: String = "",
        body: String = ""
    ) {
        self.id = UUID()
        self.createdDate = Date()
        self.recipientType = recipientType
        self.recipientName = recipientName
        self.recipientAddress = ""
        self.subject = subject
        self.body = body
        self.status = .draft
    }
}

enum RecipientType: String, Codable {
    case provider
    case insurer
    case billingDepartment
}

enum LetterStatus: String, Codable {
    case draft
    case sent
    case responded
}
