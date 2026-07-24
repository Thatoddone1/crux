//
//  SessionStore.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import Security

/// A `Session` plus the name of the on-disk directory its stores live in.
nonisolated struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let userId: String
    let deviceId: String
    let homeserverUrl: String
    let oauthData: String?
    let usesNativeSlidingSync: Bool

    /// Directory name under Application Support / Caches. Stored as a name
    /// rather than a path because the app container moves between installs.
    let sessionDirectory: String

    init(session: Session, sessionDirectory: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userId = session.userId
        deviceId = session.deviceId
        homeserverUrl = session.homeserverUrl
        oauthData = session.oauthData
        usesNativeSlidingSync = session.slidingSyncVersion == .native
        self.sessionDirectory = sessionDirectory
    }

    var session: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userId,
                deviceId: deviceId,
                homeserverUrl: homeserverUrl,
                oauthData: oauthData,
                slidingSyncVersion: usesNativeSlidingSync ? .native : .none)
    }
}

enum SessionStoreError: Error {
    case sessionNotFound
    case keychain(OSStatus)
}

/// Persists the Matrix session in the Keychain.
/// Also acts as the SDK's `ClientSessionDelegate`: with OAuth the SDK refreshes tokens on its own, and calls back here so the refreshed tokens replace the stale ones.
nonisolated final class SessionStore {
    private static let service = "me.joshuarocks.crux.session"
    private static let account = "matrix"

    func load() throws -> StoredSession? {
        var query = Self.baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(StoredSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw SessionStoreError.keychain(status)
        }
    }

    func save(_ stored: StoredSession) throws {
        let data = try JSONEncoder().encode(stored)

        var query = Self.baseQuery
        // Readable while the app refreshes tokens or syncs in the background.
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(Self.baseQuery as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw SessionStoreError.keychain(status) }
    }

    func clear() {
        SecItemDelete(Self.baseQuery as CFDictionary)
    }

    private static var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrService: service,
         kSecAttrAccount: account]
    }
}

nonisolated extension SessionStore: ClientSessionDelegate {
    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        guard let stored = try? load(), stored.userId == userId else {
            throw ClientError.Generic(msg: "No stored session for \(userId)", details: nil)
        }
        return stored.session
    }

    func saveSessionInKeychain(session: Session) {
        guard let stored = try? load(), stored.userId == session.userId else { return }
        try? save(StoredSession(session: session, sessionDirectory: stored.sessionDirectory))
    }
}
