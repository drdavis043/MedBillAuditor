//
//  AuditEngine.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation

/// Orchestrates all audit checks against a parsed bill.
/// Each checker is independent and produces its own flags.
@Observable
final class AuditEngine {
    private let priceChecker: PriceChecker
    private let duplicateChecker: DuplicateChecker
    private let unbundlingChecker: UnbundlingChecker
    private let upcodingChecker: UpcodingChecker
    private let balanceBillingChecker: BalanceBillingChecker
    
    init(pricingService: PricingService) {
        self.priceChecker = PriceChecker(pricingService: pricingService)
        self.duplicateChecker = DuplicateChecker()
        self.unbundlingChecker = UnbundlingChecker()
        self.upcodingChecker = UpcodingChecker()
        self.balanceBillingChecker = BalanceBillingChecker()
    }
    
    func audit(bill: MedicalBill) async -> AuditResult {
        let result = AuditResult()
        
        // Run all checkers concurrently
        async let priceFlags = priceChecker.check(bill.lineItems)
        async let dupeFlags = duplicateChecker.check(bill.lineItems)
        async let unbundleFlags = unbundlingChecker.check(bill.lineItems)
        async let upcodeFlags = upcodingChecker.check(bill.lineItems)
        async let balanceFlags = balanceBillingChecker.check(bill.lineItems)
        
        let allFlags = await priceFlags + dupeFlags + unbundleFlags
                     + upcodeFlags + balanceFlags
        
        result.flags = allFlags
        result.totalEstimatedOvercharge = allFlags
            .compactMap(\.estimatedImpact)
            .reduce(0, +)
        result.overallRiskScore = calculateRiskScore(flags: allFlags)
        result.recommendsDispute = result.totalEstimatedOvercharge > 50
        result.summary = generateSummary(result: result)
        
        return result
    }
    
    private func calculateRiskScore(flags: [AuditFlag]) -> Int {
        // Weighted scoring based on severity and count
        let score = flags.reduce(0) { total, flag in
            switch flag.severity {
            case .critical: return total + 30
            case .warning:  return total + 15
            case .info:     return total + 5
            }
        }
        return min(score, 100)
    }
    
    private func generateSummary(result: AuditResult) -> String {
        // Placeholder — will use LLM for natural language
        let count = result.flags.count
        if count == 0 { return "No issues found." }
        return "Found \(count) potential issue(s)."
    }
}
