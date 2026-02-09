//
//  CaptureView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
import PhotosUI
import SwiftData

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
                if newImage != nil {
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
                    ScrollView {
                        Text(ocrResult ?? "No text extracted")
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("OCR Result")
                    .toolbar {
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
    
    private func processBill(image: UIImage) {
        isProcessing = true
        Task {
            do {
                let preprocessor = ImagePreprocessor()
                let cleaned = preprocessor.preprocess(image)
                
                let ocrService = OCRService()
                let text = try await ocrService.extractText(from: cleaned)
                
                await MainActor.run {
                    ocrResult = text
                    isProcessing = false
                    createBillRecord(from: text, image: image)
                    showResult = true
                }
            } catch {
                await MainActor.run {
                    ocrResult = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
    
    private func createBillRecord(from text: String, image: UIImage) {
        let bill = MedicalBill(
            providerName: "",
            facilityType: .unknown,
            totalCharged: 0,
            sourceType: .camera
        )
        bill.rawOCRText = text
        bill.originalImage = image.jpegData(compressionQuality: 0.8)
        bill.status = .parsed
        modelContext.insert(bill)
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
