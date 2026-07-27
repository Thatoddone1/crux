//
//  MatrixService.swift
//  Crux
//

import Foundation
import MatrixRustSDK

///configuration for how the client appears to the server
enum MatrixConfiguration {
    static let clientName = "Crux"
    static let defaultServer = "matrix.org"
    static let clientURI = "https://crux.joshuarocks.me"

    ///redirect for oauth authentication (MAS)
    static let oauthRedirectURI = "me.joshuarocks.crux:/callback"
    static let oauthCallbackScheme = "me.joshuarocks.crux"

    static let oauthConfiguration = OAuthConfiguration(clientName: clientName,
                                                       redirectUri: oauthRedirectURI,
                                                       clientUri: clientURI,
                                                       logoUri: nil,
                                                       tosUri: nil,
                                                       policyUri: nil,
                                                       staticRegistrations: [:])
}

/// The login methods a homeserver advertises.
struct LoginMethods {
    let supportsOAuth: Bool
    let supportsPassword: Bool
}

enum MatrixServiceError: LocalizedError {
    case noLoginInProgress
    case invalidLoginURL

    var errorDescription: String? {
        switch self {
        case .noLoginInProgress: "No login is in progress. Choose a server first."
        case .invalidLoginURL: "The homeserver returned an invalid login URL."
        }
    }
}

///handles interface between views and matrix-rust-SDK
@Observable
final class MatrixService {
    enum State {
        /// looking for a stored session at launch.
        case restoring
        case signedOut
        case signedIn(UserSession)
    }

    private(set) var state: State = .restoring

    private let sessionStore = SessionStore()

    /// The client created for the server the user is logging in to, kept alive between choosing a server and completing the login
    private var loginClient: Client?
    private var loginSessionDirectory: String?
    private var oauthAuthorizationData: OAuthAuthorizationData?

    /// Keeps the auth-error listener alive; updates stop if this is released
    private var clientDelegateHandle: TaskHandle?

    init() {
        // The SDK's Rust core must be initialised once per process,
        // before the first Client is built.
        try? initPlatform(config: TracingConfiguration(logLevel: .info,
                                                       traceLogPacks: [],
                                                       extraTargets: [],
                                                       writeToStdoutOrSystem: true,
                                                       writeToFiles: nil,
                                                       sentryConfig: nil),
                          useLightweightTokioRuntime: false)
    }

    // MARK: - Session restoration

    /// Restores the previous session from the Keychain, if there is one.
    func restoreSession() async {
        guard case .restoring = state else { return }

        do {
            guard let stored = try sessionStore.load() else {
                state = .signedOut
                return
            }
            
            
            //If the keychain file is there, but the session files themselves are not, that is "not good"
            //so we have to delete the orphaned keychian without a session, and start login all over
            //this can happen if app is deleted (but keychain is not)
            guard FileManager.default.fileExists(atPath: Self.dataDirectory(for: stored.sessionDirectory).path) else {
                clearStoredSession()
                state = .signedOut
                return
            }
            let client = try await clientBuilder(sessionDirectory: stored.sessionDirectory)
                .homeserverUrl(url: stored.session.homeserverUrl)
                .build()
            try await client.restoreSession(session: stored.session)
            try await signIn(with: client)
        } catch {
            // if it cannot be restored, just clear it and start over
            clearStoredSession()
            state = .signedOut
        }
    }

    // MARK: - Login

    /// Builds a client for the given server (a name like "matrix.org" or a full homeserver URL) and returns the login methods it supports.
    func prepareLogin(server: String) async throws -> LoginMethods {
        let sessionDirectory = UUID().uuidString
        let client = try await clientBuilder(sessionDirectory: sessionDirectory)
            .serverNameOrHomeserverUrl(serverNameOrUrl: server)
            .build()

        loginClient = client
        loginSessionDirectory = sessionDirectory

        let details = await client.homeserverLoginDetails()
        return LoginMethods(supportsOAuth: details.supportsOauthLogin(),
                            supportsPassword: details.supportsPasswordLogin())
    }

    /// Starts an OAuth 2.0 login and returns the URL to present in a web authentication session. Registers the client with the homeserver's authentication service if needed.
    func oauthLoginURL() async throws -> URL {
        guard let client = loginClient else { throw MatrixServiceError.noLoginInProgress }

        let data = try await client.urlForOauth(oauthConfiguration: MatrixConfiguration.oauthConfiguration,
                                                prompt: .consent,
                                                loginHint: nil,
                                                deviceId: nil,
                                                additionalScopes: nil)
        oauthAuthorizationData = data

        guard let url = URL(string: data.loginUrl()) else { throw MatrixServiceError.invalidLoginURL }
        return url
    }

