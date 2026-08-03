//
//  VerificationView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/26/26.
//

import SwiftUI

struct VerificationView: View {
    @Environment(UserSession.self) var session

    var body: some View {
        Group {
            switch session.verification.phase {
            case .cancelled:
                ContentUnavailableView("Cancelled", systemImage: "exclamationmark.square", description: Text("Try cross-verification again or restart the app if the issue persists."))
                Spacer()
                Button("Try cross-verification again") {
                    Task {
                        try await session.verification.requestDeviceVerification()
                    }
                }
                .buttonStyle(.glassProminent)
            case .comparing(let emojis):
                VStack {
                    ForEach(emojis) { emoji in
                        VStack {
                            Text(emoji.symbol)
                                .font(.largeTitle)
                            Text(emoji.name)
                        }
                    }
                }
                .padding()
                
                Spacer()
                VStack {
                    Button("Matching") { Task {try await session.verification.approve()} }
                        .buttonStyle(.glassProminent)
                    Button("Different") { Task {try await session.verification.decline()} }
                        .buttonStyle(.glass)
                    
                }
                
            case .failed:
                ContentUnavailableView("Verification Failed!", systemImage: "exclamationmark.square")
            case .finished:
                Label("Finished!", systemImage: "checkmark.circle")
                    .font(.title3)
                    .fontWeight(.bold)
            case .idle:
                if session.verification.isDeviceVerified {
                    Label("Already Verified", systemImage: "checkmark.circle")
                        .font(.title3.bold())
                } else {
                    Text("Please Verify your Device")
                        .font(.title)
                        .fontWeight(.heavy)
                        .padding()
                    Text("When you sign into Matrix for the first time, it generates encryption keys that stay on your device. When you sign in on another device, you must either verify with another device that is signed in and has the keys or use a backup key. This will copy the local encryption keys to your device and allow you to read older encrypted messages.")
                        .padding()
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Emoji verification needs another signed-in device.
                    if session.verification.hasOtherDevices {
                        Button("Verify with another device") {
                            Task {
                                try await session.verification.requestDeviceVerification()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                    
                    if session.verification.canVerifyWithRecoveryKey {
                        NavigationLink("Verify with recovery key") {
                            RecoveryKeyVerificationView()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    
                    if !session.verification.hasOtherDevices && !session.verification.canVerifyWithRecoveryKey {
                        ContentUnavailableView("Can't verify yet",
                                               systemImage: "key.slash",
                                               description: Text("Sign in on another device, or set up a recovery key, then try again."))
                    }
                }
            case .incomingRequest:
                Text("Incoming Verification Request")
                VStack(){
                    Button("Accept") { Task{ try await session.verification.accept() }}
                        .buttonStyle(.glassProminent)
                    Button("Deny") { Task {try await session.verification.cancel()}}
                        .buttonStyle(.glass)
                }
            case .requesting:
                Text("Requesting")
                    .font(.title2)
                ProgressView()
                    .controlSize(.extraLarge)
            case .waitingForOtherParty:
                Text("Waiting for other party")
            }
        }
        .navigationTitle("Verification")
    }
}

