//
//  SessionPaths.swift
//  Crux
//

import Foundation

/// Where the SDK keeps its stores. They live in the App Group container so the
/// notification service extension can open them from its own process.
nonisolated enum SessionPaths {
    /// Falls back to the app's private container when the App Group isn't
    /// available, so a missing entitlement costs notifications rather than the app.
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

    /// Sessions created before the stores moved into the App Group. Temporary —
    /// delete once every install has launched a build containing this.
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