    /// Completes the OAuth 2.0 login with the redirect URL received from the web authentication session.
    func completeOAuthLogin(callbackURL: URL) async throws {
        guard let client = loginClient else { throw MatrixServiceError.noLoginInProgress }
        try await client.loginWithOauthCallback(callbackUrl: callbackURL.absoluteString)
        try await finishLogin(with: client)
    }

    /// Tells the client the user abandoned the web login, so it can clean up.
    func cancelOAuthLogin() async {
        guard let client = loginClient, let data = oauthAuthorizationData else { return }
        oauthAuthorizationData = nil
        await client.abortOauthAuth(authorizationData: data)
    }

    /// Logs in with the legacy username + password flow
    func logInWithPassword(username: String, password: String) async throws {
        guard let client = loginClient else { throw MatrixServiceError.noLoginInProgress }
        try await client.login(username: username,
                               password: password,
                               initialDeviceName: MatrixConfiguration.clientName,
                               deviceId: nil)
        try await finishLogin(with: client)
    }

    // MARK: - Logout

    func logOut() async {
        guard case .signedIn(let session) = state else { return }
        state = .signedOut

        await session.stop()
        try? await session.client.logout()
        clearStoredSession()
    }
    
    // MARK: - Private

    private func finishLogin(with client: Client) async throws {
        guard let sessionDirectory = loginSessionDirectory else { throw MatrixServiceError.noLoginInProgress }
        try sessionStore.save(StoredSession(session: client.session(),
                                            sessionDirectory: sessionDirectory))
        loginClient = nil
        loginSessionDirectory = nil
        oauthAuthorizationData = nil

        try await signIn(with: client)
    }

    private func signIn(with client: Client) async throws {
        let session = try await UserSession(client: client)

        // Sign out if the homeserver revokes the session (tokens expired
        // beyond refresh, device deleted, …). Without this the app would
        // stay signed in with a dead session and every request would 401.
        clientDelegateHandle = try? client.setDelegate(delegate: AuthErrorBridge {
            Task { @MainActor [weak self] in await self?.handleAuthError() }
        })

        await session.start()
        state = .signedIn(session)
    }

    private func handleAuthError() async {
        guard case .signedIn(let session) = state else { return }
        state = .signedOut

        await session.stop()
        clearStoredSession()
    }

    /// Removes the session from the Keychain along with its on-disk stores.
    private func clearStoredSession() {
        if let stored = try? sessionStore.load() {
            try? FileManager.default.removeItem(at: Self.dataDirectory(for: stored.sessionDirectory))
            try? FileManager.default.removeItem(at: Self.cacheDirectory(for: stored.sessionDirectory))
        }
        sessionStore.clear()
    }

    /// A builder preconfigured with everything every client needs: on-disk
    /// stores unique to the session, sliding sync and token persistence.
    private func clientBuilder(sessionDirectory: String) throws -> ClientBuilder {
        let dataDirectory = Self.dataDirectory(for: sessionDirectory)
        let cacheDirectory = Self.cacheDirectory(for: sessionDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        return ClientBuilder()
            .sessionPaths(dataPath: dataDirectory.path(percentEncoded: false),
                          cachePath: cacheDirectory.path(percentEncoded: false))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .setSessionDelegate(sessionDelegate: sessionStore)
            // Bootstrap encryption for us: set up cross-signing and key backup
            // automatically after login instead of leaving the account in a
            // half-configured state. These are the defaults a real client
            // (e.g. Element X) uses, and they drive the secret-storage setup
            // that runs on first sync of a fresh account.
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .autoEnableBackups(autoEnableBackups: true)
            .backupDownloadStrategy(backupDownloadStrategy: .afterDecryptionFailure)
            .userAgent(userAgent: MatrixConfiguration.clientName)
    }

    private static func dataDirectory(for sessionDirectory: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "MatrixSessions/\(sessionDirectory)")
    }

    private static func cacheDirectory(for sessionDirectory: String) -> URL {
        URL.cachesDirectory.appending(path: "MatrixSessions/\(sessionDirectory)")
    }
}

/// Forwards the SDK's auth-error callback from its background threads.
private nonisolated final class AuthErrorBridge: ClientDelegate {
    private let handler: @Sendable () -> Void

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func didReceiveAuthError(isSoftLogout: Bool) {
        handler()
    }

    func onBackgroundTaskErrorReport(taskName: String, error: BackgroundTaskFailureReason) {}
}
