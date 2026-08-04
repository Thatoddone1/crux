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
    private(set) var directMessages: RoomNotificationMode = .allMessages
    private(set) var groupChats: RoomNotificationMode = .allMessages
    private(set) var mentions = true
    private(set) var invites = true
    private(set) var calls = true
    private(set) var isLoaded = false

    private let client: Client
    private var settings: NotificationSettings?

    init(client: Client) {
        self.client = client
    }

    func load() async {
        let settings: NotificationSettings
        if let existing = self.settings {
            settings = existing
        } else {
            settings = await client.getNotificationSettings()
            self.settings = settings
        }

        directMessages = await settings.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: true)
        groupChats = await settings.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: false)
        mentions = (try? await settings.isUserMentionEnabled()) ?? true
        invites = (try? await settings.isInviteForMeEnabled()) ?? true
        calls = (try? await settings.isCallEnabled()) ?? true
        isLoaded = true
    }

    func setDirectMessages(_ mode: RoomNotificationMode) async {
        directMessages = mode
        await setDefaultMode(mode, isOneToOne: true)
    }

    func setGroupChats(_ mode: RoomNotificationMode) async {
        groupChats = mode
        await setDefaultMode(mode, isOneToOne: false)
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

    /// Encrypted and unencrypted rooms are separate push rules, but that's not a
    /// distinction anyone wants to configure, so both move together.
    private func setDefaultMode(_ mode: RoomNotificationMode, isOneToOne: Bool) async {
        for isEncrypted in [true, false] {
            try? await settings?.setDefaultRoomNotificationMode(isEncrypted: isEncrypted,
                                                                isOneToOne: isOneToOne,
                                                                mode: mode)
        }
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
