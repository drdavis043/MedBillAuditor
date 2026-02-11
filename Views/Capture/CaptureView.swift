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
    
    // Multi-select support
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var imageQueue: [UIImage] = []
    @State private var currentBatchIndex = 0
    @State private var totalBatchCount = 0
    @State private var isBatchProcessing = false
    @State private var batchResults: [(provider: String, lineItems: Int, total: Decimal)] = []
    @State private var showBatchResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Hero icon
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.08))
                            .frame(width: 120, height: 120)
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 52))
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, options: .repeating.speed(0.5))
                    }

                    VStack(spacing: 8) {
                        Text("Scan Your Bill")
                            .font(AppTheme.Typography.largeTitle)
                        Text("Take a photo or import a PDF to get started")
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Capture options
                VStack(spacing: 12) {
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
                        subtitle: "Select one or more bill photos",
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
                selection: $selectedItems,
                maxSelectionCount: 20,
                matching: .images
            )
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView(image: $capturedImage)
            }
            .onChange(of: selectedItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    selectedItems = []
                    
                    if images.count == 1 {
                        capturedImage = images.first
                    } else if images.count > 1 {
                        imageQueue = images
                        processBatch()
                    }
                }
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
                    .toolbar(.hidden, for: .tabBar)
                }
            }
            .overlay {
                if isProcessing && !isBatchProcessing {
                    ProcessingView(ocrResult: $ocrResult)
                }
                if isBatchProcessing {
                    BatchProcessingView(
                        currentIndex: currentBatchIndex,
                        totalCount: totalBatchCount
                    )
                }
            }
            // Single bill result sheet
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
                                                    .badge(color: .blue)
                                            }
                                            Spacer()
                                            Text("$\(item.chargedAmount)")
                                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        }
                                        Text(item.description)
                                            .font(AppTheme.Typography.caption)
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
            // Batch result sheet
            .sheet(isPresented: $showBatchResult) {
                NavigationStack {
                    List {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.Colors.success)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(batchResults.count) Bills Processed")
                                        .font(AppTheme.Typography.headline)
                                    Text("All bills have been saved. View them in the Bills tab.")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Section("Processed Bills") {
                            ForEach(Array(batchResults.enumerated()), id: \.offset) { index, result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.provider)
                                            .font(AppTheme.Typography.headline)
                                            .lineLimit(1)
                                        Text("\(result.lineItems) line items")
                                            .font(AppTheme.Typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatCurrency(result.total))
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .navigationTitle("Batch Complete")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showBatchResult = false
                                batchResults = []
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Single Bill Processing

    private func processBill(image: UIImage) {
        guard !isProcessing else { return }
        showPreview = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isProcessing = true
            Task {
                do {
                    let preprocessor = ImagePreprocessor()
                    let cleaned = preprocessor.preprocess(image)

                    let ocrService = OCRService()
                    let text = try await ocrService.extractText(from: cleaned)

                    let parser = BillParser()
                    let parsed = parser.parse(text)

                    let pricingService = PricingService()

                    await MainActor.run {
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
                        capturedImage = nil

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
                        capturedImage = nil
                    }
                }
            }
        }
    }

    // MARK: - Batch Processing

    private func processBatch() {
        guard !isBatchProcessing else { return }
        isBatchProcessing = true
        totalBatchCount = imageQueue.count
        currentBatchIndex = 0
        batchResults = []

        Task {
            let preprocessor = ImagePreprocessor()
            let ocrService = OCRService()
            let parser = BillParser()
            let pricingService = PricingService()

            for (index, image) in imageQueue.enumerated() {
                await MainActor.run {
                    currentBatchIndex = index + 1
                }

                do {
                    let cleaned = preprocessor.preprocess(image)
                    let text = try await ocrService.extractText(from: cleaned)
                    let parsed = parser.parse(text)

                    await MainActor.run {
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

                        batchResults.append((
                            provider: parsed.providerName ?? "Unknown Provider",
                            lineItems: parsed.lineItems.count,
                            total: parsed.totalCharged
                        ))

                        print("===== BATCH BILL \(index + 1)/\(imageQueue.count) =====")
                        print("Provider: \(parsed.providerName ?? "Unknown")")
                        print("Total: $\(parsed.totalCharged)")
                        print("Line items: \(parsed.lineItems.count)")
                        print("================================")
                    }
                } catch {
                    print("Error processing batch bill \(index + 1): \(error)")
                    await MainActor.run {
                        batchResults.append((
                            provider: "Error processing bill",
                            lineItems: 0,
                            total: 0
                        ))
                    }
                }
            }

            await MainActor.run {
                isBatchProcessing = false
                imageQueue = []
                showBatchResult = true
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Batch Processing View

struct BatchProcessingView: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 28) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: currentIndex)

                VStack(spacing: 8) {
                    Text("Processing bill \(currentIndex) of \(totalCount)")
                        .font(.headline)
                        .contentTransition(.numericText())

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.tint)
                                .frame(width: geo.size.width * CGFloat(currentIndex) / CGFloat(totalCount))
                                .animation(.easeInOut(duration: 0.4), value: currentIndex)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 200)

                    Text("\(totalCount - currentIndex) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Processing on-device. Your data stays private.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(36)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            .padding(40)
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
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                        .fill(color.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
