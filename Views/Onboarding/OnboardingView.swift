//
//  OnboardingView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var animateIcon = false
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "doc.text.viewfinder",
            title: "Scan Your Bill",
            subtitle: "Take a photo or import a PDF of any medical bill. Our OCR technology reads every line item and charge automatically.",
            color: .blue
        ),
        OnboardingPage(
            icon: "magnifyingglass.circle.fill",
            title: "Detect Overcharges",
            subtitle: "We compare your charges against Medicare rates and check for duplicate billing, unbundling, upcoding, and illegal balance billing.",
            color: .orange
        ),
        OnboardingPage(
            icon: "envelope.badge.shield.half.filled.fill",
            title: "Dispute & Save",
            subtitle: "Generate a professional dispute letter with one tap. Track your bills from scan to resolution — all on your device, fully private.",
            color: .green
        ),
    ]
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 24) {
                        Spacer()
                        // Animated icon
                        Image(systemName: page.icon)
                            .font(.system(size: 80))
                            .foregroundStyle(page.color)
                            .symbolEffect(.bounce, value: currentPage)
                            .shadow(color: page.color.opacity(0.3), radius: 20, y: 10)
                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.system(.title, design: .rounded, weight: .bold))
                            Text(page.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .lineSpacing(4)
                        }
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            // Bottom section
            VStack(spacing: 20) {
                // Custom page dots
                HStack(spacing: 10) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? pages[currentPage].color : Color.gray.opacity(0.3))
                            .frame(width: index == currentPage ? 28 : 8, height: 8)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }
                // Buttons
                if currentPage == pages.count - 1 {
                    Button {
                        withAnimation {
                            hasCompletedOnboarding = true
                        }
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pages[currentPage].color)
                    .padding(.horizontal, 24)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    HStack {
                        Button("Skip") {
                            withAnimation {
                                hasCompletedOnboarding = true
                            }
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            withAnimation {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Next")
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 40)
        }
        .background(
            RadialGradient(
                colors: [pages[currentPage].color.opacity(0.08), .clear],
                center: .top,
                startRadius: 100,
                endRadius: 500
            )
            .animation(.easeInOut(duration: 0.5), value: currentPage)
        )
    }
}
struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}
