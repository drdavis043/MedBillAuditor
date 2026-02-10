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
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    MedicareFeeLoader.shared.load()
                }
        }
        .modelContainer(for: [
            MedicalBill.self,
            LineItem.self,
            AuditResult.self,
            AuditFlag.self,
            DisputeLetter.self
        ])
    }
}
