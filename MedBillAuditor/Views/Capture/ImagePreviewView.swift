//
//  ImagePreviewView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
struct ImagePreviewView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onRetake: () -> Void
    
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1
    @State private var showAdjustments = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview with zoom
            GeometryReader { geo in
                ZoomableScrollView {
                    Image(uiImage: adjustedImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.02))
            
            // Adjustments panel
            if showAdjustments {
                VStack(spacing: 16) {
                    HStack {
                        Text("Brightness")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $brightness, in: -0.3...0.3, step: 0.05)
                    }
                    HStack {
                        Text("Contrast")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $contrast, in: 0.5...2.0, step: 0.1)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            
            // Action bar
            VStack(spacing: 12) {
                Divider()
                
                HStack(spacing: 16) {
                    Button(action: onRetake) {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button {
                        showAdjustments.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button {
                        onConfirm(adjustedImage)
                    } label: {
                        Label("Audit This Bill", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// Applies brightness/contrast adjustments using Core Image.
    private var adjustedImage: UIImage {
        guard brightness != 0 || contrast != 1 else { return image }
        
        guard let ciImage = CIImage(image: image) else { return image }
        
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter?.setValue(contrast, forKey: kCIInputContrastKey)
        
        guard let output = filter?.outputImage else { return image }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 0.1
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostedView)
        
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
        
        // Fit image to screen initially
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let widthScale = scrollView.bounds.width / hostedView.intrinsicContentSize.width
            let heightScale = scrollView.bounds.height / hostedView.intrinsicContentSize.height
            let minScale = min(widthScale, heightScale, 1.0)
            scrollView.minimumZoomScale = minScale * 0.5
            scrollView.zoomScale = minScale
        }
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = AnyView(content())
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: AnyView(content())))
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>
        
        init(hostingController: UIHostingController<AnyView>) {
            self.hostingController = hostingController
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }
    }
}
