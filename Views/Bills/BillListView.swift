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
    @Bindable var bill: MedicalBill
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editingCode = ""
    @State private var editingDescription = ""
    @State private var editingAmount = ""
    @State private var editingQuantity = 1
    @State private var showAddItem = false

    private let descriptions = CodeDescriptionDatabase.shared
    private let pricingService = PricingService()

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
                                if let desc = descriptions.description(for: code) {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(formatCurrency(item.chargedAmount))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                        Text(item.itemDescription)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                        if let medicare = item.medicareRate {
                            let isFacility = [.hospital, .emergency, .ambulatory].contains(bill.facilityType)
                            HStack(spacing: 4) {
                                Image(systemName: "cross.circle")
                                    .font(.caption2)
                                Text("Medicare (\(isFacility ? "facility" : "office")): \(formatCurrency(medicare))")
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppTheme.Colors.warning)
                        }
                        if item.quantity > 1 {
                            Text("Qty: \(item.quantity)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: isEditing ? deleteLineItems : nil)

                if isEditing {
                    addLineItemRow
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        finishEditing()
                    }
                    withAnimation { isEditing.toggle() }
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    }

    // MARK: - Add Line Item (inline)

    private var addLineItemRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Line Item")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.accent)

            TextField("CPT / HCPCS Code", text: $editingCode)
                .font(AppTheme.Typography.code)
                .textCase(.uppercase)
                .onChange(of: editingCode) { _, newCode in
                    let trimmed = newCode.trimmingCharacters(in: .whitespaces).uppercased()
                    if trimmed.count >= 5, editingDescription.isEmpty,
                       let desc = descriptions.description(for: trimmed) {
                        editingDescription = desc
                    }
                }

            TextField("Description", text: $editingDescription)

            HStack {
                HStack {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: $editingAmount)
                        .keyboardType(.decimalPad)
                }
                Spacer()
                Stepper("Qty: \(editingQuantity)", value: $editingQuantity, in: 1...99)
            }

            Button {
                addNewLineItem()
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .font(AppTheme.Typography.headline)
            }
            .disabled(editingAmount.isEmpty)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func deleteLineItems(at offsets: IndexSet) {
        for index in offsets {
            let item = bill.lineItems[index]
            modelContext.delete(item)
        }
        bill.lineItems.remove(atOffsets: offsets)
        invalidateAudit()
    }

    private func addNewLineItem() {
        let item = LineItem(
            itemDescription: editingDescription.isEmpty ? "Unknown Service" : editingDescription,
            chargedAmount: Decimal(string: editingAmount) ?? 0,
            quantity: editingQuantity
        )
        let code = editingCode.trimmingCharacters(in: .whitespaces).uppercased()
        if !code.isEmpty {
            if code.first?.isLetter == true {
                item.hcpcsCode = code
            } else {
                item.cptCode = code
            }
            let evaluation = pricingService.evaluate(
                chargedAmount: item.chargedAmount,
                cptCode: code,
                facilityType: bill.facilityType
            )
            item.medicareRate = evaluation.medicareRate
            item.fairMarketPrice = evaluation.typicalRate
        }
        item.dateOfService = bill.serviceDate
        bill.lineItems.append(item)

        // Reset fields
        editingCode = ""
        editingDescription = ""
        editingAmount = ""
        editingQuantity = 1

        invalidateAudit()
    }

    private func finishEditing() {
        bill.totalCharged = bill.lineItems.reduce(Decimal(0)) { $0 + $1.chargedAmount }
    }

    private func invalidateAudit() {
        if bill.auditResult != nil {
            if let result = bill.auditResult {
                modelContext.delete(result)
            }
            bill.auditResult = nil
            bill.status = .parsed
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
