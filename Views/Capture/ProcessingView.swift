//
//  ProcessingView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
struct ProcessingView: View {
    @Binding var ocrResult: String?
    @State private var currentStep = 0
    @State private var progress: CGFloat = 0
    
    private let steps = [
        ("doc.text.viewfinder", "Analyzing image..."),
        ("text.magnifyingglass", "Extracting text..."),
        ("checklist", "Identifying line items..."),
        ("checkmark.circle", "Done!"),
    ]
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            // Processing card
            VStack(spacing: 28) {
                // Animated icon
                Image(systemName: steps[currentStep].0)
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: currentStep)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 56)
                
                VStack(spacing: 8) {
                    Text(steps[currentStep].1)
                        .font(.headline)
                        .contentTransition(.numericText())
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.tint)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 200)
                }
                
                if currentStep < steps.count - 1 {
                    Text("Processing on-device. Your data stays private.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(36)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            .padding(40)
        }
        .onAppear { simulateProgress() }
        .onChange(of: ocrResult) { _, result in
            if result != nil {
                withAnimation {
                    currentStep = steps.count - 1
                    progress = 1.0
                }
            }
        }
    }
    
    private func simulateProgress() {
        // Animate through steps while OCR processes
        Task {
            for step in 0..<(steps.count - 1) {
                try? await Task.sleep(for: .seconds(1.2))
                guard ocrResult == nil else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentStep = step + 1
                    progress = CGFloat(step + 1) / CGFloat(steps.count)
                }
            }
        }
    }
}
