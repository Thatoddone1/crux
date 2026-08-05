//
//  NotificationSettingsModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// The account's push rules. These live on the homeserver, so they apply to
/// every client you're signed in on, not just this device.
@Observable
final class NotificationSettingsModel {
    var directMessages: RoomNotificationMode {
        store.notificationDefaults.encryptedOneToOne
    }
    var groupChats: RoomNotificationMode {
        store.notificationDefaults.encryptedGroup
    }

    private(set) var mentions = true
    private(set) var invites = true
    private(set) var calls = true
    private(set) var isLoaded = false

    private let client: Client
    private let store: RoomStore
    private var settings: NotificationSettings?

    init(client: Client, store: RoomStore) {
        self.client = client
        self.store = store
    }

    func load() async {
        let settings: NotificationSettings
        if let existing = self.settings {
            settings = existing
        } else {
            settings = await client.getNotificationSettings()
            self.settings = settings
        }

        await store.reloadNotificationDefaults()
        mentions = (try? await settings.isUserMentionEnabled()) ?? true
        invites = (try? await settings.isInviteForMeEnabled()) ?? true
        calls = (try? await settings.isCallEnabled()) ?? true
        isLoaded = true
    }

    func setDirectMessages(_ mode: RoomNotificationMode) async {
        await store.setDefaultNotificationMode(mode, isOneToOne: true)
    }

    func setGroupChats(_ mode: RoomNotificationMode) async {
        await store.setDefaultNotificationMode(mode, isOneToOne: false)
    }

    func setMentions(_ enabled: Bool) async {
        mentions = enabled
        try? await settings?.setUserMentionEnabled(enabled: enabled)
    }

    func setInvites(_ enabled: Bool) async {
        invites = enabled
        try? await settings?.setInviteForMeEnabled(enabled: enabled)
    }

    func setCalls(_ enabled: Bool) async {
        calls = enabled
        try? await settings?.setCallEnabled(enabled: enabled)
    }
}

extension RoomNotificationMode {
    var name: String {
        switch self {
        case .allMessages: "All Messages"
        case .mentionsAndKeywordsOnly: "Mentions Only"
        case .mute: "Nothing"
        }
    }
}
