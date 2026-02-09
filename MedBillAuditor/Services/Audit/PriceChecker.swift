//
//  PriceChecker.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

struct PriceChecker {
    let pricingService: PricingService
    
    func check(_ lineItems: [LineItem]) async -> [AuditFlag] {
        return []
    }
}
