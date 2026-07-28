//
//  SettingsView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI
import StoreKit


struct SettingsView: View {
    
    
    
    
    @Environment(MatrixService.self) var matrix
    var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
        
    var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    
    @State var environment: String = "Loading...."
    
    var body: some View {
        NavigationStack {
            List{
                Section() {
                    Button("Log out", role: .destructive) {
                        Task { await matrix.logOut() }
                    }
                    NavigationLink("Verification") {
                        VerificationView()
                    }
                }
                Section("About") {
                    Text("Version: \(version) (\(buildNumber))")
                    Link("Reach out for support", destination: URL(string: "mailto:hello@joshuarocks.me")!)
                    Text("Created by [Joshua K](https://joshuarocks.me) with ❤️")
                }
                Section("Legal") {
                    NavigationLink("Matrix Rust SDK License") {
                        ScrollView {
                            Text(matrixRustSDKLicense)
                                .padding()
                        }
                        .navigationTitle("Matrix Rust SDK License")
                    }
                    NavigationLink("Crux License") {
                        ScrollView{
                            Text(cruxLicense)
                                .padding()
                        }
                        .navigationTitle("Crux License")
                    }
                    NavigationLink("Crux License Exceptions") {
                        ScrollView {
                            Text(cruxLicenseException)
                                .padding()
                        }
                        .navigationTitle("Crux License Exceptions")
                    }
                }
            }
            .navigationTitle("Settings")
        }

    }
}

