//
//  ManualEntryView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 4/13/26.
//

import SwiftUI
import SwiftData

/// Manual bill entry form — the "last resort" when OCR/scanning fails.
/// Users enter provider info and line items by hand.
struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var providerName = ""
    @State private var facilityType: FacilityType = .unknown
    @State private var serviceDate = Date()
    @State private var lineItems: [ManualLineItem] = []
    @State private var showAddItem = false
    @State private var savedBill: MedicalBill?
    @State private var navigateToAudit = false

    private let descriptions = CodeDescriptionDatabase.shared
    private let pricingService = PricingService()

    var body: some View {
        Form {
            billInfoSection
            lineItemsSection
            addItemSection
            saveSection
        }
        .navigationTitle("Enter Bill Manually")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToAudit) {
            if let bill = savedBill {
                AuditResultView(bill: bill)
            }
        }
    }

    // MARK: - Bill Info

    private var billInfoSection: some View {
        Section("Bill Information") {
            TextField("Provider / Hospital Name", text: $providerName)
                .textContentType(.organizationName)

            Picker("Facility Type", selection: $facilityType) {
                ForEach(FacilityType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)
        }
    }

    // MARK: - Line Items

    private var lineItemsSection: some View {
        Section("Line Items (\(lineItems.count))") {
            if lineItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No line items yet")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach($lineItems) { $item in
                    ManualLineItemRow(
                        item: $item,
                        descriptions: descriptions,
                        pricingService: pricingService,
                        facilityType: facilityType
                    )
                }
                .onDelete(perform: deleteItems)
            }
        }
    }

    private var addItemSection: some View {
        Section {
            Button {
                withAnimation {
                    lineItems.append(ManualLineItem())
                }
            } label: {
                Label("Add Line Item", systemImage: "plus.circle.fill")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.accent)
            }
        }
    }

    // MARK: - Save

    private var saveSection: some View {
        Section {
            Button {
                saveBill()
            } label: {
                HStack {
                    Spacer()
                    Label("Save & Audit", systemImage: "checkmark.shield")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .disabled(providerName.isEmpty || lineItems.isEmpty)
        }
    }

    // MARK: - Actions

    private func deleteItems(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
    }

    private func saveBill() {
        let total = lineItems.reduce(Decimal(0)) { $0 + $1.amount }

        let bill = MedicalBill(
            providerName: providerName,
            facilityType: facilityType,
            totalCharged: total,
            sourceType: .manual
        )
        bill.serviceDate = serviceDate
        bill.status = .parsed

        for item in lineItems {
            let lineItem = LineItem(
                itemDescription: item.description.isEmpty ? "Unknown Service" : item.description,
                chargedAmount: item.amount,
                quantity: item.quantity
            )

            // Assign code to the right field based on format
            let code = item.code.trimmingCharacters(in: .whitespaces).uppercased()
            if !code.isEmpty {
                if code.first?.isLetter == true {
                    lineItem.hcpcsCode = code
                } else {
                    lineItem.cptCode = code
                }

                // Look up Medicare pricing
                let evaluation = pricingService.evaluate(
                    chargedAmount: item.amount,
                    cptCode: code,
                    facilityType: facilityType
                )
                lineItem.medicareRate = evaluation.medicareRate
                lineItem.fairMarketPrice = evaluation.typicalRate
            }

            lineItem.dateOfService = serviceDate
            bill.lineItems.append(lineItem)
        }

        modelContext.insert(bill)
        savedBill = bill
        navigateToAudit = true
    }
}

// MARK: - Manual Line Item Model

struct ManualLineItem: Identifiable {
    let id = UUID()
    var code: String = ""
    var description: String = ""
    var amount: Decimal = 0
    var quantity: Int = 1
}

// MARK: - Line Item Row

struct ManualLineItemRow: View {
    @Binding var item: ManualLineItem
    let descriptions: CodeDescriptionDatabase
    let pricingService: PricingService
    let facilityType: FacilityType

    @State private var amountText: String = ""
    @State private var medicareRate: String?
    @FocusState private var focusedField: Field?

    enum Field { case code, description, amount, quantity }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Code + auto-fill
            HStack {
                TextField("CPT / HCPCS Code", text: $item.code)
                    .font(AppTheme.Typography.code)
                    .textCase(.uppercase)
                    .frame(width: 120)
                    .focused($focusedField, equals: .code)
                    .onChange(of: item.code) { _, newCode in
                        autoFillFromCode(newCode)
                    }

                if let rate = medicareRate {
                    Text("Medicare: \(rate)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.info)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.info.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            TextField("Description", text: $item.description)
                .font(AppTheme.Typography.body)
                .focused($focusedField, equals: .description)

            HStack {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .onChange(of: amountText) { _, newValue in
                            item.amount = Decimal(string: newValue) ?? 0
                        }
                }
                .frame(maxWidth: 140)

                Spacer()

                HStack(spacing: 4) {
                    Text("Qty:")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Stepper("\(item.quantity)", value: $item.quantity, in: 1...99)
                        .labelsHidden()
                    Text("\(item.quantity)")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .frame(width: 24)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if item.amount > 0 {
                amountText = "\(item.amount)"
            }
        }
    }

    private func autoFillFromCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 5 else {
            medicareRate = nil
            return
        }

        // Auto-fill description if empty
        if item.description.isEmpty,
           let desc = descriptions.description(for: trimmed) {
            item.description = desc
        }

        // Show Medicare rate
        let evaluation = pricingService.evaluate(
            chargedAmount: 0,
            cptCode: trimmed,
            facilityType: facilityType
        )
        if let rate = evaluation.medicareRate {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            medicareRate = formatter.string(from: rate as NSDecimalNumber)
        } else {
            medicareRate = nil
        }
    }
}
