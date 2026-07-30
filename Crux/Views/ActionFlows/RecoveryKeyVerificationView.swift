//
//  RecoveryKeyVerificationView.swift
//  Crux
//

import SwiftUI

/// Verifies this device by entering the account's recovery key, as an alternative to the emoji ceremony.
struct RecoveryKeyVerificationView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Recovery key", text: $key, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isWorking)
            } header: {
                Text("Recovery key")
            } footer: {
                Text("Enter the recovery key you saved when you set up encryption. This verifies this device without needing another one.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Verify") {
                    Task { await verify() }
                }
                .disabled(isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Verify with key")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView() }
        }
        .onChange(of: session.verification.isDeviceVerified) { _, verified in
            if verified { dismiss() }
        }
    }

    private func verify() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await session.verification.verifyWithRecoveryKey(key)
        } catch {
            errorMessage = "Couldn't verify with that key. Check it and try again."
        }
    }
}
