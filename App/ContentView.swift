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
                    Label("Scan", systemImage: "doc.text.magnifyingglass")
                }
            BillListView()
                .tabItem {
                    Label("Bills", systemImage: "list.bullet.rectangle")
                }
            SettingsPlaceholder()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
struct SettingsPlaceholder: View {
    var body: some View {
        NavigationStack {
            Text("Settings coming soon")
                .foregroundStyle(.secondary)
                .navigationTitle("Settings")
        }
    }
}
