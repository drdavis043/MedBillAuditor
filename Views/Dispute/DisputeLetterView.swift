//
//  DisputeLetterView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/9/26.
//
import SwiftUI
import SwiftData
struct DisputeLetterView: View {
    let bill: MedicalBill
    let auditResult: AuditResult
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var recipientName = ""
    @State private var recipientAddress = ""
    @State private var patientName = ""
    @State private var accountNumber = ""
    @State private var additionalNotes = ""
    @State private var generatedLetter = ""
    @State private var showShareSheet = false
    @State private var pdfData: Data?
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Provider/Hospital Name", text: $recipientName)
                    TextField("Billing Address", text: $recipientAddress, axis: .vertical)
                        .lineLimit(3)
                }
                Section("Your Information") {
                    TextField("Patient Name", text: $patientName)
                    TextField("Account Number", text: $accountNumber)
                }
                Section("Additional Notes (optional)") {
                    TextField("Any additional context...", text: $additionalNotes, axis: .vertical)
                        .lineLimit(4)
                }
                if !generatedLetter.isEmpty {
                    Section("Preview") {
                        Text(generatedLetter)
                            .font(.system(.caption, design: .serif))
                    }
                }
                Section {
                    Button {
                        generateLetter()
                    } label: {
                        Label("Generate Letter", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    if !generatedLetter.isEmpty {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export as PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("Dispute Letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Pre-fill from bill data
                recipientName = bill.providerName
                patientName = ""  // User fills in
                accountNumber = ""
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = pdfData {
                    ShareSheet(items: [data])
                }
            }
        }
    }
    private func generateLetter() {
        let today = Date.now.formatted(date: .long, time: .omitted)
        let criticalFlags = auditResult.flags.filter { $0.severity == .critical }
        let warningFlags = auditResult.flags.filter { $0.severity == .warning }
        let allFlags = criticalFlags + warningFlags
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let overchargeStr = formatter.string(
            from: auditResult.totalEstimatedOvercharge as NSDecimalNumber
        ) ?? "$0"
        var letter = """
        \(today)
        \(recipientName)
        \(recipientAddress)
        Re: Billing Dispute
        Patient: \(patientName)
        Account: \(accountNumber)
        Date of Service: \(bill.serviceDate?.formatted(date: .long, time: .omitted) ?? "See attached")
        Dear Billing Department,
        I am writing to formally dispute charges on the above-referenced account. After careful review of my itemized bill, I have identified the following concerns totaling an estimated \(overchargeStr) in potential overcharges:
        """
        for (index, flag) in allFlags.enumerated() {
            let impactStr = flag.estimatedImpact != nil
                ? formatter.string(from: flag.estimatedImpact! as NSDecimalNumber) ?? ""
                : "TBD"
            letter += """
            \(index + 1). \(flag.title) (Estimated Impact: \(impactStr))
            \(flag.explanation)
            """
        }
        letter += """
        I respectfully request:
        1. A complete itemized statement with CPT/HCPCS codes for all charges
        2. An explanation of how each charge was determined
        3. Adjustment of the above charges to reflect fair market rates
        4. A written response within 30 days
        Under the Fair Debt Collection Practices Act, I request that no collection activity occur while this dispute is being investigated.
        """
        if !additionalNotes.isEmpty {
            letter += """
            Additional notes: \(additionalNotes)
            """
        }
        letter += """
        Please contact me to discuss these concerns. I look forward to resolving this matter.
        Sincerely,
        \(patientName)
        """
        generatedLetter = letter
        // Save to SwiftData
        let disputeLetter = DisputeLetter(
            recipientType: .provider,
            recipientName: recipientName,
            subject: "Billing Dispute - \(bill.providerName)",
            body: letter
        )
        disputeLetter.recipientAddress = recipientAddress
        disputeLetter.bill = bill
        bill.disputeLetter = disputeLetter
        bill.status = .disputed
        modelContext.insert(disputeLetter)
    }
    private func exportPDF() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Times New Roman", size: 12) ?? UIFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraphStyle,
            ]
            let textRect = CGRect(x: 72, y: 72, width: 468, height: 648)
            (generatedLetter as NSString).draw(in: textRect, withAttributes: attributes)
        }
        pdfData = data
        showShareSheet = true
    }
}
// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
