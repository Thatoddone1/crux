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
    @Environment(UserSession.self) var session
    @Environment(PushModel.self) var push
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
                Section("Notifications") {
                    switch push.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        LabeledContent("Notifications", value: "On")
                    case .denied:
                        LabeledContent("Notifications", value: "Off in Settings")
                    default:
                        Button("Turn On Notifications") {
                            Task { await push.requestAuthorization() }
                        }
                    }
                }
                Section {
                    NavigationLink("Delete Account") {
                        DeleteAccountView()
                    }
                    .foregroundStyle(.red)
                }
                Section("Mountain") {
                    Button("Rescore Mountain") {
                        Task { await session.mountain.reload(unread: session.roomList.unread) }
                    }
                }
                Section("About") {
                    NavigationLink("View Onboarding", destination: OnboardingView(showsLoginActions: false))
                    Text("Version: \(version) (\(buildNumber))")
                    Link("Reach out for support", destination: URL(string: "mailto:support@joshuarocks.me")!)
                    Text("Created by [Joshua Kellman](https://joshuarocks.me)")
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

