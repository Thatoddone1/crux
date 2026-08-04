//
//  SessionPaths.swift
//  Crux
//

import Foundation

/// Where the SDK keeps its stores.
nonisolated enum SessionPaths {
    ///fallbacks to private storage if no app groups are available
    private static var root: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroup)
            ?? URL.applicationSupportDirectory
    }

    static func dataDirectory(for sessionDirectory: String) -> URL {
        root.appending(path: "Sessions/\(sessionDirectory)/data")
    }

    static func cacheDirectory(for sessionDirectory: String) -> URL {
        root.appending(path: "Sessions/\(sessionDirectory)/cache")
    }

    /// Creates both stores, readable while the device is locked — without that
    /// the extension can't open SQLite to decrypt a notification.
    static func prepare(_ sessionDirectory: String) throws {
        for url in [dataDirectory(for: sessionDirectory), cacheDirectory(for: sessionDirectory)] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    static func remove(_ sessionDirectory: String) {
        try? FileManager.default.removeItem(at: root.appending(path: "Sessions/\(sessionDirectory)"))
    }

    /// migrate private stores from before moved to app groups (for notifications and others)
    static func migrateLegacyStores(for sessionDirectory: String) {
        let manager = FileManager.default
        let legacyData = URL.applicationSupportDirectory.appending(path: "MatrixSessions/\(sessionDirectory)")
        let data = dataDirectory(for: sessionDirectory)

        guard manager.fileExists(atPath: legacyData.path(percentEncoded: false)),
              !manager.fileExists(atPath: data.path(percentEncoded: false)) else { return }

        try? manager.createDirectory(at: data.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: legacyData, to: data)
        try? manager.moveItem(at: URL.cachesDirectory.appending(path: "MatrixSessions/\(sessionDirectory)"),
                              to: cacheDirectory(for: sessionDirectory))
    }
}
