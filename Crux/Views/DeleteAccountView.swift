//
//  DeleteAccountView.swift
//  Crux
//

import SwiftUI

/// Deletes the user's account: in-app on password servers, or via the homeserver's portal on MAS/OAuth.
struct DeleteAccountView: View {
    @Environment(MatrixService.self) private var matrix
    @Environment(\.openURL) private var openURL

    @State private var password = ""
    @State private var eraseData = false
    @State private var isWorking = false
    @State private var showsConfirmation = false
    @State private var errorMessage: String?

    @State private var portalURL: URL?
    @State private var loadedPortal = false

    private var canDeactivateInApp: Bool { matrix.canDeactivateInApp() }

    var body: some View {
        Form {
            Section {
                Text("Deleting your account is permanent. You'll be signed out of every device and won't be able to sign in again.")
                    .foregroundStyle(.secondary)
            }

            if canDeactivateInApp {
                inAppSection
            } else {
                portalSection
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView() }
        }
        .task {
            guard !canDeactivateInApp, !loadedPortal else { return }
            portalURL = await matrix.accountDeactivationURL()
            loadedPortal = true
        }
        .confirmationDialog("Delete your account?",
                            isPresented: $showsConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await deactivate() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private var inAppSection: some View {
        Section("Confirm with your password") {
            SecureField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isWorking)
        }

        Section {
            Toggle("Also erase my messages", isOn: $eraseData)
                .disabled(isWorking)
        } footer: {
            Text("Ask the server to erase your message content where possible.")
        }

        Section {
            Button("Delete Account", role: .destructive) {
                showsConfirmation = true
            }
            .disabled(isWorking || password.isEmpty)
        }
    }

    @ViewBuilder
    private var portalSection: some View {
        Section {
            if let portalURL {
                Button("Continue on \(portalURL.host() ?? "your server")") {
                    openURL(portalURL)
                }
                .disabled(isWorking)
            } else if loadedPortal {
                Text("This server doesn't offer an account-management page, so the account can't be deleted from Crux. Contact your homeserver admin.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        } footer: {
            Text("Your server handles sign-in, so account deletion happens on its account page. Once you finish there, Crux signs you out automatically.")
        }
    }

    private func deactivate() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await matrix.deactivateAccount(password: password, eraseData: eraseData)
        } catch {
            errorMessage = "Couldn't delete your account. Check your password and try again."
        }
    }
}
