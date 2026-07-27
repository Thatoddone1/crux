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
        switch session.verification.phase {
            case .cancelled:
                ContentUnavailableView("Error!", systemImage: "exclamationmark.square")
            case .comparing(let emojis):
                HStack {
                    ForEach(emojis) { emoji in
                        VStack {
                            Text(emoji.symbol)
                            Text(emoji.name)
                        }
                    }
                }
            
                Spacer()
                HStack {
                    Button("Matching") { Task {try await session.verification.approve()} }
                    Button("Different") { Task {try await session.verification.decline()} }
            
            }
            
        case .failed:
            ContentUnavailableView("Verification Failed!", systemImage: "exclamationmark.square")
        case .finished:
            Text("Finished!")
        case .idle:
            if session.verification.isDeviceVerified {
                Text("Already verified")
            } else {
                Button("Request Verification") {
                    Task {
                        try await session.verification.requestDeviceVerification()
                    }
                }
            }
        case .incomingRequest:
            Text("Incoming Verification Request")
            Button("Accept") { Task{ try await session.verification.accept() }}
            Button("Deny") { Task {try await session.verification.cancel()}}
            
        case .requesting:
            Text("Requesting")
        case .waitingForOtherParty:
            Text("Waiting for other party")
        }
    

    }
}

