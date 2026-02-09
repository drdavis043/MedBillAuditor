//
//  DocumentPickerView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .image],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            if url.pathExtension.lowercased() == "pdf" {
                parent.image = renderAllPDFPages(url: url)
            } else {
                if let data = try? Data(contentsOf: url) {
                    parent.image = UIImage(data: data)
                }
            }
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
        
        /// Renders all pages of a PDF as a single tall UIImage for OCR processing.
        private func renderAllPDFPages(url: URL) -> UIImage? {
            guard let document = PDFDocument(url: url) else { return nil }
            
            let scale: CGFloat = 2.0
            var pageImages: [UIImage] = []
            
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let size = CGSize(
                    width: bounds.width * scale,
                    height: bounds.height * scale
                )
                
                let renderer = UIGraphicsImageRenderer(size: size)
                let img = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.cgContext.translateBy(x: 0, y: size.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                pageImages.append(img)
            }
            
            guard !pageImages.isEmpty else { return nil }
            
            // Stitch all pages into one tall image
            let totalHeight = pageImages.reduce(0) { $0 + $1.size.height }
            let maxWidth = pageImages.map { $0.size.width }.max() ?? 0
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxWidth, height: totalHeight))
            return renderer.image { ctx in
                var yOffset: CGFloat = 0
                for img in pageImages {
                    img.draw(at: CGPoint(x: 0, y: yOffset))
                    yOffset += img.size.height
                }
            }
        }
    }
}
