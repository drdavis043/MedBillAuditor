//
//  CaptureView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
import SwiftData
import PhotosUI

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var ocrResult: String?
    @State private var showPreview = false
    @State private var showResult = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Hero icon
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                
                VStack(spacing: 8) {
                    Text("Scan Your Bill")
                        .font(.title.bold())
                    Text("Take a photo or import a PDF to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Capture options
                VStack(spacing: 14) {
                    CaptureButton(
                        title: "Take Photo",
                        subtitle: "Use your camera to scan a bill",
                        icon: "camera.fill",
                        color: .blue
                    ) {
                        showCamera = true
                    }
                    
                    CaptureButton(
                        title: "Choose from Photos",
                        subtitle: "Select a bill photo from your library",
                        icon: "photo.on.rectangle",
                        color: .purple
                    ) {
                        showPhotoPicker = true
                    }
                    
                    CaptureButton(
                        title: "Import PDF",
                        subtitle: "Import a bill from Files",
                        icon: "doc.fill",
                        color: .orange
                    ) {
                        showDocumentPicker = true
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("New Bill")
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: .init(get: { nil }, set: { item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            capturedImage = image
                        }
                    }
                }),
                matching: .images
            )
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                if newImage != nil && !showPreview {
                    showPreview = true
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                if let image = capturedImage {
                    ImagePreviewView(
                        image: image,
                        onConfirm: { processedImage in
                            processBill(image: processedImage)
                        },
                        onRetake: {
                            capturedImage = nil
                            showPreview = false
                        }
                    )
                }
            }
            .overlay {
                if isProcessing {
                    ProcessingView(ocrResult: $ocrResult)
                }
            }
            .sheet(isPresented: $showResult) {
                NavigationStack {
                    List {
                        if let text = ocrResult {
                            let parser = BillParser()
                            let parsed = parser.parse(text)
                            
                            Section("Bill Info") {
                                LabeledContent("Provider", value: parsed.providerName ?? "Unknown")
                                LabeledContent("Facility", value: parsed.facilityType.rawValue)
                                LabeledContent("Total Charged", value: "$\(parsed.totalCharged)")
                            }
                            
                            Section("Line Items (\(parsed.lineItems.count))") {
                                ForEach(Array(parsed.lineItems.enumerated()), id: \.offset) { _, item in
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
                                            Text("$\(item.chargedAmount)")
                                                .font(.subheadline.bold())
                                        }
                                        Text(item.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            
                            Section("Raw OCR Text") {
                                Text(text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Parsed Bill")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                                Button("Copy OCR Text") {
                                    if let text = ocrResult {
                                        UIPasteboard.general.string = text
                                    }
                                }
                            }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showResult = false
                                ocrResult = nil
                                capturedImage = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Process Bill
    
    private func processBill(image: UIImage) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            do {
                // Step 1: Preprocess image
                let preprocessor = ImagePreprocessor()
                let cleaned = preprocessor.preprocess(image)
                
                // Step 2: OCR
                let ocrService = OCRService()
                let text = try await ocrService.extractText(from: cleaned)
                
                // Step 3: Parse structured data
                let parser = BillParser()
                let parsed = parser.parse(text)
                
                // Step 4: Price evaluation
                let pricingService = PricingService()
                
                await MainActor.run {
                    // Create the bill record
                    let bill = MedicalBill(
                        providerName: parsed.providerName ?? "Unknown Provider",
                        facilityType: parsed.facilityType,
                        totalCharged: parsed.totalCharged,
                        sourceType: .camera
                    )
                    bill.rawOCRText = text
                    bill.originalImage = image.jpegData(compressionQuality: 0.8)
                    bill.serviceDate = parsed.serviceDate
                    bill.status = .parsed
                    
                    // Create line items with pricing data
                    for parsedItem in parsed.lineItems {
                        let lineItem = LineItem(
                            itemDescription: parsedItem.description,
                            chargedAmount: parsedItem.chargedAmount,
                            quantity: 1
                        )
                        lineItem.cptCode = parsedItem.cptCode
                        lineItem.hcpcsCode = parsedItem.hcpcsCode
                        lineItem.allowedAmount = parsedItem.allowedAmount
                        lineItem.paidAmount = parsedItem.paidAmount
                        lineItem.adjustmentAmount = parsedItem.adjustmentAmount
                        lineItem.dateOfService = parsedItem.dateOfService
                        lineItem.modifier = parsedItem.modifier
                        
                        // Look up fair market price
                        if let code = parsedItem.cptCode {
                            let evaluation = pricingService.evaluate(
                                chargedAmount: parsedItem.chargedAmount,
                                cptCode: code,
                                facilityType: parsed.facilityType
                            )
                            lineItem.medicareRate = evaluation.medicareRate
                            lineItem.fairMarketPrice = evaluation.typicalRate
                        }
                        
                        bill.lineItems.append(lineItem)
                    }
                    
                    modelContext.insert(bill)
                    ocrResult = text
                    isProcessing = false
                    showResult = true
                    
                    // Debug output
                    print("===== PARSED BILL =====")
                    print("Provider: \(parsed.providerName ?? "Unknown")")
                    print("Type: \(parsed.facilityType)")
                    print("Total: $\(parsed.totalCharged)")
                    print("Line items: \(parsed.lineItems.count)")
                    for item in parsed.lineItems {
                        let code = item.cptCode ?? item.hcpcsCode ?? "no code"
                        print("  [\(code)] \(item.description) — $\(item.chargedAmount)")
                    }
                    print("=======================")
                }
            } catch {
                await MainActor.run {
                    ocrResult = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Capture Button Component

struct CaptureButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
