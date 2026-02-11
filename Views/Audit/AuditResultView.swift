//
//  AuditResultView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/9/26.
//
import SwiftUI
import SwiftData
struct AuditResultView: View {
    let bill: MedicalBill
    @State private var auditResult: AuditResult?
    @State private var isAuditing = false
    @State private var showDisputeSheet = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isAuditing {
                    auditingView
                } else if let result = auditResult {
                    resultContent(result)
                } else {
                    startAuditView
                }
            }
            .padding()
        }
        .navigationTitle("Audit Report")
        .onAppear {
            if bill.auditResult != nil {
                auditResult = bill.auditResult
            }
        }
        .sheet(isPresented: $showDisputeSheet) {
            if let result = auditResult {
                DisputeLetterView(bill: bill, auditResult: result)
            }
        }
    }
    // MARK: - Start Audit
    private var startAuditView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
            }
            Text("Ready to Audit")
                .font(AppTheme.Typography.title)
            Text("We'll check \(bill.lineItems.count) line items against Medicare rates and common billing errors.")
                .font(AppTheme.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button {
                runAudit()
            } label: {
                Label("Start Audit", systemImage: "play.fill")
                    .font(AppTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.top, 8)
            Spacer()
        }
    }
    // MARK: - Auditing
    private var auditingView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your bill...")
                .font(AppTheme.Typography.headline)
            Text("Checking prices, duplicates, unbundling, upcoding, and balance billing")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
    // MARK: - Results
    @ViewBuilder
    private func resultContent(_ result: AuditResult) -> some View {
        scoreCard(result)
        if !result.summary.isEmpty {
            Text(result.summary)
                .font(AppTheme.Typography.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        }
        let criticals = result.flags.filter { $0.severity == .critical }
        let warnings = result.flags.filter { $0.severity == .warning }
        let infos = result.flags.filter { $0.severity == .info }
        if !criticals.isEmpty {
            flagSection(title: "Critical Issues", flags: criticals, color: AppTheme.Colors.danger)
        }
        if !warnings.isEmpty {
            flagSection(title: "Warnings", flags: warnings, color: AppTheme.Colors.warning)
        }
        if !infos.isEmpty {
            flagSection(title: "Information", flags: infos, color: AppTheme.Colors.info)
        }
        if result.flags.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.Colors.success)
                Text("No Issues Found")
                    .font(AppTheme.Typography.title)
                Text("This bill appears to be within normal pricing ranges.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
        if result.recommendsDispute {
            Button {
                showDisputeSheet = true
            } label: {
                Label("Generate Dispute Letter", systemImage: "envelope.fill")
                    .font(AppTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.danger)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }
    private func scoreCard(_ result: AuditResult) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(scoreColor(result.overallRiskScore).opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(result.overallRiskScore) / 100)
                    .stroke(scoreColor(result.overallRiskScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(result.overallRiskScore)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Risk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 8) {
                Text("Potential Savings")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(result.totalEstimatedOvercharge))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(result.totalEstimatedOvercharge > 0 ? AppTheme.Colors.danger : .primary)
                HStack(spacing: 12) {
                    Label("\(result.flags.filter { $0.severity == .critical }.count)", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.danger)
                        .font(.caption)
                    Label("\(result.flags.filter { $0.severity == .warning }.count)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.Colors.warning)
                        .font(.caption)
                    Label("\(result.flags.filter { $0.severity == .info }.count)", systemImage: "info.circle.fill")
                        .foregroundStyle(AppTheme.Colors.info)
                        .font(.caption)
                }
            }
        }
        .cardStyle()
    }
    private func flagSection(title: String, flags: [AuditFlag], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(color)
            ForEach(flags, id: \.id) { flag in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(flag.title)
                            .font(.subheadline.bold())
                        Spacer()
                        if let impact = flag.estimatedImpact {
                            Text(formatCurrency(impact))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    }
                    Text(flag.explanation)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(flag.recommendation)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.info)
                        .padding(.top, 2)
                }
                .padding()
                .background(color.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    // MARK: - Helpers
    private func runAudit() {
        isAuditing = true
        Task {
            let engine = AuditEngine()
            let result = await engine.audit(bill)
            await MainActor.run {
                auditResult = result
                bill.auditResult = result
                bill.status = .audited
                isAuditing = false
            }
        }
    }
    private func scoreColor(_ score: Int) -> Color {
        if score >= 50 { return AppTheme.Colors.danger }
        if score >= 25 { return AppTheme.Colors.warning }
        return AppTheme.Colors.success
    }
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
