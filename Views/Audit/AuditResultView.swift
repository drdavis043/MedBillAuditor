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
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Ready to Audit")
                .font(.title2.bold())
            Text("We'll check \(bill.lineItems.count) line items against Medicare rates and common billing errors.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                runAudit()
            } label: {
                Label("Start Audit", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 40)
    }
    // MARK: - Auditing
    private var auditingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your bill...")
                .font(.headline)
        }
        .padding(.vertical, 60)
    }
    // MARK: - Results
    @ViewBuilder
    private func resultContent(_ result: AuditResult) -> some View {
        // Score card
        scoreCard(result)
        // Summary
        if !result.summary.isEmpty {
            Text(result.summary)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        // Flags by severity
        let criticals = result.flags.filter { $0.severity == .critical }
        let warnings = result.flags.filter { $0.severity == .warning }
        let infos = result.flags.filter { $0.severity == .info }
        if !criticals.isEmpty {
            flagSection(title: "Critical Issues", flags: criticals, color: .red)
        }
        if !warnings.isEmpty {
            flagSection(title: "Warnings", flags: warnings, color: .orange)
        }
        if !infos.isEmpty {
            flagSection(title: "Information", flags: infos, color: .blue)
        }
        if result.flags.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("No Issues Found")
                    .font(.title3.bold())
                Text("This bill appears to be within normal pricing ranges.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
        // Dispute button
        if result.recommendsDispute {
            Button {
                showDisputeSheet = true
            } label: {
                Label("Generate Dispute Letter", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }
    private func scoreCard(_ result: AuditResult) -> some View {
        HStack(spacing: 20) {
            // Risk score
            ZStack {
                Circle()
                    .stroke(scoreColor(result.overallRiskScore).opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(result.overallRiskScore) / 100)
                    .stroke(scoreColor(result.overallRiskScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(result.overallRiskScore)")
                        .font(.title.bold())
                    Text("Risk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Potential Savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(formatCurrency(result.totalEstimatedOvercharge))
                    .font(.title2.bold())
                    .foregroundStyle(result.totalEstimatedOvercharge > 0 ? .red : .primary)
                HStack(spacing: 12) {
                    Label("\(result.flags.filter { $0.severity == .critical }.count)", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Label("\(result.flags.filter { $0.severity == .warning }.count)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Label("\(result.flags.filter { $0.severity == .info }.count)", systemImage: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
    private func flagSection(title: String, flags: [AuditFlag], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            ForEach(flags, id: \.id) { flag in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(flag.title)
                            .font(.subheadline.bold())
                        Spacer()
                        if let impact = flag.estimatedImpact {
                            Text(formatCurrency(impact))
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    Text(flag.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(flag.recommendation)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 2)
                }
                .padding()
                .background(color.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
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
        if score >= 50 { return .red }
        if score >= 25 { return .orange }
        return .green
    }
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
