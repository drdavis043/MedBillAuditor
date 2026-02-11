//
//  LineItem.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
import SwiftData
@main
struct MedBillAuditorApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .onAppear {
                MedicareFeeLoader.shared.load()
            }
        }
        .modelContainer(for: [
            MedicalBill.self,
            LineItem.self,
            AuditResult.self,
            AuditFlag.self,
            DisputeLetter.self,
        ])
    }
}
