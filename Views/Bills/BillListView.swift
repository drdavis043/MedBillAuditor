//
//  BillListView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
import SwiftData
struct BillListView: View {
    @Query(sort: \MedicalBill.capturedDate, order: .reverse) private var bills: [MedicalBill]
    @Environment(\.modelContext) private var modelContext
    init() {}
    var body: some View {
        NavigationStack {
            Group {
                if bills.isEmpty {
                    emptyState
                } else {
                    billList
                }
            }
            .navigationTitle("Bills")
        }
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
            Text("No Bills Yet")
                .font(AppTheme.Typography.title)
            Text("Scan a medical bill to get started.\nTap the Scan tab below.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xl)
    }
    private var billList: some View {
        List {
            // Summary card
            if bills.count > 1 {
                Section {
                    HStack(spacing: AppTheme.Spacing.md) {
                        SummaryPill(
                            value: "\(bills.count)",
                            label: "Bills",
                            icon: "doc.text",
                            color: AppTheme.Colors.info
                        )
                        SummaryPill(
                            value: formatCurrency(bills.reduce(Decimal(0)) { $0 + $1.totalCharged }),
                            label: "Total",
                            icon: "dollarsign.circle",
                            color: AppTheme.Colors.warning
                        )
                        let auditedCount = bills.filter { $0.auditResult != nil }.count
                        SummaryPill(
                            value: "\(auditedCount)",
                            label: "Audited",
                            icon: "checkmark.shield",
                            color: AppTheme.Colors.success
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
            Section {
                ForEach(bills) { bill in
                    NavigationLink(destination: BillDetailView(bill: bill)) {
                        BillRow(bill: bill)
                    }
                }
                .onDelete(perform: deleteBills)
            }
        }
    }
    private func deleteBills(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bills[index])
        }
    }
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
// MARK: - Summary Pill
struct SummaryPill: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }
}
// MARK: - Bill Row
struct BillRow: View {
    let bill: MedicalBill
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.providerName)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = bill.serviceDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Text("·")
                    Text("\(bill.lineItems.count) items")
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(bill.totalCharged))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text(bill.status.label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
    private var statusColor: Color {
        AppTheme.Colors.status(bill.status)
    }
    private var statusIcon: String {
        switch bill.status {
        case .captured, .parsing: return "doc.text"
        case .parsed: return "checkmark.circle"
        case .auditing: return "magnifyingglass"
        case .audited: return "exclamationmark.shield"
        case .disputed: return "envelope"
        case .resolved: return "checkmark.seal"
        }
    }
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
// MARK: - Bill Detail View
struct BillDetailView: View {
    let bill: MedicalBill
    var body: some View {
        List {
            // Status banner
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bill.status.label)
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.status(bill.status))
                        if let date = bill.serviceDate {
                            Text("Service date: \(date.formatted(date: .long, time: .omitted))")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(formatCurrency(bill.totalCharged))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }
            }
            Section("Provider") {
                LabeledContent("Name", value: bill.providerName)
                LabeledContent("Facility", value: bill.facilityType.rawValue.capitalized)
            }
            Section("Line Items (\(bill.lineItems.count))") {
                ForEach(bill.lineItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let code = item.cptCode ?? item.hcpcsCode {
                                Text(code)
                                    .badge(color: .blue)
                            }
                            Spacer()
                            Text(formatCurrency(item.chargedAmount))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                        Text(item.itemDescription)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                        if let medicare = item.medicareRate {
                            HStack(spacing: 4) {
                                Image(systemName: "cross.circle")
                                    .font(.caption2)
                                Text("Medicare: \(formatCurrency(medicare))")
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppTheme.Colors.warning)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            // Audit section
            Section {
                NavigationLink {
                    AuditResultView(bill: bill)
                } label: {
                    HStack {
                        Image(systemName: bill.auditResult != nil ? "checkmark.shield.fill" : "shield")
                            .foregroundStyle(bill.auditResult != nil ? AppTheme.Colors.success : .blue)
                        Text(bill.auditResult != nil ? "View Audit Results" : "Run Audit")
                            .font(AppTheme.Typography.headline)
                    }
                }
            }
            if let result = bill.auditResult {
                Section("Audit Summary") {
                    HStack {
                        Label("Risk Score", systemImage: "gauge.medium")
                        Spacer()
                        Text("\(result.overallRiskScore)/100")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(scoreColor(result.overallRiskScore))
                    }
                    HStack {
                        Label("Issues", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Text("\(result.flags.count)")
                            .font(.system(.body, design: .rounded, weight: .bold))
                    }
                    HStack {
                        Label("Potential Savings", systemImage: "dollarsign.arrow.circlepath")
                        Spacer()
                        Text(formatCurrency(result.totalEstimatedOvercharge))
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(result.totalEstimatedOvercharge > 0 ? AppTheme.Colors.danger : .primary)
                    }
                }
            }
        }
        .navigationTitle(bill.providerName)
        .navigationBarTitleDisplayMode(.inline)
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
