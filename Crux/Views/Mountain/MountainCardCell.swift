//
//  MountainCardCell.swift
//  Crux
//

import SwiftUI


struct MountainCardCell: View {
    let room: RoomModel
    var score: Int = 0
    var breakdown: MountainModel.ScoreBreakdown? = nil
    var isFocused: Bool = true
    var onOpen: (() -> Void)? = nil
    @Environment(UserSession.self) var session
    @Environment(\.deckDragCount) private var deckDragCount
    @State private var opened: RoomModel?
    @FocusState private var isComposing: Bool

    /// Normally the same object as `room`. The deck holds its cards from when it
    /// was sorted, so if a room left the list in between, `room` is an instance
    /// the store has since stopped — resolving through `openRoom` gets the live
    /// one back rather than drawing a frozen card.
    private var live: RoomModel { opened ?? room }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MountainCardHeader(
                roomName: live.name,
                avatarUrl: live.avatarUrl,
                unreadCount: live.unreadMessages,
                isFavorite: live.isFavorite,
                isDirect: live.isDirect,
                isLowPriority: live.isLowPriority,
                notification: live.notificationLabel,
                isMentioned: live.unreadMentions > 0,
                score: score,
                breakdown: breakdown,
                isFocused: isFocused,
                onOpen: onOpen
            )
            MountainCard(
                messages: latestMessages,
                isFocused: isFocused,
                canSend: canSend,
                onSend: { text in Task { try? await live.timeline.send(text) } },
                onReact: { message, key in Task { try? await live.timeline.toggleReaction(key, on: message) } },
                onReply: { text, message in Task { await reply(text, to: message) } },
                composerFocus: $isComposing
            )
        }
        .onChange(of: deckDragCount) { _, _ in isComposing = false }
        .onChange(of: isFocused) { _, focused in if !focused { isComposing = false } }
        .openRoom(session, roomId: room.id, into: $opened)
    }

    private func reply(_ text: String, to message: TimelineModel.Message) async {
        do {
            try await live.timeline.reply(text, to: message)
        } catch TimelineError.notYetSent {
            try? await live.timeline.send(text)
        } catch {}
    }

    private var canSend: Bool {
        // Optimistic until the room's info lands, so the composer doesn't flicker
        // out from under a card that's still loading.
        guard live.info != nil else { return true }
        return live.canSendMessage()
    }

    /// The last few messages (newest last), flattened to plain values for the card.
    private var latestMessages: [TimelineModel.Message] {
        let messages = live.timeline.entries.compactMap { entry -> TimelineModel.Message? in
            if case .message(let message) = entry { return message }
            return nil
        }
        return Array(messages.suffix(4))
    }
}
