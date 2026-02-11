//
//  AuditEngine.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import Foundation
import SwiftData
/// Orchestrates the full audit pipeline:
/// Takes a parsed MedicalBill, runs all checkers concurrently,
/// and produces an AuditResult with prioritized flags.
struct AuditEngine {
    private let pricingService = PricingService()
    /// Runs the complete audit on a bill and returns the result.
    func audit(_ bill: MedicalBill) async -> AuditResult {
        let lineItems = bill.lineItems
        let facilityType = bill.facilityType
        // Run all checkers concurrently
        async let priceFlags = PriceChecker(pricingService: pricingService)
            .check(lineItems, facilityType: facilityType)
        async let duplicateFlags = DuplicateChecker()
            .check(lineItems)
        async let unbundlingFlags = UnbundlingChecker()
            .check(lineItems)
        async let upcodingFlags = UpcodingChecker()
            .check(lineItems)
        async let balanceBillingFlags = BalanceBillingChecker()
            .check(lineItems)
        // Collect all flags
        let allFlags = await priceFlags + duplicateFlags + unbundlingFlags
            + upcodingFlags + balanceBillingFlags
        // Calculate metrics
        let totalOvercharge = allFlags
            .compactMap { $0.estimatedImpact }
            .reduce(Decimal(0), +)
        let criticalCount = allFlags.filter { $0.severity == .critical }.count
        let warningCount = allFlags.filter { $0.severity == .warning }.count
        // Calculate risk score (0-100)
        let riskScore = calculateRiskScore(
            flags: allFlags,
            totalCharged: bill.totalCharged,
            totalOvercharge: totalOvercharge
        )
        // Generate summary
        let summary = generateSummary(
            flags: allFlags,
            totalOvercharge: totalOvercharge,
            riskScore: riskScore
        )
        // Build result
        let result = AuditResult()
        result.overallRiskScore = riskScore
        result.totalEstimatedOvercharge = totalOvercharge
        result.summary = summary
        result.recommendsDispute = criticalCount > 0 || totalOvercharge > 50
        result.flags = allFlags
        return result
    }
    private func calculateRiskScore(
        flags: [AuditFlag],
        totalCharged: Decimal,
        totalOvercharge: Decimal
    ) -> Int {
        var score = 0
        // Points for flag severity
        for flag in flags {
            switch flag.severity {
            case .critical: score += 25
            case .warning: score += 10
            case .info: score += 3
            }
        }
        // Points for overcharge ratio
        if totalCharged > 0 {
            let ratio = NSDecimalNumber(decimal: totalOvercharge / totalCharged).doubleValue
            score += Int(ratio * 30)
        }
        return min(score, 100)
    }
    private func generateSummary(
        flags: [AuditFlag],
        totalOvercharge: Decimal,
        riskScore: Int
    ) -> String {
        if flags.isEmpty {
            return "No issues found. This bill appears to be within normal pricing ranges."
        }
        let criticalCount = flags.filter { $0.severity == .critical }.count
        let warningCount = flags.filter { $0.severity == .warning }.count
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let overchargeStr = formatter.string(from: totalOvercharge as NSDecimalNumber) ?? "$0"
        var parts: [String] = []
        parts.append("Found \(flags.count) potential issue(s).")
        if criticalCount > 0 {
            parts.append("\(criticalCount) critical issue(s) require immediate attention.")
        }
        if totalOvercharge > 0 {
            parts.append("Estimated potential overcharge: \(overchargeStr).")
        }
        if riskScore >= 50 {
            parts.append("We strongly recommend disputing this bill.")
        } else if riskScore >= 25 {
            parts.append("Consider reviewing flagged items with your provider.")
        }
        return parts.joined(separator: " ")
    }
}
