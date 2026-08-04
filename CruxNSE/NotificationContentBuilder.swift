//
//  NotificationContentBuilder.swift
//  CruxNSE
//

import Intents
import MatrixRustSDK
import UIKit
import UserNotifications

/// Turns a decrypted `NotificationItem` into the notification iOS shows.
enum NotificationContentBuilder {
    /// An empty content tells iOS to drop the notification entirely.
    static let suppressed = UNNotificationContent()

    static func content(for item: NotificationItem,
                        roomId: String,
                        eventId: String,
                        badge: NSNumber?,
                        client: Client) async -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        let senderName = item.senderInfo.displayName ?? senderId(of: item)

        content.title = senderName
        // In a DM the room name is just the sender again.
        if !item.roomInfo.isDm {
            content.subtitle = item.roomInfo.displayName
        }
        content.body = body(of: item)
        content.badge = badge
        content.sound = item.isNoisy == true ? .default : nil
        content.interruptionLevel = item.hasMention == true ? .timeSensitive : .active
        // Groups every notification from one room together in Notification Centre.
        content.threadIdentifier = roomId
        content.categoryIdentifier = AppConfiguration.Push.messageCategory
        content.userInfo = [AppConfiguration.Push.roomIdKey: roomId,
                            AppConfiguration.Push.eventIdKey: eventId]

        let avatar = await avatar(for: item, client: client)
        return (try? await communicationContent(content,
                                                item: item,
                                                roomId: roomId,
                                                senderName: senderName,
                                                avatar: avatar)) ?? content
    }

    /// Gives the notification the same treatment Messages gets: the sender's
    /// avatar in a circle and a conversation iOS can group and reply to.
    private static func communicationContent(_ content: UNMutableNotificationContent,
                                             item: NotificationItem,
                                             roomId: String,
                                             senderName: String,
                                             avatar: INImage?) async throws -> UNNotificationContent {
        let senderId = senderId(of: item)
        let sender = INPerson(personHandle: INPersonHandle(value: senderId, type: .unknown),
                              nameComponents: nil,
                              displayName: senderName,
                              image: avatar,
                              contactIdentifier: nil,
                              customIdentifier: senderId)

        let groupName = item.roomInfo.isDm ? nil : INSpeakableString(spokenPhrase: item.roomInfo.displayName)
        let intent = INSendMessageIntent(recipients: nil,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: nil,
                                         speakableGroupName: groupName,
                                         conversationIdentifier: roomId,
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)
        if groupName != nil, let avatar {
            intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try await interaction.donate()

        return try content.updating(from: intent)
    }

    /// Built from data rather than a URL — URL-backed images routinely fail to
    /// load inside an extension's sandbox.
    private static func avatar(for item: NotificationItem, client: Client) async -> INImage? {
        guard let url = item.senderInfo.avatarUrl ?? item.roomInfo.avatarUrl,
              let image = await MediaLoader.shared.avatar(for: url, client: client, pixelSize: 128),
              let data = image.pngData() else { return nil }
        return INImage(imageData: data)
    }

    private static func senderId(of item: NotificationItem) -> String {
        switch item.event {
        case .invite(let sender): sender
        case .timeline(let event): event.senderId()
        }
    }

    private static func body(of item: NotificationItem) -> String {
        switch item.event {
        case .invite:
            return "Invited you to \(item.roomInfo.displayName)"
        case .timeline(let event):
            guard case .messageLike(let content)? = try? event.content() else { return "Sent a message" }
            switch content {
            case .roomMessage(let messageType, _): return body(of: messageType)
            case .poll(let question): return question
            case .sticker: return "Sent a sticker"
            default: return "Sent a message"
            }
        }
    }

    private static func body(of messageType: MessageType) -> String {
        switch messageType {
        case .text(let content): content.body
        case .notice(let content): content.body
        case .emote(let content): content.body
        case .image: "Sent a photo"
        case .video: "Sent a video"
        case .audio: "Sent an audio message"
        case .file: "Sent a file"
        case .gallery: "Sent photos"
        case .location: "Shared a location"
        case .other(_, let body): body
        }
    }
}
