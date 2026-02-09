//
//  LineItem.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import Foundation
import SwiftData

@Model
final class LineItem {
    var id: UUID
    var cptCode: String?
    var hcpcsCode: String?
    var itemDescription: String
    var quantity: Int
    var chargedAmount: Decimal
    var allowedAmount: Decimal?
    var paidAmount: Decimal?
    var adjustmentAmount: Decimal?
    var dateOfService: Date?
    var revenueCode: String?
    var modifier: String?
    var placeOfService: String?
    
    // Audit reference
    var fairMarketPrice: Decimal?
    var medicareRate: Decimal?
    
    var bill: MedicalBill? = nil
    
    init(
        itemDescription: String = "",
        chargedAmount: Decimal = 0,
        quantity: Int = 1
    ) {
        self.id = UUID()
        self.itemDescription = itemDescription
        self.chargedAmount = chargedAmount
        self.quantity = quantity
    }
    
    var primaryCode: String? {
        cptCode ?? hcpcsCode
    }
    
    var potentialOvercharge: Decimal? {
        guard let fair = fairMarketPrice else { return nil }
        let diff = chargedAmount - fair
        return diff > 0 ? diff : nil
    }
}
