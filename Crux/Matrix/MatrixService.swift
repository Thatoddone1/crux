//
//  MatrixService.swift
//  Crux
//

import Foundation
import MatrixRustSDK

///configuration for how the client appears to the server
enum MatrixConfiguration {
    static let clientName = AppConfiguration.clientName
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

    /// A few public homeservers to suggest to newcomers who don't have an account yet.
    /// These are just examples — the directory link in the UI has the current full list.
    static let exampleServers: [ExampleServer] = [
        ExampleServer(name: "matrix.org",
                      blurb: "Run by the non-profit Matrix.org Foundation. The most popular starting point and a safe default.",
                      homepage: "https://matrix.org"),
        ExampleServer(name: "tchncs.de",
                      blurb: "A large, long-running community server hosting thousands of public rooms.",
                      homepage: "https://tchncs.de"),
        ExampleServer(name: "glasgow.social",
                      blurb: "A smaller community server — an example of the many communities you can call home.",
                      homepage: "https://glasgow.social"),
    ]
}

/// A public homeserver we can suggest, with a short human explanation and a link to learn more.
struct ExampleServer: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let blurb: String
    let homepage: String
}

/// The login methods a homeserver advertises.
struct LoginMethods {
    let supportsOAuth: Bool
    let supportsPassword: Bool
}

enum MatrixServiceError: LocalizedError {
    case noLoginInProgress
    case invalidLoginURL
    case signedOut

    var errorDescription: String? {
        switch self {
        case .noLoginInProgress: "No login is in progress. Choose a server first."
        case .invalidLoginURL: "The homeserver returned an invalid login URL."
        case .signedOut: "You're not signed in."
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
    private let push: PushModel

    /// Held so concurrent callers share one restore instead of each building a
    /// client on the same store — a notification tap and the UI both ask.
    private var restoreTask: Task<Void, Never>?

    /// The client created for the server the user is logging in to, kept alive between choosing a server and completing the login
    private var loginClient: Client?
    private var loginSessionDirectory: String?
    private var oauthAuthorizationData: OAuthAuthorizationData?

    /// Keeps the auth-error listener alive; updates stop if this is released
    private var clientDelegateHandle: TaskHandle?

    init(push: PushModel) {
        self.push = push

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
    /// Safe to call from anywhere: concurrent callers await the same restore.
    func restoreSession() async {
        if let restoreTask { return await restoreTask.value }
        guard case .restoring = state else { return }

        let task = Task { await performRestore() }
        restoreTask = task
        await task.value
    }

    private func performRestore() async {
        do {
            guard let stored = try sessionStore.load() else {
                state = .signedOut
                return
            }

            SessionPaths.migrateLegacyStores(for: stored.sessionDirectory)

            //If the keychain file is there, but the session files themselves are not, that is "not good"
            //so we have to delete the orphaned keychian without a session, and start login all over
            //this can happen if app is deleted (but keychain is not)
            guard FileManager.default.fileExists(atPath: SessionPaths.dataDirectory(for: stored.sessionDirectory).path) else {
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

        await push.signingOut(session.client)
        await session.stop()
        try? await session.client.logout()
        clearStoredSession()
    }

    // MARK: - Account deactivation

    /// True only on legacy `m.login.password` servers; MAS/OAuth servers deactivate via `accountDeactivationURL()`.
    func canDeactivateInApp() -> Bool {
        guard case .signedIn(let session) = state else { return false }
        return session.client.canDeactivateAccount()
    }

    /// The homeserver's account-management page for deactivation (MAS/OAuth), or `nil` if it doesn't offer one.
    func accountDeactivationURL() async -> URL? {
        guard case .signedIn(let session) = state else { return nil }
        guard let string = try? await session.client.accountUrl(action: .accountDeactivate),
              let url = URL(string: string) else { return nil }
        return url
    }

    /// Permanently deletes a password-based account, then tears down the local session.
    func deactivateAccount(password: String, eraseData: Bool) async throws {
        guard case .signedIn(let session) = state else { return }
        let authData = AuthData.password(passwordDetails: .init(identifier: session.userId, password: password))
        try await session.client.deactivateAccount(authData: authData, eraseData: eraseData)

        state = .signedOut
        await push.signingOut(session.client)
        await session.stop()
        clearStoredSession()
    }

    // MARK: - Notification actions

    func sendMessage(_ markdown: String, in roomId: String) async {
        await withRestoredSession { try await $0.sendMessage(markdown, in: roomId) }
    }

    func react(_ key: String, toEvent eventId: String, in roomId: String) async {
        await withRestoredSession { try await $0.react(key, toEvent: eventId, in: roomId) }
    }

    /// Notification actions can arrive before there is any UI, so the session
    /// may still need restoring.
    private func withRestoredSession(_ work: (UserSession) async throws -> Void) async {
        await restoreSession()
        guard case .signedIn(let session) = state else { return }
        try? await work(session)
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
        push.signedIn(client)
    }

    private func handleAuthError() async {
        guard case .signedIn(let session) = state else { return }
        state = .signedOut

        await push.signingOut(session.client)
        await session.stop()
        clearStoredSession()
    }

    /// Removes the session from the Keychain along with its on-disk stores.
    private func clearStoredSession() {
        if let stored = try? sessionStore.load() {
            SessionPaths.remove(stored.sessionDirectory)
        }
        sessionStore.clear()
        restoreTask = nil
    }

    private func clientBuilder(sessionDirectory: String) throws -> ClientBuilder {
        try MatrixClientFactory.builder(sessionDirectory: sessionDirectory,
                                        process: .app,
                                        sessionDelegate: sessionStore)
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
