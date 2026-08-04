//
//  AppConfiguration.swift
//  Crux
//

import Foundation

/// Identifiers shared by the app and the notification service extension.
nonisolated enum AppConfiguration {
    static let clientName = "Crux"

    static let appGroup = "group.me.joshuarocks.crux"
    static let keychainAccessGroup = "72FYH894PU.me.joshuarocks.crux"

    /// The app writes preferences here so the extension can read them.
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    enum Push {
        // Single-level subdomain: Cloudflare's universal certificate doesn't
        // cover *.crux.joshuarocks.me, and TLS fails before the request is made.
        static let gatewayURL = "https://push-crux.joshuarocks.me/_matrix/push/v1/notify"

        /// Xcode builds get sandbox APNs tokens and TestFlight gets production
        /// ones; a single push gateway app can't serve both.
        #if DEBUG
        static let appId = "me.joshuarocks.crux.ios.dev"
        #else
        static let appId = "me.joshuarocks.crux.ios.prod"
        #endif

        /// `mutable-content` is what lets the extension run at all; the alert is
        /// only ever seen if it fails.
        static let defaultPayload = #"{"aps":{"mutable-content":1,"alert":{"loc-key":"Notification","loc-args":[]}}}"#

        static let messageCategory = "me.joshuarocks.crux.message"
        static let replyAction = "me.joshuarocks.crux.reply"

        /// Offered as one-tap actions on a message notification.
        static let reactions = ["👍", "❤️", "😂"]

        private static let reactionActionPrefix = "me.joshuarocks.crux.react."

        static func reactionAction(for key: String) -> String { reactionActionPrefix + key }

        static func reactionKey(forAction identifier: String) -> String? {
            identifier.hasPrefix(reactionActionPrefix)
                ? String(identifier.dropFirst(reactionActionPrefix.count))
                : nil
        }

        static let timeSensitiveMentionsKey = "push.timeSensitiveMentions"

        static var timeSensitiveMentions: Bool {
            AppConfiguration.defaults.object(forKey: timeSensitiveMentionsKey) as? Bool ?? true
        }

        /// Keys Sygnal puts in the payload when the pusher format is event-id-only.
        static let roomIdKey = "room_id"
        static let eventIdKey = "event_id"
    }
}
