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
