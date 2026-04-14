//
//  SettingsView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @Query private var bills: [MedicalBill]
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                }

                Section("Audit Database") {
                    LabeledContent("Medicare Pricing Codes") {
                        Text("\(MedicareFeeLoader.shared.allCodes.count)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Bundling Pairs (NCCI)") {
                        Text("\(BundlingDatabase.shared.pairCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Code Descriptions") {
                        Text("\(CodeDescriptionDatabase.shared.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Your Data") {
                    LabeledContent("Saved Bills") {
                        Text("\(bills.count)")
                            .foregroundStyle(.secondary)
                    }
                    let auditedCount = bills.filter { $0.auditResult != nil }.count
                    LabeledContent("Audited") {
                        Text("\(auditedCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Support") {
                    Link(destination: URL(string: "mailto:support@medbillauditor.com")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                }

                Section {
                    Button("Replay Onboarding") {
                        hasCompletedOnboarding = false
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Bills", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete All Bills?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    deleteAllBills()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(bills.count) bill(s) and their audit results. This cannot be undone.")
            }
        }
    }

    private func deleteAllBills() {
        for bill in bills {
            modelContext.delete(bill)
        }
    }
}
