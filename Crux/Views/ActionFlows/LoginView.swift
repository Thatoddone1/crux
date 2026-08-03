import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(MatrixService.self) private var matrix
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    
    // UI Navigation State
    enum LoginPhase {
        case server
        case credentials
    }
    
    @State private var phase: LoginPhase = .server
    @State private var isWorking = false
    @State private var errorMessage: String?
    
    // Educational Toggles
    @State private var showServerEducation = false
    @State private var showMXIDEducation = false
    
    // User Data
    @State private var server = MatrixConfiguration.defaultServer
    @State private var username = ""
    @State private var password = ""
    
    // Animation Namespace for the smooth UI shifting
    @Namespace private var loginAnimation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // MARK: - Header
                    VStack(spacing: 8) {
                        Text(phase == .server ? "Where is your account?" : "Who are you?")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: phase)
                        
                        Text(phase == .server ? "Crux uses the open Matrix protocol." : "Enter your credentials to unlock your messages.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // MARK: - Interactive Login Card
                    VStack(spacing: 0) {
                        if phase == .server {
                            serverInputPhase
                                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                        } else {
                            credentialsInputPhase
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
                    .padding(.horizontal)
                    
                    // MARK: - Educational Section
                    educationalFooter
                        .padding(.horizontal, 24)
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase == .credentials {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                phase = .server
                                errorMessage = nil
                                showMXIDEducation = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Phase 1: Server Input
    private var serverInputPhase: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)
                TextField("matrix.org", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .matchedGeometryEffect(id: "serverField", in: loginAnimation)
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(12)
            
            Button(action: {
                Task { await checkServer() }
            }) {
                HStack {
                    Spacer()
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding()
                .background(server.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isWorking || server.isEmpty)
        }
        .padding(20)
    }
    
    // MARK: - Phase 2: MXID Builder (Credentials)
    private var credentialsInputPhase: some View {
        VStack(spacing: 20) {
            // The Visual MXID Builder, helpful for some newcomers hopefully that do already have an account (non MAS)
            HStack(spacing: 4) {
                Text("@")
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                
                Text(":")
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Server locks into place on the right
                Text(server)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .matchedGeometryEffect(id: "serverField", in: loginAnimation)
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(12)
            
            // Password Field
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                SecureField("Password", text: $password)
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(12)
            
            Button(action: {
                Task { await login() }
            }) {
                HStack {
                    Spacer()
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In Securely")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding()
                .background(username.isEmpty || password.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isWorking || username.isEmpty || password.isEmpty)
        }
        .padding(20)
    }
    
    // MARK: - Example Servers
    private var exampleServers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No account yet? Tap a community and click continue to make your account there — or type any server in the field above.")
                .font(.footnote)
                .foregroundColor(.secondary)

            ForEach(MatrixConfiguration.exampleServers) { example in
                HStack(spacing: 12) {
                    // Tapping the row (except the link) fills the field above.
                    Button {
                        withAnimation(.easeInOut) { server = example.name }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Text(example.blurb)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // The globe opens the server's own website in a browser.
                    if let url = URL(string: example.homepage) {
                        Link(destination: url) {
                            Image(systemName: "safari")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }

            Link(destination: URL(string: "https://servers.joinmatrix.org")!) {
                HStack(spacing: 4) {
                    Text("Browse a public server directory")
                    Image(systemName: "arrow.up.right")
                }
                .font(.footnote.weight(.medium))
            }
            .padding(.top, 2)
        }
    }

    /// A tiny "two servers, connected" picture for people who'd rather not read.
    private var homeserverGraphic: some View {
        HStack(spacing: 16) {
            serverTile(name: "matrix.org", tint: .accentColor, who: "You")
            VStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right")
                Text("federated").font(.system(size: 9))
            }
            .foregroundColor(.secondary)
            serverTile(name: "example.org", tint: .purple, who: "A friend")
        }
        .frame(maxWidth: .infinity)
    }

    private func serverTile(name: String, tint: Color, who: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "person.fill.badge.plus")
                        .font(.caption2)
                        .foregroundColor(tint)
                        .padding(3)
                        .background(.background, in: Circle())
                        .offset(x: 4, y: 4)
                }
            Text(name).font(.caption2.weight(.medium))
            Text(who).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    // MARK: - Interactive Educational Footer
    private var educationalFooter: some View {
        VStack(alignment: .leading, spacing: 16) {
            if phase == .server {
                exampleServers

                DisclosureGroup(
                    isExpanded: $showServerEducation,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            homeserverGraphic
                                .padding(.top, 12)

                            Text("Just like email (where `someone@gmail.com` can email `someone@yahoo.com`), Matrix is decentralized. \n\nYou can choose any server to host your account, and still securely message anyone else on the network. **matrix.org** is the largest server and default, but you can enter a custom one above.\n\nDon't have an account yet? Some servers let you sign up right here in your browser. Others use a password — for those, create your account on the server's own website first, then come back.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    },
                    label: {
                        Label("What is a homeserver?", systemImage: "questionmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                )
            } else {
                DisclosureGroup(
                    isExpanded: $showMXIDEducation,
                    content: {
                        Text("The text above is your **Matrix ID (MXID)**. \n\nBecause Matrix is an open network, you need both your username and your server to identify yourself uniquely. You can use this exact MXID to log into *any* Matrix app, not just Crux!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    },
                    label: {
                        Label("Understanding your MXID", systemImage: "person.text.rectangle")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                )
                .onAppear {
                    // Auto-expand for the educational "aha!" moment
                    withAnimation(.spring().delay(0.5)) {
                        showMXIDEducation = true
                    }
                }
            }
        }
    }
    
    // MARK: - Matrix Logic
    //most of the sign in logic is in the MatrixService, but a bit lies here that makes sense to be here
    
    private func checkServer() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        
        do {
            let methods = try await matrix.prepareLogin(server: server)
            if methods.supportsOAuth {
                // Skips Phase 2 entirely if OAuth is required
                try await signInWithOAuth()
            } else if methods.supportsPassword {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    phase = .credentials
                }
            } else {
                errorMessage = "This server doesn't support any login method that Crux is compatible with."
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            await matrix.cancelOAuthLogin()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func login() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        
        do {
            try await matrix.logInWithPassword(username: username, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithOAuth() async throws {
        let url = try await matrix.oauthLoginURL()
        let callbackURL = try await webAuthenticationSession
            .authenticate(using: url, callbackURLScheme: MatrixConfiguration.oauthCallbackScheme)
        try await matrix.completeOAuthLogin(callbackURL: callbackURL)
    }
}
