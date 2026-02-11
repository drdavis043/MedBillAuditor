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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Bills Yet")
                .font(.title3.bold())
            Text("Scan a medical bill to get started")
                .foregroundStyle(.secondary)
        }
    }
    private var billList: some View {
        List {
            ForEach(bills) { bill in
                NavigationLink(destination: BillDetailView(bill: bill)) {
                    BillRow(bill: bill)
                }
            }
            .onDelete(perform: deleteBills)
        }
    }
    private func deleteBills(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bills[index])
        }
    }
}
// MARK: - Bill Row
struct BillRow: View {
    let bill: MedicalBill
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.providerName)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(bill.serviceDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(bill.lineItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(bill.totalCharged))
                    .font(.subheadline.bold())
                Text(bill.status.label)
                    .font(.caption2)
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
        switch bill.status {
        case .captured, .parsing:  return .gray
        case .parsed:              return .blue
        case .auditing:            return .orange
        case .audited:             return .purple
        case .disputed:            return .red
        case .resolved:            return .green
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
            Section("Bill Info") {
                LabeledContent("Provider", value: bill.providerName)
                LabeledContent("Facility", value: bill.facilityType.rawValue.capitalized)
                LabeledContent("Status", value: bill.status.label)
                if let date = bill.serviceDate {
                    LabeledContent("Date of Service", value: date.formatted(date: .long, time: .omitted))
                }
                LabeledContent("Total Charged", value: formatCurrency(bill.totalCharged))
            }
            Section("Line Items (\(bill.lineItems.count))") {
                ForEach(bill.lineItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let code = item.cptCode ?? item.hcpcsCode {
                                Text(code)
                                    .font(.caption.monospaced().bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()
                            Text(formatCurrency(item.chargedAmount))
                                .font(.subheadline.bold())
                        }
                        Text(item.itemDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let medicare = item.medicareRate {
                            Text("Medicare: \(formatCurrency(medicare))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                NavigationLink("Run Audit", destination: AuditResultView(bill: bill))
            }
            if let result = bill.auditResult {
                Section("Audit Summary") {
                    LabeledContent("Risk Score", value: "\(result.overallRiskScore)/100")
                    LabeledContent("Issues Found", value: "\(result.flags.count)")
                    LabeledContent("Potential Savings", value: formatCurrency(result.totalEstimatedOvercharge))
                }
            }
        }
        .navigationTitle(bill.providerName)
        .navigationBarTitleDisplayMode(.inline)
    }
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
