//
//  MatrixClientFactory.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// Which process is building the client. The SDK's cross-process store lock
/// needs a name that identifies the holder, so these must stay distinct.
nonisolated enum ClientProcess: String {
    case app
    case notificationService = "nse"
}

/// Builds clients configured identically in the app and the extension, so both
/// open the same stores under the same lock.
nonisolated enum MatrixClientFactory {
    static func builder(sessionDirectory: String,
                        process: ClientProcess,
                        sessionDelegate: ClientSessionDelegate) throws -> ClientBuilder {
        try SessionPaths.prepare(sessionDirectory)

        let builder = ClientBuilder()
            .sessionPaths(dataPath: SessionPaths.dataDirectory(for: sessionDirectory).path(percentEncoded: false),
                          cachePath: SessionPaths.cacheDirectory(for: sessionDirectory).path(percentEncoded: false))
            .crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: process.rawValue))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .setSessionDelegate(sessionDelegate: sessionDelegate)
            .userAgent(userAgent: AppConfiguration.clientName)

        switch process {
        case .app:
            // Bootstrap encryption for us: set up cross-signing and key backup
            // automatically after login instead of leaving the account in a
            // half-configured state. These are the defaults a real client
            // (e.g. Element X) uses, and they drive the secret-storage setup
            // that runs on first sync of a fresh account.
            return builder
                .autoEnableCrossSigning(autoEnableCrossSigning: true)
                .autoEnableBackups(autoEnableBackups: true)
                .backupDownloadStrategy(backupDownloadStrategy: .afterDecryptionFailure)
        case .notificationService:
            // The extension gets ~24 MB, and must never bootstrap encryption.
            return builder.systemIsMemoryConstrained()
        }
    }
}
