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

    enum Push {
        static let gatewayURL = "https://push.crux.joshuarocks.me/_matrix/push/v1/notify"

        /// Xcode builds get sandbox APNs tokens and TestFlight gets production
        /// ones; a single push gateway app can't serve both.
        #if DEBUG
        static let appId = "me.joshuarocks.crux.ios.dev"
        #else
        static let appId = "me.joshuarocks.crux.ios.prod"
        #endif

        /// `mutable-content` is what lets the extension run at all. The alert is
        /// only ever seen if the extension fails, so it stays deliberately vague.
        static let defaultPayload = #"{"aps":{"mutable-content":1,"alert":{"loc-key":"Notification","loc-args":[]}}}"#

        static let messageCategory = "me.joshuarocks.crux.message"
        static let replyAction = "me.joshuarocks.crux.reply"

        /// Keys Sygnal puts in the payload when the pusher format is event-id-only.
        static let roomIdKey = "room_id"
        static let eventIdKey = "event_id"
    }
}
