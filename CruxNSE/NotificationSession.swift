//
//  NotificationSession.swift
//  CruxNSE
//

import Foundation
import MatrixRustSDK

enum NotificationSessionError: Error {
    case signedOut
}

/// The signed-in client the extension decrypts with. iOS reuses the extension
/// process across notifications, so this is built once and kept.
actor NotificationSession {
    static let shared = NotificationSession()

    private let sessionStore = SessionStore()
    private var platformInitialised = false
    private var connection: (client: Client, notifications: NotificationClient)?

    func notification(roomId: String, eventId: String) async throws -> (status: NotificationStatus, client: Client) {
        let connection = try await connect()
        let status = try await connection.notifications.getNotification(roomId: roomId, eventId: eventId)
        return (status, connection.client)
    }

    private func connect() async throws -> (client: Client, notifications: NotificationClient) {
        if let connection { return connection }

        initialisePlatform()
        guard let stored = try sessionStore.load() else { throw NotificationSessionError.signedOut }

        let client = try await MatrixClientFactory
            .builder(sessionDirectory: stored.sessionDirectory,
                     process: .notificationService,
                     sessionDelegate: sessionStore)
            .homeserverUrl(url: stored.session.homeserverUrl)
            .build()
        try await client.restoreSession(session: stored.session)

        let connection = (client, try await client.notificationClient(processSetup: .multipleProcesses))
        self.connection = connection
        return connection
    }

    /// The Rust core initialises once per process, before the first client.
    private func initialisePlatform() {
        guard !platformInitialised else { return }
        platformInitialised = true

        try? initPlatform(config: TracingConfiguration(logLevel: .warn,
                                                       traceLogPacks: [],
                                                       extraTargets: [],
                                                       writeToStdoutOrSystem: true,
                                                       writeToFiles: nil,
                                                       sentryConfig: nil),
                          useLightweightTokioRuntime: true)
    }
}
