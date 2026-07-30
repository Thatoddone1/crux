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
                Section {
                    NavigationLink("Delete Account") {
                        DeleteAccountView()
                    }
                    .foregroundStyle(.red)
                }
                Section("About") {
                    NavigationLink("View Onboarding", destination: OnboardingView(showsLoginActions: false))
                    Text("Version: \(version) (\(buildNumber))")
                    Link("Reach out for support", destination: URL(string: "mailto:support@joshuarocks.me")!)
                    Text("Created by [Joshua K](https://joshuarocks.me) with ❤️")
                    Text("See the source code on [GitHub](https://github.com/Thatoddone1/crux)")
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
                    Link("Privacy Policy", destination: URL(string: "https://joshuarocks.me/crux/privacy")!)
                }
            }
            .navigationTitle("Settings")
        }

    }
}

