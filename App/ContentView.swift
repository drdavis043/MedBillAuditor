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
