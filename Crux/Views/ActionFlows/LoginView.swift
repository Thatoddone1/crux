//
//  LoginView.swift
//  Crux
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(MatrixService.self) private var matrix //this is the abstraction for all the matrix stuff, from CruxApp.Swift
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var server = MatrixConfiguration.defaultServer
    @State private var username = ""
    @State private var password = ""
    @State private var showsPasswordLogin = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Homeserver") {
                    TextField("matrix.org", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if showsPasswordLogin {
                    Section("Sign In") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                    }
                }

                Section {
                    Button(showsPasswordLogin ? "Sign In" : "Continue") {
                        Task { await continueTapped() }
                    }
                    .disabled(isWorking || server.isEmpty)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Crux")
            .overlay {
                if isWorking { ProgressView() }
            }
        }
    }

    private func continueTapped() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        do {
            if showsPasswordLogin {
                try await matrix.logInWithPassword(username: username, password: password)
                return
            }

            let methods = try await matrix.prepareLogin(server: server)
            if methods.supportsOAuth {
                try await signInWithOAuth()
            } else if methods.supportsPassword {
                showsPasswordLogin = true
            } else {
                errorMessage = "This server doesn't support any login method that Crux works with. Please submit a bug report!"
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            await matrix.cancelOAuthLogin()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the homeserver's account portal (MAS) in a system web sheet and
    /// completes the login with the callback it redirects to.
    private func signInWithOAuth() async throws {
        let url = try await matrix.oauthLoginURL()
        let callbackURL = try await webAuthenticationSession
            .authenticate(using: url, callbackURLScheme: MatrixConfiguration.oauthCallbackScheme)
        try await matrix.completeOAuthLogin(callbackURL: callbackURL)
    }
}

