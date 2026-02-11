//
//  ContentView.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/8/26.
//
import SwiftUI
struct ContentView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem {
                    Label("Scan", systemImage: "doc.text.viewfinder")
                }
            BillListView()
                .tabItem {
                    Label("Bills", systemImage: "list.bullet.rectangle.portrait")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
struct SettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                }
                Section("Data") {
                    LabeledContent("Medicare Codes") {
                        Text("\(MedicareFeeLoader.shared.allCodes.count) loaded")
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
            }
            .navigationTitle("Settings")
        }
    }
}
